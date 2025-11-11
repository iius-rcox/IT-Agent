# Enhanced SSH Public Key Authentication Diagnostic Script
# Run on INSDAL9DC01 to diagnose key auth issues
# Based on troubleshooting steps from Windows OpenSSH documentation

param(
    [switch]$TestNonAdminAuth,
    [switch]$DisableAdminMatch,
    [switch]$RunDebugMode,
    [switch]$CheckACLs,
    [switch]$FixKeyFile
)

Write-Host "`n=== SSH Public Key Authentication Diagnostic Tool ===" -ForegroundColor Cyan
Write-Host "Current Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# 1. Check current user context and group membership
Write-Host "`n=== Current User Context ===" -ForegroundColor Yellow
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
Write-Host "User: $($currentUser.Name)"
$isAdmin = ([Security.Principal.WindowsPrincipal]$currentUser).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Is Administrator: $isAdmin" -ForegroundColor $(if($isAdmin){"Red"}else{"Green"})

# 2. Check authorized_keys file locations and contents
Write-Host "`n=== Authorized Keys File Analysis ===" -ForegroundColor Yellow

$adminKeysFile = "C:\ProgramData\ssh\administrators_authorized_keys"
$userKeysFile = "$env:USERPROFILE\.ssh\authorized_keys"

# Check admin keys file
if (Test-Path $adminKeysFile) {
    Write-Host "`nAdmin Keys File: $adminKeysFile" -ForegroundColor Cyan
    Write-Host "File exists: YES" -ForegroundColor Green

    # Check file encoding
    $bytes = [System.IO.File]::ReadAllBytes($adminKeysFile)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        Write-Host "WARNING: File has UTF-16 BOM - OpenSSH cannot read this!" -ForegroundColor Red
        Write-Host "Fix with: Set-Content -Path '$adminKeysFile' -Value (Get-Content $adminKeysFile) -Encoding ASCII" -ForegroundColor Yellow
    } else {
        Write-Host "File encoding: OK (no UTF-16 BOM detected)" -ForegroundColor Green
    }

    # Check ACLs
    Write-Host "`nFile Permissions (ACL):"
    $acl = Get-Acl $adminKeysFile
    $acl.Access | ForEach-Object {
        $color = "Gray"
        if ($_.IdentityReference -match "Administrators|SYSTEM") {
            $color = "Green"
        } elseif ($_.IdentityReference -notmatch "Administrators|SYSTEM") {
            $color = "Red"
        }
        Write-Host "  $($_.IdentityReference): $($_.FileSystemRights) [$($_.AccessControlType)]" -ForegroundColor $color
    }

    # Count keys in file
    $keyCount = (Get-Content $adminKeysFile | Where-Object {$_ -match "^ssh-"}).Count
    Write-Host "`nPublic keys in file: $keyCount"

    if ($keyCount -gt 0) {
        Write-Host "Key fingerprints:"
        Get-Content $adminKeysFile | Where-Object {$_ -match "^ssh-"} | ForEach-Object {
            $keyParts = $_ -split ' '
            Write-Host "  Type: $($keyParts[0]), Comment: $($keyParts[2])" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "`nAdmin Keys File: $adminKeysFile" -ForegroundColor Cyan
    Write-Host "File exists: NO" -ForegroundColor Red
}

# Check user keys file
if (Test-Path $userKeysFile) {
    Write-Host "`nUser Keys File: $userKeysFile" -ForegroundColor Cyan
    Write-Host "File exists: YES" -ForegroundColor Green
    $keyCount = (Get-Content $userKeysFile | Where-Object {$_ -match "^ssh-"}).Count
    Write-Host "Public keys in file: $keyCount"
} else {
    Write-Host "`nUser Keys File: $userKeysFile" -ForegroundColor Cyan
    Write-Host "File exists: NO" -ForegroundColor Yellow
}

# 3. Check sshd_config for Match Group administrators
Write-Host "`n=== SSH Server Configuration ===" -ForegroundColor Yellow
$sshdConfig = "C:\ProgramData\ssh\sshd_config"
$matchGroupAdmin = Get-Content $sshdConfig | Select-String "Match Group administrators" | Where-Object {$_ -notmatch "^\s*#"}

if ($matchGroupAdmin) {
    Write-Host "Match Group administrators: ENABLED" -ForegroundColor Red
    Write-Host "Admin users MUST use: $adminKeysFile" -ForegroundColor Yellow
    Write-Host "To test with user's authorized_keys, comment out these lines in sshd_config:" -ForegroundColor Yellow
    Write-Host "  # Match Group administrators"
    Write-Host "  #        AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys"
} else {
    Write-Host "Match Group administrators: DISABLED" -ForegroundColor Green
    Write-Host "All users use their profile's authorized_keys file" -ForegroundColor Green
}

# 4. Fix ACLs if requested
if ($CheckACLs -or $FixKeyFile) {
    Write-Host "`n=== Fixing ACLs on administrators_authorized_keys ===" -ForegroundColor Yellow

    if (Test-Path $adminKeysFile) {
        if ($FixKeyFile) {
            Write-Host "Applying correct ACLs..." -ForegroundColor Cyan
            & icacls $adminKeysFile /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" 2>&1
            Write-Host "ACLs fixed. Only Administrators and SYSTEM have access." -ForegroundColor Green
        } else {
            Write-Host "Run with -FixKeyFile to automatically fix ACLs" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Cannot fix ACLs - file does not exist" -ForegroundColor Red
    }
}

# 5. Test with disabled admin match if requested
if ($DisableAdminMatch) {
    Write-Host "`n=== Testing with Disabled Admin Match ===" -ForegroundColor Yellow
    Write-Host "Creating backup of sshd_config..." -ForegroundColor Cyan
    Copy-Item $sshdConfig "$sshdConfig.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    Write-Host "Commenting out Match Group administrators..." -ForegroundColor Cyan
    $content = Get-Content $sshdConfig
    $content = $content -replace '^(\s*)(Match Group administrators)', '$1# $2'
    $content = $content -replace '^(\s*)(AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys)', '$1# $2'
    Set-Content $sshdConfig $content

    Write-Host "Restarting SSH service..." -ForegroundColor Cyan
    Restart-Service sshd
    Start-Sleep -Seconds 2

    Write-Host "Configuration updated. Test SSH key auth now." -ForegroundColor Green
    Write-Host "To restore: Copy-Item '$sshdConfig.backup_*' '$sshdConfig' -Force; Restart-Service sshd" -ForegroundColor Yellow
}

# 6. Run sshd in debug mode if requested
if ($RunDebugMode) {
    Write-Host "`n=== Running SSH Server in Debug Mode ===" -ForegroundColor Yellow
    Write-Host "Stopping SSH service..." -ForegroundColor Cyan
    Stop-Service sshd

    Write-Host "`nStarting sshd in debug mode (Ctrl+C to stop):" -ForegroundColor Cyan
    Write-Host "Try connecting from your client while watching this output" -ForegroundColor Yellow
    Write-Host "Look for errors about:" -ForegroundColor Yellow
    Write-Host "  - Failed publickey for user"
    Write-Host "  - key_load_public: invalid format"
    Write-Host "  - Authentication refused"
    Write-Host "`nStarting debug server..." -ForegroundColor Green

    & "C:\Program Files\OpenSSH\sshd.exe" -d -d -d

    Write-Host "`nDebug session ended. Restarting SSH service..." -ForegroundColor Cyan
    Start-Service sshd
}

# 7. Check for domain account restrictions
Write-Host "`n=== Domain Account Settings ===" -ForegroundColor Yellow
try {
    $domainUser = Get-ADUser -Identity $env:USERNAME -Properties SmartCardLogonRequired, PasswordNeverExpires, AccountExpirationDate, Enabled
    Write-Host "Account: $($domainUser.SamAccountName)"
    Write-Host "  Enabled: $($domainUser.Enabled)" -ForegroundColor $(if($domainUser.Enabled){"Green"}else{"Red"})
    Write-Host "  SmartCard Required: $($domainUser.SmartCardLogonRequired)" -ForegroundColor $(if($domainUser.SmartCardLogonRequired){"Red"}else{"Green"})
    Write-Host "  Password Never Expires: $($domainUser.PasswordNeverExpires)"
    Write-Host "  Account Expiration: $($domainUser.AccountExpirationDate ?? 'Never')"
} catch {
    Write-Host "Unable to query AD user properties (may need RSAT tools)" -ForegroundColor Yellow
}

# 8. Recent SSH authentication attempts
Write-Host "`n=== Recent SSH Authentication Events ===" -ForegroundColor Yellow
$events = Get-WinEvent -LogName "OpenSSH/Operational" -MaxEvents 20 |
    Where-Object { $_.Message -match "publickey|password|Accepted|Failed|reset" }

if ($events) {
    $events | Select-Object TimeCreated, @{Name="Type";Expression={
        if ($_.Message -match "Accepted password") { "PASSWORD-SUCCESS" }
        elseif ($_.Message -match "Accepted publickey") { "KEY-SUCCESS" }
        elseif ($_.Message -match "Failed publickey") { "KEY-FAILED" }
        elseif ($_.Message -match "Failed password") { "PASSWORD-FAILED" }
        elseif ($_.Message -match "Connection reset.*preauth") { "KEY-REJECTED-PREAUTH" }
        else { "OTHER" }
    }}, Message | Format-Table -AutoSize -Wrap
} else {
    Write-Host "No recent authentication events found" -ForegroundColor Yellow
}

# 9. Recommendations
Write-Host "`n=== Recommendations Based on Analysis ===" -ForegroundColor Cyan

if ($isAdmin) {
    Write-Host "• You're testing with an Administrator account" -ForegroundColor Yellow
    Write-Host "  → Public key MUST be in: $adminKeysFile" -ForegroundColor White
    Write-Host "  → Consider using a non-admin service account instead" -ForegroundColor White
}

if ($matchGroupAdmin) {
    Write-Host "• Match Group administrators is ENABLED" -ForegroundColor Yellow
    Write-Host "  → Test with -DisableAdminMatch to use user's authorized_keys" -ForegroundColor White
}

if (!(Test-Path $adminKeysFile) -and $isAdmin) {
    Write-Host "• administrators_authorized_keys file is MISSING" -ForegroundColor Red
    Write-Host "  → Create it and add your public key" -ForegroundColor White
}

Write-Host "`n=== Quick Fix Options ===" -ForegroundColor Green
Write-Host "1. Use password auth with Azure Key Vault (90% complete already)"
Write-Host "2. Create non-admin service account 'svc-n8n-ssh' (avoids admin restrictions)"
Write-Host "3. Run: .\diagnose-ssh-key-auth.ps1 -DisableAdminMatch (test workaround)"
Write-Host "4. Run: .\diagnose-ssh-key-auth.ps1 -RunDebugMode (see detailed errors)"
Write-Host "5. Run: .\diagnose-ssh-key-auth.ps1 -FixKeyFile (fix ACLs on key file)"

Write-Host "`n=== Next Steps ===" -ForegroundColor Magenta
Write-Host "Based on the 'connection reset by peer [preauth]' error, the most likely issues are:"
Write-Host "1. Wrong authorized_keys file location (admin vs user)"
Write-Host "2. Incorrect file encoding (UTF-16 instead of ASCII)"
Write-Host "3. Wrong ACLs on administrators_authorized_keys"
Write-Host "4. Domain account restrictions (SmartCard required)"
Write-Host "`nRun this script with different switches to test each scenario." -ForegroundColor White