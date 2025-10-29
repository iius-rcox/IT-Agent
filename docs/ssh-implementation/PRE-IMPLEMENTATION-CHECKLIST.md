# Pre-Implementation Verification Checklist

**Purpose**: Verify your environment before configuring SSH-based PowerShell execution for n8n.

**Estimated Time**: 10 minutes

---

## 1. Domain Controller Information

### 1.1 Identify Domain Controller
Run this command on your DC to get system information:

```powershell
# Get DC hostname and IP
Get-WmiObject Win32_ComputerSystem | Select-Object Name, Domain
Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | Select-Object IPAddress, InterfaceAlias
```

**Record the following**:
- [ ] DC Hostname/FQDN: ____________________________________
- [ ] DC IP Address: ____________________________________
- [ ] Domain Name: ____________________________________

### 1.2 Verify Network Connectivity
From a machine that can access your AKS cluster, test connectivity to the DC:

```powershell
# Test network connectivity
Test-NetConnection -ComputerName YOUR-DC-HOSTNAME -Port 22
```

**Expected**: If OpenSSH is already installed, connection should succeed. If not, connection will fail (expected - we'll enable it next).

- [ ] Network connectivity to DC confirmed (can reach port 22, even if refused)

---

## 2. Certificate Verification

### 2.1 Check Certificate Store
Run this on your DC to find the Azure AD app certificate:

```powershell
# List all certificates in LocalMachine\My store
Get-ChildItem Cert:\LocalMachine\My | Select-Object Thumbprint, Subject, NotAfter, HasPrivateKey | Format-Table -AutoSize

# Look for certificate with subject matching your Azure AD app
# Example subject: CN=n8n-automation-app or similar
```

**Record the following**:
- [ ] Certificate found: Yes / No
- [ ] Certificate Thumbprint: ____________________________________
- [ ] Certificate Subject: ____________________________________
- [ ] Certificate Expiration Date: ____________________________________
- [ ] Has Private Key: Yes / No (must be Yes!)

### 2.2 Test Certificate Authentication
Test that the certificate can authenticate to Microsoft Graph:

```powershell
# Install Microsoft.Graph module if not already installed
# Install-Module Microsoft.Graph -Scope CurrentUser

# Test certificate authentication
$TenantId = "YOUR-TENANT-ID"  # Replace with your tenant ID
$ClientId = "YOUR-APP-CLIENT-ID"  # Replace with your app client ID
$CertThumbprint = "YOUR-CERT-THUMBPRINT"  # From step 2.1

Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -CertificateThumbprint $CertThumbprint

# If successful, try a test query
Get-MgUser -Top 1 | Select-Object Id, DisplayName, UserPrincipalName

# Disconnect
Disconnect-MgGraph
```

**Expected**: Connection should succeed and return a user.

- [ ] Certificate authentication to Graph API works
- [ ] Tenant ID: ____________________________________
- [ ] App Client ID: ____________________________________

### 2.3 Test Exchange Online Authentication
Test that the certificate can authenticate to Exchange Online:

```powershell
# Test Exchange Online authentication
Connect-ExchangeOnline -CertificateThumbprint $CertThumbprint `
                       -AppId $ClientId `
                       -Organization "yourdomain.onmicrosoft.com"

# If successful, try a test query
Get-Mailbox -ResultSize 1 | Select-Object DisplayName, PrimarySmtpAddress

# Disconnect
Disconnect-ExchangeOnline -Confirm:$false
```

**Expected**: Connection should succeed and return a mailbox.

- [ ] Certificate authentication to Exchange Online works

---

## 3. PowerShell Modules Verification

### 3.1 Check Installed Modules
Run this on your DC:

```powershell
# Check for required modules
$requiredModules = @(
    "Microsoft.Graph",
    "ExchangeOnlineManagement",
    "ActiveDirectory"
)

foreach ($module in $requiredModules) {
    $installed = Get-Module -ListAvailable -Name $module
    if ($installed) {
        Write-Host "✓ $module installed (Version: $($installed[0].Version))" -ForegroundColor Green
    } else {
        Write-Host "✗ $module NOT installed" -ForegroundColor Red
    }
}
```

- [ ] Microsoft.Graph module installed
  - Version: ____________________________________
- [ ] ExchangeOnlineManagement module installed
  - Version: ____________________________________
- [ ] ActiveDirectory module installed
  - Version: ____________________________________

### 3.2 Verify Module Functionality
Test that each module can load and execute basic commands:

```powershell
# Test Microsoft.Graph
Import-Module Microsoft.Graph
Get-Command -Module Microsoft.Graph.Users -Name Get-MgUser

# Test ExchangeOnlineManagement
Import-Module ExchangeOnlineManagement
Get-Command -Module ExchangeOnlineManagement -Name Set-Mailbox

# Test ActiveDirectory
Import-Module ActiveDirectory
Get-Command -Module ActiveDirectory -Name Get-ADUser
```

**Expected**: Each command should list the corresponding cmdlet without errors.

- [ ] All modules load without errors
- [ ] All cmdlets are available

---

## 4. PowerShell Script Location

### 4.1 Check for Existing Script
Check if the termination script already exists on the DC:

```powershell
# Check common script locations
$scriptLocations = @(
    "C:\Scripts\Terminate-Employee.ps1",
    "C:\Automation\Terminate-Employee.ps1",
    "C:\IT\Scripts\Terminate-Employee.ps1"
)

foreach ($location in $scriptLocations) {
    if (Test-Path $location) {
        Write-Host "✓ Script found at: $location" -ForegroundColor Green
        Get-Item $location | Select-Object FullName, Length, LastWriteTime
    }
}
```

- [ ] Script location: ____________________________________
- [ ] Script exists: Yes / No
- [ ] Script last modified: ____________________________________

### 4.2 Create Scripts Directory (if needed)
If script doesn't exist, create the directory:

```powershell
# Create C:\Scripts directory
$scriptDir = "C:\Scripts"
if (-not (Test-Path $scriptDir)) {
    New-Item -Path $scriptDir -ItemType Directory
    Write-Host "Created directory: $scriptDir"
}

# Set permissions (Administrators: Full Control)
$acl = Get-Acl $scriptDir
$permission = "BUILTIN\Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
$acl.SetAccessRule($accessRule)
Set-Acl $scriptDir $acl

Write-Host "✓ Scripts directory ready: $scriptDir"
```

- [ ] Scripts directory exists: ____________________________________
- [ ] Permissions set correctly

---

## 5. Current n8n Configuration

### 5.1 Check n8n Deployment
Verify your n8n deployment in Kubernetes:

```bash
# From a machine with kubectl access
kubectl get pods -n n8n-prod
kubectl get deployment -n n8n-prod
kubectl describe pod -n n8n-prod -l app=n8n | grep Image:
```

**Record the following**:
- [ ] n8n namespace: ____________________________________
- [ ] n8n pod name: ____________________________________
- [ ] n8n image version: ____________________________________
- [ ] n8n pod status: Running / Not Running

### 5.2 Test kubectl exec
Verify you can execute commands in the n8n pod:

```bash
# Test kubectl exec
kubectl exec -it -n n8n-prod deployment/n8n -- whoami
kubectl exec -it -n n8n-prod deployment/n8n -- pwd
kubectl exec -it -n n8n-prod deployment/n8n -- which ssh
```

**Expected**: Commands should execute. If `which ssh` returns a path, SSH client is already installed.

- [ ] kubectl exec works
- [ ] SSH client installed in n8n pod: Yes / No

---

## 6. Workflow Status

### 6.1 Locate Current Workflow
Identify where your employee termination workflow is stored:

- [ ] Workflow is in n8n UI (need to export JSON)
- [ ] Workflow is in local file: ____________________________________
- [ ] Workflow is in git repository: ____________________________________

### 6.2 Current Workflow Configuration
Review the current workflow and note:

- [ ] Workflow ID (if in n8n): ____________________________________
- [ ] Current execution method: Execute Command / Other
- [ ] File path in Execute Command node: ____________________________________
- [ ] Number of nodes in workflow: ____________________________________

---

## 7. Access and Permissions

### 7.1 Domain Administrator Access
Verify you have the necessary permissions:

```powershell
# Check current user permissions
whoami /groups | findstr /I "Domain Admins"
whoami /groups | findstr /I "Administrators"
```

- [ ] Current user is Domain Admin or Administrator
- [ ] Can modify DC configuration
- [ ] Can install Windows features
- [ ] Can modify firewall rules

### 7.2 Azure Kubernetes Access
Verify you have AKS admin access:

```bash
# Check RBAC permissions
kubectl auth can-i create secrets -n n8n-prod
kubectl auth can-i create deployments -n n8n-prod
kubectl auth can-i exec pods -n n8n-prod
```

**Expected**: All commands should return "yes"

- [ ] Can create secrets in n8n namespace
- [ ] Can create/update deployments
- [ ] Can exec into pods

---

## 8. Security Considerations

### 8.1 Firewall Rules
Check if SSH port is allowed:

```powershell
# Check Windows Firewall rules for SSH
Get-NetFirewallRule -DisplayName "*SSH*" | Select-Object DisplayName, Enabled, Direction, Action

# Check if port 22 is open
Get-NetFirewallPortFilter | Where-Object {$_.LocalPort -eq 22} | Get-NetFirewallRule
```

- [ ] SSH firewall rules exist: Yes / No
- [ ] Current rules documented: ____________________________________

### 8.2 Network Security Groups (Azure)
If using Azure, verify NSG rules:

- [ ] NSG allows traffic from AKS to DC on port 22: Verified / Not Verified
- [ ] Network path documented: ____________________________________

---

## Verification Summary

Once you've completed all sections, verify:

**Critical Requirements (Must Have)**:
- [ ] Domain Controller accessible from network
- [ ] Certificate in DC cert store with private key
- [ ] Certificate authentication to Graph and Exchange works
- [ ] All three PowerShell modules installed and functional
- [ ] Domain Admin access to DC
- [ ] kubectl exec access to n8n pod

**Ready to Proceed**: Yes / No

**Blockers** (if any):
____________________________________
____________________________________
____________________________________

---

## Next Steps

If all critical requirements are met:
1. Proceed to **SSH Configuration Guide** (SSH-CONFIGURATION.md)
2. Follow the step-by-step setup instructions
3. Return here if any issues arise

If blockers exist:
1. Resolve certificate or module issues first
2. Ensure network connectivity
3. Verify permissions
4. Re-run this checklist

---

## Troubleshooting

### Certificate Issues
If certificate not found or authentication fails:
1. Verify app registration in Azure AD
2. Re-upload certificate to Azure AD app
3. Export certificate with private key (.pfx)
4. Import to DC cert store: `Import-PfxCertificate -FilePath cert.pfx -CertStoreLocation Cert:\LocalMachine\My`

### Module Issues
If modules missing or outdated:
```powershell
# Update modules
Install-Module Microsoft.Graph -Force -AllowClobber
Install-Module ExchangeOnlineManagement -Force -AllowClobber
Install-WindowsFeature RSAT-AD-PowerShell  # For ActiveDirectory module
```

### Network Issues
If connectivity fails:
1. Check firewall rules on DC
2. Check NSG rules in Azure
3. Verify AKS egress configuration
4. Test with: `Test-NetConnection -ComputerName DC-IP -Port 22`

---

**Document Version**: 1.0
**Last Updated**: 2025-10-28
**Related Documents**:
- SSH-CONFIGURATION.md (next step)
- POWERSHELL-DEPLOYMENT-GUIDE.md (updated architecture)
- PRPs/employee-termination-workflow-enhanced.md (workflow details)
