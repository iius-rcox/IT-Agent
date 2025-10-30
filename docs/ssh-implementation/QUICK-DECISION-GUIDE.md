# Quick Decision Guide: AD Management from n8n

## Your Current Situation
- **Goal**: Manage Active Directory from n8n (employee termination workflows)
- **Environment**: On-premises Windows DC + Azure Kubernetes Service (AKS)
- **Current Blocker**: SSH public key auth failing, considering alternatives

## Top 3 Solutions - Quick Comparison

### 🥇 Option 1: Microsoft Graph API (If you have Azure AD)
**Setup Time**: 2-3 hours
**Command to Check**:
```powershell
# On DC: Check if Azure AD Connect is installed
Get-Service "ADSync" -ErrorAction SilentlyContinue
```

**If YES** → This is your best option!
- Use n8n's Microsoft Entra ID node
- No firewall/SSH issues
- Works immediately from cloud

**Quick Setup**:
1. Create Azure App Registration
2. Configure n8n Microsoft OAuth2 credential
3. Use Microsoft Entra ID node in workflows

---

### 🥈 Option 2: Direct LDAP Connection
**Setup Time**: 1-2 hours
**Command to Test**:
```powershell
# On DC: Check if LDAP is accessible
Test-NetConnection -ComputerName localhost -Port 389
```

**Best for**: Real-time AD changes without Azure
- Use n8n's LDAP node
- Industry standard protocol
- Direct connection to DC

**Quick Setup**:
1. Enable LDAPS (secure LDAP) on port 636
2. Create service account for LDAP
3. Configure n8n LDAP credential
4. Use LDAP node in workflows

---

### 🥉 Option 3: Complete Current SSH Approach
**Setup Time**: 1 hour (you're 80% done)
**Your Progress**: Password auth working, Key Vault configured

**Quick Fix**:
1. Scale AKS nodes: `az aks nodepool scale -g rg_prod --cluster-name dev-aks -n systempool --node-count 4`
2. Grant Key Vault access (run the command in docs)
3. Restart n8n pod
4. Use password auth (skip public keys)

---

## Decision Flowchart

```
Start Here
    ↓
Do you have Azure AD Connect configured?
    ├─ YES → Use Microsoft Graph API ✅
    │
    ├─ NO → Can you open LDAPS port (636)?
    │        ├─ YES → Use Direct LDAP ✅
    │        │
    │        └─ NO → Complete SSH Setup ✅
    │
    └─ NOT SURE → Check with:
                  Get-Service "ADSync"
```

## One Command to Decide

Run this on your Domain Controller:

```powershell
# Quick environment check
Write-Host "=== AD Management Options Check ===" -ForegroundColor Cyan

# Check Azure AD Connect
if (Get-Service "ADSync" -ErrorAction SilentlyContinue) {
    Write-Host "✅ Azure AD Connect found - Use Microsoft Graph API" -ForegroundColor Green
} else {
    Write-Host "❌ No Azure AD Connect" -ForegroundColor Yellow
}

# Check LDAP
if (Test-NetConnection -ComputerName localhost -Port 389 -InformationLevel Quiet) {
    Write-Host "✅ LDAP available - Can use Direct LDAP" -ForegroundColor Green
} else {
    Write-Host "❌ LDAP not accessible" -ForegroundColor Red
}

# Check SSH
if (Get-Service sshd -ErrorAction SilentlyContinue) {
    Write-Host "✅ SSH configured - Current approach viable" -ForegroundColor Green
} else {
    Write-Host "❌ SSH not configured" -ForegroundColor Red
}
```

## Immediate Next Step Based on Your Situation

Since you've already invested time in SSH and it's partially working:

### Complete SSH First (1 hour)
```bash
# 1. Fix AKS resources
az aks nodepool scale -g rg_prod --cluster-name dev-aks -n systempool --node-count 4

# 2. Grant Key Vault access
az role assignment create \
  --assignee 9c1b71c4-7355-47ad-8e17-49d1e49aeb65 \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/a78954fe-f6fe-4279-8be0-2c748be2f266/resourceGroups/rg_prod/providers/Microsoft.KeyVault/vaults/iius-akv"

# 3. Restart n8n
kubectl rollout restart deployment/n8n -n n8n-prod

# 4. Test the workflow
```

### Then Evaluate Better Options
Once SSH is working, evaluate Microsoft Graph or LDAP for long-term:
- More reliable
- Better security
- Easier maintenance

## My Recommendation

**For immediate needs**: Complete SSH setup (you're almost done!)

**For production**: Implement Microsoft Graph API if you have Azure AD, otherwise LDAP

**Why**: SSH to Windows DC is always problematic. Microsoft Graph or LDAP are purpose-built for AD management.

---

**Need help?** Start with completing SSH (1 hour), then we can implement the better solution (2-3 hours).