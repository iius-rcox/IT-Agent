## AKS Performance Recommendations (dev-aks / rg_prod)

### Current State
- Cluster: `dev-aks` in `rg_prod`, Kubernetes 1.32.7
- Control Plane: Private, VNet integrated
- Networking: Azure CNI Overlay + Cilium dataplane/policy
- Node Pools: Single `systempool` (Linux `Standard_D4lds_v5`, 3 nodes, AZ 1/2/3)
- Node Config: Ephemeral OS disk, `maxPods=250`, autoscaling disabled, pool surge `10%`
- Autoscaler Profile: Not configured
- Features: NodeLocal DNS disabled, Image Cleaner not configured

### Target End State
- Separate `userpool` (autoscaling enabled, zones 1/2/3) + slim `systempool`
- NodeLocal DNS enabled; tuned Cluster Autoscaler profile for faster and smarter scaling
- Pod density: `systempool maxPods=50`, `userpool maxPods≈110`
- Image cleaner enabled to manage disk usage and image churn
- Outbound egress via NAT Gateway (UDR) to eliminate SNAT limits under load
- Upgrade posture: higher surge on `userpool` (≈33%) and upgraded to Kubernetes 1.33.x
- Kubelet/resource governance tuned for stability under pressure

### Current Snapshot (from az CLI)
- Network: Azure CNI Overlay with Cilium dataplane and policy
- API Server: Private cluster with VNet integration
- Node Pools: Single `systempool` (Linux, `Standard_D4lds_v5`, 3 nodes, zones 1/2/3)
- Node Config: Ephemeral OS disk, `maxPods=250`, autoscaling disabled, `maxSurge=10%`
- Cluster Autoscaler Profile: Not configured
- Features: NodeLocal DNS disabled, Image Cleaner not configured
- K8s Version: 1.32.7 (1.33.x available)

> Note: System and user workloads are currently mixed on the system pool. For best performance and safer upgrades, workloads should run on a separate `User` pool with autoscaling.

### Current vs Target (at-a-glance)

- **Node pools**: `systempool` only → `systempool` (addons) + `userpool` (apps, CA on)
- **Autoscaling**: disabled → enabled on user pool + tuned CA profile
- **DNS**: kube-dns only → NodeLocal DNS enabled
- **Pod density**: 250 on systempool → 50 on systempool, ~110 on userpool
- **Egress**: SLB outbound → NAT Gateway via UDR (userDefinedRouting)
- **Upgrades**: surge 10% → surge ~33% on `userpool` and k8s 1.33.x
- **Kubelet**: defaults → eviction/log/image-GC thresholds set

---

### 1) Create a dedicated User node pool with autoscaling and move workloads
- Objective: Improve bin-packing, reduce contention on system components, and enable safe rolling upgrades.
- Commands:
```powershell
az aks nodepool add -g rg_prod --cluster-name dev-aks -n userpool \
  --mode User --vm-size Standard_D4lds_v5 \
  --enable-cluster-autoscaler --min-count 3 --max-count 10 \
  --max-pods 110 --os-disk-type Ephemeral --zones 1 2 3

# Prefer scheduling add-ons to systempool, and app workloads to userpool
az aks nodepool update -g rg_prod --cluster-name dev-aks -n systempool \
  --node-taints CriticalAddonsOnly=true:NoSchedule
```

---

### 2) Enable NodeLocal DNS and tune cluster autoscaler profile
- Objective: Reduce DNS latency/iptables pressure and make scaling decisions faster with better packing.
- Commands:
```powershell
az aks update -g rg_prod -n dev-aks --enable-node-local-dns

az aks update -g rg_prod -n dev-aks --cluster-autoscaler-profile \
  balanced-similar-node-groups=true \
  scan-interval=10s \
  scale-down-unneeded-time=5m \
  scale-down-utilization-threshold=0.5 \
  max-graceful-termination-sec=600
```

---

### 3) Right-size pod density and enable image cleaner
- Objective: Avoid kubelet pressure on system nodes and reduce image churn to improve pull times.
- Commands:
```powershell
# Reduce density on systempool, increase density on userpool (overlay supports higher)
az aks nodepool update -g rg_prod --cluster-name dev-aks -n systempool --max-pods 50
az aks nodepool update -g rg_prod --cluster-name dev-aks -n userpool --max-pods 110

# Enable image cleaner to keep node disk usage in check over time
az aks update -g rg_prod -n dev-aks --workload-autoscaler-profile image-cleaner=true
```

---

### 4) Use NAT Gateway for scalable outbound SNAT and egress performance
- Objective: Prevent SNAT exhaustion and improve egress throughput/latency for outbound-heavy workloads.
- Steps:
  - Create NAT Gateway and associate it to the AKS node subnet.
  - Switch cluster outbound type to `userDefinedRouting` and use UDR to route via NAT Gateway.
- Commands (example):
```powershell
# Create NAT Gateway
az network public-ip create -g rg_prod -n nat-pip --sku Standard --zone 1 2 3
az network nat gateway create -g rg_prod -n aks-nat --public-ip-addresses nat-pip --idle-timeout 10

# Associate NAT Gateway to subnet (replace with your subnet name if different)
az network vnet subnet update \
  --ids /subscriptions/a78954fe-f6fe-4279-8be0-2c748be2f266/resourceGroups/rg_prod/providers/Microsoft.Network/virtualNetworks/vnet_prod/subnets/aks-subnet \
  --nat-gateway aks-nat

# Update cluster outbound type (requires maintenance window/roll)
az aks update -g rg_prod -n dev-aks --outbound-type userDefinedRouting
```

---

### 5) Accelerate safe upgrades and adopt 1.33.x
- Objective: Reduce maintenance windows and get performance/stability improvements in newer Kubernetes.
- Commands:
```powershell
# Increase surge on userpool for faster rolling upgrades (after userpool is created)
az aks nodepool update -g rg_prod --cluster-name dev-aks -n userpool --max-surge 33%

# Preview available upgrades
az aks get-upgrades -g rg_prod -n dev-aks -o table

# Upgrade control plane, then node pool(s)
az aks upgrade -g rg_prod -n dev-aks --kubernetes-version 1.33.3 --control-plane-only --yes
az aks nodepool upgrade -g rg_prod --cluster-name dev-aks -n userpool --kubernetes-version 1.33.3 --yes
```

---

### 6) Kubelet and resource governance tuning
- Objective: Improve node stability and workload throughput under pressure via kubelet settings and resource requests/limits.
- Approach:
  - Set kubelet eviction thresholds, container log limits, and image GC thresholds via `--kubelet-config`.
  - Enforce sensible `requests/limits` via a `LimitRange` and use PriorityClasses for critical services.
- Example kubelet config file (`kubelet-config.json`):
```json
{
  "evictionHard": {
    "imagefs.available": "10%",
    "nodefs.available": "10%",
    "memory.available": "500Mi"
  },
  "imageGCHighThresholdPercent": 80,
  "imageGCLowThresholdPercent": 60,
  "containerLogMaxSize": "20Mi",
  "containerLogMaxFiles": 5
}
```
- Apply to pools (requires nodes to roll):
```powershell
az aks nodepool update -g rg_prod --cluster-name dev-aks -n systempool --kubelet-config kubelet-config.json
az aks nodepool update -g rg_prod --cluster-name dev-aks -n userpool --kubelet-config kubelet-config.json
```

---

### Validation Checklist
- `kubectl top nodes` shows headroom on system nodes; user workloads scheduled to userpool.
- DNS latency drops (NodeLocal DNS DaemonSet running; pods resolve via 169.254.20.10).
- Scale events occur within ~10s scan interval; scale-down after 5m idle.
- No SNAT exhaustion during load tests; egress IP is from NAT Gateway PIP(s).
- Upgrades complete faster with higher surge; disruption budgets honored.
- Nodes keep image/log usage bounded; fewer eviction events during stress.

### Rollout Order (recommended)
1) Add `userpool` with autoscaling → migrate workloads.
2) Enable NodeLocal DNS → apply autoscaler profile.
3) Adjust `maxPods` and enable image cleaner.
4) Introduce NAT Gateway outbound.
5) Increase surge on `userpool` → upgrade to 1.33.x.
6) Apply kubelet config → verify via canary pool or one AZ first.
