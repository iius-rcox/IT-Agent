# Microsoft Graph API Setup Script for n8n AD Management
# Run this on a machine with Azure PowerShell modules installed

param(
    [switch]$CheckOnly,
    [switch]$AutoSetup
)

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "  Microsoft Graph API Setup for n8n" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Function to check prerequisites
function Test-Prerequisites {
    Write-Host "`nChecking Prerequisites..." -ForegroundColor Yellow

    $hasIssues = $false

    # Check Azure PowerShell
    if (Get-Module -ListAvailable -Name Az.Accounts) {
        Write-Host "  ✅ Azure PowerShell module installed" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Azure PowerShell not installed" -ForegroundColor Red
        Write-Host "     Install with: Install-Module -Name Az -AllowClobber -Force" -ForegroundColor Yellow
        $hasIssues = $true
    }

    # Check Azure CLI
    try {
        $azVersion = az version 2>$null | ConvertFrom-Json
        if ($azVersion) {
            Write-Host "  ✅ Azure CLI installed (version $($azVersion.'azure-cli'))" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ⚠️  Azure CLI not installed (optional)" -ForegroundColor Yellow
        Write-Host "     Download from: https://aka.ms/installazurecliwindows" -ForegroundColor Gray
    }

    # Check Azure AD Connect on DC
    Write-Host "`nChecking Azure AD Connect Status..." -ForegroundColor Yellow

    if ($env:COMPUTERNAME -match "DC") {
        $adSync = Get-Service "ADSync" -ErrorAction SilentlyContinue
        if ($adSync) {
            Write-Host "  ✅ Azure AD Connect is $($adSync.Status)" -ForegroundColor Green

            # Check sync schedule
            try {
                Import-Module ADSync -ErrorAction SilentlyContinue
                $scheduler = Get-ADSyncScheduler -ErrorAction SilentlyContinue
                if ($scheduler) {
                    Write-Host "     Sync Enabled: $($scheduler.SyncCycleEnabled)" -ForegroundColor Cyan
                    Write-Host "     Next Sync: $($scheduler.NextSyncCycleStartTimeInUTC) UTC" -ForegroundColor Cyan
                }
            } catch {
                Write-Host "     Could not check sync schedule" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ❌ Azure AD Connect not installed" -ForegroundColor Red
            Write-Host "     Download from: https://www.microsoft.com/en-us/download/details.aspx?id=47594" -ForegroundColor Yellow
            $hasIssues = $true
        }
    } else {
        Write-Host "  ⚠️  Not running on DC - cannot check Azure AD Connect" -ForegroundColor Yellow
        Write-Host "     Run 'Get-Service ADSync' on your DC to verify" -ForegroundColor Gray
    }

    return -not $hasIssues
}

# Function to create app registration
function New-GraphAppRegistration {
    param(
        [string]$AppName = "n8n-ad-management"
    )

    Write-Host "`nCreating App Registration..." -ForegroundColor Yellow

    # Login to Azure
    Write-Host "Logging into Azure..." -ForegroundColor Cyan
    Connect-AzAccount

    # Get tenant information
    $context = Get-AzContext
    $tenantId = $context.Tenant.Id
    Write-Host "  Tenant ID: $tenantId" -ForegroundColor Green

    # Create app registration using Azure CLI (more reliable for permissions)
    Write-Host "`nCreating app registration '$AppName'..." -ForegroundColor Cyan

    $appJson = az ad app create `
        --display-name $AppName `
        --sign-in-audience "AzureADMyOrg" 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ❌ Failed to create app registration" -ForegroundColor Red
        Write-Host "     You may need to login first: az login" -ForegroundColor Yellow
        return $null
    }

    $app = $appJson | ConvertFrom-Json
    $appId = $app.appId

    Write-Host "  ✅ App Registration created" -ForegroundColor Green
    Write-Host "     Application ID: $appId" -ForegroundColor Cyan

    # Create client secret
    Write-Host "`nCreating client secret..." -ForegroundColor Yellow
    $secretJson = az ad app credential reset `
        --id $appId `
        --years 2 2>$null

    $secret = $secretJson | ConvertFrom-Json
    $clientSecret = $secret.password

    Write-Host "  ✅ Client secret created (expires in 2 years)" -ForegroundColor Green

    # Add required permissions
    Write-Host "`nAdding Microsoft Graph permissions..." -ForegroundColor Yellow

    # Permission IDs for Microsoft Graph
    $permissions = @(
        "741f803b-c850-494e-b5df-cde7c675a1ca", # User.ReadWrite.All
        "62a82d76-70ea-41e2-9197-370581804d09", # Group.ReadWrite.All
        "7ab1d382-f21e-4acd-a863-ba3e13f7da61"  # Directory.Read.All
    )

    foreach ($permId in $permissions) {
        az ad app permission add `
            --id $appId `
            --api "00000003-0000-0000-c000-000000000000" `
            --api-permissions "$permId=Role" 2>$null | Out-Null
    }

    Write-Host "  ✅ Permissions added" -ForegroundColor Green

    # Grant admin consent
    Write-Host "`nGranting admin consent..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3  # Wait for permissions to propagate

    az ad app permission admin-consent --id $appId 2>$null | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Admin consent granted" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Admin consent needs to be granted manually in Azure Portal" -ForegroundColor Yellow
    }

    # Return credentials
    return @{
        TenantId = $tenantId
        ClientId = $appId
        ClientSecret = $clientSecret
        AppName = $AppName
    }
}

# Function to test Graph API connection
function Test-GraphAPIConnection {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )

    Write-Host "`nTesting Microsoft Graph API connection..." -ForegroundColor Yellow

    # Get access token
    $body = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $ClientId
        client_secret = $ClientSecret
    }

    try {
        $tokenResponse = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -ContentType "application/x-www-form-urlencoded" `
            -Body $body -ErrorAction Stop

        Write-Host "  ✅ Successfully obtained access token" -ForegroundColor Green

        # Test API call
        $headers = @{
            "Authorization" = "Bearer $($tokenResponse.access_token)"
        }

        $users = Invoke-RestMethod -Method Get `
            -Uri "https://graph.microsoft.com/v1.0/users?`$top=3" `
            -Headers $headers -ErrorAction Stop

        Write-Host "  ✅ Successfully retrieved $($users.value.Count) users from Azure AD" -ForegroundColor Green

        if ($users.value.Count -gt 0) {
            Write-Host "`n  Sample users:" -ForegroundColor Cyan
            $users.value | Select-Object displayName, userPrincipalName | Format-Table
        }

        return $true
    }
    catch {
        Write-Host "  ❌ Connection failed: $_" -ForegroundColor Red
        return $false
    }
}

# Function to generate n8n configuration
function Get-N8nConfiguration {
    param(
        [hashtable]$Credentials
    )

    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "  n8n Configuration" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    Write-Host "`nUse these values in n8n:" -ForegroundColor Yellow
    Write-Host @"

Credential Type: Microsoft OAuth2 API

Grant Type: Client Credentials
Client ID: $($Credentials.ClientId)
Client Secret: $($Credentials.ClientSecret)
Access Token URL: https://login.microsoftonline.com/$($Credentials.TenantId)/oauth2/v2.0/token
Scope: https://graph.microsoft.com/.default

"@ -ForegroundColor White

    # Save to file
    $configFile = ".\graph-api-credentials.txt"
    @"
Microsoft Graph API Credentials for n8n
Generated: $(Get-Date)
========================================

App Name: $($Credentials.AppName)
Tenant ID: $($Credentials.TenantId)
Client ID: $($Credentials.ClientId)
Client Secret: $($Credentials.ClientSecret)

Access Token URL: https://login.microsoftonline.com/$($Credentials.TenantId)/oauth2/v2.0/token
Scope: https://graph.microsoft.com/.default

IMPORTANT: Keep this file secure and delete after configuring n8n!
"@ | Out-File -FilePath $configFile -Encoding UTF8

    Write-Host "`n✅ Configuration saved to: $configFile" -ForegroundColor Green
    Write-Host "⚠️  Delete this file after configuring n8n!" -ForegroundColor Yellow
}

# Main execution
if ($CheckOnly) {
    Write-Host "`nRunning in Check-Only mode..." -ForegroundColor Cyan
    $ready = Test-Prerequisites

    if ($ready) {
        Write-Host "`n✅ All prerequisites met! Ready to set up Microsoft Graph API." -ForegroundColor Green
        Write-Host "Run this script with -AutoSetup to create app registration automatically." -ForegroundColor Cyan
    } else {
        Write-Host "`n⚠️  Some prerequisites are missing. Address the issues above first." -ForegroundColor Yellow
    }
}
elseif ($AutoSetup) {
    Write-Host "`nRunning Automatic Setup..." -ForegroundColor Cyan

    $ready = Test-Prerequisites
    if (-not $ready) {
        Write-Host "`n⚠️  Cannot continue with setup. Fix prerequisites first." -ForegroundColor Yellow
        exit 1
    }

    # Create app registration
    $creds = New-GraphAppRegistration

    if ($creds) {
        # Test the connection
        $success = Test-GraphAPIConnection `
            -TenantId $creds.TenantId `
            -ClientId $creds.ClientId `
            -ClientSecret $creds.ClientSecret

        if ($success) {
            # Show n8n configuration
            Get-N8nConfiguration -Credentials $creds

            Write-Host "`n==========================================" -ForegroundColor Green
            Write-Host "  Setup Complete!" -ForegroundColor Green
            Write-Host "==========================================" -ForegroundColor Green
            Write-Host @"

Next Steps:
1. Configure n8n credential with the values above
2. Import the test workflow from n8n-workflow-examples.json
3. Test the connection
4. Delete the graph-api-credentials.txt file

"@ -ForegroundColor White
        }
    }
}
else {
    # Interactive mode
    Write-Host @"

This script helps you set up Microsoft Graph API for n8n AD management.

Options:
  -CheckOnly    : Check prerequisites only
  -AutoSetup    : Automatically create app registration and configure permissions

Example:
  .\setup-graph-api.ps1 -CheckOnly
  .\setup-graph-api.ps1 -AutoSetup

"@ -ForegroundColor White

    $choice = Read-Host "Would you like to check prerequisites? (Y/N)"
    if ($choice -eq 'Y') {
        $ready = Test-Prerequisites

        if ($ready) {
            $choice = Read-Host "`nPrerequisites met. Create app registration now? (Y/N)"
            if ($choice -eq 'Y') {
                $creds = New-GraphAppRegistration
                if ($creds) {
                    $success = Test-GraphAPIConnection `
                        -TenantId $creds.TenantId `
                        -ClientId $creds.ClientId `
                        -ClientSecret $creds.ClientSecret

                    if ($success) {
                        Get-N8nConfiguration -Credentials $creds
                    }
                }
            }
        }
    }
}

Write-Host "`nScript completed." -ForegroundColor Cyan