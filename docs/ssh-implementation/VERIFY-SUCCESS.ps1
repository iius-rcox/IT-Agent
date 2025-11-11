# Verify AD Automation Success
# Run after implementing password auth with Key Vault

Write-Host "`n=== AD Automation Verification Checklist ===" -ForegroundColor Cyan
Write-Host "This script verifies each component is working correctly" -ForegroundColor Gray

$checks = @{
    "AKS Pod Running" = $false
    "Workload Identity Active" = $false
    "Key Vault Accessible" = $false
    "SSH Connection Working" = $false
    "PowerShell Script Executable" = $false
    "AD Commands Functional" = $false
}

Write-Host "`n[1/6] Checking AKS Pod Status..." -ForegroundColor Yellow
$podStatus = kubectl get pods -n n8n -o json | ConvertFrom-Json
if ($podStatus.items[0].status.phase -eq "Running") {
    $checks["AKS Pod Running"] = $true
    Write-Host "✅ Pod is running" -ForegroundColor Green
    $podName = $podStatus.items[0].metadata.name
    Write-Host "   Pod name: $podName" -ForegroundColor Gray
} else {
    Write-Host "❌ Pod is not running" -ForegroundColor Red
    Write-Host "   Run: .\fix-aks-resources.ps1 -QuickFix" -ForegroundColor Yellow
}

Write-Host "`n[2/6] Checking Workload Identity..." -ForegroundColor Yellow
$azureVars = kubectl exec -n n8n $podName -- env | Select-String "AZURE_"
if ($azureVars) {
    $checks["Workload Identity Active"] = $true
    Write-Host "✅ Workload identity configured" -ForegroundColor Green
    $azureVars | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
} else {
    Write-Host "❌ Workload identity not active" -ForegroundColor Red
    Write-Host "   Pod needs to be restarted with identity enabled" -ForegroundColor Yellow
}

Write-Host "`n[3/6] Testing Key Vault Access..." -ForegroundColor Yellow
$tokenTest = kubectl exec -n n8n $podName -- sh -c 'curl -s -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" 2>/dev/null | grep access_token'
if ($tokenTest) {
    $checks["Key Vault Accessible"] = $true
    Write-Host "✅ Can acquire Key Vault token" -ForegroundColor Green
} else {
    Write-Host "❌ Cannot acquire Key Vault token" -ForegroundColor Red
    Write-Host "   Check workload identity configuration" -ForegroundColor Yellow
}

Write-Host "`n[4/6] Testing SSH Connection to DC..." -ForegroundColor Yellow
Write-Host "   Enter Administrator password to test:" -ForegroundColor Gray
$sshTest = ssh -o ConnectTimeout=5 -o PasswordAuthentication=yes administrator@10.0.0.200 "hostname" 2>&1
if ($sshTest -eq "INSDAL9DC01") {
    $checks["SSH Connection Working"] = $true
    Write-Host "✅ SSH connection successful" -ForegroundColor Green
} else {
    Write-Host "❌ SSH connection failed" -ForegroundColor Red
    Write-Host "   Check firewall and SSH service on DC" -ForegroundColor Yellow
}

Write-Host "`n[5/6] Checking Termination Script..." -ForegroundColor Yellow
$scriptExists = ssh administrator@10.0.0.200 "Test-Path 'C:\Scripts\Terminate-Employee.ps1'" 2>&1
if ($scriptExists -eq "True") {
    $checks["PowerShell Script Executable"] = $true
    Write-Host "✅ Termination script exists on DC" -ForegroundColor Green
} else {
    Write-Host "❌ Termination script not found" -ForegroundColor Red
    Write-Host "   Deploy Terminate-Employee.ps1 to C:\Scripts\ on DC" -ForegroundColor Yellow
}

Write-Host "`n[6/6] Testing AD Commands..." -ForegroundColor Yellow
$adTest = ssh administrator@10.0.0.200 "Get-ADUser -Identity Guest -ErrorAction SilentlyContinue | Select -ExpandProperty Name" 2>&1
if ($adTest -eq "Guest") {
    $checks["AD Commands Functional"] = $true
    Write-Host "✅ AD PowerShell commands working" -ForegroundColor Green
} else {
    Write-Host "❌ AD commands not working" -ForegroundColor Red
    Write-Host "   Ensure AD PowerShell module is installed" -ForegroundColor Yellow
}

Write-Host "`n=== Final Status ===" -ForegroundColor Cyan
$working = ($checks.Values | Where-Object {$_ -eq $true}).Count
$total = $checks.Count

if ($working -eq $total) {
    Write-Host "🎉 ALL CHECKS PASSED! System is ready for production!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. Test complete employee termination workflow from n8n"
    Write-Host "2. Set up monitoring and alerting"
    Write-Host "3. Document the solution"
    Write-Host "4. Plan migration to Graph API (optional)"
} else {
    Write-Host "⚠️  $working/$total checks passed" -ForegroundColor Yellow
    Write-Host "`nFailed checks:" -ForegroundColor Red
    $checks.GetEnumerator() | Where-Object {$_.Value -eq $false} | ForEach-Object {
        Write-Host "   ❌ $($_.Key)" -ForegroundColor Red
    }
    Write-Host "`nFix the failed items and run this script again" -ForegroundColor Yellow
}

Write-Host "`n=== Quick Test Command ===" -ForegroundColor Magenta
Write-Host "Test the full flow with this command:" -ForegroundColor Gray
Write-Host 'ssh administrator@10.0.0.200 "powershell -c \"Write-Host \"Connected as: `$env:USERNAME\"; Get-ADUser -Identity Guest | Select Name, Enabled\""' -ForegroundColor White