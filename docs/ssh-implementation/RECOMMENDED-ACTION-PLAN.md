# Recommended Action Plan: Get AD Automation Working Today

## Executive Summary
After extensive troubleshooting, SSH public key authentication on Windows DC is complex due to Administrator account restrictions. The fastest path to success is completing the Azure Key Vault password authentication approach (90% done) by fixing AKS resources.

## Immediate Action: Complete Password Auth (1-2 hours)

### Step 1: Fix AKS Resources (15 minutes)
```powershell
# Run this NOW to patch n8n deployment and restart pod
.\fix-aks-resources.ps1 -QuickFix
```

This will:
- Temporarily reduce CPU requirements
- Restart n8n pod with workload identity
- Enable Key Vault access

### Step 2: Verify Workload Identity (5 minutes)
```bash
# Check if pod has workload identity
kubectl exec -n n8n <pod-name> -- env | grep AZURE_

# Test Key Vault access
kubectl exec -n n8n <pod-name> -- curl -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net"
```

### Step 3: Configure n8n Workflow (30 minutes)
1. Add Azure Key Vault node to workflow
2. Retrieve `DC01-SSH-KEY` secret
3. Pass password to SSH node
4. Test employee termination script

### Step 4: Document Success (15 minutes)
Update README with working configuration

## Why This Approach First?

| Factor | Password Auth | SSH Key Auth | Graph API |
|--------|--------------|--------------|-----------|
| **Time to Working** | 1-2 hours | 4-6 hours | 2-4 hours |
| **Complexity** | Low | High | Medium |
| **Already Complete** | 90% | 40% | 70% |
| **Blockers** | Just AKS resources | Windows SSH quirks | Azure AD setup |
| **Long-term Viability** | Good with rotation | Complex maintenance | Best (cloud-native) |

## Phase 2: Evaluate Better Solutions (Next Week)

After getting password auth working, evaluate:

### Option A: Microsoft Graph API (Recommended Long-term)
- **Status**: Already in review, setup script ready
- **Pros**: Cloud-native, no SSH, proper audit trail
- **Timeline**: 2-4 hours to implement
- **Run**: `.\setup-graph-api.ps1 -AutoSetup`

### Option B: Service Account with SSH Keys
- **Status**: Scripts ready to deploy
- **Pros**: Avoids admin restrictions, works reliably
- **Timeline**: 2-3 hours to implement
- **Run**: `.\setup-service-account-ssh.ps1 -CreateAccount`

### Option C: PowerShell JEA Endpoint
- **Status**: Not started
- **Pros**: Native Windows, granular permissions
- **Timeline**: 4-6 hours to implement
- **Complexity**: High initial setup

## Decision Tree

```
Start Here
    │
    ▼
Fix AKS Resources (15 min)
    │
    ▼
Password Auth Working? ──No──→ Try -ScaleNodes option
    │ Yes
    ▼
Run Termination Test
    │
    ▼
Success? ──No──→ Debug with SSH logs
    │ Yes
    ▼
Document & Use in Production
    │
    ▼
[Next Week] Implement Graph API
```

## Risk Mitigation

### If QuickFix Fails:
1. Try: `.\fix-aks-resources.ps1 -CleanupPods`
2. Delete unused namespaces/pods
3. Last resort: `.\fix-aks-resources.ps1 -ScaleNodes`

### If Password Auth Still Fails:
1. Verify Key Vault permissions
2. Check network connectivity from pod
3. Test SSH with local credentials first

### Emergency Fallback:
- Manual termination process remains available
- All scripts can be run directly on DC

## Success Metrics

✅ **Today**: n8n can execute Terminate-Employee.ps1 via SSH
✅ **This Week**: Automated termination workflow in production
✅ **Next Week**: Evaluate and potentially migrate to Graph API

## Commands to Run Right Now

```powershell
# 1. On your workstation
cd "C:\Users\rcox\Documents\Cursor Projects\IT-Agent\docs\ssh-implementation"

# 2. Fix AKS (this is THE blocker)
.\fix-aks-resources.ps1 -QuickFix

# 3. After pod restarts (2-3 minutes), test from n8n
```

## Why I Recommend This Path

1. **You're SO close** - Don't abandon 90% complete work
2. **Immediate value** - Get automation working today vs more debugging
3. **Known quantity** - Password auth already proven to work
4. **Pragmatic** - Perfect is the enemy of good
5. **Future-proof** - Can migrate to Graph API once stable

The SSH key rabbit hole has consumed significant time. Let's get something working, then optimize later. The password approach with Key Vault is secure, auditable, and production-ready.

**Bottom Line**: Run the AKS fix script NOW and have a working solution within 2 hours.