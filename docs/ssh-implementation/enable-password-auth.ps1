# Enable Password Authentication for SSH on Windows DC
# Run on INSDAL9DC01

Write-Host "`n=== Enabling PasswordAuthentication in sshd_config ===" -ForegroundColor Cyan

$configPath = "C:\ProgramData\ssh\sshd_config"
$config = Get-Content $configPath

# Check if PasswordAuthentication is already set
$hasPasswordAuth = $config | Where-Object { $_ -match "^\s*PasswordAuthentication\s+" -and $_ -notmatch "^\s*#" }

if ($hasPasswordAuth) {
    Write-Host "PasswordAuthentication is already configured:" -ForegroundColor Yellow
    $hasPasswordAuth

    # Check if it's set to 'no'
    if ($hasPasswordAuth -match "no") {
        Write-Host "`nChanging 'no' to 'yes'..." -ForegroundColor Yellow
        $config = $config -replace "^\s*PasswordAuthentication\s+no", "PasswordAuthentication yes"
        Set-Content -Path $configPath -Value $config
        Write-Host "Updated to: PasswordAuthentication yes" -ForegroundColor Green
    } else {
        Write-Host "`nAlready set to 'yes' - no changes needed" -ForegroundColor Green
    }
} else {
    Write-Host "PasswordAuthentication not found in config. Adding it..." -ForegroundColor Yellow

    # Add before the Match Group line
    $newConfig = @()
    $added = $false

    foreach ($line in $config) {
        if ($line -match "^\s*Match Group" -and -not $added) {
            $newConfig += "PasswordAuthentication yes"
            $newConfig += ""
            $added = $true
        }
        $newConfig += $line
    }

    # If no Match Group found, just add at the end
    if (-not $added) {
        $newConfig += ""
        $newConfig += "PasswordAuthentication yes"
    }

    Set-Content -Path $configPath -Value $newConfig
    Write-Host "Added: PasswordAuthentication yes" -ForegroundColor Green
}

Write-Host "`n=== Verifying Configuration ===" -ForegroundColor Cyan
Get-Content $configPath | Select-String "PasswordAuthentication"

Write-Host "`n=== Restarting SSH Service ===" -ForegroundColor Cyan
Restart-Service sshd

Start-Sleep -Seconds 2

Write-Host "`n=== Service Status ===" -ForegroundColor Cyan
Get-Service sshd | Format-List Name, Status, StartType

Write-Host "`n=== Testing Configuration ===" -ForegroundColor Cyan
$testResult = & "C:\Windows\System32\OpenSSH\sshd.exe" -t 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Configuration syntax is valid!" -ForegroundColor Green
} else {
    Write-Host "Configuration has errors:" -ForegroundColor Red
    $testResult
}

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host "PasswordAuthentication is now enabled. Test from AKS pod." -ForegroundColor Cyan
