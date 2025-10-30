# Check OpenSSH Server Logs on Domain Controller
# Run this on INSDAL9DC01

# Check recent SSH connections
Write-Host "`n=== Recent SSH Connection Attempts (Last 20) ===" -ForegroundColor Cyan
Get-WinEvent -LogName "OpenSSH/Operational" -MaxEvents 20 |
    Select-Object TimeCreated, LevelDisplayName, Message |
    Format-Table -Wrap -AutoSize

Write-Host "`n=== SSH Authentication Errors ===" -ForegroundColor Cyan
Get-WinEvent -LogName "OpenSSH/Operational" -MaxEvents 50 |
    Where-Object { $_.Message -match "authentication|failed|error|reset" } |
    Select-Object TimeCreated, Message |
    Format-List

Write-Host "`n=== Security Event Log - Failed Logons ===" -ForegroundColor Cyan
Get-WinEvent -LogName "Security" -MaxEvents 20 |
    Where-Object { $_.Id -in @(4625, 4648) } |
    Select-Object TimeCreated, Id, Message |
    Format-List

Write-Host "`n=== Check SSH Service Status ===" -ForegroundColor Cyan
Get-Service sshd | Format-List

Write-Host "`n=== Current sshd_config (relevant lines) ===" -ForegroundColor Cyan
Get-Content "C:\ProgramData\ssh\sshd_config" |
    Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' } |
    Select-String -Pattern "(PubkeyAuthentication|PasswordAuthentication|PermitRootLogin|Match|AuthorizedKeys|LogLevel)"

Write-Host "`n=== Test if SSHD accepts connections ===" -ForegroundColor Cyan
Test-NetConnection -ComputerName localhost -Port 22 | Format-List

Write-Host "`n=== Active SSH Sessions ===" -ForegroundColor Cyan
netstat -ano | Select-String ":22"
