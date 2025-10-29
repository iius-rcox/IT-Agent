# PowerShell Script Deployment Guide for Domain Controller

**Purpose**: Deploy and test the `Terminate-Employee.ps1` script on your Windows Domain Controller.

**Prerequisites**:
- Complete [PRE-IMPLEMENTATION-CHECKLIST.md](PRE-IMPLEMENTATION-CHECKLIST.md)
- Complete [SSH-CONFIGURATION.md](SSH-CONFIGURATION.md)

**Estimated Time**: 10-15 minutes

---

## Overview

This guide walks through deploying the employee termination PowerShell script to your Domain Controller, where it will be executed via SSH from n8n.

**Deployment Path**: `C:\Scripts\Terminate-Employee.ps1`

---

## Phase 1: Prepare the Script

### Step 1.1: Extract Script from Documentation

The complete PowerShell script is available in [POWERSHELL-DEPLOYMENT-GUIDE.md](POWERSHELL-DEPLOYMENT-GUIDE.md), lines 78-315.

**Option A**: Copy directly from that file
**Option B**: Use the script extraction command below

### Step 1.2: Create Local Script File

On your **local machine** (not the DC yet), create a file:

**Windows PowerShell**:
```powershell
# Create script locally first for review
$scriptPath = "$env:USERPROFILE\Downloads\Terminate-Employee.ps1"

# Read script content from POWERSHELL-DEPLOYMENT-GUIDE.md (lines 78-315)
# For now, create empty file - you'll paste content next
New-Item -Path $scriptPath -ItemType File -Force

# Open in notepad for editing
notepad $scriptPath
```

**Linux/macOS**:
```bash
# Create script locally
touch ~/Downloads/Terminate-Employee.ps1

# Open in editor
nano ~/Downloads/Terminate-Employee.ps1
# or
code ~/Downloads/Terminate-Employee.ps1
```

### Step 1.3: Copy Script Content

1. Open [POWERSHELL-DEPLOYMENT-GUIDE.md](POWERSHELL-DEPLOYMENT-GUIDE.md)
2. Copy lines 78-315 (the complete PowerShell script)
3. Paste into `Terminate-Employee.ps1` file
4. Save the file

### Step 1.4: Verify Script Syntax Locally (Optional)

If you have PowerShell available locally:

```powershell
# Test syntax without executing
powershell.exe -NoProfile -File "$env:USERPROFILE\Downloads\Terminate-Employee.ps1" -EmployeeId "TEST" -WhatIf

# Should not show any syntax errors
```

---

## Phase 2: Prepare Domain Controller

### Step 2.1: Verify Prerequisites on DC

SSH into your DC and verify prerequisites:

```bash
# SSH to DC
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME

# Now you're on the DC - run these PowerShell commands:
```

```powershell
# Check PowerShell version (should be 5.1+)
$PSVersionTable.PSVersion

# Check if required modules are installed
$requiredModules = @("Microsoft.Graph", "ExchangeOnlineManagement", "ActiveDirectory")
foreach ($module in $requiredModules) {
    $installed = Get-Module -ListAvailable -Name $module
    if ($installed) {
        Write-Host "✓ $module installed (Version: $($installed[0].Version))" -ForegroundColor Green
    } else {
        Write-Host "✗ $module NOT installed" -ForegroundColor Red
    }
}

# Check certificate (replace thumbprint with yours from checklist)
$certThumbprint = "DE0FF14C5EABA90BA328030A59662518A3673009"
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Thumbprint -eq $certThumbprint}
if ($cert) {
    Write-Host "✓ Certificate found" -ForegroundColor Green
    Write-Host "  Subject: $($cert.Subject)"
    Write-Host "  Expiration: $($cert.NotAfter)"
    Write-Host "  Has Private Key: $($cert.HasPrivateKey)"
} else {
    Write-Host "✗ Certificate NOT found" -ForegroundColor Red
}
```

**Expected**: All modules installed, certificate found with private key.

### Step 2.2: Create Scripts Directory on DC

Still connected via SSH:

```powershell
# Create directory
$scriptDir = "C:\Scripts"
if (-not (Test-Path $scriptDir)) {
    New-Item -Path $scriptDir -ItemType Directory -Force
    Write-Host "✓ Created directory: $scriptDir"
} else {
    Write-Host "✓ Directory already exists: $scriptDir"
}

# Set permissions (Administrators: Full Control)
$acl = Get-Acl $scriptDir
$permission = "BUILTIN\Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
$acl.SetAccessRule($accessRule)
Set-Acl $scriptDir $acl

Write-Host "✓ Permissions set on $scriptDir"

# Verify
Get-Acl $scriptDir | Format-List Owner, AccessToString
```

### Step 2.3: Set Environment Variables on DC

Set required environment variables (still in SSH session):

```powershell
# Replace these values with yours from PRE-IMPLEMENTATION-CHECKLIST
$envVars = @{
    "AD_BASE_DN" = "DC=insulationsinc,DC=local"
    "AD_DISABLED_OU" = "OU=Disabled Users,DC=insulationsinc,DC=local"
    "AZURE_TENANT_ID" = "953922e6-5370-4a01-a3d5-773a30df726b"
    "AZURE_APP_ID" = "73b82823-d860-4bf6-938b-74deabeebab7"
    "CERT_THUMBPRINT" = "DE0FF14C5EABA90BA328030A59662518A3673009"
    "ORGANIZATION_DOMAIN" = "ii-us.com"
}

# Set machine-level environment variables
foreach ($key in $envVars.Keys) {
    [Environment]::SetEnvironmentVariable($key, $envVars[$key], "Machine")
    Write-Host "✓ Set $key"
}

# Verify
Write-Host "`nVerifying environment variables:"
foreach ($key in $envVars.Keys) {
    $value = [Environment]::GetEnvironmentVariable($key, "Machine")
    Write-Host "$key = $value"
}
```

**Note**: Disconnect and reconnect SSH session for environment variables to take effect.

---

## Phase 3: Deploy Script to DC

### Step 3.1: Upload Script via SCP

From your **local machine** (exit SSH session first):

```bash
# Upload script to DC
scp -i ~/.ssh/n8n_dc_automation ~/Downloads/Terminate-Employee.ps1 Administrator@DC-HOSTNAME:C:/Scripts/Terminate-Employee.ps1

# Verify upload
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -Command 'Test-Path C:\Scripts\Terminate-Employee.ps1'"

# Expected output: True
```

**Alternative (Windows local machine)**:
```powershell
# From Windows PowerShell
scp -i "$env:USERPROFILE\.ssh\n8n_dc_automation" "$env:USERPROFILE\Downloads\Terminate-Employee.ps1" "Administrator@DC-HOSTNAME:C:/Scripts/Terminate-Employee.ps1"
```

**Alternative (Manual Copy)**:
If SCP doesn't work, you can manually copy via RDP or shared folder.

### Step 3.2: Verify Script on DC

SSH back to DC and verify:

```bash
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME
```

```powershell
# Verify script exists
Test-Path C:\Scripts\Terminate-Employee.ps1
# Expected: True

# Check file size (should be ~10-12 KB)
(Get-Item C:\Scripts\Terminate-Employee.ps1).Length

# View first few lines
Get-Content C:\Scripts\Terminate-Employee.ps1 -TotalCount 10

# Should show the script header starting with <#
```

### Step 3.3: Set Execution Policy

```powershell
# Check current execution policy
Get-ExecutionPolicy

# Set to RemoteSigned if not already
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine

# Verify
Get-ExecutionPolicy
# Expected: RemoteSigned or Unrestricted
```

---

## Phase 4: Test Script on DC

### Step 4.1: Test with Test Parameters (Dry Run)

```powershell
# Test script syntax - this will fail on user lookup but verify syntax
C:\Scripts\Terminate-Employee.ps1 -EmployeeId "TEST123" -SupervisorEmail "test@ii-us.com"

# Expected: Script runs, connects to services, then fails on user lookup
# Look for JSON output at the end
```

**Expected Output** (JSON format):
```json
{
  "success": false,
  "employeeId": "TEST123",
  "operations": {
    "adLookup": {
      "success": false,
      "message": "User not found in AD"
    }
    // ... other operations
  },
  "errors": ["User with Employee ID TEST123 not found in Active Directory"],
  "timestamp": "2025-10-28T16:45:00.000Z"
}
```

### Step 4.2: Create Test User (Optional but Recommended)

Create a test user to perform a full termination test:

```powershell
# Create test user in AD
$testPassword = ConvertTo-SecureString "TempTestPass123!" -AsPlainText -Force

New-ADUser -Name "Test Termination User" `
           -GivenName "Test" `
           -Surname "Termination" `
           -SamAccountName "testterm01" `
           -UserPrincipalName "testterm01@ii-us.com" `
           -EmployeeID "999999" `
           -AccountPassword $testPassword `
           -Enabled $true `
           -Path "CN=Users,DC=insulationsinc,DC=local"  # Adjust path

# Verify user created
Get-ADUser -Filter {EmployeeID -eq "999999"} | Select-Object Name, UserPrincipalName, Enabled

# Note: You'll also need to create this user in M365 and assign a license
# for full testing (or accept that M365 operations will fail)
```

### Step 4.3: Run Test Termination

```powershell
# Run script on test user
C:\Scripts\Terminate-Employee.ps1 -EmployeeId "999999" -SupervisorEmail "your-email@ii-us.com" -Reason "Testing" -TicketNumber "TEST001"

# Review JSON output
# Check for "success": true or false
# Review each operation status
```

### Step 4.4: Verify Test Results

```powershell
# Check if test user was disabled
Get-ADUser -Filter {EmployeeID -eq "999999"} -Properties Enabled, DistinguishedName |
    Select-Object Name, Enabled, DistinguishedName

# Expected: Enabled = False, DistinguishedName contains Disabled OU

# Check mailbox (if M365 user was created)
Get-Mailbox -Identity "testterm01@ii-us.com" -ErrorAction SilentlyContinue |
    Select-Object DisplayName, RecipientTypeDetails

# Expected: RecipientTypeDetails = SharedMailbox (if Exchange operations succeeded)
```

### Step 4.5: Cleanup Test User (Optional)

```powershell
# Remove test user after successful test
Remove-ADUser -Identity "testterm01" -Confirm:$false

# Remove M365 user (if created)
Remove-MgUser -UserId "testterm01@ii-us.com"
```

---

## Phase 5: Test via SSH (Critical!)

Now test execution via SSH, which is how n8n will call it.

### Step 5.1: Test SSH Execution from Local Machine

From your **local machine**:

```bash
# Test SSH execution of script
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId TEST123 -SupervisorEmail test@ii-us.com"

# Expected: JSON output returned via SSH
```

**Important**: Verify that:
- Script executes without hanging
- JSON output is returned
- No interactive prompts appear

### Step 5.2: Test SSH Execution from n8n Pod

```bash
# Get n8n pod name
kubectl get pods -n n8n-prod

# Exec into n8n pod
kubectl exec -it -n n8n-prod POD-NAME -- /bin/bash

# Test SSH from pod (use existing test key if copied earlier, or create new one)
ssh -i /path/to/key -o StrictHostKeyChecking=no Administrator@DC-HOSTNAME "powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId TEST123 -SupervisorEmail test@ii-us.com"

# Expected: JSON output

# Exit pod
exit
```

### Step 5.3: Test SSH with Real User (If Test User Created)

```bash
# From local machine or n8n pod
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId 999999 -SupervisorEmail your-email@ii-us.com"

# Review JSON output
# Verify operations completed successfully
```

---

## Phase 6: Troubleshooting

### Issue: "Module not found" Error

**Symptoms**: Script fails with "Module 'Microsoft.Graph' not found"

**Solution**:
```powershell
# SSH to DC and install modules
Install-Module -Name Microsoft.Graph -Force -AllowClobber -Scope AllUsers
Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope AllUsers
# ActiveDirectory module: Install-WindowsFeature RSAT-AD-PowerShell
```

### Issue: "Certificate not found" Error

**Symptoms**: Script fails with "Certificate with thumbprint ... not found"

**Solution**:
```powershell
# Verify certificate thumbprint in script matches installed cert
$certThumbprint = "YOUR-CERT-THUMBPRINT"
Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Thumbprint -eq $certThumbprint}

# If not found, verify environment variable
[Environment]::GetEnvironmentVariable("CERT_THUMBPRINT", "Machine")

# Re-import certificate if needed
Import-PfxCertificate -FilePath "path\to\cert.pfx" -CertStoreLocation Cert:\LocalMachine\My
```

### Issue: "Access Denied" to Exchange/Graph

**Symptoms**: Script connects but gets access denied errors

**Solution**:
1. Verify Azure AD app permissions:
   - User.ReadWrite.All
   - Directory.ReadWrite.All
   - Group.ReadWrite.All
   - Exchange.ManageAsApp
2. Grant admin consent in Azure portal
3. Verify certificate is associated with app in Azure

### Issue: Script Hangs When Run via SSH

**Symptoms**: SSH command doesn't return, script appears to hang

**Solution**:
```powershell
# Add timeout to SSH command
ssh -i ~/.ssh/n8n_dc_automation -o ServerAliveInterval=60 Administrator@DC-HOSTNAME "powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId TEST"

# Or modify sshd_config on DC:
# ClientAliveInterval 60
# ClientAliveCountMax 3
```

### Issue: Environment Variables Not Found

**Symptoms**: Script fails with "Cannot bind argument to parameter 'TenantId' because it is null"

**Solution**:
```powershell
# Verify environment variables are set
[Environment]::GetEnvironmentVariable("AZURE_TENANT_ID", "Machine")

# If null, reconnect SSH session or restart PowerShell
# Environment variables require new session to load

# Verify in new SSH session:
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -Command '$env:AZURE_TENANT_ID'"
```

### Issue: JSON Output Not Returned

**Symptoms**: Script runs but no output visible

**Solution**:
```powershell
# Ensure script ends with output statement (line 314 in original)
$results | ConvertTo-Json -Depth 10

# Test output locally:
$test = C:\Scripts\Terminate-Employee.ps1 -EmployeeId TEST
$test | ConvertFrom-Json

# Verify SSH doesn't suppress output
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -Command 'Write-Output test'"
# Should show: test
```

---

## Verification Checklist

After completing deployment and testing:

- [ ] Script deployed to `C:\Scripts\Terminate-Employee.ps1` on DC
- [ ] Environment variables set on DC
- [ ] PowerShell modules installed and verified
- [ ] Certificate verified and accessible
- [ ] Execution policy set to RemoteSigned
- [ ] Script executes locally on DC
- [ ] Test user termination succeeds (or test with dummy ID shows expected error)
- [ ] SSH execution from local machine works
- [ ] SSH execution from n8n pod works
- [ ] JSON output returns correctly
- [ ] No hanging or timeout issues

**All items checked**: Yes / No

---

## Security Notes

1. **Script Permissions**: Only Administrators should have access to `C:\Scripts\`
2. **Environment Variables**: Stored at machine level (less secure than secrets vault)
3. **Logging**: Consider adding transcript logging:
   ```powershell
   # Add at start of script
   Start-Transcript -Path "C:\Logs\Terminations\termination-$EmployeeId-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

   # Add at end of script
   Stop-Transcript
   ```
4. **Audit Trail**: All AD changes are logged in Windows Event logs
5. **Certificate Security**: Protect certificate private key

---

## Next Steps

Once script deployment is verified:

1. ✅ **Complete**: PowerShell script deployed and tested
2. ➡️ **Next**: Configure n8n SSH credentials (if not done yet)
3. ➡️ **Next**: Update n8n workflow to use SSH node
4. ➡️ **Next**: Test end-to-end workflow from n8n UI

---

## Quick Reference

### Script Location
```
DC: C:\Scripts\Terminate-Employee.ps1
```

### Test Command (Local on DC)
```powershell
C:\Scripts\Terminate-Employee.ps1 -EmployeeId "999999" -SupervisorEmail "test@ii-us.com"
```

### Test Command (via SSH)
```bash
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME "powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId 999999 -SupervisorEmail test@ii-us.com"
```

### View Execution Logs
```powershell
# If transcript logging enabled
Get-ChildItem C:\Logs\Terminations\ | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-28
**Related Documents**:
- [PRE-IMPLEMENTATION-CHECKLIST.md](PRE-IMPLEMENTATION-CHECKLIST.md) (prerequisites)
- [SSH-CONFIGURATION.md](SSH-CONFIGURATION.md) (SSH setup)
- [POWERSHELL-DEPLOYMENT-GUIDE.md](POWERSHELL-DEPLOYMENT-GUIDE.md) (original script source)
- [N8N-WORKFLOW-SSH-UPDATE.md](N8N-WORKFLOW-SSH-UPDATE.md) (next: workflow update)
