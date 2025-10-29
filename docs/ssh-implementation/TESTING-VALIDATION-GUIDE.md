# Testing and Validation Guide
## SSH-Based Employee Termination Workflow

**Purpose**: Comprehensive testing procedures for validating the SSH-based employee termination workflow.

**Prerequisites**: All setup steps completed
- [PRE-IMPLEMENTATION-CHECKLIST.md](PRE-IMPLEMENTATION-CHECKLIST.md) ✅
- [SSH-CONFIGURATION.md](SSH-CONFIGURATION.md) ✅
- [PS-SCRIPT-DC-DEPLOYMENT.md](PS-SCRIPT-DC-DEPLOYMENT.md) ✅
- [N8N-WORKFLOW-SSH-UPDATE.md](N8N-WORKFLOW-SSH-UPDATE.md) ✅

**Estimated Time**: 30-45 minutes

---

## Testing Strategy

### Test Levels

1. **Unit Tests**: Individual component testing
   - SSH connectivity
   - PowerShell script execution
   - JSON parsing

2. **Integration Tests**: End-to-end workflow testing
   - Webhook trigger → Script execution → Response
   - Error handling scenarios

3. **User Acceptance Tests**: Real-world scenarios
   - Test user termination
   - Production-like conditions

---

## Phase 1: Component Testing

### Test 1.1: SSH Connectivity

**Purpose**: Verify SSH connection from n8n to DC

**Steps**:
```bash
# From local machine
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -Command 'Write-Output SSH-Test-Success'"
```

**Expected Result**:
```
SSH-Test-Success
```

**✅ Pass Criteria**: Command executes and returns expected output
**❌ Fail**: See SSH-CONFIGURATION.md troubleshooting

---

### Test 1.2: PowerShell Script Syntax

**Purpose**: Verify script has no syntax errors

**Steps**:
```bash
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -Command 'Test-Path C:\Scripts\Terminate-Employee.ps1'"
```

**Expected Result**:
```
True
```

**✅ Pass Criteria**: Returns True
**❌ Fail**: Script not deployed - see PS-SCRIPT-DC-DEPLOYMENT.md

---

### Test 1.3: Environment Variables

**Purpose**: Verify all required environment variables are set on DC

**Steps**:
```bash
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -Command '\$env:AZURE_TENANT_ID'"
```

**Expected Result**:
```
953922e6-5370-4a01-a3d5-773a30df726b
```

**Repeat for all variables**:
- `AZURE_TENANT_ID`
- `AZURE_APP_ID`
- `CERT_THUMBPRINT`
- `ORGANIZATION_DOMAIN`
- `AD_DISABLED_OU`

**✅ Pass Criteria**: All variables return correct values
**❌ Fail**: Re-set environment variables on DC

---

### Test 1.4: Certificate Authentication

**Purpose**: Verify certificate can authenticate to Graph/Exchange

**Steps**:
```bash
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -Command 'Connect-MgGraph -ClientId \$env:AZURE_APP_ID -TenantId \$env:AZURE_TENANT_ID -CertificateThumbprint \$env:CERT_THUMBPRINT; Get-MgUser -Top 1 | Select-Object DisplayName'"
```

**Expected Result**:
```
DisplayName
-----------
Some User Name
```

**✅ Pass Criteria**: Connects and returns a user
**❌ Fail**: Check certificate and Azure AD app permissions

---

### Test 1.5: PowerShell Modules

**Purpose**: Verify all required modules load correctly

**Steps**:
```bash
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -Command 'Import-Module Microsoft.Graph, ExchangeOnlineManagement, ActiveDirectory; Write-Output Modules-Loaded'"
```

**Expected Result**:
```
Modules-Loaded
```

**✅ Pass Criteria**: No errors, "Modules-Loaded" displayed
**❌ Fail**: Install missing modules on DC

---

## Phase 2: Script Testing

### Test 2.1: Script Execution with Invalid Employee ID

**Purpose**: Verify script handles non-existent users gracefully

**Steps**:
```bash
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId INVALID999 -SupervisorEmail test@ii-us.com"
```

**Expected Result** (JSON):
```json
{
  "success": false,
  "employeeId": "INVALID999",
  "employeeName": null,
  "operations": {
    "adLookup": {
      "success": false,
      "message": "User not found in AD"
    }
  },
  "errors": ["User with Employee ID INVALID999 not found in Active Directory"],
  "timestamp": "2025-10-28T..."
}
```

**✅ Pass Criteria**:
- Returns valid JSON
- `success: false`
- Error message clear and descriptive

---

### Test 2.2: Script Execution Time

**Purpose**: Verify script completes within acceptable time

**Steps**:
```bash
time ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId TEST123 -SupervisorEmail test@ii-us.com"
```

**Expected Result**:
```
real    0m15.234s  # Should be < 2 minutes
user    0m0.123s
sys     0m0.045s
```

**✅ Pass Criteria**: Completes in under 2 minutes (120 seconds)
**❌ Fail**: Check DC performance, network latency

---

## Phase 3: n8n Workflow Testing

### Test 3.1: SSH Node Configuration

**Purpose**: Verify SSH node is properly configured in workflow

**Steps**:
1. Open n8n workflow
2. Click on SSH node (Execute Termination via SSH)
3. Review configuration

**Expected Configuration**:
- ✅ Credentials: `DC-PowerShell-Automation`
- ✅ Command contains: `powershell.exe -File C:\Scripts\Terminate-Employee.ps1`
- ✅ Parameters use n8n expressions: `{{ $json.employeeId }}`
- ✅ Node is connected to previous and next nodes

**✅ Pass Criteria**: All checkboxes verified

---

### Test 3.2: Parser Node Testing

**Purpose**: Verify parser correctly extracts JSON from SSH output

**Steps**:
1. In n8n workflow, click on "Parse PowerShell Results" node
2. Click "Execute node"
3. Provide test input:
```json
{
  "stdout": "{\"success\": false, \"employeeId\": \"TEST\"}",
  "stderr": "",
  "exitCode": 0
}
```

**Expected Output**:
```json
{
  "success": false,
  "employeeId": "TEST"
}
```

**✅ Pass Criteria**: JSON correctly parsed from stdout
**❌ Fail**: Update parser node code (see N8N-WORKFLOW-SSH-UPDATE.md)

---

### Test 3.3: Manual Workflow Execution

**Purpose**: Test complete workflow with manual trigger

**Steps**:
1. Open n8n workflow
2. Click on webhook or manual trigger node
3. Click "Execute Workflow"
4. Provide test payload:
```json
{
  "employeeId": "TEST123",
  "supervisorEmail": "test@ii-us.com",
  "reason": "Manual test execution",
  "ticketNumber": "TEST001"
}
```
5. Review execution results

**Expected Result**:
- ✅ All nodes execute successfully
- ✅ SSH node shows stdout with JSON
- ✅ Parser extracts JSON correctly
- ✅ Final response contains termination results

**✅ Pass Criteria**: Workflow completes without errors, JSON response received

---

### Test 3.4: Webhook Trigger Testing

**Purpose**: Test workflow via webhook (production-like)

**Steps**:
1. Get webhook URL from n8n workflow
2. Execute curl command:
```bash
curl -X POST https://n8n.ii-us.com/webhook/employee-termination \
  -H "Content-Type: application/json" \
  -d '{
    "employeeId": "TEST456",
    "supervisorEmail": "manager@ii-us.com",
    "reason": "Webhook test",
    "ticketNumber": "WH-TEST-001"
  }'
```

**Expected Result** (HTTP 200):
```json
{
  "success": false,
  "employeeId": "TEST456",
  "message": "User not found in AD",
  "operations": { ... }
}
```

**✅ Pass Criteria**:
- HTTP 200 status code
- JSON response received
- Response matches expected structure

---

## Phase 4: Test User Scenarios

### Test 4.1: Create Test User

**Purpose**: Create a complete test user for full termination testing

**Steps on DC**:
```powershell
# 1. Create AD user
$testPassword = ConvertTo-SecureString "Test123Pass!" -AsPlainText -Force
New-ADUser -Name "Test Termination User" `
           -GivenName "Test" `
           -Surname "Term" `
           -SamAccountName "testterm99" `
           -UserPrincipalName "testterm99@ii-us.com" `
           -EmployeeID "999999" `
           -AccountPassword $testPassword `
           -Enabled $true `
           -Path "CN=Users,DC=insulationsinc,DC=local"

# 2. Sync to Azure AD
Start-ADSyncSyncCycle -PolicyType Delta

# Wait 3-5 minutes for sync

# 3. Verify in Azure AD
Connect-MgGraph -ClientId $env:AZURE_APP_ID -TenantId $env:AZURE_TENANT_ID -CertificateThumbprint $env:CERT_THUMBPRINT
Get-MgUser -Filter "userPrincipalName eq 'testterm99@ii-us.com'"

# 4. Assign a test license (optional, for full testing)
# Use Azure portal or PowerShell to assign Microsoft 365 E3 or similar

# 5. Create a test group membership
New-ADGroup -Name "Test-Termination-Group" -GroupScope Global -GroupCategory Security
Add-ADGroupMember -Identity "Test-Termination-Group" -Members "testterm99"
```

**✅ Pass Criteria**:
- User created in AD with Employee ID 999999
- User synced to Azure AD
- User has at least one license (optional)
- User is member of at least one group

---

### Test 4.2: Full Termination Test

**Purpose**: Execute complete termination on test user

**Steps**:
```bash
# Execute via webhook
curl -X POST https://n8n.ii-us.com/webhook/employee-termination \
  -H "Content-Type: application/json" \
  -d '{
    "employeeId": "999999",
    "supervisorEmail": "your-email@ii-us.com",
    "reason": "Full termination test",
    "ticketNumber": "FULL-TEST-001"
  }'
```

**Expected Result**:
```json
{
  "success": true,
  "employeeId": "999999",
  "employeeName": "Test Termination User",
  "userPrincipalName": "testterm99@ii-us.com",
  "operations": {
    "adLookup": { "success": true, "message": "User found: Test Termination User" },
    "m365Lookup": { "success": true, "message": "User found in M365" },
    "licenseRemoval": { "success": true, "licensesRemoved": 1, "message": "Removed 1 licenses" },
    "mailboxConversion": { "success": true, "message": "Mailbox converted to shared" },
    "supervisorAccess": { "success": true, "message": "Granted your-email@ii-us.com full access" },
    "adDisable": { "success": true, "message": "Account disabled" },
    "groupRemoval": { "success": true, "groupsRemoved": 1, "message": "Removed from 1 groups" },
    "ouMove": { "success": true, "message": "Moved to OU=Disabled Users,..." }
  },
  "errors": [],
  "timestamp": "2025-10-28T..."
}
```

**✅ Pass Criteria**: `success: true` and all operations succeeded

---

### Test 4.3: Verify Termination Results

**Purpose**: Manually verify all termination operations completed

**Steps**:
```powershell
# 1. Check AD account status
Get-ADUser -Filter {EmployeeID -eq "999999"} -Properties Enabled, DistinguishedName, memberOf |
    Select-Object Name, Enabled, DistinguishedName, @{N='Groups';E={$_.memberOf.Count}}

# Expected:
# Enabled: False
# DistinguishedName: CN=Test Termination User,OU=Disabled Users,...
# Groups: 0

# 2. Check mailbox status
Get-Mailbox -Identity "testterm99@ii-us.com" |
    Select-Object DisplayName, RecipientTypeDetails

# Expected: RecipientTypeDetails: SharedMailbox

# 3. Check supervisor access
Get-MailboxPermission -Identity "testterm99@ii-us.com" |
    Where-Object {$_.User -like "*your-email*"}

# Expected: AccessRights contains "FullAccess"

# 4. Check licenses (Azure AD)
Get-MgUserLicenseDetail -UserId "testterm99@ii-us.com"

# Expected: No licenses or empty result
```

**✅ Pass Criteria**:
- Account disabled ✅
- Moved to Disabled OU ✅
- Removed from all groups ✅
- Mailbox converted to shared ✅
- Supervisor has access ✅
- Licenses removed ✅

---

### Test 4.4: Cleanup Test User

**Purpose**: Remove test user after successful testing

**Steps**:
```powershell
# Remove test user from AD
Remove-ADUser -Identity "testterm99" -Confirm:$false

# Remove from Azure AD (if still present)
Remove-MgUser -UserId "testterm99@ii-us.com"

# Remove test group
Remove-ADGroup -Identity "Test-Termination-Group" -Confirm:$false
```

---

## Phase 5: Error Scenario Testing

### Test 5.1: Invalid Supervisor Email

**Purpose**: Verify workflow handles invalid supervisor emails

**Input**:
```json
{
  "employeeId": "999999",
  "supervisorEmail": "invalid-email-that-does-not-exist@ii-us.com",
  "reason": "Test invalid supervisor",
  "ticketNumber": "ERR-TEST-001"
}
```

**Expected Result**:
```json
{
  "success": false,  // or partial success
  "operations": {
    "supervisorAccess": {
      "success": false,
      "message": "Failed to grant supervisor access: ..."
    }
  }
}
```

**✅ Pass Criteria**: Error handled gracefully, other operations still complete

---

### Test 5.2: SSH Connection Failure

**Purpose**: Test behavior when SSH connection fails

**Steps**:
1. Temporarily stop SSH service on DC:
```powershell
Stop-Service sshd
```
2. Trigger workflow
3. Observe error handling
4. Restart SSH:
```powershell
Start-Service sshd
```

**Expected Result**:
- Workflow reports connection error
- Error message is clear
- No partial state changes

**✅ Pass Criteria**: Error caught and reported properly

---

### Test 5.3: Certificate Expiration

**Purpose**: Verify script handles expired/invalid certificates

**Steps**: (Simulation - don't actually break prod certificate!)
1. Note that in production, monitor certificate expiration
2. Test behavior should include clear error message

**Expected Behavior**:
- Script reports authentication failure
- Error includes certificate-related message

---

### Test 5.4: Timeout Scenario

**Purpose**: Test workflow behavior if script takes too long

**Steps**:
1. Modify SSH node timeout to very short value (e.g., 5000ms)
2. Execute workflow
3. Observe timeout handling
4. Restore normal timeout (300000ms)

**Expected Result**:
- Timeout error reported
- Workflow fails gracefully
- No hanging state

---

## Phase 6: Performance Testing

### Test 6.1: Response Time Measurement

**Purpose**: Measure end-to-end response time

**Steps**:
```bash
# Measure 5 executions
for i in {1..5}; do
  echo "Test $i:"
  time curl -X POST https://n8n.ii-us.com/webhook/employee-termination \
    -H "Content-Type: application/json" \
    -d '{"employeeId":"TEST'$i'","supervisorEmail":"test@ii-us.com","reason":"Perf test","ticketNumber":"PERF-'$i'"}'
  echo ""
done
```

**Expected Results**:
- Average response time: 15-30 seconds
- 95th percentile: < 45 seconds
- No timeouts

**✅ Pass Criteria**: All requests complete within 60 seconds

---

### Test 6.2: Concurrent Execution

**Purpose**: Test handling of simultaneous termination requests

**Steps**:
```bash
# Execute 3 requests concurrently
curl -X POST https://n8n.ii-us.com/webhook/employee-termination -d '{"employeeId":"TEST1","supervisorEmail":"test@ii-us.com"}' &
curl -X POST https://n8n.ii-us.com/webhook/employee-termination -d '{"employeeId":"TEST2","supervisorEmail":"test@ii-us.com"}' &
curl -X POST https://n8n.ii-us.com/webhook/employee-termination -d '{"employeeId":"TEST3","supervisorEmail":"test@ii-us.com"}' &
wait
```

**Expected Result**:
- All requests complete successfully
- No resource contention errors
- Each returns appropriate response

**✅ Pass Criteria**: All concurrent requests handled correctly

---

## Validation Checklist

### Pre-Production Checklist

Before deploying to production, verify:

**Infrastructure**:
- [ ] SSH service running and set to auto-start on DC
- [ ] Firewall rules allow SSH traffic from AKS
- [ ] Certificate valid for > 90 days
- [ ] PowerShell modules up to date
- [ ] Environment variables set correctly
- [ ] Backup of workflow JSON exported

**Workflow**:
- [ ] SSH node configured with correct credentials
- [ ] Command syntax correct (including backslashes)
- [ ] Parser node extracts JSON from stdout
- [ ] Error handling catches all failure scenarios
- [ ] Response node returns proper HTTP status codes
- [ ] Workflow saved and activated

**Testing**:
- [ ] All Phase 1 tests (components) pass
- [ ] All Phase 2 tests (script) pass
- [ ] All Phase 3 tests (workflow) pass
- [ ] Test user termination successful
- [ ] All error scenarios handled
- [ ] Performance acceptable

**Documentation**:
- [ ] All setup guides completed
- [ ] Troubleshooting procedures documented
- [ ] Rollback plan ready
- [ ] Monitoring configured
- [ ] Team trained on new process

---

## Monitoring and Maintenance

### Ongoing Monitoring

**Weekly**:
- Review n8n execution logs
- Check SSH connection success rate
- Monitor script execution times

**Monthly**:
- Test termination with test user
- Verify certificate expiration date
- Review and update documentation

**Quarterly**:
- Rotate SSH keys
- Update PowerShell modules
- Review and optimize script

---

## Troubleshooting Quick Reference

| Issue | Check | Fix |
|-------|-------|-----|
| SSH connection fails | SSH service running? | Restart sshd |
| Authentication error | Credentials correct? | Re-check SSH credentials in n8n |
| Script not found | Path correct? | Verify `C:\Scripts\Terminate-Employee.ps1` |
| Certificate error | Cert valid? | Check expiration, re-import if needed |
| Slow execution | DC performance? | Check CPU/memory on DC |
| No output | Script runs? | Test script manually on DC |
| JSON parse error | Output format? | Check for non-JSON text in stdout |

---

## Success Criteria Summary

✅ **Implementation Success**:
- All 6 testing phases pass
- Test user termination completes successfully
- Error scenarios handled appropriately
- Performance within acceptable range
- Team confident in new process

✅ **Ready for Production**:
- All checklist items verified
- Backup and rollback plan ready
- Monitoring configured
- Documentation complete

---

**Document Version**: 1.0
**Last Updated**: 2025-10-28
**Related Documents**:
- All setup guides (PRE-IMPLEMENTATION through N8N-WORKFLOW-SSH-UPDATE)
- [POWERSHELL-DEPLOYMENT-GUIDE.md](POWERSHELL-DEPLOYMENT-GUIDE.md)
- [SSH-CONFIGURATION.md](SSH-CONFIGURATION.md)
