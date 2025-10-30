# Check Available AD Management Options for n8n
# Run this on your Domain Controller to determine the best approach

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host " AD Management Options Checker for n8n" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan

$results = @{
    GraphAPI = $false
    LDAP = $false
    LDAPS = $false
    SSH = $false
    WinRM = $false
    Recommendations = @()
}

# 1. Check Azure AD Connect (for Microsoft Graph API)
Write-Host "Checking Azure AD Connect..." -ForegroundColor Yellow
$azureADConnect = Get-Service "ADSync" -ErrorAction SilentlyContinue
if ($azureADConnect) {
    Write-Host "  ✅ Azure AD Connect is installed and $($azureADConnect.Status)" -ForegroundColor Green
    $results.GraphAPI = $true
    $results.Recommendations += "Microsoft Graph API (Best Option)"

    # Check sync status
    try {
        Import-Module ADSync -ErrorAction SilentlyContinue
        $syncStatus = Get-ADSyncScheduler -ErrorAction SilentlyContinue
        if ($syncStatus) {
            Write-Host "  ℹ️  Sync is $($syncStatus.SyncCycleEnabled) (Interval: $($syncStatus.CustomizedSyncCycleInterval))" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "  ⚠️  Could not check sync status" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ❌ Azure AD Connect not found" -ForegroundColor Red
    Write-Host "  ℹ️  To use Microsoft Graph API, install Azure AD Connect" -ForegroundColor Yellow
}

# 2. Check LDAP availability
Write-Host "`nChecking LDAP Services..." -ForegroundColor Yellow
$ldapPort = Test-NetConnection -ComputerName localhost -Port 389 -InformationLevel Quiet -WarningAction SilentlyContinue
$ldapsPort = Test-NetConnection -ComputerName localhost -Port 636 -InformationLevel Quiet -WarningAction SilentlyContinue

if ($ldapPort) {
    Write-Host "  ✅ LDAP is available on port 389" -ForegroundColor Green
    $results.LDAP = $true

    if ($ldapsPort) {
        Write-Host "  ✅ LDAPS (Secure LDAP) is available on port 636" -ForegroundColor Green
        $results.LDAPS = $true
        $results.Recommendations += "Direct LDAPS Connection (Recommended)"
    } else {
        Write-Host "  ⚠️  LDAPS not configured on port 636" -ForegroundColor Yellow
        Write-Host "  ℹ️  To enable LDAPS, configure AD Certificate Services" -ForegroundColor Yellow
        $results.Recommendations += "Direct LDAP Connection (Not Secure - Configure LDAPS)"
    }

    # Check for LDAP certificate
    $certs = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match $env:COMPUTERNAME }
    if ($certs) {
        Write-Host "  ℹ️  Found $($certs.Count) certificate(s) for LDAPS" -ForegroundColor Cyan
    }
} else {
    Write-Host "  ❌ LDAP service not responding" -ForegroundColor Red
}

# 3. Check SSH Service (current approach)
Write-Host "`nChecking SSH Service..." -ForegroundColor Yellow
$sshService = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshService) {
    Write-Host "  ✅ SSH service is $($sshService.Status)" -ForegroundColor Green
    $results.SSH = $true

    # Check SSH configuration
    if (Test-Path "C:\ProgramData\ssh\sshd_config") {
        $sshConfig = Get-Content "C:\ProgramData\ssh\sshd_config" | Select-String "PasswordAuthentication|PubkeyAuthentication" | Where-Object { $_ -notmatch "^#" }
        Write-Host "  ℹ️  SSH Configuration:" -ForegroundColor Cyan
        $sshConfig | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
    }

    $results.Recommendations += "SSH + PowerShell (Current Approach)"
} else {
    Write-Host "  ❌ SSH not installed or configured" -ForegroundColor Red
}

# 4. Check WinRM Service
Write-Host "`nChecking WinRM Service..." -ForegroundColor Yellow
$winrmService = Get-Service WinRM -ErrorAction SilentlyContinue
if ($winrmService -and $winrmService.Status -eq "Running") {
    Write-Host "  ✅ WinRM is $($winrmService.Status)" -ForegroundColor Green
    $results.WinRM = $true

    # Check WinRM listeners
    try {
        $listeners = Get-WSManInstance -ResourceURI winrm/config/listener -Enumerate -ErrorAction SilentlyContinue
        if ($listeners) {
            Write-Host "  ℹ️  WinRM Listeners configured: $($listeners.Count)" -ForegroundColor Cyan
            $listeners | ForEach-Object {
                Write-Host "      Transport: $($_.Transport), Address: $($_.Address)" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "  ⚠️  Could not enumerate WinRM listeners" -ForegroundColor Yellow
    }

    $results.Recommendations += "PowerShell Remoting via WinRM"
} else {
    Write-Host "  ❌ WinRM not running" -ForegroundColor Red
}

# 5. Check Network Connectivity from AKS
Write-Host "`nChecking Network Accessibility..." -ForegroundColor Yellow
$ipAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "^127\." -and $_.IPAddress -notmatch "^169\.254\." } | Select-Object -First 1).IPAddress
Write-Host "  ℹ️  DC IP Address: $ipAddress" -ForegroundColor Cyan

# Check Windows Firewall rules
$firewallRules = Get-NetFirewallRule | Where-Object {
    $_.Enabled -eq 'True' -and
    $_.Direction -eq 'Inbound' -and
    ($_.DisplayName -match 'LDAP|SSH|WinRM|Remote')
}

if ($firewallRules) {
    Write-Host "  ℹ️  Relevant Firewall Rules:" -ForegroundColor Cyan
    $firewallRules | Select-Object -First 5 | ForEach-Object {
        Write-Host "      $($_.DisplayName) - Port: $(Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_ | Select-Object -ExpandProperty LocalPort)" -ForegroundColor Gray
    }
}

# 6. Check Active Directory Module
Write-Host "`nChecking PowerShell AD Module..." -ForegroundColor Yellow
if (Get-Module -ListAvailable -Name ActiveDirectory) {
    Write-Host "  ✅ Active Directory PowerShell module available" -ForegroundColor Green

    # Test AD connectivity
    try {
        $domain = Get-ADDomain -ErrorAction SilentlyContinue
        if ($domain) {
            Write-Host "  ℹ️  Domain: $($domain.DNSRoot)" -ForegroundColor Cyan
            Write-Host "  ℹ️  Forest: $($domain.Forest)" -ForegroundColor Cyan
            Write-Host "  ℹ️  Domain Controllers: $($domain.ReplicaDirectoryServers.Count)" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "  ⚠️  Could not query AD domain" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ❌ Active Directory module not found" -ForegroundColor Red
}

# 7. Summary and Recommendations
Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host " SUMMARY & RECOMMENDATIONS" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan

Write-Host "Available Options:" -ForegroundColor Green
if ($results.GraphAPI) { Write-Host "  ✅ Microsoft Graph API (via Azure AD Connect)" -ForegroundColor Green }
if ($results.LDAPS) { Write-Host "  ✅ Secure LDAP (LDAPS)" -ForegroundColor Green }
elseif ($results.LDAP) { Write-Host "  ⚠️  LDAP (Not Secure)" -ForegroundColor Yellow }
if ($results.SSH) { Write-Host "  ✅ SSH + PowerShell" -ForegroundColor Green }
if ($results.WinRM) { Write-Host "  ✅ PowerShell Remoting (WinRM)" -ForegroundColor Green }

Write-Host "`nRecommended Approach Priority:" -ForegroundColor Cyan
$priority = 1
foreach ($rec in $results.Recommendations) {
    Write-Host "  $priority. $rec" -ForegroundColor White
    $priority++
}

# Specific action items
Write-Host "`nNext Steps:" -ForegroundColor Yellow

if ($results.GraphAPI) {
    Write-Host @"
  For Microsoft Graph API:
    1. Create Azure App Registration
    2. Grant User.ReadWrite.All permission
    3. Configure n8n Microsoft Entra ID node
    4. Test with provided workflow examples
"@ -ForegroundColor White
} elseif ($results.LDAPS) {
    Write-Host @"
  For LDAPS Connection:
    1. Create LDAP service account
    2. Configure n8n LDAP node with port 636
    3. Use provided LDAP workflow examples
"@ -ForegroundColor White
} elseif ($results.SSH) {
    Write-Host @"
  For SSH (Current Approach):
    1. Complete Key Vault integration
    2. Use service account instead of Administrator
    3. Consider moving to Graph API or LDAP later
"@ -ForegroundColor White
} else {
    Write-Host @"
  No optimal solution currently available. Consider:
    1. Installing Azure AD Connect for Graph API
    2. Configuring LDAPS for direct connection
    3. Enabling SSH service
"@ -ForegroundColor Yellow
}

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host " Configuration Files Generated:" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  - AD-MANAGEMENT-BEST-PRACTICES.md" -ForegroundColor White
Write-Host "  - QUICK-DECISION-GUIDE.md" -ForegroundColor White
Write-Host "  - n8n-workflow-examples.json" -ForegroundColor White
Write-Host "  - create-service-account.ps1" -ForegroundColor White

Write-Host "`nRun completed successfully!" -ForegroundColor Green