# Microsoft Graph API Implementation for AD Management

## Quick Start Guide

This guide will help you implement Microsoft Graph API for managing Active Directory from n8n. This is the best approach for hybrid environments with Azure AD Connect.

## Prerequisites Checklist

### Step 1: Verify Azure AD Connect
Run this on your Domain Controller:

```powershell
# Check if Azure AD Connect is installed and running
Get-Service "ADSync" | Format-Table Name, Status, StartType

# If not installed, you'll need to set it up first
# Download from: https://www.microsoft.com/en-us/download/details.aspx?id=47594
```

**Expected Output:**
```
Name    Status  StartType
----    ------  ---------
ADSync  Running Automatic
```

If Azure AD Connect is NOT installed, you need to install it first. Otherwise, proceed to Step 2.

---

## Step 2: Create Azure App Registration

### Using Azure Portal (Easier)

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** → **App registrations** → **New registration**
3. Configure:
   - **Name**: `n8n-ad-management`
   - **Supported account types**: Accounts in this organizational directory only
   - **Redirect URI**: Leave blank for now
4. Click **Register**
5. Copy the **Application (client) ID** - you'll need this

### Using Azure CLI

```bash
# Login to Azure
az login

# Create app registration
az ad app create --display-name "n8n-ad-management" \
  --sign-in-audience "AzureADMyOrg" \
  --query appId -o tsv

# Save the output - this is your Client ID
```

---

## Step 3: Create Client Secret

### Using Azure Portal

1. In your app registration, go to **Certificates & secrets**
2. Click **New client secret**
3. Description: `n8n-access`
4. Expires: **24 months** (or your preference)
5. Click **Add**
6. **COPY THE VALUE NOW** (it won't be shown again)

### Using Azure CLI

```bash
# Replace <app-id> with your Application ID from Step 2
az ad app credential reset --id <app-id> \
  --query password -o tsv

# Save this password - it's your client secret
```

---

## Step 4: Grant API Permissions

### Required Permissions

You need these Microsoft Graph permissions:

```json
{
  "User.ReadWrite.All": "Read and write all users' full profiles",
  "Group.ReadWrite.All": "Read and write all groups",
  "Directory.ReadWrite.All": "Read and write directory data"
}
```

### Using Azure Portal

1. In your app registration, go to **API permissions**
2. Click **Add a permission**
3. Select **Microsoft Graph**
4. Select **Application permissions** (not Delegated)
5. Add these permissions:
   - User → User.ReadWrite.All
   - Group → Group.ReadWrite.All
   - Directory → Directory.ReadWrite.All
6. Click **Grant admin consent for [Your Organization]**
7. Confirm the consent

### Using Azure CLI

```bash
# Get the app ID
APP_ID=$(az ad app list --display-name "n8n-ad-management" --query "[0].appId" -o tsv)

# Add permissions
az ad app permission add --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions \
    741f803b-c850-494e-b5df-cde7c675a1ca=Role \
    62a82d76-70ea-41e2-9197-370581804d09=Role \
    19dbc75e-c2e2-444c-a04e-fae7c624c8a0=Role

# Grant admin consent
az ad app permission admin-consent --id $APP_ID
```

**Permission IDs Reference:**
- `741f803b-c850-494e-b5df-cde7c675a1ca` = User.ReadWrite.All
- `62a82d76-70ea-41e2-9197-370581804d09` = Group.ReadWrite.All
- `19dbc75e-c2e2-444c-a04e-fae7c624c8a0` = Directory.ReadWrite.All

---

## Step 5: Gather Required Information

You need these values for n8n:

```powershell
# Run this to get your Tenant ID
az account show --query tenantId -o tsv

# Or find it in Azure Portal:
# Azure Active Directory → Overview → Tenant ID
```

**Required Values Checklist:**
- [ ] **Tenant ID**: ________________________________
- [ ] **Client ID** (Application ID): ________________________________
- [ ] **Client Secret**: ________________________________
- [ ] **Resource**: `https://graph.microsoft.com` (fixed value)

---

## Step 6: Configure n8n Credential

### In n8n Web Interface

1. Go to **Credentials** → **Add Credential**
2. Search for **Microsoft OAuth2 API** (not "Microsoft Entra ID Oauth2 API")
3. Configure:

```yaml
Credential Data:
  Grant Type: Client Credentials
  Client ID: [Your Application/Client ID]
  Client Secret: [Your Client Secret]
  Authentication URL: Leave empty
  Access Token URL: https://login.microsoftonline.com/[TENANT-ID]/oauth2/v2.0/token
  Scope: https://graph.microsoft.com/.default
  Auth URI Query Parameters: Leave empty
  Auth URI Query Parameters: Leave empty
```

4. Click **Save**
5. Test the connection

---

## Step 7: Test with Simple Workflow

### Test Workflow 1: List Users

```json
{
  "name": "Test - List AD Users",
  "nodes": [
    {
      "parameters": {
        "resource": "user",
        "operation": "getAll",
        "returnAll": false,
        "limit": 5
      },
      "name": "List Users",
      "type": "n8n-nodes-base.microsoftEntra",
      "typeVersion": 1,
      "position": [250, 300],
      "credentials": {
        "microsoftEntraOAuth2Api": {
          "id": "1",
          "name": "Microsoft OAuth2 API"
        }
      }
    }
  ],
  "connections": {}
}
```

### Test Workflow 2: Get Specific User

```json
{
  "name": "Test - Get User by Email",
  "nodes": [
    {
      "parameters": {},
      "name": "Start",
      "type": "n8n-nodes-base.start",
      "typeVersion": 1,
      "position": [250, 300]
    },
    {
      "parameters": {
        "resource": "user",
        "operation": "get",
        "userId": "user@company.com"
      },
      "name": "Get User",
      "type": "n8n-nodes-base.microsoftEntra",
      "typeVersion": 1,
      "position": [450, 300],
      "credentials": {
        "microsoftEntraOAuth2Api": {
          "id": "1",
          "name": "Microsoft OAuth2 API"
        }
      }
    }
  ],
  "connections": {
    "Start": {
      "main": [[{"node": "Get User", "type": "main", "index": 0}]]
    }
  }
}
```

---

## Step 8: Production Workflow - Employee Termination

### Complete Employee Termination Workflow

```json
{
  "name": "Employee Termination - Microsoft Graph",
  "nodes": [
    {
      "parameters": {
        "httpMethod": "POST",
        "path": "terminate-employee",
        "options": {}
      },
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 1,
      "position": [250, 300],
      "webhookId": "terminate-employee"
    },
    {
      "parameters": {
        "resource": "user",
        "operation": "get",
        "userId": "={{ $json.employeeEmail }}"
      },
      "name": "Get User Details",
      "type": "n8n-nodes-base.microsoftEntra",
      "typeVersion": 1,
      "position": [450, 300]
    },
    {
      "parameters": {
        "resource": "user",
        "operation": "update",
        "userId": "={{ $node['Get User Details'].json.id }}",
        "updateFields": {
          "accountEnabled": false,
          "city": "TERMINATED",
          "department": "",
          "jobTitle": "Terminated - {{ $today.format('yyyy-MM-dd') }}",
          "officeLocation": ""
        }
      },
      "name": "Disable Account",
      "type": "n8n-nodes-base.microsoftEntra",
      "typeVersion": 1,
      "position": [650, 300]
    },
    {
      "parameters": {
        "jsCode": "// Get all groups the user is member of\nconst userId = $input.first().json.id;\nconst userEmail = $input.first().json.mail;\n\n// You'll need to make a separate API call to get memberships\n// For now, return the user info for the next step\nreturn [{\n  json: {\n    userId: userId,\n    userEmail: userEmail,\n    status: 'disabled',\n    terminationDate: new Date().toISOString()\n  }\n}];"
      },
      "name": "Process Groups",
      "type": "n8n-nodes-base.code",
      "typeVersion": 1,
      "position": [850, 300]
    },
    {
      "parameters": {
        "resource": "user",
        "operation": "removeFromGroup",
        "userId": "={{ $json.userId }}",
        "groupId": "={{ $json.groupId }}"
      },
      "name": "Remove from Groups",
      "type": "n8n-nodes-base.microsoftEntra",
      "typeVersion": 1,
      "position": [1050, 300],
      "disabled": true
    }
  ],
  "connections": {
    "Webhook": {
      "main": [[{"node": "Get User Details", "type": "main", "index": 0}]]
    },
    "Get User Details": {
      "main": [[{"node": "Disable Account", "type": "main", "index": 0}]]
    },
    "Disable Account": {
      "main": [[{"node": "Process Groups", "type": "main", "index": 0}]]
    }
  }
}
```

---

## Step 9: Test the Complete Setup

### PowerShell Test Script

```powershell
# Test Microsoft Graph API directly
$tenantId = "YOUR-TENANT-ID"
$clientId = "YOUR-CLIENT-ID"
$clientSecret = "YOUR-CLIENT-SECRET"

# Get access token
$body = @{
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
    client_id     = $clientId
    client_secret = $clientSecret
}

$tokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body $body

$accessToken = $tokenResponse.access_token

# Test: Get users
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

$users = Invoke-RestMethod -Method Get `
    -Uri "https://graph.microsoft.com/v1.0/users?`$top=5" `
    -Headers $headers

Write-Host "Found $($users.value.Count) users" -ForegroundColor Green
$users.value | Select-Object displayName, userPrincipalName, accountEnabled | Format-Table
```

---

## Step 10: Sync Considerations

### Understanding Azure AD Connect Sync

- **Default sync interval**: 30 minutes
- Changes made via Graph API appear in Azure AD immediately
- Changes sync to on-premises AD within 30 minutes

### Check Sync Status

```powershell
# On Domain Controller with Azure AD Connect
Import-Module ADSync
Get-ADSyncScheduler

# Force immediate sync (if needed)
Start-ADSyncSyncCycle -PolicyType Delta
```

### To Make Changes Immediate

For critical terminations that need immediate effect:

1. Use Graph API to disable in Azure AD (immediate)
2. Run PowerShell on DC to disable locally:

```powershell
# Immediate local disable while waiting for sync
Disable-ADAccount -Identity "username@domain.com"
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. "Insufficient privileges to complete the operation"
- **Cause**: Missing admin consent for permissions
- **Fix**: Grant admin consent in Azure Portal

#### 2. "Invalid client secret provided"
- **Cause**: Wrong secret or expired
- **Fix**: Generate new client secret

#### 3. "User not found"
- **Cause**: User not synced to Azure AD
- **Fix**: Check Azure AD Connect sync status

#### 4. "The identity of the calling application could not be established"
- **Cause**: Wrong tenant ID or client ID
- **Fix**: Verify all IDs in credential configuration

### Debug Commands

```powershell
# Check if user exists in Azure AD
Get-AzureADUser -Filter "userPrincipalName eq 'user@domain.com'"

# Check last sync time
Get-ADSyncScheduler | Select-Object NextSyncCycleStartTimeInUTC

# Check sync errors
Get-ADSyncConnectorRunStatus
```

---

## Security Best Practices

### 1. Limit Permissions
Instead of Directory.ReadWrite.All, use minimal permissions:
- User.ReadWrite.All (for user management)
- Group.Read.All (if only reading groups)

### 2. Implement Conditional Logic
```javascript
// In n8n Code node - verify before termination
if (userEmail.includes('executive') || userEmail.includes('admin')) {
  throw new Error('Cannot terminate executive/admin accounts via automation');
}
```

### 3. Audit Logging
Add logging nodes to track all changes:
```json
{
  "name": "Log to Database",
  "type": "n8n-nodes-base.postgres",
  "parameters": {
    "operation": "insert",
    "table": "audit_log",
    "columns": "action,user_affected,changed_by,timestamp"
  }
}
```

### 4. Secret Rotation
Schedule client secret rotation every 6-12 months

---

## Next Steps

1. ✅ Complete Steps 1-6 to set up the credential
2. ✅ Test with simple workflows (Step 7)
3. ✅ Implement production workflow (Step 8)
4. ⏳ Set up monitoring and alerting
5. ⏳ Document the process for your team
6. ⏳ Create additional workflows for other AD operations

---

## Additional Resources

- [Microsoft Graph API Documentation](https://learn.microsoft.com/en-us/graph/api/resources/user)
- [n8n Microsoft Entra ID Node Docs](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.microsoftentra/)
- [Azure AD Connect Sync](https://learn.microsoft.com/en-us/azure/active-directory/hybrid/how-to-connect-sync-whatis)

---

**Support Needed?**
- Check the Troubleshooting section first
- Review Azure AD audit logs
- Verify sync status with Azure AD Connect

---

Last Updated: October 30, 2025
Status: Ready for Implementation