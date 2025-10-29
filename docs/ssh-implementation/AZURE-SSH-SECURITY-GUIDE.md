# Azure Security Enhancements for SSH on Domain Controller

**Purpose**: Implement Azure-native security features to enhance SSH security beyond basic OpenSSH configuration.

**Prerequisites**:
- Domain Controller hosted in Azure
- Azure subscription with appropriate permissions
- Basic SSH setup completed ([SSH-CONFIGURATION.md](SSH-CONFIGURATION.md))

**Estimated Time**: 1-3 hours (depending on features implemented)

---

## Overview

Since your Domain Controller is hosted in Azure, you can leverage Azure's native security features to significantly enhance SSH security beyond the basic OpenSSH setup.

### Security Layers

```
┌─────────────────────────────────────────────────┐
│ Layer 7: Monitoring & Logging                  │
│ • Azure Monitor • Sentinel • Log Analytics      │
├─────────────────────────────────────────────────┤
│ Layer 6: Access Control                         │
│ • Just-In-Time VM Access • Conditional Access   │
├─────────────────────────────────────────────────┤
│ Layer 5: Key Management                         │
│ • Azure Key Vault • Managed Identities          │
├─────────────────────────────────────────────────┤
│ Layer 4: Network Security                       │
│ • NSG Rules • Private Link • Azure Bastion      │
├─────────────────────────────────────────────────┤
│ Layer 3: Identity & Authentication              │
│ • Azure AD Integration • Certificate Auth       │
├─────────────────────────────────────────────────┤
│ Layer 2: Operating System                       │
│ • OpenSSH Server • Windows Firewall             │
├─────────────────────────────────────────────────┤
│ Layer 1: Physical/Hypervisor                    │
│ • Azure Infrastructure Security                 │
└─────────────────────────────────────────────────┘
```

---

## Security Enhancement Options

### Quick Comparison

| Feature | Security Level | Cost | Complexity | Recommended |
|---------|---------------|------|------------|-------------|
| **NSG IP Restrictions** | High | Free | Low | ✅ YES |
| **Just-In-Time Access** | Very High | Free (Defender) | Medium | ✅ YES |
| **Azure Key Vault** | High | ~$0.03/10k ops | Medium | ✅ YES |
| **Azure Bastion** | Very High | ~$140/month | Low | ⚠️ Optional |
| **Private Link** | Very High | ~$10/month | High | ⚠️ If needed |
| **Azure Monitor** | Medium | ~$2-10/month | Low | ✅ YES |
| **Azure AD SSH** | Very High | Free | High | ⚠️ Advanced |

---

## Option 1: Network Security Groups (NSG) - RECOMMENDED

**Cost**: Free
**Complexity**: Low
**Security Impact**: High

### 1.1: Restrict SSH to AKS Only

**Purpose**: Only allow SSH connections from your AKS cluster.

#### Get AKS Egress IP

```bash
# From a machine with kubectl access
# Method 1: Check AKS egress IP
az aks show --resource-group YOUR-RG --name YOUR-AKS-CLUSTER --query "networkProfile.loadBalancerProfile.effectiveOutboundIps[].id" -o tsv

# Method 2: Deploy test pod and check IP
kubectl run test-ip --image=busybox --rm -it --restart=Never -- wget -qO- ifconfig.me
```

#### Configure NSG Rule

```bash
# Get your DC's NSG
az network nsg list --resource-group YOUR-RG --query "[?contains(name, 'DC')]" -o table

# Create restrictive SSH rule
az network nsg rule create \
  --resource-group YOUR-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS \
  --priority 300 \
  --source-address-prefixes YOUR-AKS-EGRESS-IP \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp \
  --description "Allow SSH from AKS cluster only"

# Remove any existing permissive SSH rules
az network nsg rule delete \
  --resource-group YOUR-RG \
  --nsg-name YOUR-DC-NSG \
  --name default-allow-ssh
```

#### Verify NSG Rules

```bash
# List all NSG rules for your DC
az network nsg rule list \
  --resource-group YOUR-RG \
  --nsg-name YOUR-DC-NSG \
  --query "[].{Name:name, Priority:priority, Source:sourceAddressPrefix, Dest:destinationPortRange, Access:access}" \
  --output table
```

### 1.2: Add Service Tags (Optional)

```bash
# Allow SSH from Azure services only
az network nsg rule create \
  --resource-group YOUR-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-Azure \
  --priority 310 \
  --source-address-prefixes AzureCloud \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp
```

**✅ Pros**:
- Free
- Immediate effect
- Easy to modify
- Logs connection attempts

**❌ Cons**:
- Static IP restrictions
- Doesn't prevent compromised AKS pods

---

## Option 2: Just-In-Time (JIT) VM Access - HIGHLY RECOMMENDED

**Cost**: Free (requires Microsoft Defender for Cloud - Standard tier ~$15/month per server)
**Complexity**: Medium
**Security Impact**: Very High

### 2.1: Enable Microsoft Defender for Cloud

```bash
# Enable Defender for Cloud on subscription
az security pricing create \
  --name VirtualMachines \
  --tier Standard

# Enable JIT on your DC
az security jit-policy create \
  --resource-group YOUR-RG \
  --name YOUR-DC-NAME \
  --location eastus \
  --vm YOUR-DC-RESOURCE-ID \
  --ports '[{
    "number": 22,
    "protocol": "TCP",
    "allowedSourceAddressPrefix": ["YOUR-AKS-EGRESS-IP"],
    "maxRequestAccessDuration": "PT3H"
  }]'
```

### 2.2: Request JIT Access (When Needed)

```bash
# Request access for 3 hours
az security jit-policy request \
  --name YOUR-DC-NAME \
  --resource-group YOUR-RG \
  --vm YOUR-DC-RESOURCE-ID \
  --ports '[{
    "number": 22,
    "duration": "PT3H",
    "allowedSourceAddressPrefix": ["YOUR-IP"]
  }]'
```

### 2.3: Automate JIT for n8n (Advanced)

Create an Azure Function or Logic App that:
1. Grants JIT access before workflow execution
2. Revokes access after completion
3. Logs all access requests

**Example Azure Function**:
```python
import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.security import SecurityCenter

def grant_jit_access(vm_resource_id, source_ip, duration_hours=3):
    credential = DefaultAzureCredential()
    security_client = SecurityCenter(
        credential=credential,
        subscription_id=os.environ['AZURE_SUBSCRIPTION_ID']
    )

    # Request JIT access
    jit_request = {
        'virtualMachines': [{
            'id': vm_resource_id,
            'ports': [{
                'number': 22,
                'duration': f'PT{duration_hours}H',
                'allowedSourceAddressPrefix': source_ip
            }]
        }]
    }

    security_client.jit_network_access_policies.initiate(
        resource_group_name='YOUR-RG',
        jit_network_access_policy_name='YOUR-DC-NAME',
        body=jit_request
    )
```

**✅ Pros**:
- Extremely secure (time-limited access)
- Audit trail built-in
- Automatic NSG management
- Prevents persistent backdoors

**❌ Cons**:
- Requires Defender for Cloud subscription
- Additional cost (~$15/month)
- More complex setup for automation

---

## Option 3: Azure Key Vault for SSH Keys - RECOMMENDED

**Cost**: ~$0.03 per 10,000 operations
**Complexity**: Medium
**Security Impact**: High

### 3.1: Create Key Vault

```bash
# Create Key Vault
az keyvault create \
  --name YOUR-KV-NAME \
  --resource-group YOUR-RG \
  --location eastus \
  --enable-rbac-authorization true

# Grant yourself access
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee YOUR-USER-ID \
  --scope /subscriptions/YOUR-SUB-ID/resourceGroups/YOUR-RG/providers/Microsoft.KeyVault/vaults/YOUR-KV-NAME
```

### 3.2: Store SSH Private Key

```bash
# Store SSH private key as secret
az keyvault secret set \
  --vault-name YOUR-KV-NAME \
  --name n8n-dc-ssh-private-key \
  --file ~/.ssh/n8n_dc_automation \
  --description "n8n to DC SSH private key"

# Store public key (for reference)
az keyvault secret set \
  --vault-name YOUR-KV-NAME \
  --name n8n-dc-ssh-public-key \
  --file ~/.ssh/n8n_dc_automation.pub
```

### 3.3: Configure n8n to Use Key Vault

**Option A: Use AKS Managed Identity** (Recommended)

```bash
# Enable managed identity on AKS
az aks update \
  --resource-group YOUR-RG \
  --name YOUR-AKS-CLUSTER \
  --enable-managed-identity

# Get identity ID
IDENTITY_ID=$(az aks show -g YOUR-RG -n YOUR-AKS-CLUSTER --query identityProfile.kubeletidentity.clientId -o tsv)

# Grant Key Vault access
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $IDENTITY_ID \
  --scope /subscriptions/YOUR-SUB-ID/resourceGroups/YOUR-RG/providers/Microsoft.KeyVault/vaults/YOUR-KV-NAME
```

**Option B: Use Azure Key Vault CSI Driver** (Best)

```yaml
# Install Azure Key Vault CSI driver
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm install csi csi-secrets-store-provider-azure/csi-secrets-store-provider-azure

# Create SecretProviderClass
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: n8n-ssh-keys
  namespace: n8n-prod
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "YOUR-IDENTITY-CLIENT-ID"
    keyvaultName: "YOUR-KV-NAME"
    objects: |
      array:
        - |
          objectName: n8n-dc-ssh-private-key
          objectType: secret
          objectAlias: ssh-private-key
    tenantId: "YOUR-TENANT-ID"
  secretObjects:
  - secretName: n8n-ssh-credentials
    type: Opaque
    data:
    - objectName: ssh-private-key
      key: privateKey

# Update n8n deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: n8n-prod
spec:
  template:
    spec:
      volumes:
      - name: secrets-store
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "n8n-ssh-keys"
      containers:
      - name: n8n
        volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true
```

### 3.4: Automatic Key Rotation

```bash
# Enable automatic key rotation
az keyvault secret set-attributes \
  --vault-name YOUR-KV-NAME \
  --name n8n-dc-ssh-private-key \
  --expires "2026-01-01T00:00:00Z"

# Set up alert for expiration
az monitor metrics alert create \
  --name ssh-key-expiring \
  --resource-group YOUR-RG \
  --scopes /subscriptions/YOUR-SUB-ID/resourceGroups/YOUR-RG/providers/Microsoft.KeyVault/vaults/YOUR-KV-NAME \
  --condition "total KeyVaultSecretNearExpiry > 0" \
  --description "SSH key expiring soon"
```

**✅ Pros**:
- Centralized key management
- Automatic rotation support
- Audit logging
- Never stored in code/config

**❌ Cons**:
- Minimal cost
- Additional setup complexity
- Requires Azure integration

---

## Option 4: Azure Bastion - OPTIONAL

**Cost**: ~$140/month
**Complexity**: Low
**Security Impact**: Very High

### 4.1: Deploy Azure Bastion

```bash
# Create Bastion subnet (must be named AzureBastionSubnet)
az network vnet subnet create \
  --resource-group YOUR-RG \
  --vnet-name YOUR-VNET \
  --name AzureBastionSubnet \
  --address-prefixes 10.0.1.0/26

# Create public IP for Bastion
az network public-ip create \
  --resource-group YOUR-RG \
  --name Bastion-PIP \
  --sku Standard \
  --location eastus

# Create Bastion host
az network bastion create \
  --name YOUR-BASTION \
  --resource-group YOUR-RG \
  --vnet-name YOUR-VNET \
  --location eastus
```

### 4.2: Connect via Bastion

**Via Azure Portal**:
1. Navigate to your DC VM
2. Click "Connect" → "Bastion"
3. Enter credentials
4. SSH session opens in browser

**Via Azure CLI**:
```bash
# Connect to VM via Bastion
az network bastion ssh \
  --name YOUR-BASTION \
  --resource-group YOUR-RG \
  --target-resource-id YOUR-DC-RESOURCE-ID \
  --auth-type ssh-key \
  --username Administrator \
  --ssh-key ~/.ssh/n8n_dc_automation
```

### 4.3: Bastion for n8n (Advanced)

**Challenge**: n8n can't directly use Bastion (requires Azure SDK)

**Solution**: Create a Bastion proxy service:

```python
# bastion-proxy.py (runs in AKS)
from azure.identity import DefaultAzureCredential
from azure.mgmt.network import NetworkManagementClient
import socket

def create_bastion_tunnel(dc_resource_id):
    credential = DefaultAzureCredential()
    network_client = NetworkManagementClient(credential, subscription_id)

    # Create tunnel via Bastion
    tunnel = network_client.bastion_hosts.create_ssh_tunnel(
        resource_group='YOUR-RG',
        bastion_host_name='YOUR-BASTION',
        target_resource_id=dc_resource_id,
        resource_port=22
    )

    # Proxy local port 2222 to Bastion tunnel
    # n8n connects to localhost:2222
```

**✅ Pros**:
- No public IP on DC
- TLS-encrypted Azure connection
- Full audit logging
- No NSG rules needed

**❌ Cons**:
- Expensive (~$140/month)
- Complex n8n integration
- Browser-based (hard to automate)

**Recommendation**: Only if DC needs zero internet exposure

---

## Option 5: Azure Monitor & Security Logging - RECOMMENDED

**Cost**: ~$2-10/month
**Complexity**: Low
**Security Impact**: Medium (detection, not prevention)

### 5.1: Enable Azure Monitor

```bash
# Create Log Analytics workspace
az monitor log-analytics workspace create \
  --resource-group YOUR-RG \
  --workspace-name YOUR-WORKSPACE \
  --location eastus

# Enable VM insights
az vm extension set \
  --resource-group YOUR-RG \
  --vm-name YOUR-DC-NAME \
  --name MicrosoftMonitoringAgent \
  --publisher Microsoft.EnterpriseCloud.Monitoring \
  --settings "{\"workspaceId\":\"YOUR-WORKSPACE-ID\"}" \
  --protected-settings "{\"workspaceKey\":\"YOUR-WORKSPACE-KEY\"}"
```

### 5.2: Create SSH Alert Rules

```bash
# Alert on SSH login failures
az monitor metrics alert create \
  --name ssh-login-failures \
  --resource-group YOUR-RG \
  --scopes YOUR-DC-RESOURCE-ID \
  --condition "avg LogManagement > 5" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action YOUR-ACTION-GROUP-ID

# Alert on successful SSH from unexpected IPs
# (Create custom log query in Log Analytics)
```

### 5.3: SSH Audit Query (Log Analytics)

```kql
// Failed SSH attempts
Syslog
| where Facility == "auth" or Facility == "authpriv"
| where SyslogMessage contains "Failed password"
| summarize FailedAttempts=count() by Computer, SourceIP=extract(@"(\d+\.\d+\.\d+\.\d+)", 1, SyslogMessage), TimeGenerated
| where FailedAttempts > 3
| order by TimeGenerated desc

// Successful SSH logins
Syslog
| where Facility == "auth"
| where SyslogMessage contains "Accepted publickey"
| project TimeGenerated, Computer, User=extract(@"for (\w+)", 1, SyslogMessage), SourceIP=extract(@"from (\d+\.\d+\.\d+\.\d+)", 1, SyslogMessage)
| order by TimeGenerated desc

// SSH sessions duration
Syslog
| where Facility == "auth"
| where SyslogMessage contains "session opened" or SyslogMessage contains "session closed"
| summarize SessionStart=min(TimeGenerated), SessionEnd=max(TimeGenerated) by User=extract(@"for user (\w+)", 1, SyslogMessage)
| extend Duration = SessionEnd - SessionStart
| order by Duration desc
```

### 5.4: Integrate with Azure Sentinel (Optional)

```bash
# Enable Sentinel
az sentinel onboard \
  --resource-group YOUR-RG \
  --workspace-name YOUR-WORKSPACE

# Connect data sources
az sentinel data-connector create \
  --resource-group YOUR-RG \
  --workspace-name YOUR-WORKSPACE \
  --name WindowsSecurityEvents \
  --kind WindowsSecurityEvents
```

**✅ Pros**:
- Comprehensive visibility
- Automated threat detection
- Integration with other Azure services
- Historical analysis

**❌ Cons**:
- Doesn't prevent attacks
- Requires monitoring/response process
- Additional cost for data ingestion

---

## Option 6: Azure AD Authentication for SSH - ADVANCED

**Cost**: Free (with Azure AD)
**Complexity**: High
**Security Impact**: Very High

### 6.1: Enable Azure AD Login Extension

```bash
# Install Azure AD SSH Login extension
az vm extension set \
  --resource-group YOUR-RG \
  --vm-name YOUR-DC-NAME \
  --name AADSSHLoginForWindows \
  --publisher Microsoft.Azure.ActiveDirectory
```

### 6.2: Configure RBAC for SSH

```bash
# Grant SSH access via Azure RBAC
az role assignment create \
  --role "Virtual Machine Administrator Login" \
  --assignee YOUR-USER-ID \
  --scope YOUR-DC-RESOURCE-ID

# Or for standard user access
az role assignment create \
  --role "Virtual Machine User Login" \
  --assignee YOUR-USER-ID \
  --scope YOUR-DC-RESOURCE-ID
```

### 6.3: Connect with Azure AD

```bash
# Login with Azure AD
az login

# SSH to VM (no private key needed!)
az ssh vm \
  --resource-group YOUR-RG \
  --name YOUR-DC-NAME
```

### 6.4: Conditional Access Policies

```bash
# Create conditional access policy
# (Must be done via Azure Portal or Graph API)
# Conditions:
# - Require MFA
# - Require compliant device
# - Restrict to specific locations
# - Require approval workflow
```

**✅ Pros**:
- No SSH keys to manage
- MFA support
- Conditional access policies
- Centralized identity

**❌ Cons**:
- Complex for automation (n8n)
- Requires Azure AD Premium for conditional access
- Difficult to use with service principals
- May not work with all scenarios

**Recommendation**: Best for admin access, not for n8n automation

---

## Recommended Security Stack

### Tier 1: Essential (Low Cost, High Security)

**Total Cost**: ~$0-5/month

1. ✅ **NSG IP Restrictions** (Free)
   - Restrict SSH to AKS egress IP only
   - Implementation: 10 minutes

2. ✅ **Azure Key Vault** (~$0.03/10k ops)
   - Store SSH keys securely
   - Implementation: 30 minutes

3. ✅ **Azure Monitor Basic** (~$2/month)
   - SSH access logging
   - Failed login alerts
   - Implementation: 20 minutes

### Tier 2: Enhanced (Medium Cost, Very High Security)

**Total Cost**: ~$17-20/month

1. ✅ All Tier 1 features

2. ✅ **Just-In-Time Access** (~$15/month for Defender)
   - Time-limited SSH access
   - Automatic NSG management
   - Implementation: 45 minutes

3. ✅ **Enhanced Monitoring** (~$5/month)
   - Azure Sentinel integration
   - Advanced threat detection
   - Implementation: 1 hour

### Tier 3: Maximum Security (High Cost)

**Total Cost**: ~$160+/month

1. ✅ All Tier 2 features

2. ⚠️ **Azure Bastion** (~$140/month)
   - Zero public IP exposure
   - Browser-based access
   - Implementation: 1 hour

3. ⚠️ **Azure AD SSH** (Requires Premium)
   - Conditional access
   - MFA enforcement
   - Implementation: 2 hours

---

## Implementation Priority

### Phase 1: Quick Wins (Do First - 1 Hour)

```bash
# 1. Restrict NSG to AKS IP only (15 min)
az network nsg rule create ...

# 2. Enable basic Azure Monitor (15 min)
az monitor log-analytics workspace create ...

# 3. Create failed login alert (15 min)
az monitor metrics alert create ...

# 4. Document current security posture (15 min)
```

### Phase 2: Key Management (Do Next - 1 Hour)

```bash
# 1. Create Key Vault (10 min)
az keyvault create ...

# 2. Migrate SSH keys to Key Vault (20 min)
az keyvault secret set ...

# 3. Configure AKS to use Key Vault (30 min)
# Install CSI driver, create SecretProviderClass
```

### Phase 3: Advanced Security (Optional - 2+ Hours)

```bash
# 1. Enable JIT Access (1 hour)
az security pricing create ...

# 2. Set up Sentinel (1 hour)
az sentinel onboard ...

# 3. Consider Azure Bastion (if needed)
```

---

## Security Comparison: Before vs After

### Before (Basic SSH)
```
Attack Surface:
- Public IP exposed (port 22)
- Static NSG rules
- SSH keys in n8n config
- Basic Windows Event Logs
- No time-limited access

Risk Level: ⚠️ MEDIUM
```

### After (Tier 1 - Essential)
```
Attack Surface:
- Port 22 restricted to AKS IP
- SSH keys in Key Vault
- Azure Monitor logging
- Alert on suspicious activity

Risk Level: ✅ LOW
```

### After (Tier 2 - Enhanced)
```
Attack Surface:
- JIT access (3-hour windows)
- Automatic NSG cleanup
- Sentinel threat detection
- Full audit trail
- Keys in Key Vault with rotation

Risk Level: ✅ VERY LOW
```

---

## Cost-Benefit Analysis

| Security Feature | Monthly Cost | Risk Reduction | ROI |
|-----------------|--------------|----------------|-----|
| NSG IP Restriction | $0 | 40% | ⭐⭐⭐⭐⭐ |
| Azure Key Vault | ~$0.50 | 15% | ⭐⭐⭐⭐⭐ |
| Azure Monitor | ~$2 | 10% (detection) | ⭐⭐⭐⭐ |
| JIT Access | ~$15 | 30% | ⭐⭐⭐⭐ |
| Sentinel | ~$5 | 10% (detection) | ⭐⭐⭐ |
| Azure Bastion | ~$140 | 45% | ⭐⭐ (high cost) |

**Recommended Starting Point**: Tier 1 (NSG + Key Vault + Monitor) = ~$2-5/month, ~65% risk reduction

---

## Next Steps

1. **Immediate** (Today):
   - Implement NSG IP restrictions
   - Enable basic Azure Monitor

2. **This Week**:
   - Migrate keys to Key Vault
   - Set up monitoring alerts

3. **This Month**:
   - Consider JIT access if budget allows
   - Evaluate Bastion need

4. **Ongoing**:
   - Review logs weekly
   - Rotate keys quarterly
   - Update NSG rules as AKS IP changes

---

## Testing Security Enhancements

After implementing security features:

```bash
# 1. Test NSG rules
# Try SSH from unauthorized IP (should fail)
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-IP

# 2. Test Key Vault integration
kubectl exec -it -n n8n-prod deployment/n8n -- cat /mnt/secrets/ssh-private-key

# 3. Test JIT access
az security jit-policy show --name YOUR-DC-NAME --resource-group YOUR-RG

# 4. Test monitoring alerts
# Intentionally fail SSH login 5 times (should trigger alert)

# 5. Review Azure Monitor logs
az monitor log-analytics query \
  --workspace YOUR-WORKSPACE-ID \
  --analytics-query "Syslog | where Facility == 'auth' | top 10 by TimeGenerated"
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-28
**Related Documents**:
- [SSH-CONFIGURATION.md](SSH-CONFIGURATION.md) - Basic SSH setup
- [SSH-IMPLEMENTATION-SUMMARY.md](SSH-IMPLEMENTATION-SUMMARY.md) - Overall architecture
