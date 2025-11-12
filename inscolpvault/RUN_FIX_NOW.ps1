# RUN THIS SCRIPT IMMEDIATELY TO FIX TIMEOUT ISSUES
# Requires SQL Server credentials

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,

    [Parameter(Mandatory=$true)]
    [SecureString]$Password
)

$Server = "inscolpvault.insulationsinc.local,55859"
$Database = "PaperlessEnvironments"
$ScriptPath = "IMMEDIATE_FIX_SCRIPT.sql"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PVAULT TIMEOUT FIX - RUNNING NOW" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Convert secure string to plain text for sqlcmd
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

Write-Host "Connecting to: $Server" -ForegroundColor Yellow
Write-Host "Database: $Database" -ForegroundColor Yellow
Write-Host ""

# Run the fix script
Write-Host "Executing fix script..." -ForegroundColor Green
$output = sqlcmd -S $Server -d $Database -U $Username -P $PlainPassword -i $ScriptPath -b 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host $output
    Write-Host ""
    Write-Host "✓ FIX COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANT NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Test the invoice loading function NOW" -ForegroundColor White
    Write-Host "2. Check if timeout errors are resolved" -ForegroundColor White
    Write-Host "3. Monitor performance for 30 minutes" -ForegroundColor White
} else {
    Write-Host "✗ FIX FAILED!" -ForegroundColor Red
    Write-Host $output
    Write-Host ""
    Write-Host "Please run the script manually in SSMS:" -ForegroundColor Yellow
    Write-Host "  File: IMMEDIATE_FIX_SCRIPT.sql" -ForegroundColor White
}

# Clear password from memory
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")