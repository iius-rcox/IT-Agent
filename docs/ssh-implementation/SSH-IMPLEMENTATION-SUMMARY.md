# SSH-Based PowerShell Execution - Implementation Summary

**Date**: 2025-10-28
**Status**: Documentation Complete
**Implementation Time**: ~70 minutes (when following guides)

---

## Problem Identified

Your n8n instance runs in a **Linux container** on Azure Kubernetes Service (AKS), but the employee termination workflow requires executing Windows PowerShell scripts that interact with:
- Active Directory (Windows-only)
- Exchange Online (requires Exchange PowerShell module)
- Microsoft Graph API (certificate authentication in Windows cert store)

**Root Issue**: Linux containers cannot execute Windows PowerShell or access Windows-specific resources.

---

## Solution Implemented

**SSH-based remote execution**: n8n (Linux) connects to Windows Domain Controller via SSH to execute PowerShell scripts remotely.

### Architecture

```
┌─────────────────────────┐
│ n8n (Linux Container)   │
│ Azure Kubernetes (AKS)  │
└───────────┬─────────────┘
            │
            │ SSH (Port 22)
            │ Private Key Auth
            │
┌───────────▼─────────────┐
│ Windows Domain          │
│ Controller              │
│ ┌─────────────────────┐ │
│ │ OpenSSH Server      │ │
│ └──────────┬──────────┘ │
│            │             │
│ ┌──────────▼──────────┐ │
│ │ Terminate-          │ │
│ │ Employee.ps1        │ │
│ └─────────────────────┘ │
│ • Microsoft.Graph       │
│ • ExchangeOnline        │
│ • ActiveDirectory       │
└─────────────────────────┘
```

---

## Implementation Guides Created

All guides have been created and are ready to use:

### 1. PRE-IMPLEMENTATION-CHECKLIST.md
**Purpose**: Verify environment before starting
**Time**: 10 minutes
**Covers**:
- Domain Controller information
- Certificate verification
- PowerShell modules check
- Network connectivity
- Access permissions

### 2. SSH-CONFIGURATION.md
**Purpose**: Set up SSH on Windows DC
**Time**: 15-20 minutes
**Covers**:
- OpenSSH Server installation
- SSH key generation
- Key deployment and permissions
- Service configuration
- Connection testing

### 3. PS-SCRIPT-DC-DEPLOYMENT.md
**Purpose**: Deploy PowerShell script to DC
**Time**: 10-15 minutes
**Covers**:
- Script deployment via SCP
- Environment variable configuration
- Script testing on DC
- Permission setup
- Validation

### 4. N8N-SSH-CREDENTIALS-GUIDE.md
**Purpose**: Configure SSH credentials in n8n
**Time**: 5 minutes
**Covers**:
- Private key format
- Credential creation in n8n UI
- Connection testing
- Troubleshooting

### 5. N8N-WORKFLOW-SSH-UPDATE.md
**Purpose**: Update workflow to use SSH
**Time**: 15 minutes
**Covers**:
- Replace Execute Command with SSH node
- Update command syntax
- Fix JSON parsing
- Connect nodes properly
- Test execution

### 6. TESTING-VALIDATION-GUIDE.md
**Purpose**: Comprehensive testing
**Time**: 30-45 minutes
**Covers**:
- Component testing
- Integration testing
- Test user scenarios
- Error handling
- Performance validation

---

## Implementation Checklist

Follow these steps in order:

### Phase 1: Preparation (10 min)
- [ ] Read PRE-IMPLEMENTATION-CHECKLIST.md
- [ ] Document DC hostname/IP
- [ ] Verify certificate exists
- [ ] Verify PowerShell modules installed
- [ ] Test network connectivity

### Phase 2: SSH Setup (20 min)
- [ ] Follow SSH-CONFIGURATION.md
- [ ] Install OpenSSH on DC
- [ ] Generate SSH key pair
- [ ] Deploy public key to DC
- [ ] Test SSH connection

### Phase 3: Script Deployment (15 min)
- [ ] Follow PS-SCRIPT-DC-DEPLOYMENT.md
- [ ] Upload script to DC
- [ ] Set environment variables
- [ ] Test script execution
- [ ] Verify output format

### Phase 4: n8n Configuration (20 min)
- [ ] Follow N8N-SSH-CREDENTIALS-GUIDE.md
- [ ] Add SSH credentials
- [ ] Test connection from n8n
- [ ] Follow N8N-WORKFLOW-SSH-UPDATE.md
- [ ] Update workflow nodes
- [ ] Test workflow execution

### Phase 5: Testing (30 min)
- [ ] Follow TESTING-VALIDATION-GUIDE.md
- [ ] Run component tests
- [ ] Create test user
- [ ] Execute full termination test
- [ ] Verify results
- [ ] Test error scenarios

---

## Key Files

### Configuration Files
| File | Location | Purpose |
|------|----------|---------|
| Terminate-Employee.ps1 | `C:\Scripts\` on DC | Main termination script |
| administrators_authorized_keys | `C:\ProgramData\ssh\` on DC | SSH public keys |
| n8n workflow JSON | n8n instance | Workflow definition |
| SSH private key | n8n credentials | Authentication key |

### Environment Variables (DC)
```powershell
AZURE_TENANT_ID=953922e6-5370-4a01-a3d5-773a30df726b
AZURE_APP_ID=73b82823-d860-4bf6-938b-74deabeebab7
CERT_THUMBPRINT=DE0FF14C5EABA90BA328030A59662518A3673009
ORGANIZATION_DOMAIN=ii-us.com
AD_DISABLED_OU=OU=Disabled Users,DC=insulationsinc,DC=local
AD_BASE_DN=DC=insulationsinc,DC=local
```

---

## Quick Start Guide

If you're ready to implement immediately:

```bash
# 1. Start with pre-implementation checklist
# Complete all verification steps

# 2. Configure SSH (on DC)
# Install OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# 3. Generate SSH keys (local machine)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/n8n_dc_automation

# 4. Deploy public key to DC
# Copy ~/.ssh/n8n_dc_automation.pub content to DC:
# C:\ProgramData\ssh\administrators_authorized_keys

# 5. Deploy script to DC
scp -i ~/.ssh/n8n_dc_automation ~/Terminate-Employee.ps1 Administrator@DC:C:/Scripts/

# 6. Test SSH execution
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC "powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId TEST"

# 7. Configure n8n
# Add SSH credentials in n8n UI with private key

# 8. Update workflow
# Replace Execute Command with SSH node
# Set command: powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId {{ $json.employeeId }}

# 9. Test
# Trigger workflow and verify JSON response
```

---

## Common Issues and Solutions

### Issue: SSH connection fails
**Fix**: Verify sshd service running, firewall allows port 22, credentials correct

### Issue: PowerShell script not found
**Fix**: Verify path `C:\Scripts\Terminate-Employee.ps1`, check backslashes in command

### Issue: Certificate authentication fails
**Fix**: Verify certificate in `Cert:\LocalMachine\My`, check thumbprint matches

### Issue: JSON parse error
**Fix**: Update parser node to extract from `stdout` field, add `-NoProfile` to PowerShell command

### Issue: Workflow times out
**Fix**: Increase SSH node timeout to 300000ms (5 minutes), check DC performance

---

## Security Considerations

1. **SSH Key Management**
   - Private key stored only in n8n credentials
   - Rotate keys every 90-180 days
   - Use unique keys per application

2. **Certificate Security**
   - Monitor expiration date
   - Protect private key
   - Regular audits

3. **Access Control**
   - Limit SSH access by IP (optional)
   - Enable SSH logging
   - Review logs weekly

4. **Script Permissions**
   - Only Administrators can access `C:\Scripts\`
   - Environment variables at machine level
   - Consider transcript logging

---

## Monitoring Recommendations

### Daily
- Monitor n8n execution logs
- Check for failed terminations

### Weekly
- Review SSH access logs
- Verify workflow success rate
- Check DC performance

### Monthly
- Test with test user
- Review certificate expiration
- Update documentation as needed

### Quarterly
- Rotate SSH keys
- Update PowerShell modules
- Review and optimize script
- Team training refresh

---

## Alternative Approaches Considered

### 1. n8n Native Nodes (HTTP + LDAP)
**Pros**: Visual, easier to debug
**Cons**: Still requires PowerShell for Exchange mailbox operations
**Decision**: Rejected - doesn't solve core issue

### 2. Azure Automation Runbook
**Pros**: Centralized, managed, scalable
**Cons**: Additional cost, more complex setup
**Decision**: Valid alternative for future if centralization needed

### 3. Windows-based Sidecar Container
**Pros**: Low latency, same pod
**Cons**: Requires Windows node pool ($100-300/month), significant complexity
**Decision**: Rejected - too expensive

### 4. External API Endpoint
**Pros**: Clean separation, flexible
**Cons**: Additional service to maintain
**Decision**: Valid alternative for future if API layer needed

**Selected**: SSH approach - simplest, fastest, zero cost, leverages existing infrastructure

---

## Success Criteria

✅ **Implementation Complete When**:
- SSH connection from n8n to DC works
- PowerShell script executes via SSH
- Test user termination succeeds
- All operations complete (AD disable, mailbox conversion, group removal, OU move)
- JSON response returns correctly
- Error scenarios handled appropriately
- Team trained on new process

✅ **Production Ready When**:
- All tests pass
- Documentation complete
- Monitoring configured
- Backup/rollback plan ready
- Performance acceptable
- User acceptance testing complete

---

## Rollback Plan

If issues occur:

1. **Immediate Rollback** (< 5 minutes):
   - Disable SSH node in n8n workflow
   - Re-enable original Execute Command node
   - Note: Original approach won't work on Linux, but allows time to troubleshoot

2. **Manual Processing** (interim):
   - Document steps in runbook
   - Execute PowerShell script manually on DC when needed
   - Maintain audit trail

3. **Fix Forward**:
   - Review error logs
   - Fix specific issue
   - Re-test
   - Re-enable SSH approach

---

## Next Steps

### Immediate (Now)
1. Review all guides
2. Schedule implementation window
3. Gather team for implementation

### Implementation (Day 1)
1. Follow guides in order
2. Complete all phases
3. Test thoroughly
4. Document any issues

### Post-Implementation (Day 2+)
1. Monitor execution logs
2. Gather team feedback
3. Refine documentation
4. Plan monitoring/alerting

### Long-term (Month 1+)
1. Regular testing with test users
2. Key rotation schedule
3. Performance optimization
4. Consider automation improvements

---

## Support and Troubleshooting

### Primary Resources
1. Implementation guides (this directory)
2. SSH-CONFIGURATION.md troubleshooting section
3. TESTING-VALIDATION-GUIDE.md error scenarios

### Escalation Path
1. Check guide troubleshooting sections
2. Review n8n execution logs
3. Check DC SSH logs: `Get-WinEvent -LogName 'OpenSSH/Operational'`
4. Test components individually
5. Review this summary for common issues

---

## Document Maintenance

**Review Schedule**: Quarterly
**Update Triggers**:
- Infrastructure changes
- n8n version updates
- PowerShell module updates
- Security policy changes
- Lessons learned from incidents

**Version History**:
- v1.0 (2025-10-28): Initial implementation documentation

---

## Team Training Checklist

Ensure team members can:
- [ ] Locate and read implementation guides
- [ ] Understand SSH-based architecture
- [ ] Test SSH connectivity
- [ ] Execute workflow from n8n UI
- [ ] Interpret JSON responses
- [ ] Handle common errors
- [ ] Know escalation path
- [ ] Access monitoring dashboards

---

## Conclusion

**Status**: ✅ **Documentation Complete**

All implementation guides have been created. You're ready to proceed with the SSH-based PowerShell execution setup for your employee termination workflow.

**Estimated Total Time**: 70 minutes
**Cost**: $0 (uses existing infrastructure)
**Complexity**: Medium
**Risk**: Low (with proper testing)

**Start Here**: [PRE-IMPLEMENTATION-CHECKLIST.md](PRE-IMPLEMENTATION-CHECKLIST.md)

---

**Questions or Issues?**
Refer to the troubleshooting sections in each guide, or review common issues in this summary.

**Ready to Deploy?**
Follow the Implementation Checklist section above, starting with Phase 1.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-28
**Related Project**: SSH PowerShell Execution for n8n (Archon Project ID: d71729f0-26af-44c5-8f6c-6970425c7186)
