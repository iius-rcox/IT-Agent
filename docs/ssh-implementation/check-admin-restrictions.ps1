# Check for Administrator account restrictions on Domain Controller
# Run on INSDAL9DC01

Write-Host "`n=== Check Administrator Account Status ===" -ForegroundColor Cyan
Get-ADUser -Identity Administrator -Properties * |
    Select-Object Enabled, LockedOut, AccountExpirationDate, PasswordExpired, PasswordLastSet, PasswordNeverExpires |
    Format-List

Write-Host "`n=== Check Deny Network Logon Policy ===" -ForegroundColor Cyan
secedit /export /cfg C:\temp-sec-policy.inf | Out-Null
$policy = Get-Content C:\temp-sec-policy.inf

Write-Host "SeDenyNetworkLogonRight (users denied network logon):"
$policy | Select-String "SeDenyNetworkLogonRight"

Write-Host "`nSeDenyRemoteInteractiveLogonRight (users denied RDP/RemoteInteractive):"
$policy | Select-String "SeDenyRemoteInteractiveLogonRight"

Remove-Item C:\temp-sec-policy.inf -ErrorAction SilentlyContinue

Write-Host "`n=== Check if Administrator is in specific groups ===" -ForegroundColor Cyan
Get-ADUser -Identity Administrator -Properties MemberOf |
    Select-Object -ExpandProperty MemberOf

Write-Host "`n=== Test Local SSH Authentication ===" -ForegroundColor Cyan
Write-Host "Testing from localhost (this should work if SSH is properly configured)..."
Write-Host "Command: ssh -o PubkeyAuthentication=no -o PasswordAuthentication=yes administrator@127.0.0.1 hostname"
Write-Host "Enter password when prompted (or Ctrl+C to skip):"
ssh -o PubkeyAuthentication=no -o PasswordAuthentication=yes -o PreferredAuthentications=password administrator@127.0.0.1 hostname 2>&1

Write-Host "`n=== Check Match Group Configuration ===" -ForegroundColor Cyan
Write-Host "Checking for Match Group administrators block in sshd_config:"
Get-Content "C:\ProgramData\ssh\sshd_config" |
    Select-String -Pattern "Match Group" -Context 0,5

Write-Host "`n=== Windows Defender Firewall - SSH Rules ===" -ForegroundColor Cyan
Get-NetFirewallRule | Where-Object { $_.DisplayName -match "SSH" -or $_.DisplayName -match "OpenSSH" } |
    Select-Object DisplayName, Enabled, Direction, Action |
    Format-Table -AutoSize
