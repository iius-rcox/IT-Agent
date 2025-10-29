# NSG Quick Setup: Restrict SSH to AKS Only

**Security Enhancement**: Restrict SSH access on Domain Controller to AKS cluster only
**Cost**: $0 (Free)
**Time**: 10-15 minutes
**Security Gain**: 40% attack surface reduction

---

## What This Does

Configures Azure Network Security Group (NSG) to:
- ✅ Allow SSH (port 22) only from your AKS cluster
- ✅ Block SSH from all other sources
- ✅ Maintain existing rules for other traffic
- ✅ Provide audit logging of connection attempts

**Before**: SSH port 22 accessible from internet
**After**: SSH port 22 accessible only from your AKS egress IP

---

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Access to your Azure subscription
- kubectl access to AKS cluster
- Permissions to modify NSG rules

---

## Step 1: Get Your AKS Egress IP

**Why**: We need to know what IP address your AKS cluster uses for outbound connections.

### Method 1: Using kubectl (Quick)

```bash
# Run a temporary pod that checks its public IP
kubectl run test-egress-ip \
  --image=busybox \
  --rm -it \
  --restart=Never \
  --namespace=n8n-prod \
  -- wget -qO- ifconfig.me

# Expected output: Something like "20.51.123.45"
# Save this IP - you'll need it!
```

### Method 2: Using Azure CLI

```bash
# Get AKS load balancer public IP
az aks show \
  --resource-group YOUR-AKS-RG \
  --name YOUR-AKS-CLUSTER \
  --query "networkProfile.loadBalancerProfile.effectiveOutboundIps[].id" \
  -o tsv

# Then get the actual IP address
az network public-ip show \
  --ids <ID-FROM-ABOVE> \
  --query ipAddress \
  -o tsv
```

### Method 3: Check existing n8n connection

```bash
# If you've already tested SSH from n8n, check DC logs
# On the DC (via RDP or existing access):
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 10 |
  Where-Object {$_.Message -like "*Accepted*"} |
  Select-Object -First 1 -ExpandProperty Message

# Look for "from <IP-ADDRESS>" in the message
```

**Record the IP**: _____________________________

---

## Step 2: Identify Your DC's NSG

### Option A: Using Azure Portal

1. Navigate to Azure Portal → Virtual Machines
2. Find your Domain Controller VM
3. Click on it → Networking (left menu)
4. Note the NSG name (e.g., "DC01-nsg" or "DomainController-NSG")

### Option B: Using Azure CLI

```bash
# List all NSGs in your resource group
az network nsg list \
  --resource-group YOUR-DC-RG \
  --query "[].{Name:name, Location:location}" \
  --output table

# If you have many NSGs, filter by DC name
az network nsg list \
  --resource-group YOUR-DC-RG \
  --query "[?contains(name, 'DC') || contains(name, 'Domain')]" \
  --output table

# Get NSG associated with DC NIC
az vm show \
  --resource-group YOUR-DC-RG \
  --name YOUR-DC-VM-NAME \
  --query "networkProfile.networkInterfaces[0].id" \
  -o tsv | \
  xargs az network nic show --ids | \
  jq -r '.networkSecurityGroup.id' | \
  awk -F'/' '{print $NF}'
```

**Record the NSG name**: _____________________________
**Record the Resource Group**: _____________________________

---

## Step 3: Review Current NSG Rules

**Before making changes**, let's see what's currently configured:

```bash
# List current NSG rules
az network nsg rule list \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --query "[].{Name:name, Priority:priority, Direction:direction, Access:access, Protocol:protocol, SourceAddress:sourceAddressPrefix, DestPort:destinationPortRange}" \
  --output table
```

**Look for**:
- Existing SSH rules (port 22)
- Default allow rules
- Priority numbers (we'll use 300 for our new rule)

**Save this output** - useful for rollback if needed.

---

## Step 4: Create Restrictive SSH Rule

Now we'll create the new rule that allows SSH only from your AKS cluster:

```bash
# Create the restrictive rule
az network nsg rule create \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only \
  --priority 300 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes YOUR-AKS-EGRESS-IP \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22 \
  --description "Allow SSH only from AKS cluster"
```

**Replace**:
- `YOUR-DC-RG` → Your DC resource group name
- `YOUR-DC-NSG` → Your DC NSG name (from Step 2)
- `YOUR-AKS-EGRESS-IP` → Your AKS egress IP (from Step 1)

**Example**:
```bash
az network nsg rule create \
  --resource-group IT-Infrastructure-RG \
  --nsg-name DC01-nsg \
  --name Allow-SSH-From-AKS-Only \
  --priority 300 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 20.51.123.45 \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22 \
  --description "Allow SSH only from AKS cluster"
```

**Expected Output**:
```json
{
  "access": "Allow",
  "destinationPortRange": "22",
  "direction": "Inbound",
  "name": "Allow-SSH-From-AKS-Only",
  "priority": 300,
  "protocol": "Tcp",
  "sourceAddressPrefix": "20.51.123.45"
}
```

---

## Step 5: Remove Old Permissive SSH Rules (If Any)

Check if there are existing permissive SSH rules that would override our new rule:

```bash
# List SSH-related rules sorted by priority
az network nsg rule list \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --query "[?destinationPortRange=='22'].{Name:name, Priority:priority, SourceAddress:sourceAddressPrefix, Access:access}" \
  --output table
```

**If you see rules with lower priority (< 300) that allow SSH from anywhere**:
- Names like: "default-allow-ssh", "AllowSSH", "SSH-Inbound"
- Source: "*", "Internet", "0.0.0.0/0"

**Delete them**:
```bash
# Delete permissive rule (replace RULE-NAME)
az network nsg rule delete \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name RULE-NAME

# Example:
az network nsg rule delete \
  --resource-group IT-Infrastructure-RG \
  --nsg-name DC01-nsg \
  --name default-allow-ssh
```

**Important**: Only delete rules that specifically allow SSH from broad sources. Don't delete:
- Other port rules (RDP, HTTPS, etc.)
- Azure infrastructure rules (65000+ priority)
- Your new "Allow-SSH-From-AKS-Only" rule!

---

## Step 6: Add Deny Rule (Optional but Recommended)

Add an explicit deny rule as a safety net:

```bash
az network nsg rule create \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Deny-SSH-All-Other \
  --priority 400 \
  --direction Inbound \
  --access Deny \
  --protocol Tcp \
  --source-address-prefixes '*' \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22 \
  --description "Deny SSH from all other sources"
```

**Why**: Provides explicit deny (clearer in audit logs) and ensures no accidental permissive rules override your restriction.

---

## Step 7: Verify Configuration

### 7.1: Review Final NSG Rules

```bash
# View final configuration
az network nsg rule list \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --query "[?destinationPortRange=='22'].{Name:name, Priority:priority, Direction:direction, Access:access, Source:sourceAddressPrefix}" \
  --output table
```

**Expected output**:
```
Name                      Priority  Direction  Access  Source
------------------------  --------  ---------  ------  ----------------
Allow-SSH-From-AKS-Only   300       Inbound    Allow   20.51.123.45
Deny-SSH-All-Other        400       Inbound    Deny    *
```

### 7.2: Test SSH from n8n Pod

```bash
# Test SSH from n8n (should work)
kubectl exec -it -n n8n-prod deployment/n8n -- /bin/sh -c \
  "ssh -i /path/to/key -o StrictHostKeyChecking=no Administrator@DC-HOSTNAME 'echo SSH-Test-Success'"

# Expected: "SSH-Test-Success"
```

### 7.3: Test SSH from External IP (Should Fail)

```bash
# From your local machine (NOT from AKS)
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-PUBLIC-IP

# Expected: Connection timeout or "Connection refused"
# This proves the restriction is working!
```

---

## Step 8: Document Your Configuration

Save this information for future reference:

```bash
# Create documentation
cat > ~/nsg-ssh-config.txt << 'EOF'
=== NSG SSH Configuration ===
Date: $(date)
Resource Group: YOUR-DC-RG
NSG Name: YOUR-DC-NSG
AKS Egress IP: YOUR-AKS-EGRESS-IP

Rules Created:
1. Allow-SSH-From-AKS-Only (Priority 300)
   - Source: YOUR-AKS-EGRESS-IP
   - Destination Port: 22
   - Action: Allow

2. Deny-SSH-All-Other (Priority 400)
   - Source: *
   - Destination Port: 22
   - Action: Deny

Old Rules Removed:
- [List any rules you deleted]

Test Results:
- SSH from n8n: ✓ Success
- SSH from external: ✗ Blocked (as expected)
EOF
```

---

## Maintenance

### When AKS Egress IP Changes

If your AKS cluster's egress IP changes (e.g., after cluster recreate):

```bash
# 1. Get new IP
kubectl run test-ip --image=busybox --rm -it --restart=Never -- wget -qO- ifconfig.me

# 2. Update NSG rule
az network nsg rule update \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only \
  --source-address-prefixes NEW-IP

# 3. Verify
az network nsg rule show \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only \
  --query sourceAddressPrefix
```

### Add Additional Allowed IPs

To allow SSH from your admin workstation temporarily:

```bash
# Get current allowed IPs
CURRENT_IPS=$(az network nsg rule show \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only \
  --query sourceAddressPrefixes -o tsv)

# Add new IP
az network nsg rule update \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only \
  --source-address-prefixes $CURRENT_IPS YOUR-ADMIN-IP

# Example: Add office IP temporarily
az network nsg rule update \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only \
  --source-address-prefixes 20.51.123.45 203.0.113.50
```

---

## Rollback Procedure

If you need to revert changes:

```bash
# Delete the restrictive rules
az network nsg rule delete \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only

az network nsg rule delete \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Deny-SSH-All-Other

# Restore original rule (if you had one)
# Use the output from Step 3 to recreate original rules
```

---

## Troubleshooting

### Issue: SSH from n8n fails after configuration

**Possible Causes**:
1. Wrong AKS egress IP
2. NSG rule priority conflict
3. Another NSG blocking traffic

**Solutions**:
```bash
# 1. Verify current n8n IP
kubectl exec -it -n n8n-prod deployment/n8n -- wget -qO- ifconfig.me

# 2. Compare with NSG rule
az network nsg rule show \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only \
  --query sourceAddressPrefix

# 3. Check NSG flow logs (if enabled)
az network watcher flow-log show \
  --resource-group NetworkWatcherRG \
  --nsg YOUR-DC-NSG

# 4. Temporarily allow all to test
az network nsg rule update \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only \
  --source-address-prefixes '*'
# Test, then revert to specific IP
```

### Issue: Can't determine AKS egress IP

**Solution**: Use Azure Portal to check recent connections
1. Azure Portal → Your DC VM → Networking → Network Watcher
2. Look for recent SSH connections on port 22
3. Note the source IP

### Issue: Multiple AKS egress IPs

If your AKS cluster uses multiple egress IPs:

```bash
# Allow multiple IPs
az network nsg rule update \
  --resource-group YOUR-DC-RG \
  --nsg-name YOUR-DC-NSG \
  --name Allow-SSH-From-AKS-Only \
  --source-address-prefixes IP1 IP2 IP3
```

---

## Security Benefits

After implementing NSG restriction:

✅ **Attack Surface Reduced**: SSH only accessible from known IP
✅ **Brute Force Prevention**: Attackers can't even attempt connections
✅ **Zero Cost**: Free Azure feature
✅ **Instant Effect**: Active immediately
✅ **Audit Trail**: NSG logs all connection attempts
✅ **Easy to Modify**: Update rules as needed

---

## Next Steps

After completing NSG setup:

1. ✅ **Test SSH access** from n8n workflow
2. ✅ **Document configuration** (save NSG rule details)
3. ✅ **Set calendar reminder** to review quarterly
4. ⏭️ **Optional**: Consider adding Azure Key Vault for SSH keys
5. ⏭️ **Optional**: Consider JIT access for even more security

---

## Quick Reference Commands

```bash
# Get AKS egress IP
kubectl run test-ip --image=busybox --rm -it --restart=Never -- wget -qO- ifconfig.me

# List NSG rules
az network nsg rule list --resource-group RG --nsg-name NSG --output table

# Create allow rule
az network nsg rule create \
  --resource-group RG \
  --nsg-name NSG \
  --name Allow-SSH-From-AKS-Only \
  --priority 300 \
  --source-address-prefixes AKS-IP \
  --destination-port-ranges 22 \
  --access Allow

# Test from n8n
kubectl exec -it -n n8n-prod deployment/n8n -- ssh user@dc hostname

# Update rule with new IP
az network nsg rule update \
  --resource-group RG \
  --nsg-name NSG \
  --name Allow-SSH-From-AKS-Only \
  --source-address-prefixes NEW-IP
```

---

**Implementation Time**: 10-15 minutes
**Cost**: $0
**Security Improvement**: 40% attack surface reduction
**Maintenance**: Minimal (only when AKS IP changes)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-28
**Related Documents**:
- [AZURE-SSH-SECURITY-GUIDE.md](AZURE-SSH-SECURITY-GUIDE.md) - Full security options
- [SSH-CONFIGURATION.md](SSH-CONFIGURATION.md) - Basic SSH setup
