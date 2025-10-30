# Check if password authentication is enabled
# Run on INSDAL9DC01

Write-Host "`n=== Checking PasswordAuthentication Setting ===" -ForegroundColor Cyan

$sshd_config = Get-Content "C:\ProgramData\ssh\sshd_config"

Write-Host "`nAll PasswordAuthentication lines:" -ForegroundColor Yellow
$sshd_config | Select-String "PasswordAuthentication"

Write-Host "`n`nActive (uncommented) lines only:" -ForegroundColor Yellow
$sshd_config | Where-Object { $_ -match "^\s*PasswordAuthentication" -and $_ -notmatch "^\s*#" }

Write-Host "`n`nFull sshd_config (non-comment lines):" -ForegroundColor Yellow
$sshd_config | Where-Object { $_ -notmatch "^\s*#" -and $_ -match "\S" }

Write-Host "`n`n=== Testing SSH locally with password ===" -ForegroundColor Cyan
Write-Host "Note: You'll need to enter the Administrator password"
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password administrator@localhost hostname
