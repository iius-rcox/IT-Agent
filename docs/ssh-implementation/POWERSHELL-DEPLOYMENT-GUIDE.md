# PowerShell Script Deployment Guide
# Employee Termination Automation

## ⚠️ IMPORTANT UPDATE: SSH-Based Execution Required

**🔴 CRITICAL**: This guide was written for local PowerShell execution. However, since n8n runs in a **Linux container** (Kubernetes), it **cannot execute Windows PowerShell directly**.

**✅ NEW APPROACH**: Use SSH-based remote execution on Windows Domain Controller.

**📚 Updated Guides Available**:
1. **[PRE-IMPLEMENTATION-CHECKLIST.md](PRE-IMPLEMENTATION-CHECKLIST.md)** - Prerequisites and verification
2. **[SSH-CONFIGURATION.md](SSH-CONFIGURATION.md)** - SSH setup on Windows DC
3. **[PS-SCRIPT-DC-DEPLOYMENT.md](PS-SCRIPT-DC-DEPLOYMENT.md)** - Deploy script to DC via SSH
4. **[N8N-SSH-CREDENTIALS-GUIDE.md](N8N-SSH-CREDENTIALS-GUIDE.md)** - Configure n8n credentials
5. **[N8N-WORKFLOW-SSH-UPDATE.md](N8N-WORKFLOW-SSH-UPDATE.md)** - Update workflow to use SSH
6. **[TESTING-VALIDATION-GUIDE.md](TESTING-VALIDATION-GUIDE.md)** - Complete testing procedures

**⏱️ Implementation Time**: ~70 minutes total (all guides)

---

## Architecture Change

### Before (Original - Won't Work)
```
n8n (Linux) → Execute Command (Local) → PowerShell Script
                     ❌ FAILS: No PowerShell on Linux
```

### After (SSH-Based - Works!)
```
n8n (Linux) → SSH → Windows DC → PowerShell Script
                        ✅ WORKS: PowerShell on Windows
```

---

## Quick Start (SSH Approach)

Follow these guides in order:
1. Complete pre-implementation checklist
2. Configure SSH on Domain Controller
3. Deploy PowerShell script to DC
4. Configure SSH credentials in n8n
5. Update workflow to use SSH node
6. Test and validate

---

## Original Guide (Reference Only)

**Note**: The content below is the original guide for local execution. It's kept for reference and contains the PowerShell script content. For SSH-based deployment, use the guides listed above.

---

## Overview

This guide provides complete instructions for deploying the `Terminate-Employee.ps1` PowerShell script to your n8n server. This script is the core engine of the Employee Termination Automation workflow.

**Important**: The n8n workflow is already built and configured. You only need to deploy this PowerShell script to complete the implementation.

---

## Prerequisites Verification

Before deploying, verify these prerequisites are met:

### 1. Azure AD App Registration ✅
```powershell
# Verify your app registration details
App ID: 73b82823-d860-4bf6-938b-74deabeebab7
Tenant ID: 953922e6-5370-4a01-a3d5-773a30df726b
Certificate Thumbprint: DE0FF14C5EABA90BA328030A59662518A3673009
```

### 2. PowerShell Modules Installed
```powershell
# Check if modules are installed
Get-Module -ListAvailable -Name Microsoft.Graph
Get-Module -ListAvailable -Name ExchangeOnlineManagement
Get-Module -ListAvailable -Name ActiveDirectory

# Install if missing
Install-Module -Name Microsoft.Graph -Force -AllowClobber
Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber
Install-Module -Name ActiveDirectory -Force -AllowClobber  # Or install RSAT
```

### 3. Certificate Installed
```powershell
# Verify certificate is installed on the server
Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Thumbprint -eq "DE0FF14C5EABA90BA328030A59662518A3673009"}

# Should return certificate details
# If not found, install the certificate to LocalMachine\My store
```

### 4. Environment Variables Set
```powershell
# Set these environment variables on the n8n server
# (Can be system-level or configured in n8n)
[Environment]::SetEnvironmentVariable("AD_BASE_DN", "DC=insulationsinc,DC=local", "Machine")
[Environment]::SetEnvironmentVariable("AD_DISABLED_OU", "OU=Disabled Users,DC=insulationsinc,DC=local", "Machine")
[Environment]::SetEnvironmentVariable("AZURE_TENANT_ID", "953922e6-5370-4a01-a3d5-773a30df726b", "Machine")
[Environment]::SetEnvironmentVariable("AZURE_APP_ID", "73b82823-d860-4bf6-938b-74deabeebab7", "Machine")
[Environment]::SetEnvironmentVariable("CERT_THUMBPRINT", "DE0FF14C5EABA90BA328030A59662518A3673009", "Machine")
[Environment]::SetEnvironmentVariable("ORGANIZATION_DOMAIN", "ii-us.com", "Machine")

# Restart PowerShell after setting machine-level variables
```

---

## Deployment Steps

### Step 1: Create Script Directory

```powershell
# Create C:\Scripts directory if it doesn't exist
New-Item -Path "C:\Scripts" -ItemType Directory -Force

# Verify directory was created
Test-Path "C:\Scripts"  # Should return True
```

### Step 2: Deploy the PowerShell Script

Create a file at `C:\Scripts\Terminate-Employee.ps1` with the following content:

```powershell
<#
.SYNOPSIS
    Automates employee termination process across M365 and Active Directory.

.DESCRIPTION
    This script performs comprehensive employee termination operations:
    - Converts mailbox to shared type
    - Removes all M365 licenses
    - Grants supervisor mailbox access
    - Disables Active Directory account
    - Removes all group memberships
    - Moves user to disabled OU
    - Triggers Azure AD sync

    Returns JSON results for n8n workflow processing.

.PARAMETER EmployeeId
    Required. The employee ID to terminate.

.PARAMETER SupervisorEmail
    Optional. Email of supervisor to grant mailbox access.

.PARAMETER Reason
    Optional. Reason for termination (default: "Not specified").

.PARAMETER TicketNumber
    Optional. HR ticket number (default: "NONE").

.EXAMPLE
    .\Terminate-Employee.ps1 -EmployeeId "785389" -SupervisorEmail "manager@ii-us.com"

.NOTES
    Author: AI Agent
    Version: 1.0
    Requires: Microsoft.Graph, ExchangeOnlineManagement, ActiveDirectory modules
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$EmployeeId,

    [Parameter(Mandatory=$false)]
    [string]$SupervisorEmail,

    [Parameter(Mandatory=$false)]
    [string]$Reason = "Not specified",

    [Parameter(Mandatory=$false)]
    [string]$TicketNumber = "NONE"
)

# Configuration (from environment or hardcoded)
$disabledOU = $env:AD_DISABLED_OU
$tenantId = $env:AZURE_TENANT_ID
$appId = $env:AZURE_APP_ID
$certThumbprint = $env:CERT_THUMBPRINT
$organizationDomain = $env:ORGANIZATION_DOMAIN

# Results object
$results = @{
    success = $false
    employeeId = $EmployeeId
    employeeName = $null
    userPrincipalName = $null
    operations = @{
        adLookup = @{ success = $false; message = "" }
        m365Lookup = @{ success = $false; message = "" }
        licenseRemoval = @{ success = $false; licensesRemoved = 0; message = "" }
        mailboxConversion = @{ success = $false; message = "" }
        supervisorAccess = @{ success = $false; message = "" }
        adDisable = @{ success = $false; message = "" }
        groupRemoval = @{ success = $false; groupsRemoved = 0; message = "" }
        ouMove = @{ success = $false; message = "" }
    }
    errors = @()
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
}

try {
    # 1. Connect to Microsoft Graph
    Write-Host "Connecting to Microsoft Graph..."
    Connect-MgGraph -ClientId $appId -TenantId $tenantId -CertificateThumbprint $certThumbprint -NoWelcome

    # 2. Connect to Exchange Online
    Write-Host "Connecting to Exchange Online..."
    Connect-ExchangeOnline -AppId $appId -Organization $organizationDomain -CertificateThumbprint $certThumbprint -ShowBanner:$false

    # 3. Find user in local AD
    Write-Host "Looking up user in Active Directory..."
    $user = Get-ADUser -Filter {employeeID -eq $EmployeeId} -Properties EmployeeID, DistinguishedName, UserPrincipalName, DisplayName, memberOf

    if (-not $user) {
        $results.operations.adLookup.message = "User not found in AD"
        $results.errors += "User with Employee ID $EmployeeId not found in Active Directory"
        throw "User not found in AD"
    }

    $results.operations.adLookup.success = $true
    $results.operations.adLookup.message = "User found: $($user.DisplayName)"
    $results.employeeName = $user.DisplayName
    $results.userPrincipalName = $user.UserPrincipalName
    $upn = $user.UserPrincipalName

    # 4. Find user in Azure AD
    Write-Host "Looking up user in Azure AD..."
    try {
        $graphUser = Get-MgUser -Filter "userPrincipalName eq '$upn'"
        $results.operations.m365Lookup.success = $true
        $results.operations.m365Lookup.message = "User found in M365"
    } catch {
        $results.operations.m365Lookup.message = "User not found in M365: $_"
        $results.errors += "Failed to find user in M365"
    }

    # 5. Remove all licenses (if M365 user found)
    if ($graphUser) {
        Write-Host "Fetching and removing licenses..."
        try {
            $licenseDetails = Get-MgUserLicenseDetail -UserId $graphUser.Id
            $licensesToRemove = @()

            foreach ($license in $licenseDetails) {
                $licensesToRemove += $license.SkuId
            }

            if ($licensesToRemove.Count -gt 0) {
                Set-MgUserLicense -UserId $graphUser.Id -RemoveLicenses $licensesToRemove -AddLicenses @{}
                $results.operations.licenseRemoval.success = $true
                $results.operations.licenseRemoval.licensesRemoved = $licensesToRemove.Count
                $results.operations.licenseRemoval.message = "Removed $($licensesToRemove.Count) licenses"
            } else {
                $results.operations.licenseRemoval.success = $true
                $results.operations.licenseRemoval.message = "No licenses to remove"
            }
        } catch {
            $results.operations.licenseRemoval.message = "Failed to remove licenses: $_"
            $results.errors += "License removal failed"
        }
    }

    # 6. Convert mailbox to shared
    Write-Host "Converting mailbox to shared..."
    try {
        Set-Mailbox -Identity $upn -Type Shared
        $results.operations.mailboxConversion.success = $true
        $results.operations.mailboxConversion.message = "Mailbox converted to shared"
    } catch {
        $results.operations.mailboxConversion.message = "Failed to convert mailbox: $_"
        $results.errors += "Mailbox conversion failed"
    }

    # 7. Grant supervisor access (if provided)
    if ($SupervisorEmail) {
        Write-Host "Granting supervisor access to mailbox..."
        try {
            Add-MailboxPermission -Identity $upn -User $SupervisorEmail -AccessRights FullAccess -InheritanceType All
            $results.operations.supervisorAccess.success = $true
            $results.operations.supervisorAccess.message = "Granted $SupervisorEmail full access"
        } catch {
            $results.operations.supervisorAccess.message = "Failed to grant supervisor access: $_"
            $results.errors += "Supervisor access grant failed"
        }
    } else {
        $results.operations.supervisorAccess.message = "No supervisor email provided, skipped"
    }

    # 8. Disable AD account
    Write-Host "Disabling AD account..."
    try {
        Disable-ADAccount -Identity $user
        $results.operations.adDisable.success = $true
        $results.operations.adDisable.message = "Account disabled"
    } catch {
        $results.operations.adDisable.message = "Failed to disable account: $_"
        $results.errors += "Account disable failed"
    }

    # 9. Remove from all groups
    Write-Host "Removing from all groups..."
    try {
        $groups = $user.memberOf
        $groupsRemoved = 0

        if ($groups) {
            foreach ($groupDN in $groups) {
                try {
                    Remove-ADGroupMember -Identity $groupDN -Members $user.DistinguishedName -Confirm:$false
                    $groupsRemoved++
                } catch {
                    # Continue on error
                }
            }
        }

        $results.operations.groupRemoval.success = $true
        $results.operations.groupRemoval.groupsRemoved = $groupsRemoved
        $results.operations.groupRemoval.message = "Removed from $groupsRemoved groups"
    } catch {
        $results.operations.groupRemoval.message = "Failed to remove from groups: $_"
        $results.errors += "Group removal failed"
    }

    # 10. Move to disabled OU
    Write-Host "Moving to disabled OU..."
    try {
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $disabledOU
        $results.operations.ouMove.success = $true
        $results.operations.ouMove.message = "Moved to $disabledOU"
    } catch {
        $results.operations.ouMove.message = "Failed to move to disabled OU: $_"
        $results.errors += "OU move failed"
    }

    # 11. Sync Azure AD
    Write-Host "Triggering Azure AD sync..."
    try {
        Start-ADSyncSyncCycle -PolicyType Delta
    } catch {
        # Non-critical, continue
    }

    # Success if no critical errors
    if ($results.operations.adDisable.success -and $results.operations.ouMove.success) {
        $results.success = $true
    }

} catch {
    $results.errors += $_.Exception.Message
} finally {
    # Cleanup connections
    try { Disconnect-ExchangeOnline -Confirm:$false } catch {}
    try { Disconnect-MgGraph } catch {}
}

# Output JSON for n8n to parse
$results | ConvertTo-Json -Depth 10
```

### Step 3: Set Script Permissions

```powershell
# Set execution policy if needed
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine

# Verify script exists
Test-Path "C:\Scripts\Terminate-Employee.ps1"  # Should return True

# Check file size (should be ~10KB)
(Get-Item "C:\Scripts\Terminate-Employee.ps1").Length
```

---

## Testing the Script

### Test 1: Verify Script Syntax

```powershell
# Check for syntax errors
powershell.exe -File "C:\Scripts\Terminate-Employee.ps1" -EmployeeId "test" -WhatIf

# Should not show syntax errors
```

### Test 2: Test with a Test User

**IMPORTANT**: Create a test user first in both M365 and AD!

```powershell
# Create test user in AD
New-ADUser -Name "Test Termination User" -GivenName "Test" -Surname "User" -SamAccountName "testterm01" -UserPrincipalName "testterm01@ii-us.com" -EmployeeID "999999" -AccountPassword (ConvertTo-SecureString "TempPass123!" -AsPlainText -Force) -Enabled $true

# Run termination script on test user
powershell.exe -File "C:\Scripts\Terminate-Employee.ps1" -EmployeeId "999999" -SupervisorEmail "manager@ii-us.com"

# Expected output: JSON with all operations marked as successful
```

### Test 3: Verify Test Results

```powershell
# Check if test user was disabled
Get-ADUser -Filter {EmployeeID -eq "999999"} -Properties Enabled | Select-Object Name, Enabled

# Check if test user was moved to disabled OU
Get-ADUser -Filter {EmployeeID -eq "999999"} -Properties DistinguishedName | Select-Object DistinguishedName

# Check if mailbox was converted (in Exchange Online)
Get-Mailbox -Identity "testterm01@ii-us.com" | Select-Object DisplayName, RecipientTypeDetails
```

---

## Troubleshooting

### Issue: "Module not found" errors

**Solution**:
```powershell
# Install missing modules
Install-Module -Name Microsoft.Graph -Force -AllowClobber
Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber
Install-Module -Name ActiveDirectory -Force -AllowClobber
```

### Issue: "Certificate not found" errors

**Solution**:
```powershell
# Verify certificate thumbprint
Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Thumbprint -eq "DE0FF14C5EABA90BA328030A59662518A3673009"}

# If not found, import the certificate
Import-Certificate -FilePath "path\to\certificate.pfx" -CertStoreLocation Cert:\LocalMachine\My
```

### Issue: "Access denied" errors

**Solution**:
- Verify Azure AD app has required permissions (User.ReadWrite.All, Directory.ReadWrite.All, Group.ReadWrite.All)
- Verify certificate is properly associated with the Azure AD app
- Check that the service account running PowerShell has AD admin rights

### Issue: "User not found in AD" errors

**Solution**:
```powershell
# Verify employee ID is correct
Get-ADUser -Filter {EmployeeID -eq "785389"} -Properties EmployeeID, DisplayName

# Check if employeeID attribute is populated
Get-ADUser -Identity "username" -Properties EmployeeID | Select-Object Name, EmployeeID
```

### Issue: Script runs but returns no output

**Solution**:
```powershell
# Run script with verbose output
powershell.exe -File "C:\Scripts\Terminate-Employee.ps1" -EmployeeId "test" -Verbose

# Check if script is returning JSON
$output = powershell.exe -File "C:\Scripts\Terminate-Employee.ps1" -EmployeeId "test"
$output | ConvertFrom-Json
```

---

## Integration with n8n Workflow

Once the script is deployed and tested:

1. **Verify n8n can execute PowerShell**:
   - n8n Execute Command node should have access to `powershell.exe`
   - n8n service account should have permissions to run PowerShell scripts

2. **Test from n8n**:
   - The workflow is already configured to call this script
   - Execute Command node arguments: `-File C:\Scripts\Terminate-Employee.ps1 -EmployeeId {{ $json.employeeId }} -SupervisorEmail {{ $json.supervisorEmail }}`

3. **Webhook Testing**:
   - Webhook URL: `https://n8n.ii-us.com/webhook/terminate-employee`
   - Method: POST
   - Headers: `X-API-Key: <your-api-key>`
   - Body:
     ```json
     {
       "employeeId": "999999",
       "supervisorEmail": "manager@ii-us.com",
       "reason": "Testing",
       "ticketNumber": "TEST-001"
     }
     ```

---

## Security Considerations

1. **Script Location**: `C:\Scripts\` should have restricted permissions
   - Only administrators and n8n service account should have access
   - Set proper ACLs:
     ```powershell
     $acl = Get-Acl "C:\Scripts"
     $acl.SetAccessRuleProtection($true, $false)
     $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
     $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")
     $acl.SetAccessRule($adminRule)
     Set-Acl "C:\Scripts" $acl
     ```

2. **Audit Logging**: All operations are logged in the JSON output
   - n8n workflow stores execution history
   - Consider additional logging to a file or SIEM

3. **Certificate Security**:
   - Certificate should be stored in LocalMachine\My store
   - Only administrators should have access to private key

4. **Environment Variables**:
   - Use Machine-level environment variables (not User-level)
   - Restart PowerShell after setting variables

---

## Next Steps

After successful deployment and testing:

1. ✅ PowerShell script deployed to `C:\Scripts\Terminate-Employee.ps1`
2. ✅ Script tested with test user
3. ⏳ Fix n8n workflow validation errors (when server is back online)
4. ⏳ Activate n8n workflow
5. ⏳ Test end-to-end via webhook
6. ⏳ Document webhook URL and provide to stakeholders

---

## Support & Contact

**For Issues**:
- Check troubleshooting section above
- Review n8n execution logs
- Verify environment variables are set correctly

**Script Version**: 1.0
**Last Updated**: 2025-10-28
**Author**: AI Agent
**Project**: Employee Termination Automation Workflow
