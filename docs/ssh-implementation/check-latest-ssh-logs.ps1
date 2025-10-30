# Check latest SSH connection attempts
# Run on INSDAL9DC01 AFTER attempting SSH from AKS pod

Write-Host "`n=== Latest SSH Events (Last 10) ===" -ForegroundColor Cyan
Get-WinEvent -LogName "OpenSSH/Operational" -MaxEvents 10 |
    Select-Object TimeCreated, LevelDisplayName, Message |
    Format-Table -Wrap -AutoSize

Write-Host "`n=== Filtering for Connection/Reset/Auth Events ===" -ForegroundColor Cyan
Get-WinEvent -LogName "OpenSSH/Operational" -MaxEvents 30 |
    Where-Object { $_.Message -match "Connection|reset|authentication|Accepted|Failed" } |
    Select-Object TimeCreated, Message |
    Format-List

Write-Host "`n=== Current sshd_config (active lines) ===" -ForegroundColor Cyan
Get-Content "C:\ProgramData\ssh\sshd_config" |
    Where-Object { $_ -notmatch "^\s*#" -and $_ -match "\S" }

Write-Host "`n=== Testing LOCAL password SSH ===" -ForegroundColor Cyan
Write-Host "Attempting: ssh -o PubkeyAuthentication=no administrator@localhost hostname"
Write-Host "Enter password when prompted..."
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password administrator@localhost hostname 2>&1

Write-Host "`n=== Recent Security Events (Logon Failures) ===" -ForegroundColor Cyan
Get-WinEvent -LogName "Security" -MaxEvents 10 |
    Where-Object { $_.Id -in @(4625, 4648, 4776) } |
    Select-Object TimeCreated, Id, Message |
    Format-List
