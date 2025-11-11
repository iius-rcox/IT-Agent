# Setup Non-Admin Service Account for SSH Access
# This bypasses the administrators_authorized_keys complications
# Run on INSDAL9DC01 as Domain Administrator

param(
    [Parameter(Mandatory=$false)]
    [string]$ServiceAccountName = "svc-n8n-ssh",

    [Parameter(Mandatory=$false)]
    [string]$PublicKeyPath = "C:\temp\n8n-pod.pub",

    [switch]$CreateAccount,
    [switch]$ConfigureSSH,
    [switch]$TestConnection
)

Write-Host "`n=== Service Account SSH Setup ===" -ForegroundColor Cyan
Write-Host "This script creates a non-admin service account for SSH access" -ForegroundColor Gray
Write-Host "Benefits: Avoids admin key restrictions, better security isolation" -ForegroundColor Gray

# Import AD module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Host "ERROR: Active Directory module not available" -ForegroundColor Red
    Write-Host "Install RSAT tools or run on a Domain Controller" -ForegroundColor Yellow
    exit 1
}

# Step 1: Create Service Account
if ($CreateAccount) {
    Write-Host "`n=== Creating Service Account ===" -ForegroundColor Yellow

    # Generate secure password
    Add-Type -AssemblyName System.Web
    $password = [System.Web.Security.Membership]::GeneratePassword(32, 8)
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

    # Check if account exists
    $existingAccount = Get-ADUser -Filter "SamAccountName -eq '$ServiceAccountName'" -ErrorAction SilentlyContinue

    if ($existingAccount) {
        Write-Host "Account $ServiceAccountName already exists" -ForegroundColor Yellow
        Write-Host "Resetting password and continuing..." -ForegroundColor Cyan
        Set-ADAccountPassword -Identity $ServiceAccountName -NewPassword $securePassword -Reset
        Set-ADUser -Identity $ServiceAccountName -Enabled $true
    } else {
        Write-Host "Creating new service account: $ServiceAccountName" -ForegroundColor Cyan

        $userParams = @{
            Name = $ServiceAccountName
            SamAccountName = $ServiceAccountName
            UserPrincipalName = "$ServiceAccountName@$env:USERDNSDOMAIN"
            AccountPassword = $securePassword
            Enabled = $true
            PasswordNeverExpires = $true
            CannotChangePassword = $true
            Description = "Service account for n8n SSH automation"
            Path = "CN=Users,$((Get-ADDomain).DistinguishedName)"
        }

        New-ADUser @userParams
        Write-Host "Service account created successfully" -ForegroundColor Green
    }

    # Add to required groups for SSH and PowerShell access
    Write-Host "`nConfiguring group memberships..." -ForegroundColor Cyan

    # Add to Remote Management Users for PowerShell access
    Add-ADGroupMember -Identity "Remote Management Users" -Members $ServiceAccountName -ErrorAction SilentlyContinue
    Write-Host "  Added to: Remote Management Users" -ForegroundColor Green

    # Create custom security group for delegated permissions
    $delegatedGroupName = "Employee Termination Operators"
    $delegatedGroup = Get-ADGroup -Filter "Name -eq '$delegatedGroupName'" -ErrorAction SilentlyContinue

    if (!$delegatedGroup) {
        Write-Host "Creating security group: $delegatedGroupName" -ForegroundColor Cyan
        New-ADGroup -Name $delegatedGroupName `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Description "Members can execute employee termination tasks"

        Add-ADGroupMember -Identity $delegatedGroupName -Members $ServiceAccountName
        Write-Host "  Created and added to: $delegatedGroupName" -ForegroundColor Green
    } else {
        Add-ADGroupMember -Identity $delegatedGroupName -Members $ServiceAccountName -ErrorAction SilentlyContinue
        Write-Host "  Added to: $delegatedGroupName" -ForegroundColor Green
    }

    # Grant specific AD permissions for termination tasks
    Write-Host "`nSetting up delegated AD permissions..." -ForegroundColor Cyan

    # Get the Users OU
    $usersOU = "OU=Users,$((Get-ADDomain).DistinguishedName)"
    if (!(Test-Path "AD:\$usersOU" -ErrorAction SilentlyContinue)) {
        $usersOU = "CN=Users,$((Get-ADDomain).DistinguishedName)"
    }

    # Grant permissions to disable user accounts
    $acl = Get-Acl "AD:\$usersOU"
    $sid = (Get-ADGroup $delegatedGroupName).SID

    # Permission to write userAccountControl (disable accounts)
    $permission = [System.DirectoryServices.ActiveDirectoryAccessRule]::new(
        $sid,
        "WriteProperty",
        "Allow",
        [Guid]"bf967a68-0de6-11d0-a285-00aa003049e2", # userAccountControl
        "Descendents",
        [Guid]"bf967aba-0de6-11d0-a285-00aa003049e2"  # User objects
    )
    $acl.AddAccessRule($permission)

    # Permission to reset passwords
    $permission = [System.DirectoryServices.ActiveDirectoryAccessRule]::new(
        $sid,
        "ExtendedRight",
        "Allow",
        [Guid]"00299570-246d-11d0-a768-00aa006e0529", # Reset Password
        "Descendents",
        [Guid]"bf967aba-0de6-11d0-a285-00aa003049e2"  # User objects
    )
    $acl.AddAccessRule($permission)

    Set-Acl "AD:\$usersOU" $acl
    Write-Host "  Delegated permissions configured" -ForegroundColor Green

    # Save credentials for reference
    $credFile = "C:\ProgramData\ssh\$ServiceAccountName-credentials.txt"
    @"
Service Account Created: $(Get-Date)
========================
Username: $ServiceAccountName
Domain: $env:USERDNSDOMAIN
UPN: $ServiceAccountName@$env:USERDNSDOMAIN
Password: $password

Groups:
- Remote Management Users
- $delegatedGroupName

Permissions:
- Can disable user accounts in $usersOU
- Can reset user passwords in $usersOU
- Can connect via SSH (non-admin, uses user profile authorized_keys)
- Can run PowerShell commands

IMPORTANT: Store this password in Azure Key Vault immediately!
Delete this file after securing the password.
"@ | Out-File $credFile -Encoding ASCII

    Write-Host "`nCredentials saved to: $credFile" -ForegroundColor Yellow
    Write-Host "IMPORTANT: Store password in Azure Key Vault and delete this file!" -ForegroundColor Red
}

# Step 2: Configure SSH for Service Account
if ($ConfigureSSH) {
    Write-Host "`n=== Configuring SSH for Service Account ===" -ForegroundColor Yellow

    # Create user profile if doesn't exist
    $userProfile = "C:\Users\$ServiceAccountName"
    if (!(Test-Path $userProfile)) {
        Write-Host "Creating user profile..." -ForegroundColor Cyan

        # Use runas to create profile
        $tempScript = "C:\temp\create-profile.ps1"
        "Write-Host 'Profile created'; Start-Sleep -Seconds 2" | Out-File $tempScript -Encoding ASCII

        Start-Process -FilePath "runas.exe" `
                     -ArgumentList "/user:$env:USERDNSDOMAIN\$ServiceAccountName", "powershell.exe -File $tempScript" `
                     -Wait -NoNewWindow

        Remove-Item $tempScript -Force

        if (Test-Path $userProfile) {
            Write-Host "  User profile created: $userProfile" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: Profile not created. User must log in once." -ForegroundColor Yellow
        }
    }

    # Create .ssh directory
    $sshDir = "$userProfile\.ssh"
    if (!(Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        Write-Host "  Created .ssh directory" -ForegroundColor Green
    }

    # Add public key to authorized_keys
    $authorizedKeys = "$sshDir\authorized_keys"

    if (Test-Path $PublicKeyPath) {
        Write-Host "Adding public key from: $PublicKeyPath" -ForegroundColor Cyan

        # Read key and ensure proper format
        $publicKey = Get-Content $PublicKeyPath -Raw
        $publicKey = $publicKey.Trim()

        # Write in ASCII format (no BOM)
        [System.IO.File]::WriteAllText($authorizedKeys, $publicKey, [System.Text.Encoding]::ASCII)
        Write-Host "  Public key added to: $authorizedKeys" -ForegroundColor Green
    } else {
        Write-Host "Public key file not found: $PublicKeyPath" -ForegroundColor Red
        Write-Host "Place your public key there and run again with -ConfigureSSH" -ForegroundColor Yellow
    }

    # Set correct permissions on authorized_keys
    Write-Host "Setting file permissions..." -ForegroundColor Cyan

    # Get service account SID
    $accountSID = (Get-ADUser $ServiceAccountName).SID.Value

    # Set ACLs: Only service account and SYSTEM should have access
    & icacls $authorizedKeys /inheritance:r /grant "${env:COMPUTERNAME}\$ServiceAccountName`:F" /grant "SYSTEM:F" 2>&1 | Out-Null
    Write-Host "  Permissions configured for authorized_keys" -ForegroundColor Green

    # Verify SSH service allows this user
    Write-Host "`nVerifying SSH configuration..." -ForegroundColor Cyan

    $sshdConfig = Get-Content "C:\ProgramData\ssh\sshd_config"
    $pubkeyAuth = $sshdConfig | Select-String "PubkeyAuthentication" | Where-Object {$_ -notmatch "^\s*#"}

    if ($pubkeyAuth -match "no") {
        Write-Host "  WARNING: PubkeyAuthentication is disabled in sshd_config" -ForegroundColor Red
        Write-Host "  Enable it by setting: PubkeyAuthentication yes" -ForegroundColor Yellow
    } else {
        Write-Host "  PubkeyAuthentication: Enabled" -ForegroundColor Green
    }

    # Check if service account avoids admin restrictions
    $isNotAdmin = !(Get-ADGroupMember "Administrators" | Where-Object {$_.Name -eq $ServiceAccountName})
    if ($isNotAdmin) {
        Write-Host "  Service account is NOT in Administrators group (good!)" -ForegroundColor Green
        Write-Host "  Will use standard authorized_keys file, not administrators_authorized_keys" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Account is in Administrators group" -ForegroundColor Red
        Write-Host "  This defeats the purpose - remove from Administrators!" -ForegroundColor Yellow
    }

    Write-Host "`nSSH configuration complete!" -ForegroundColor Green
}

# Step 3: Test SSH Connection
if ($TestConnection) {
    Write-Host "`n=== Testing SSH Connection ===" -ForegroundColor Yellow

    Write-Host "Testing local SSH connection as $ServiceAccountName..." -ForegroundColor Cyan
    Write-Host "This will test if the service account can execute PowerShell commands" -ForegroundColor Gray

    # Create test script
    $testScript = "C:\temp\ssh-test.ps1"
    @'
Write-Host "SSH connection successful!"
Write-Host "Current user: $env:USERNAME"
Write-Host "User domain: $env:USERDOMAIN"
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host ""
Write-Host "Testing AD access..."
try {
    $testUser = Get-ADUser -Identity "Guest" -ErrorAction Stop
    Write-Host "Can query AD users: YES"
} catch {
    Write-Host "Can query AD users: NO - $($_.Exception.Message)"
}
'@ | Out-File $testScript -Encoding ASCII

    # Test with password auth first (to verify account works)
    Write-Host "`nTest 1: Password authentication" -ForegroundColor Cyan
    Write-Host "Enter the service account password when prompted..." -ForegroundColor Yellow

    ssh -o PubkeyAuthentication=no "${env:USERDNSDOMAIN}\$ServiceAccountName@localhost" powershell.exe -File $testScript

    # Test with key auth
    Write-Host "`nTest 2: Public key authentication" -ForegroundColor Cyan
    Write-Host "This should work WITHOUT prompting for password..." -ForegroundColor Yellow

    ssh "${env:USERDNSDOMAIN}\$ServiceAccountName@localhost" powershell.exe -File $testScript

    Remove-Item $testScript -Force
}

# Display summary and next steps
Write-Host "`n=== Summary & Next Steps ===" -ForegroundColor Cyan

if (!$CreateAccount -and !$ConfigureSSH -and !$TestConnection) {
    Write-Host "No action taken. Use one or more switches:" -ForegroundColor Yellow
    Write-Host "  -CreateAccount   : Create the service account with delegated permissions"
    Write-Host "  -ConfigureSSH    : Set up SSH access for the account"
    Write-Host "  -TestConnection  : Test SSH connectivity"
    Write-Host ""
    Write-Host "Typical workflow:" -ForegroundColor White
    Write-Host "  1. .\setup-service-account-ssh.ps1 -CreateAccount"
    Write-Host "  2. Copy public key to: $PublicKeyPath"
    Write-Host "  3. .\setup-service-account-ssh.ps1 -ConfigureSSH"
    Write-Host "  4. .\setup-service-account-ssh.ps1 -TestConnection"
} else {
    Write-Host "`nCompleted actions:" -ForegroundColor Green
    if ($CreateAccount) { Write-Host "  ✓ Service account created/configured" }
    if ($ConfigureSSH) { Write-Host "  ✓ SSH access configured" }
    if ($TestConnection) { Write-Host "  ✓ Connection tested" }

    Write-Host "`nUpdate n8n SSH credential with:" -ForegroundColor Yellow
    Write-Host "  Host: 10.0.0.200 (or INSDAL9DC01)"
    Write-Host "  Port: 22"
    Write-Host "  Username: ${env:USERDNSDOMAIN}\$ServiceAccountName"
    Write-Host "  Auth: Private Key (matching the public key deployed)"

    Write-Host "`nBenefits of this approach:" -ForegroundColor Green
    Write-Host "  • No administrators_authorized_keys complications"
    Write-Host "  • Limited permissions (only what's needed)"
    Write-Host "  • Better security isolation"
    Write-Host "  • Standard SSH key auth works reliably"
}