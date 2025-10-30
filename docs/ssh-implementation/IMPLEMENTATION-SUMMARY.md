# SSH Implementation Summary & Recommendations

**Date:** October 30, 2025
**Project:** Azure Key Vault SSH Password Authentication for n8n
**Status:** Partially Implemented - Blocked by AKS Resources

## Executive Summary

After extensive troubleshooting (~4 hours), public key SSH authentication to Windows Domain Controller is blocked by DC-specific security policies. The team has successfully pivoted to password-based authentication using Azure Key Vault for secure credential management.

## Current Implementation Status

### ✅ Completed
- Network connectivity (Azure NSG configured for pod CIDR 10.244.0.0/16)
- SSH service running on DC (OpenSSH 9.5)
- Password authentication confirmed working
- Azure Key Vault secret created (`DC01-SSH-KEY`)
- Managed Identity created (`n8n-keyvault-identity`)
- Workload Identity federated credential configured
- Service account annotated with workload identity

### ⏳ Pending
- Grant Key Vault access to managed identity (command ready)
- Restart n8n pod (blocked by cluster CPU resources)
- Test end-to-end workflow with Key Vault integration
- Update n8n workflow with Key Vault nodes

### ❌ Abandoned
- Public key authentication for Administrator account (DC security restriction)

## Root Cause Analysis

### Why Public Key Auth Failed
1. **Windows Server Domain Controller Restrictions**: DCs have enhanced security policies that block SSH key authentication for Administrator accounts
2. **Match Group administrators Block**: The sshd_config section for administrators has special handling that appears to reject key auth
3. **No Detailed Logs**: Connection resets immediately after protocol negotiation, before auth methods are attempted

### Key Learning
- **Network Issue Resolution**: Azure CNI Overlay means pods use different CIDR (10.244.0.0/16) than node subnet (10.0.3.0/24)
- **DC Security**: Domain Controllers have stricter authentication policies than regular Windows Servers
- **Password Auth Works**: Confirms SSH service and network are properly configured

## Recommended Solution Path

### Phase 1: Complete Current Implementation (1-2 days)
```bash
# 1. Free up AKS resources (scale nodes or clean up pods)
az aks nodepool scale -g rg_prod --cluster-name dev-aks -n systempool --node-count 4

# 2. Grant Key Vault access
az role assignment create \
  --assignee 9c1b71c4-7355-47ad-8e17-49d1e49aeb65 \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/a78954fe-f6fe-4279-8be0-2c748be2f266/resourceGroups/rg_prod/providers/Microsoft.KeyVault/vaults/iius-akv"

# 3. Restart n8n pod
kubectl rollout restart deployment/n8n -n n8n-prod

# 4. Test workflow
```

### Phase 2: Implement Service Account (3-5 days)
Create dedicated `svc-n8n-ssh` account with:
- Constrained delegation permissions
- SSH key authentication (works for non-admin users)
- Principle of least privilege
- Better security than Administrator account

### Phase 3: Consider JEA Endpoint (1 week)
PowerShell Just Enough Administration provides:
- Native Windows security model
- No SSH dependencies
- Granular permission control
- Superior audit logging
- Role-based access control

## Alternative Solutions Matrix

| Solution | Implementation Time | Security Level | Maintenance | Recommendation |
|----------|-------------------|----------------|-------------|----------------|
| **Key Vault + Password** | 1 day | Medium | Medium | ✅ Complete this |
| **Service Account + Keys** | 3 days | High | Low | ✅ Implement next |
| **JEA Endpoint** | 1 week | Very High | Low | Consider for future |
| **Certificate SSH** | 2 days | High | Medium | If service account fails |
| **WinRM + Certs** | 3 days | High | High | Complex, avoid |
| **Azure Arc** | 1 week | Very High | Low | Long-term strategy |

## Critical Next Steps

### Immediate Actions (Today)
1. **Resolve AKS resource issue** to unblock n8n pod restart
2. **Run Key Vault role assignment** command
3. **Test token retrieval** from IMDS endpoint
4. **Verify Key Vault secret access**

### Short-term Actions (This Week)
1. **Complete password-based workflow** testing
2. **Create service account** for better security
3. **Test service account** SSH key authentication
4. **Document working solution**

### Medium-term Actions (This Month)
1. **Implement password rotation** automation
2. **Evaluate JEA endpoint** approach
3. **Set up monitoring** for SSH access
4. **Create runbook** for troubleshooting

## Risk Mitigation

### Current Risks
1. **Cluster Resources**: n8n pod can't restart - blocking entire implementation
2. **Password in Key Vault**: Less secure than key auth but acceptable with rotation
3. **Administrator Account**: Using high-privilege account for automation

### Mitigation Strategies
1. **Add AKS user pool** with autoscaling per performance recommendations
2. **Implement 90-day password rotation** with automated workflow
3. **Move to service account** with constrained permissions ASAP

## Troubleshooting Checklist

If issues persist after implementation:

- [ ] Verify workload identity labels on pod
- [ ] Check IMDS token endpoint (http://169.254.169.254/metadata/identity/oauth2/token)
- [ ] Confirm Key Vault role assignment
- [ ] Test network connectivity (nc -zv 10.0.0.200 22)
- [ ] Check SSH service status on DC
- [ ] Review Azure NSG rules
- [ ] Examine n8n pod logs
- [ ] Verify Key Vault secret exists and is accessible

## Documentation Updates Needed

1. Update README with new password-based approach
2. Document Key Vault integration steps
3. Create password rotation runbook
4. Archive public key authentication attempts
5. Create troubleshooting guide for common issues

## Lessons Learned

1. **Start Simple**: Password auth should have been tested first
2. **DC Restrictions**: Domain Controllers have unique security constraints
3. **Pod Networking**: Understanding Azure CNI Overlay is critical
4. **Multiple Approaches**: Having fallback options is essential
5. **Resource Planning**: Ensure cluster has capacity before deployments

## Success Metrics

- [ ] n8n successfully retrieves password from Key Vault
- [ ] SSH connection established to DC
- [ ] Employee termination script executes successfully
- [ ] Audit logs show proper authentication trail
- [ ] Password rotation implemented and tested

## Contact for Support

- **Azure Issues**: Check AKS cluster health, Key Vault access logs
- **DC Issues**: Review Event Viewer, SSH service logs
- **n8n Issues**: Check pod logs, workflow execution history
- **Network Issues**: Verify NSG rules, test with nc/telnet

---

**Next Review Date:** November 6, 2025
**Project Status:** In Progress - Awaiting Resource Resolution