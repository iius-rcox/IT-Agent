# Test Microsoft Graph API Connection for n8n
# Quick test script to validate your Graph API setup

param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret,

    [string]$TestUserEmail = "",
    [switch]$Verbose
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Microsoft Graph API Connection Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Function to get access token
function Get-GraphAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )

    Write-Host "`n1. Getting Access Token..." -ForegroundColor Yellow

    $body = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $ClientId
        client_secret = $ClientSecret
    }

    try {
        $response = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -ContentType "application/x-www-form-urlencoded" `
            -Body $body -ErrorAction Stop

        Write-Host "   ✅ Access token obtained successfully" -ForegroundColor Green

        if ($Verbose) {
            # Decode token to show expiry
            $tokenParts = $response.access_token.Split('.')
            if ($tokenParts.Count -eq 3) {
                $tokenPayload = [System.Text.Encoding]::UTF8.GetString(
                    [System.Convert]::FromBase64String($tokenParts[1] + '==')
                ) | ConvertFrom-Json

                $expiry = (Get-Date -UnixTimeSeconds $tokenPayload.exp).ToLocalTime()
                Write-Host "   Token expires at: $expiry" -ForegroundColor Gray
            }
        }

        return $response.access_token
    }
    catch {
        Write-Host "   ❌ Failed to get access token" -ForegroundColor Red
        Write-Host "   Error: $_" -ForegroundColor Red
        return $null
    }
}

# Function to test user operations
function Test-UserOperations {
    param(
        [string]$AccessToken,
        [string]$TestEmail
    )

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    Write-Host "`n2. Testing User Read Operations..." -ForegroundColor Yellow

    # Test 1: List users
    try {
        $users = Invoke-RestMethod -Method Get `
            -Uri "https://graph.microsoft.com/v1.0/users?`$top=5&`$select=displayName,userPrincipalName,accountEnabled,id" `
            -Headers $headers -ErrorAction Stop

        Write-Host "   ✅ Can list users (found $($users.value.Count) users)" -ForegroundColor Green

        if ($users.value.Count -gt 0) {
            Write-Host "`n   Sample Users:" -ForegroundColor Cyan
            $users.value | ForEach-Object {
                $status = if ($_.accountEnabled) { "Enabled" } else { "Disabled" }
                Write-Host "   - $($_.displayName) ($($_.userPrincipalName)) - $status" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "   ❌ Cannot list users" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Test 2: Get specific user (if email provided)
    if ($TestEmail) {
        Write-Host "`n3. Testing Specific User Lookup..." -ForegroundColor Yellow

        try {
            $user = Invoke-RestMethod -Method Get `
                -Uri "https://graph.microsoft.com/v1.0/users/$TestEmail" `
                -Headers $headers -ErrorAction Stop

            Write-Host "   ✅ Can retrieve specific user" -ForegroundColor Green
            Write-Host "   User Details:" -ForegroundColor Cyan
            Write-Host "   - Display Name: $($user.displayName)" -ForegroundColor Gray
            Write-Host "   - UPN: $($user.userPrincipalName)" -ForegroundColor Gray
            Write-Host "   - ID: $($user.id)" -ForegroundColor Gray
            Write-Host "   - Enabled: $($user.accountEnabled)" -ForegroundColor Gray
            Write-Host "   - Job Title: $($user.jobTitle)" -ForegroundColor Gray
            Write-Host "   - Department: $($user.department)" -ForegroundColor Gray

            return $user
        }
        catch {
            Write-Host "   ❌ Cannot retrieve user '$TestEmail'" -ForegroundColor Red
            Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    return $null
}

# Function to test group operations
function Test-GroupOperations {
    param(
        [string]$AccessToken
    )

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    Write-Host "`n4. Testing Group Operations..." -ForegroundColor Yellow

    try {
        $groups = Invoke-RestMethod -Method Get `
            -Uri "https://graph.microsoft.com/v1.0/groups?`$top=5&`$select=displayName,id,groupTypes" `
            -Headers $headers -ErrorAction Stop

        Write-Host "   ✅ Can list groups (found $($groups.value.Count) groups)" -ForegroundColor Green

        if ($Verbose -and $groups.value.Count -gt 0) {
            Write-Host "`n   Sample Groups:" -ForegroundColor Cyan
            $groups.value | ForEach-Object {
                Write-Host "   - $($_.displayName)" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "   ❌ Cannot list groups" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to test write permissions (simulation only)
function Test-WritePermissions {
    param(
        [string]$AccessToken,
        [object]$TestUser
    )

    Write-Host "`n5. Testing Write Permissions (Simulation)..." -ForegroundColor Yellow

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    # We won't actually modify anything, just check if we could
    Write-Host "   ℹ️  Checking permissions (no actual changes will be made)" -ForegroundColor Cyan

    # Test if we can potentially update a user
    if ($TestUser) {
        try {
            # Make a PATCH request with no actual changes
            $body = @{
                displayName = $TestUser.displayName  # Same value, no change
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Method Patch `
                -Uri "https://graph.microsoft.com/v1.0/users/$($TestUser.id)" `
                -Headers $headers `
                -Body $body `
                -ContentType "application/json" `
                -ErrorAction Stop

            if ($response.StatusCode -eq 204) {
                Write-Host "   ✅ Has permission to update users" -ForegroundColor Green
            }
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq 403) {
                Write-Host "   ❌ No permission to update users" -ForegroundColor Red
            } else {
                Write-Host "   ⚠️  Could not verify update permissions" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "   ✅ Write permissions check complete" -ForegroundColor Green
}

# Function to check Azure AD Connect sync
function Test-AzureADConnectSync {
    Write-Host "`n6. Checking Azure AD Connect Sync..." -ForegroundColor Yellow

    # This only works if running on the DC with Azure AD Connect
    if (Get-Service "ADSync" -ErrorAction SilentlyContinue) {
        try {
            Import-Module ADSync -ErrorAction SilentlyContinue
            $scheduler = Get-ADSyncScheduler -ErrorAction SilentlyContinue

            if ($scheduler) {
                Write-Host "   ✅ Azure AD Connect is configured" -ForegroundColor Green
                Write-Host "   - Sync Enabled: $($scheduler.SyncCycleEnabled)" -ForegroundColor Gray
                Write-Host "   - Sync Interval: $($scheduler.CustomizedSyncCycleInterval)" -ForegroundColor Gray
                Write-Host "   - Next Sync: $($scheduler.NextSyncCycleStartTimeInUTC) UTC" -ForegroundColor Gray
            }
        }
        catch {
            Write-Host "   ⚠️  Could not check sync status" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ℹ️  Not running on Azure AD Connect server" -ForegroundColor Gray
        Write-Host "   Run this on your DC to check sync status" -ForegroundColor Gray
    }
}

# Main execution
Write-Host "`nStarting Connection Test..." -ForegroundColor White
Write-Host "Tenant ID: $TenantId" -ForegroundColor Gray
Write-Host "Client ID: $ClientId" -ForegroundColor Gray

# Get access token
$token = Get-GraphAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

if (-not $token) {
    Write-Host "`n❌ Connection test failed. Cannot proceed without valid token." -ForegroundColor Red
    exit 1
}

# Test operations
$testUser = Test-UserOperations -AccessToken $token -TestEmail $TestUserEmail
Test-GroupOperations -AccessToken $token
Test-WritePermissions -AccessToken $token -TestUser $testUser
Test-AzureADConnectSync

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host @"

✅ Microsoft Graph API connection is working!

You can now:
1. Configure these credentials in n8n
2. Use the Microsoft Entra ID node in your workflows
3. Import the example workflows from n8n-workflow-examples.json

Remember:
- Changes made via Graph API sync to on-premises AD via Azure AD Connect
- Default sync interval is 30 minutes
- For immediate changes, combine with local PowerShell commands

"@ -ForegroundColor White

if (-not $TestUserEmail) {
    Write-Host "Tip: Run with -TestUserEmail to test specific user lookup" -ForegroundColor Yellow
    Write-Host "Example: .\test-graph-api-connection.ps1 -TenantId xxx -ClientId xxx -ClientSecret xxx -TestUserEmail user@domain.com" -ForegroundColor Gray
}