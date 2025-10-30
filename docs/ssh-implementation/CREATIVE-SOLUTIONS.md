# Creative Solutions for SSH Implementation Challenges

**Date:** October 30, 2025
**Status:** Alternative approaches for n8n → Domain Controller connectivity

## Problem Summary

Public key authentication to Windows Domain Controller fails with "connection reset" despite correct configuration. This appears to be a Windows Server DC-specific security restriction on the Administrator account.

## Solutions Not Yet Attempted

### 1. Certificate-Based SSH Authentication

Windows OpenSSH supports certificate authentication which may bypass DC restrictions.

**Implementation:**

```powershell
# Step 1: Generate Certificate Authority (one-time setup)
ssh-keygen -t rsa -b 4096 -f C:\SSH-CA\ca_key -C "n8n SSH Certificate Authority"

# Step 2: Configure DC to trust CA
Add-Content "C:\ProgramData\ssh\sshd_config" @"

# Certificate Authentication
TrustedUserCAKeys C:\ProgramData\ssh\ca.pub
CASignatureAlgorithms ssh-rsa,rsa-sha2-256,rsa-sha2-512
"@

# Step 3: Copy CA public key to DC
Copy-Item C:\SSH-CA\ca_key.pub C:\ProgramData\ssh\ca.pub

# Step 4: Sign user certificate (valid for 1 year)
ssh-keygen -s C:\SSH-CA\ca_key -I n8n-automation -n administrator -V +52w n8n_dc_automation.pub

# Step 5: Deploy certificate to n8n
# The signed certificate (n8n_dc_automation-cert.pub) goes alongside the private key
```

**Advantages:**
- Certificates can have expiration dates
- Better audit trail
- May bypass key authentication restrictions

---

### 2. Dedicated Service Account Approach

Create a non-Administrator account with specific delegated permissions.

```powershell
# Create service account
$password = ConvertTo-SecureString "GenerateSecurePassword123!" -AsPlainText -Force
New-ADUser -Name "svc-n8n-ssh" `
  -UserPrincipalName "svc-n8n-ssh@insulationsinc.local" `
  -AccountPassword $password `
  -Enabled $true `
  -PasswordNeverExpires $true `
  -CannotChangePassword $true `
  -Description "Service account for n8n automation"

# Grant specific permissions (not Domain Admin)
Add-ADGroupMember -Identity "Remote Management Users" -Members "svc-n8n-ssh"
Add-ADGroupMember -Identity "Account Operators" -Members "svc-n8n-ssh"

# Configure constrained delegation
Set-ADUser svc-n8n-ssh -Add @{
  'msDS-AllowedToDelegateTo' = @(
    'HOST/INSDAL9DC01.insulationsinc.local',
    'HOST/INSDAL9DC01'
  )
}

# Create user profile and SSH directory
$userProfile = "C:\Users\svc-n8n-ssh"
New-Item -Path "$userProfile\.ssh" -ItemType Directory -Force

# Add public key to user's authorized_keys (NOT administrators file)
$publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII15oR1ICDywSpc0aBKNh8+5jRDVhYuAcIhw9MFUpScH n8n-dc-automation"
Set-Content "$userProfile\.ssh\authorized_keys" $publicKey

# Set permissions
icacls "$userProfile\.ssh" /inheritance:r
icacls "$userProfile\.ssh" /grant "svc-n8n-ssh:(OI)(CI)F" /grant "SYSTEM:(OI)(CI)F"
icacls "$userProfile\.ssh\authorized_keys" /inheritance:r
icacls "$userProfile\.ssh\authorized_keys" /grant "svc-n8n-ssh:F" /grant "SYSTEM:F"
```

**Test from AKS:**
```bash
kubectl exec -n n8n-prod ssh-test -- ssh -i /root/.ssh/id_ed25519 \
  svc-n8n-ssh@10.0.0.200 "whoami"
```

---

### 3. PowerShell JEA (Just Enough Administration)

Create a constrained PowerShell endpoint that doesn't require SSH.

**Setup JEA Endpoint:**

```powershell
# Create JEA configuration directory
New-Item -Path C:\JEA -ItemType Directory -Force

# Create Role Capability
$roleCapPath = "C:\JEA\EmployeeTermination.psrc"
New-PSRoleCapabilityFile -Path $roleCapPath `
  -VisibleCmdlets @('Get-ADUser', 'Set-ADUser', 'Disable-ADAccount') `
  -VisibleFunctions @('Terminate-Employee') `
  -FunctionDefinitions @{
    Name = 'Terminate-Employee'
    ScriptBlock = {
      param(
        [Parameter(Mandatory=$true)]
        [string]$EmployeeID
      )

      # Call existing termination script
      & C:\Scripts\Terminate-Employee.ps1 -EmployeeID $EmployeeID
    }
  }

# Create Session Configuration
$sessionConfigPath = "C:\JEA\EmployeeTermination.pssc"
New-PSSessionConfigurationFile -Path $sessionConfigPath `
  -SessionType RestrictedRemoteServer `
  -RunAsVirtualAccount `
  -RoleDefinitions @{
    'INSULATIONSINC\svc-n8n-ssh' = @{ RoleCapabilities = 'EmployeeTermination' }
  } `
  -LanguageMode 'NoLanguage'

# Register the JEA endpoint
Register-PSSessionConfiguration -Path $sessionConfigPath `
  -Name 'EmployeeTermination' `
  -Force

# Test the endpoint
$cred = Get-Credential svc-n8n-ssh
Invoke-Command -ComputerName localhost `
  -ConfigurationName EmployeeTermination `
  -Credential $cred `
  -ScriptBlock { Terminate-Employee -EmployeeID 'TEST001' }
```

**n8n Integration:**
```javascript
// n8n Execute Command node
{
  "command": "pwsh",
  "arguments": [
    "-Command",
    "Invoke-Command -ComputerName INSDAL9DC01 -ConfigurationName EmployeeTermination -Credential $cred -ScriptBlock { Terminate-Employee -EmployeeID '{{$json.employeeId}}' }"
  ]
}
```

---

### 4. WinRM with Certificate Authentication

More Windows-native than SSH, with better integration.

```powershell
# Generate certificate for WinRM
$cert = New-SelfSignedCertificate -DnsName "INSDAL9DC01.insulationsinc.local" `
  -CertStoreLocation Cert:\LocalMachine\My `
  -KeyExportPolicy Exportable

# Configure HTTPS listener
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * `
  -CertificateThumbPrint $cert.Thumbprint -Force

# Enable certificate authentication
Set-Item -Path WSMan:\localhost\Service\Auth\Certificate -Value $true

# Map certificate to user account
New-Item -Path WSMan:\localhost\ClientCertificate `
  -Subject "svc-n8n-ssh@insulationsinc.local" `
  -URI * -Issuer $cert.Thumbprint `
  -Credential (Get-Credential svc-n8n-ssh)

# Export certificate for n8n
$pwd = ConvertTo-SecureString -String "CertPassword123!" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath C:\Temp\winrm-cert.pfx -Password $pwd
```

---

### 5. Azure Arc-enabled Servers

Deploy Azure Arc for cloud-native management.

```powershell
# Download and install Azure Arc agent
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri https://aka.ms/ArcInstallScriptWin -OutFile .\ArcInstall.ps1

# Connect server to Azure Arc
.\ArcInstall.ps1 -subscriptionId "a78954fe-f6fe-4279-8be0-2c748be2f266" `
  -resourceGroup "rg_prod" `
  -location "southcentralus" `
  -tenantId "your-tenant-id" `
  -servicePrincipalId "sp-id" `
  -servicePrincipalSecret "sp-secret"

# Once connected, use Azure Automation or Azure Functions
```

Then trigger from n8n:
```javascript
// HTTP Request to Azure Function
{
  "url": "https://your-function.azurewebsites.net/api/terminate-employee",
  "method": "POST",
  "headers": {
    "x-functions-key": "{{ $credentials.azureFunctionKey }}"
  },
  "body": {
    "employeeId": "{{ $json.employeeId }}"
  }
}
```

---

### 6. Local API Gateway

Deploy a lightweight REST API on the DC.

```powershell
# Install IIS and ASP.NET Core Hosting Bundle
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Install-WindowsFeature -Name Web-Asp-Net45

# Download ASP.NET Core Hosting Bundle
Invoke-WebRequest -Uri "https://download.visualstudio.microsoft.com/download/pr/hosting-bundle.exe" `
  -OutFile "hosting-bundle.exe"
Start-Process -FilePath "hosting-bundle.exe" -ArgumentList "/quiet" -Wait

# Deploy simple API (example structure)
# C:\inetpub\EmployeeAPI\
#   - Program.cs
#   - Controllers\EmployeeController.cs
#   - Services\TerminationService.cs
```

**Simple API Controller:**
```csharp
[ApiController]
[Route("api/[controller]")]
public class EmployeeController : ControllerBase
{
    [HttpPost("terminate")]
    [Authorize] // Use Azure AD or API key auth
    public async Task<IActionResult> Terminate([FromBody] TerminateRequest request)
    {
        // Execute PowerShell script
        using var ps = PowerShell.Create();
        ps.AddScript($@"C:\Scripts\Terminate-Employee.ps1 -EmployeeID '{request.EmployeeId}'");

        var results = await ps.InvokeAsync();
        return Ok(new { success = true, results });
    }
}
```

---

## Troubleshooting Steps Not Yet Tried

### 1. Check Group Policy SSH Restrictions

```powershell
# Generate comprehensive GPO report
gpresult /H C:\GPOReport.html /F

# Check specific SSH-related policies
Get-GPO -All | ForEach-Object {
    $report = Get-GPOReport -Guid $_.Id -ReportType Xml
    if ($report -match "SSH|OpenSSH|RemoteAccess") {
        Write-Host "GPO: $($_.DisplayName) contains SSH-related settings"
    }
}

# Check local security policy
secedit /export /cfg C:\SecurityPolicy.inf
Select-String -Path C:\SecurityPolicy.inf -Pattern "SSH|Remote"
```

### 2. Event Log Deep Dive

```powershell
# Check Security event log for authentication failures
Get-WinEvent -FilterHashtable @{
    LogName='Security'
    ID=4625,4768,4771,4776
    StartTime=(Get-Date).AddHours(-1)
} | Format-Table TimeCreated,Id,Message -Wrap

# Check System event log for service issues
Get-WinEvent -FilterHashtable @{
    LogName='System'
    ProviderName='sshd'
} | Select-Object -First 20

# Enable SSH debug logging to file
Add-Content C:\ProgramData\ssh\sshd_config @"
LogLevel DEBUG3
SyslogFacility LOCAL0
"@
Restart-Service sshd
```

### 3. Test with Local System Account

```powershell
# Create scheduled task running as SYSTEM to test key auth
$action = New-ScheduledTaskAction -Execute 'ssh' `
  -Argument '-i C:\TestKeys\id_ed25519 administrator@localhost hostname'

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)

Register-ScheduledTask -TaskName "TestSSHAuth" `
  -Action $action -Trigger $trigger `
  -User "NT AUTHORITY\SYSTEM" -RunLevel Highest

# Check task output
Get-ScheduledTaskInfo -TaskName "TestSSHAuth"
```

### 4. Registry Deep Scan

```powershell
# Search for any SSH-related registry restrictions
$paths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SSH',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL',
    'HKLM:\SOFTWARE\OpenSSH'
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Write-Host "Checking $path" -ForegroundColor Yellow
        Get-ItemProperty $path
    }
}

# Check for certificate restrictions
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography\OID\EncodingType 0\CertDllCreateCertificateChainEngine\Config"
```

---

## Recommendation Priority

Based on complexity and likelihood of success:

1. **Immediate**: Complete Key Vault password auth (90% done)
2. **Short-term**: Service Account approach (high success rate)
3. **Medium-term**: JEA Endpoint (most secure, Windows-native)
4. **Long-term**: Azure Arc or API Gateway (modern architecture)

## Security Comparison Matrix

| Solution | Security | Complexity | Maintenance | DC-Friendly | Audit |
|----------|----------|------------|-------------|-------------|-------|
| Password + Key Vault | Medium | Low | Medium | Yes | Good |
| Service Account + Keys | High | Medium | Low | Yes | Good |
| JEA Endpoint | Very High | Medium | Low | Native | Excellent |
| WinRM + Certs | High | High | Medium | Native | Good |
| Azure Arc | Very High | High | Low | Yes | Excellent |
| API Gateway | High | High | High | Yes | Excellent |

---

## Next Steps

1. Test service account approach (highest success probability)
2. If that fails, implement JEA endpoint (Windows-native solution)
3. Document successful approach for future reference
4. Implement automated password/key rotation regardless of solution

**Created:** October 30, 2025
**Author:** IT-Agent Analysis