# Create Service Account for n8n SSH Access
# This bypasses Administrator restrictions on Domain Controllers
# Run on INSDAL9DC01 as Domain Administrator

param(
    [string]$ServiceAccountName = "svc-n8n-ssh",
    [string]$PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII15oR1ICDywSpc0aBKNh8+5jRDVhYuAcIhw9MFUpScH n8n-dc-automation"
)

Write-Host "`n=== Creating Service Account for n8n SSH Access ===" -ForegroundColor Cyan

# Generate secure password
Add-Type -AssemblyName System.Web
$password = [System.Web.Security.Membership]::GeneratePassword(20, 5)
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force

Write-Host "`nGenerated secure password (save this in Azure Key Vault):" -ForegroundColor Yellow
Write-Host $password -ForegroundColor Green

# Create the service account
Write-Host "`nCreating service account: $ServiceAccountName" -ForegroundColor Cyan
try {
    New-ADUser -Name $ServiceAccountName `
        -UserPrincipalName "$ServiceAccountName@insulationsinc.local" `
        -AccountPassword $securePassword `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -CannotChangePassword $true `
        -Description "Service account for n8n SSH automation" `
        -ErrorAction Stop

    Write-Host "Service account created successfully!" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -match "already exists") {
        Write-Host "Service account already exists. Resetting password..." -ForegroundColor Yellow
        Set-ADAccountPassword -Identity $ServiceAccountName -NewPassword $securePassword -Reset
        Enable-ADAccount -Identity $ServiceAccountName
        Write-Host "Password reset and account enabled." -ForegroundColor Green
    } else {
        Write-Error $_
        exit 1
    }
}

# Add to necessary groups
Write-Host "`nAdding to security groups..." -ForegroundColor Cyan
$groups = @(
    "Remote Management Users",
    "Event Log Readers"
)

foreach ($group in $groups) {
    try {
        Add-ADGroupMember -Identity $group -Members $ServiceAccountName -ErrorAction Stop
        Write-Host "  + Added to: $group" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -match "already a member") {
            Write-Host "  - Already member of: $group" -ForegroundColor Yellow
        } else {
            Write-Warning "Failed to add to $group : $_"
        }
    }
}

# Grant specific delegated permissions for PowerShell execution
Write-Host "`nConfiguring delegation permissions..." -ForegroundColor Cyan
try {
    Set-ADUser $ServiceAccountName -Add @{
        'msDS-AllowedToDelegateTo' = @(
            'HOST/INSDAL9DC01.insulationsinc.local',
            'HOST/INSDAL9DC01',
            'WSMAN/INSDAL9DC01.insulationsinc.local',
            'WSMAN/INSDAL9DC01'
        )
    }
    Write-Host "Delegation permissions configured." -ForegroundColor Green
} catch {
    Write-Warning "Failed to set delegation: $_"
}

# Grant specific AD permissions for employee termination tasks
Write-Host "`nGranting AD permissions for user management..." -ForegroundColor Cyan

# Get the service account's SID
$serviceAccountSID = (Get-ADUser $ServiceAccountName).SID

# Create ACL for user management permissions
$rootDSE = Get-ADRootDSE
$usersDN = "CN=Users,$($rootDSE.defaultNamingContext)"

# Grant permissions to disable/modify user accounts
$acl = Get-Acl "AD:$usersDN"
$permission = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $serviceAccountSID,
    "GenericAll",
    "Allow",
    "Descendents",
    "bf967aba-0de6-11d0-a285-00aa003049e2"  # User class GUID
)
$acl.AddAccessRule($permission)
Set-Acl "AD:$usersDN" $acl
Write-Host "AD permissions granted for user management." -ForegroundColor Green

# Create local profile directory
Write-Host "`nCreating local user profile..." -ForegroundColor Cyan
$userProfile = "C:\Users\$ServiceAccountName"
$sshDir = "$userProfile\.ssh"

# Force create the directories
New-Item -Path $userProfile -ItemType Directory -Force | Out-Null
New-Item -Path $sshDir -ItemType Directory -Force | Out-Null

# Add the public key
Write-Host "Adding SSH public key..." -ForegroundColor Cyan
$authorizedKeysFile = "$sshDir\authorized_keys"
Set-Content -Path $authorizedKeysFile -Value $PublicKey -Encoding UTF8

# Set proper permissions
Write-Host "Setting NTFS permissions..." -ForegroundColor Cyan

# Profile directory
icacls $userProfile /inheritance:r /grant "${env:COMPUTERNAME}\${ServiceAccountName}:(OI)(CI)F" /grant "SYSTEM:(OI)(CI)F" /grant "Administrators:(OI)(CI)RX" | Out-Null

# .ssh directory
icacls $sshDir /inheritance:r /grant "${env:COMPUTERNAME}\${ServiceAccountName}:(OI)(CI)F" /grant "SYSTEM:(OI)(CI)F" | Out-Null

# authorized_keys file
icacls $authorizedKeysFile /inheritance:r /grant "${env:COMPUTERNAME}\${ServiceAccountName}:F" /grant "SYSTEM:F" | Out-Null

Write-Host "Permissions set successfully!" -ForegroundColor Green

# Update sshd_config if needed
Write-Host "`nChecking SSH configuration..." -ForegroundColor Cyan
$sshdConfig = Get-Content "C:\ProgramData\ssh\sshd_config"

# Check if we need to add configuration for non-admin users
if (-not ($sshdConfig -match "Match User $ServiceAccountName")) {
    Write-Host "Adding SSH configuration for service account..." -ForegroundColor Yellow

    # Add specific configuration for the service account
    $newConfig = @"

# Configuration for n8n service account
Match User $ServiceAccountName
    AuthorizedKeysFile .ssh/authorized_keys
    PasswordAuthentication yes
    PubkeyAuthentication yes
"@

    Add-Content "C:\ProgramData\ssh\sshd_config" $newConfig

    Write-Host "Restarting SSH service..." -ForegroundColor Cyan
    Restart-Service sshd
    Start-Sleep -Seconds 2
}

# Test the configuration
Write-Host "`n=== Testing Configuration ===" -ForegroundColor Cyan
$testResult = & "C:\Windows\System32\OpenSSH\sshd.exe" -t 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "SSH configuration is valid!" -ForegroundColor Green
} else {
    Write-Host "SSH configuration has errors:" -ForegroundColor Red
    $testResult
}

# Create a PowerShell profile for the service account with execution permissions
Write-Host "`nCreating PowerShell profile for service account..." -ForegroundColor Cyan
$psProfileDir = "$userProfile\Documents\WindowsPowerShell"
New-Item -Path $psProfileDir -ItemType Directory -Force | Out-Null

$profileContent = @'
# PowerShell profile for n8n service account
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Add Scripts directory to PATH
$env:Path += ";C:\Scripts"

# Function to execute employee termination
function Invoke-EmployeeTermination {
    param([string]$EmployeeID)
    & C:\Scripts\Terminate-Employee.ps1 -EmployeeID $EmployeeID
}

Write-Host "n8n service account PowerShell session initialized" -ForegroundColor Green
'@

Set-Content "$psProfileDir\Microsoft.PowerShell_profile.ps1" $profileContent

# Output summary
Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host @"

Service Account Created: $ServiceAccountName@insulationsinc.local
Password: $password

Next Steps:
1. Store the password in Azure Key Vault as backup
2. Test SSH connection from AKS:
   kubectl exec -n n8n-prod ssh-test -- ssh -i /root/.ssh/id_ed25519 $ServiceAccountName@10.0.0.200 whoami

3. If SSH key auth works, update n8n to use this account
4. If SSH key auth fails, the account can still use password auth

Permissions Granted:
- Remote Management Users
- Event Log Readers
- User account management in AD
- PowerShell script execution

SSH Configuration:
- Public key installed in: $authorizedKeysFile
- Both password and key authentication enabled
- Specific Match rule added to sshd_config

"@ -ForegroundColor Cyan

Write-Host "Script completed successfully!" -ForegroundColor Green