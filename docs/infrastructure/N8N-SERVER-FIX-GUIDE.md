# n8n Server Instability Fix Guide

## Problem Summary

Your n8n pod on AKS has been crash-looping with **880 restarts** over 11 days due to failed health checks.

### Root Causes Identified

1. **CPU Starvation** (CRITICAL)
   - Current limit: 200m (0.2 cores)
   - Current usage: 135m (67.5% of limit)
   - **Problem**: n8n is CPU-throttled and can't respond to health checks in time
   - **Impact**: Health check timeouts → pod restarts → cascade failures

2. **Health Check Timeouts Too Aggressive**
   - Liveness: 5 second timeout
   - Readiness: 3 second timeout
   - **Problem**: CPU-starved n8n can't respond fast enough
   - **Evidence**: 2,276 liveness failures, 6,024 readiness failures

3. **SQLite Performance Issues**
   - No connection pool configured (`DB_SQLITE_POOL_SIZE` not set)
   - **Problem**: Slower database operations add to health check latency
   - **Evidence**: Warning in logs about missing pool configuration

4. **Cascade Effect**
   - Restarts interrupt running workflows
   - Creates "unfinished executions" (found 6066, 6070)
   - Next startup is slower loading these
   - Triggers more health check failures
   - **Result**: Death spiral

---

## Changes Made in Fix

### Resource Limits (Most Important)

```yaml
# BEFORE
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 200m      # TOO LOW!
    memory: 1Gi

# AFTER
resources:
  requests:
    cpu: 250m      # 2.5x increase
    memory: 512Mi  # 2x increase
  limits:
    cpu: 1000m     # 5x increase - this is key!
    memory: 2Gi    # 2x increase
```

**Rationale**:
- n8n with 5 active workflows needs at least 500m CPU
- Giving 1 core (1000m) provides headroom for spikes
- More memory helps with caching and reduces disk I/O

### Health Check Timeouts

```yaml
# BEFORE - Liveness
livenessProbe:
  initialDelaySeconds: 30    # Too short for startup
  periodSeconds: 10          # Too frequent
  timeoutSeconds: 5          # Too short
  failureThreshold: 3        # Too aggressive

# AFTER - Liveness
livenessProbe:
  initialDelaySeconds: 60    # 2x - allows full startup
  periodSeconds: 15          # 1.5x - less frequent checks
  timeoutSeconds: 10         # 2x - more time to respond
  failureThreshold: 5        # 1.67x - more tolerance
```

```yaml
# BEFORE - Readiness
readinessProbe:
  initialDelaySeconds: 10    # Way too short
  periodSeconds: 5           # Too frequent
  timeoutSeconds: 3          # Way too short!
  failureThreshold: 3

# AFTER - Readiness
readinessProbe:
  initialDelaySeconds: 30    # 3x - allows startup
  periodSeconds: 10          # 2x - less pressure
  timeoutSeconds: 8          # 2.67x - realistic timeout
  failureThreshold: 5        # More tolerance
```

**Rationale**:
- n8n startup takes ~20-30 seconds with active workflows
- Under CPU pressure, health checks can take 5-8 seconds
- More tolerance prevents unnecessary restarts

### Environment Variables (New)

```yaml
# Fix SQLite performance warning
- name: DB_SQLITE_POOL_SIZE
  value: "3"

# Enable task runners (n8n recommendation)
- name: N8N_RUNNERS_ENABLED
  value: "true"

# Security best practices
- name: N8N_BLOCK_ENV_ACCESS_IN_NODE
  value: "false"
- name: N8N_GIT_NODE_DISABLE_BARE_REPOS
  value: "true"
- name: N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS
  value: "true"
```

**Rationale**:
- SQLite pool improves database performance
- Task runners reduce main process load
- Security vars address deprecation warnings

---

## How to Apply the Fix

### Option 1: Apply the Full Deployment (Recommended)

```bash
# Navigate to the fix file
cd "C:\Users\rcox\Documents\Cursor Projects\IT-Agent"

# Apply the fix
kubectl apply -f n8n-deployment-fix.yaml

# Watch the rollout
kubectl rollout status deployment/n8n -n n8n-prod

# Monitor the new pod
kubectl get pods -n n8n-prod -w
```

**Expected behavior**:
- Old pod will terminate gracefully
- New pod will start with new configuration
- Should become Ready in ~60 seconds
- **No more restarts!**

### Option 2: Patch Existing Deployment (Faster)

If you want to apply just the critical CPU fix quickly:

```bash
# Increase CPU limits immediately
kubectl patch deployment n8n -n n8n-prod --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "1000m"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "250m"}
]'

# Increase memory limits
kubectl patch deployment n8n -n n8n-prod --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "2Gi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "512Mi"}
]'

# Fix liveness probe timeout
kubectl patch deployment n8n -n n8n-prod --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value": 10},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value": 60},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/failureThreshold", "value": 5}
]'

# Fix readiness probe timeout
kubectl patch deployment n8n -n n8n-prod --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/timeoutSeconds", "value": 8},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 30},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/failureThreshold", "value": 5}
]'
```

---

## Verification Steps

### 1. Check Pod Status

```bash
# Wait for new pod to be running
kubectl get pods -n n8n-prod

# Should show:
# NAME                   READY   STATUS    RESTARTS   AGE
# n8n-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
#                                          ↑
#                                    Should be 0!
```

### 2. Monitor for Restarts

```bash
# Watch pod for 10 minutes
kubectl get pods -n n8n-prod -w

# In another terminal, check events
watch -n 5 'kubectl get events -n n8n-prod --sort-by=.lastTimestamp | tail -20'
```

**Expected**:
- ✅ No "Killing" events
- ✅ No "Unhealthy" events
- ✅ No restarts

### 3. Check Health Endpoint Directly

```bash
# Port forward to the pod
kubectl port-forward -n n8n-prod deployment/n8n 5678:5678

# In another terminal, test health endpoint
time curl http://localhost:5678/healthz

# Should respond in < 1 second with status 200
```

### 4. Check Resource Usage

```bash
# Check CPU/Memory usage
kubectl top pod -n n8n-prod

# Should show:
# NAME                   CPU(cores)   MEMORY(bytes)
# n8n-xxxxxxxxxx-xxxxx   200m-400m    300Mi-600Mi
#                        ↑ More CPU available now
```

### 5. Test n8n API

```bash
# Test the API (should not get 502/503 errors anymore)
curl -I https://n8n.ii-us.com
```

**Expected**: `HTTP/2 200` (not 502 or 503)

---

## Expected Results

### Immediate (0-5 minutes)
- ✅ Deployment updated successfully
- ✅ Old pod terminates
- ✅ New pod starts with increased resources
- ✅ Health checks pass within 60 seconds
- ✅ Pod enters Ready state

### Short Term (5-30 minutes)
- ✅ No restarts occur
- ✅ Health check events show all success
- ✅ API responds reliably (no 502/503)
- ✅ MCP tools can connect successfully

### Long Term (1+ hours)
- ✅ Restart count stays at 0
- ✅ Active workflows run without interruption
- ✅ No "unfinished executions" accumulate
- ✅ Stable performance

---

## Monitoring Commands

### Real-time Pod Monitoring

```bash
# Watch pod status
watch -n 2 'kubectl get pods -n n8n-prod'

# Watch events
kubectl get events -n n8n-prod --watch

# Tail logs
kubectl logs -n n8n-prod -l app=n8n --follow
```

### Check for Improvements

```bash
# Before: 880 restarts
# After: Should stay at 0
kubectl get pod -n n8n-prod -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'

# Check if health probes are passing
kubectl describe pod -n n8n-prod -l app=n8n | grep -A 5 "Conditions:"
```

---

## Troubleshooting

### Problem: Pod still restarting

**Check**:
```bash
kubectl logs -n n8n-prod -l app=n8n --previous
kubectl describe pod -n n8n-prod -l app=n8n | tail -50
```

**Possible causes**:
- Database corruption (check PVC)
- OOM kills (check if memory limit was hit)
- Application crash (check logs)

### Problem: Not enough CPU/Memory on nodes

**Check node resources**:
```bash
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
```

**Solution**: Increase node size or add more nodes

### Problem: Fix didn't apply

**Check deployment**:
```bash
kubectl get deployment n8n -n n8n-prod -o yaml | grep -A 10 resources:
```

**Verify CPU limit shows 1000m, not 200m**

---

## Cost Impact

**Resource Increase**:
- CPU: 100m → 250m request, 200m → 1000m limit
- Memory: 256Mi → 512Mi request, 1Gi → 2Gi limit

**Azure Cost Estimate**:
- Previous: ~$5-10/month for n8n pod
- New: ~$15-25/month for n8n pod
- **Difference**: ~$10-15/month additional cost

**ROI**: Worth it for stability! The constant restarts and interrupted workflows were costing more in:
- Lost productivity
- Incomplete workflow executions
- Time spent troubleshooting

---

## Additional Recommendations

### 1. Fix Backup Jobs

You have 4 backup jobs stuck in ContainerCreating:
```bash
kubectl get pods -n n8n-prod | grep backup
```

**Check what's wrong**:
```bash
kubectl describe pod -n n8n-prod n8n-backup-29345880-r5ggm
```

**Likely issues**:
- PVC not available
- Image pull issues
- Resource constraints

### 2. Consider PostgreSQL

SQLite is not ideal for production. Consider migrating to PostgreSQL:
- Better performance
- No file locking issues
- Better for concurrent access
- Easier backups

### 3. Add Monitoring

Set up Prometheus/Grafana to monitor:
- Pod restarts
- Health check success rate
- CPU/Memory usage over time
- Workflow execution times

### 4. Review Other Pods

Check if other pods in the cluster have similar issues:
```bash
kubectl get pods --all-namespaces | grep -E 'CrashLoop|Error|ContainerCreating'
```

---

## Summary

**Problem**: n8n pod crash-looping due to CPU starvation and aggressive health checks

**Root Causes**:
1. CPU limit too low (200m)
2. Health check timeouts too short (3-5 seconds)
3. SQLite without connection pool
4. Cascade effect from restarts

**Solution**:
- Increase CPU to 1000m (5x)
- Increase memory to 2Gi (2x)
- Increase health check timeouts (2-3x)
- Add SQLite pool and other optimizations

**Apply**:
```bash
kubectl apply -f n8n-deployment-fix.yaml
```

**Expected Result**: Stable n8n with 0 restarts and reliable API responses

---

## Next Steps

1. ✅ Apply the fix
2. ✅ Monitor for 30 minutes
3. ✅ Verify 0 restarts
4. ✅ Test n8n API reliability
5. ✅ Return to Employee Termination workflow fixes

Once n8n is stable, we can complete the workflow validation fixes!
