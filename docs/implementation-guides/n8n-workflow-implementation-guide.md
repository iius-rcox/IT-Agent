# n8n Employee Termination Workflow - Implementation Guide

## Overview
This guide provides step-by-step instructions for implementing the automated employee termination workflow in n8n. Follow each task in order, as many depend on previous tasks being completed.

---

## Phase 1: Foundation & Prerequisites

### Task 1: Configure Azure AD App Registration

**Status**: EXTERNAL - Must be completed in Azure Portal before n8n configuration

**Prerequisites**:
- Azure AD admin access
- Access to Azure Portal

**Step-by-Step Instructions**:

1. **Navigate to Azure Portal**
   - Go to https://portal.azure.com
   - Sign in with admin credentials

2. **Create App Registration**
   - Navigate to: Azure Active Directory → App registrations
   - Click "New registration"
   - Configure:
     - Name: `n8n-Employee-Termination-Workflow`
     - Supported account types: "Accounts in this organizational directory only"
     - Redirect URI: Leave blank (not needed for client credentials)
   - Click "Register"

3. **Record Application Details**
   - Copy and save the following (you'll need these for n8n credentials):
     - **Application (client) ID**
     - **Directory (tenant) ID**

4. **Create Client Secret**
   - In the app registration, navigate to: Certificates & secrets
   - Click "New client secret"
   - Description: `n8n-workflow-secret`
   - Expires: Choose appropriate timeframe (recommend 12-24 months)
   - Click "Add"
   - **IMPORTANT**: Copy the secret **Value** immediately (it won't be shown again)
   - Save this as **Client Secret**
   - Note the expiration date for rotation planning

5. **Configure API Permissions**
   - Navigate to: API permissions
   - Click "Add a permission"
   - Select "Microsoft Graph"
   - Select "Application permissions" (NOT Delegated)

   Add the following permissions:
   - **User.ReadWrite.All**
     - Path: Microsoft Graph → Application permissions → User → User.ReadWrite.All
     - Allows: Read and write all users' full profiles

   - **Directory.ReadWrite.All**
     - Path: Microsoft Graph → Application permissions → Directory → Directory.ReadWrite.All
     - Allows: Read and write directory data

   - **MailboxSettings.ReadWrite**
     - Path: Microsoft Graph → Application permissions → MailboxSettings → MailboxSettings.ReadWrite
     - Allows: Read and write user mailbox settings
     - **Note**: This has limited support for mailbox conversion

   - **Group.ReadWrite.All**
     - Path: Microsoft Graph → Application permissions → Group → Group.ReadWrite.All
     - Allows: Read and write all groups (needed for group removal)

6. **Grant Admin Consent**
   - After adding all permissions, click "Grant admin consent for [Your Organization]"
   - Confirm the action
   - Verify all permissions show "Granted for [Your Organization]"

7. **Verify Configuration**
   - Ensure all 4 permissions are present and granted
   - Verify Application ID and Tenant ID are recorded
   - Verify Client Secret is securely stored
   - Document secret expiration date

**Security Notes**:
- Store Client ID, Tenant ID, and Secret securely (use password manager)
- Never commit these values to version control
- Set calendar reminder for secret rotation before expiration
- Consider using certificate-based authentication for production

**What You'll Need for Next Steps**:
- ✅ Application (client) ID
- ✅ Directory (tenant) ID
- ✅ Client Secret value
- ✅ All permissions granted

**Estimated Time**: 30 minutes

---

### Task 2: Setup n8n Credentials

**Status**: EXTERNAL - Must be configured in n8n UI

**Prerequisites**:
- Task 1 completed (Azure AD app registration details)
- Access to n8n instance
- Active Directory service account credentials
- Domain controller hostname/IP

**Step-by-Step Instructions**:

#### 2.1: Create Microsoft Graph API OAuth2 Credential

1. **Navigate to Credentials**
   - Open your n8n instance
   - Click on "Credentials" in the left sidebar
   - Click "Add Credential"

2. **Select Credential Type**
   - Search for "OAuth2 API"
   - Select "OAuth2 API"

3. **Configure OAuth2 Settings**
   - **Credential name**: `Microsoft Graph - Employee Termination`
   - **Grant Type**: `Client Credentials`
   - **Authorization URL**: Leave empty (not used for client credentials)
   - **Access Token URL**:
     ```
     https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token
     ```
     Replace `{TENANT_ID}` with your Directory (tenant) ID from Task 1

   - **Client ID**: Paste Application (client) ID from Task 1
   - **Client Secret**: Paste Client Secret value from Task 1
   - **Scope**:
     ```
     https://graph.microsoft.com/.default
     ```
   - **Auth URI Query Parameters**: Leave empty
   - **Authentication**: `Body`

4. **Test Connection**
   - Click "Create" to save
   - The credential should show as created
   - You can test it by creating a test HTTP Request node with this credential

5. **Verify Token Retrieval**
   - Create a simple workflow with HTTP Request node
   - Use this credential
   - Try a simple GET request to: `https://graph.microsoft.com/v1.0/users?$top=1`
   - Should return user data (confirms authentication works)

#### 2.2: Create LDAP Credential

1. **Add New Credential**
   - In Credentials, click "Add Credential"
   - Search for "LDAP"
   - Select "LDAP"

2. **Configure LDAP Connection**
   - **Credential name**: `Active Directory - Employee Termination`

   - **Connection Settings**:
     - **Host**: Domain controller hostname or IP
       - Example: `dc01.company.local` or `10.0.1.10`
     - **Port**:
       - `389` for LDAP (plain or STARTTLS)
       - `636` for LDAPS (recommended for production)
     - **Use TLS**:
       - Enable if using port 636 (LDAPS)
       - Enable with STARTTLS if using port 389 securely

   - **Authentication**:
     - **Bind DN**: Service account distinguished name
       - Example: `CN=n8n-service,OU=Service Accounts,DC=company,DC=com`
     - **Bind Password**: Service account password

3. **Service Account Requirements**
   The LDAP service account needs these Active Directory permissions:
   - **Read** permissions on user objects (entire domain)
   - **Write** permission on `userAccountControl` attribute
   - **Write** permission to move objects between OUs
   - **Modify** permission on group membership

   To verify permissions:
   ```powershell
   # In PowerShell on domain controller
   Get-ADUser -Identity "n8n-service" -Properties MemberOf
   ```

4. **Test Connection**
   - Click "Create" to save
   - Test with a simple LDAP search in a test workflow

5. **Verify LDAP Connectivity**
   - Create test workflow with LDAP node
   - Operation: Search
   - Base DN: Your domain (e.g., `DC=company,DC=com`)
   - Filter: `(objectClass=user)`
   - Limit: 1
   - Should return one user object

#### 2.3: Create Webhook Authentication Credential

1. **Add New Credential**
   - Click "Add Credential"
   - Search for "Header Auth"
   - Select "Header Auth"

2. **Configure Header Authentication**
   - **Credential name**: `Webhook API Key - Employee Termination`
   - **Name**: `X-API-Key` (or `Authorization` if you prefer)
   - **Value**: Generate a strong random key
     - Use password generator or:
     ```bash
     # Generate 32-byte random key
     openssl rand -base64 32
     ```
   - **Example value**: `dGhpc2lzYXNlY3VyZWtleWZvcnRoZXdvcmtmbG93MTIz`

3. **Save the API Key**
   - Store the API key securely
   - Document it for API callers
   - This will be used in webhook requests:
     ```bash
     curl -X POST https://n8n.domain.com/webhook/terminate-employee \
       -H "X-API-Key: YOUR_API_KEY_HERE" \
       -H "Content-Type: application/json" \
       -d '{"employeeId": "12345"}'
     ```

4. **Click "Create"** to save

**Security Checklist**:
- ✅ Graph API credentials tested and working
- ✅ LDAP credentials tested and working
- ✅ Webhook API key generated and stored securely
- ✅ Service accounts use least privilege permissions
- ✅ LDAPS (TLS) enabled for production
- ✅ No credentials hardcoded in workflows

**What You'll Need for Next Steps**:
- ✅ Graph API credential name: `Microsoft Graph - Employee Termination`
- ✅ LDAP credential name: `Active Directory - Employee Termination`
- ✅ Webhook credential name: `Webhook API Key - Employee Termination`

**Estimated Time**: 20 minutes

---

### Task 3: Setup Environment Variables

**Status**: EXTERNAL - Must be configured in n8n settings

**Prerequisites**:
- Access to n8n instance or server
- Active Directory domain structure knowledge

**Step-by-Step Instructions**:

Environment variables in n8n can be set in multiple ways depending on your deployment:

#### Option 1: n8n Cloud / Self-hosted with UI (Recommended)

1. **Navigate to Settings**
   - Open n8n
   - Click on "Settings" (gear icon)
   - Look for "Environment Variables" or "Variables" section
   - Note: UI for environment variables may vary by n8n version

2. **Add Variables** (if UI available)
   - Click "Add Variable"
   - Add each variable below

#### Option 2: Self-hosted via Environment File

1. **Locate n8n Configuration**
   - Find your n8n installation directory
   - Look for `.env` file or create one

2. **Add Variables to .env File**
   ```bash
   # Active Directory Base DN
   AD_BASE_DN=dc=company,dc=com

   # Disabled Users OU Full DN
   AD_DISABLED_OU=OU=Disabled Users,DC=company,DC=com

   # Microsoft Graph API Base URL
   GRAPH_API_BASE_URL=https://graph.microsoft.com/v1.0

   # Azure Tenant ID
   AZURE_TENANT_ID=your-tenant-id-here
   ```

3. **Restart n8n** to load new environment variables
   ```bash
   # If using systemd
   sudo systemctl restart n8n

   # If using docker
   docker restart n8n

   # If using npm
   # Stop n8n (Ctrl+C) and restart with:
   n8n start
   ```

#### Option 3: Docker Compose

If using Docker Compose, add to your `docker-compose.yml`:

```yaml
services:
  n8n:
    image: n8nio/n8n
    environment:
      - AD_BASE_DN=dc=company,dc=com
      - AD_DISABLED_OU=OU=Disabled Users,DC=company,DC=com
      - GRAPH_API_BASE_URL=https://graph.microsoft.com/v1.0
      - AZURE_TENANT_ID=your-tenant-id-here
    # ... other config
```

Then: `docker-compose down && docker-compose up -d`

#### Variable Configuration Details

**AD_BASE_DN**
- Description: The base Distinguished Name for your Active Directory domain
- Format: `dc=yourdomain,dc=com`
- Example: `dc=contoso,dc=com`
- How to find:
  ```powershell
  # In PowerShell
  (Get-ADDomain).DistinguishedName
  ```

**AD_DISABLED_OU**
- Description: Full DN path to the OU where disabled users should be moved
- Format: `OU=OUName,DC=domain,DC=com`
- Example: `OU=Disabled Users,OU=Administration,DC=contoso,DC=com`
- **Prerequisites**: This OU must already exist in Active Directory
- How to find/create:
  ```powershell
  # Check if OU exists
  Get-ADOrganizationalUnit -Filter "Name -eq 'Disabled Users'"

  # Create if doesn't exist
  New-ADOrganizationalUnit -Name "Disabled Users" -Path "DC=contoso,DC=com"
  ```

**GRAPH_API_BASE_URL**
- Description: Base URL for Microsoft Graph API
- Value: `https://graph.microsoft.com/v1.0`
- **Do not change** unless using a different API version (v1.0 is stable)

**AZURE_TENANT_ID**
- Description: Your Azure AD tenant ID (same as Task 1)
- Value: Copy from Azure Portal → Azure Active Directory → Properties → Tenant ID
- Format: GUID (e.g., `12345678-1234-1234-1234-123456789012`)

#### Verify Environment Variables

Create a test workflow to verify variables are accessible:

1. **Create Test Workflow**
   - Add a "Set" node or "Code" node
   - In Code node, add:
     ```javascript
     return [
       {
         json: {
           AD_BASE_DN: $env.AD_BASE_DN,
           AD_DISABLED_OU: $env.AD_DISABLED_OU,
           GRAPH_API_BASE_URL: $env.GRAPH_API_BASE_URL,
           AZURE_TENANT_ID: $env.AZURE_TENANT_ID
         }
       }
     ];
     ```
   - Execute the node
   - All variables should show their values (not undefined)

2. **Delete Test Workflow** after verification

**Prerequisite: Create Disabled Users OU**

If the Disabled Users OU doesn't exist:

```powershell
# Connect to AD (run on domain controller or with RSAT tools)
Import-Module ActiveDirectory

# Create Disabled Users OU
New-ADOrganizationalUnit `
  -Name "Disabled Users" `
  -Path "DC=company,DC=com" `
  -Description "Organizational Unit for disabled user accounts" `
  -ProtectedFromAccidentalDeletion $true

# Verify creation
Get-ADOrganizationalUnit -Filter "Name -eq 'Disabled Users'"
```

**Security Notes**:
- Environment variables are visible to all workflows in the n8n instance
- Do not store secrets in environment variables (use credentials instead)
- Tenant ID is not sensitive but good to keep private

**Configuration Checklist**:
- ✅ AD_BASE_DN matches your domain structure
- ✅ AD_DISABLED_OU exists in Active Directory
- ✅ GRAPH_API_BASE_URL is correct (v1.0)
- ✅ AZURE_TENANT_ID matches your tenant
- ✅ n8n restarted (if required)
- ✅ Variables verified in test workflow

**Estimated Time**: 10 minutes

---

## Phase 2: Building the Workflow Foundation

Now we'll begin creating the actual n8n workflow. For all remaining tasks, you'll be working in the n8n workflow editor.

### Getting Started with n8n Workflow

1. **Create New Workflow**
   - Open n8n
   - Click "New Workflow"
   - Name: `Employee Termination Automation`
   - Save the workflow

2. **Workflow Canvas**
   - You'll add nodes by clicking the "+" button or dragging from the node panel
   - Connect nodes by dragging from output dots to input dots
   - Configure each node by clicking on it

3. **Layout Tips**
   - Arrange nodes top-to-bottom or left-to-right for readability
   - Use sticky notes to label sections (Phase 1, Phase 2, etc.)
   - Keep error paths clearly separate from success paths

Let's begin building!

---

### Task 4: Create Webhook Trigger Node

**Status**: READY TO IMPLEMENT

**Node Type**: Webhook (n8n-nodes-base.webhook)

**Purpose**: Creates the HTTP endpoint that receives termination requests

**Step-by-Step Configuration**:

1. **Add Webhook Node**
   - Click "+" on the canvas
   - Search for "Webhook"
   - Select "Webhook" trigger node
   - This will be the starting node of your workflow

2. **Configure Webhook Settings**

   **HTTP Method**:
   - Select: `POST`

   **Path**:
   - Enter: `terminate-employee`
   - Full URL will be: `https://your-n8n-domain.com/webhook/terminate-employee`
   - Or for production: Use the production URL shown in the node

   **Authentication**:
   - Select: `Header Auth`
   - Credential to connect with: Select `Webhook API Key - Employee Termination` (from Task 2)

   **Respond**:
   - Select: `Using 'Respond to Webhook' Node`
   - This allows custom responses later in the workflow

3. **Configure Options** (Click "Add Option")

   **Ignore Bots**:
   - Enable: `ON`
   - Prevents link preview crawlers from triggering the workflow

   **Raw Body**:
   - Enable: `ON`
   - Allows receiving JSON payloads

   **IP(s) Whitelist** (Optional but recommended for production):
   - Add IPs of systems allowed to call this webhook
   - Example: `192.168.1.0/24,10.0.0.50`
   - Leave empty to allow all IPs (during development)

4. **Test the Webhook**

   Click "Listen for Test Event" in the webhook node

   Then test with curl:
   ```bash
   curl -X POST https://your-n8n-domain.com/webhook-test/terminate-employee \
     -H "X-API-Key: your-api-key-from-task-2" \
     -H "Content-Type: application/json" \
     -d '{
       "employeeId": "testuser01",
       "supervisorEmail": "manager@company.com",
       "reason": "Testing webhook",
       "ticketNumber": "TEST001"
     }'
   ```

   You should see the data appear in the webhook node

5. **Verify Webhook Configuration**
   - Webhook shows as listening
   - Test request appears in node output
   - Payload is correctly formatted JSON

**Expected Input Payload Schema**:
```json
{
  "employeeId": "string (optional if employeeName provided)",
  "employeeName": "string (optional if employeeId provided)",
  "supervisorEmail": "string (optional - will lookup manager if not provided)",
  "forwardeeEmail": "string (optional)",
  "reason": "string (optional)",
  "ticketNumber": "string (optional)"
}
```

**Node Output**:
The webhook node will output whatever JSON is received in the body.

**Common Issues**:
- **Authentication fails**: Check that API key matches credential
- **404 Not Found**: Verify webhook path is correct
- **Payload not showing**: Ensure "Raw Body" option is enabled
- **Bot traffic**: Enable "Ignore Bots" option

**Next Connection**:
Connect this webhook node to the "Input Validation Node" (Task 5)

**Estimated Time**: 15 minutes

---

### Task 5: Input Validation Node

**Status**: READY TO IMPLEMENT

**Node Type**: Code (n8n-nodes-base.code)

**Purpose**: Validates webhook input and determines user lookup strategy

**Step-by-Step Configuration**:

1. **Add Code Node**
   - Click "+" after the Webhook node
   - Search for "Code"
   - Select "Code" node
   - Name it: `Input Validation`

2. **Configure Code Node**

   **Language**: JavaScript (default)

   **Mode**: Run Once for All Items (default)

3. **Paste JavaScript Code**:

```javascript
// Get input from webhook
const input = $input.first().json;

// Validation: Require either employeeId or employeeName
if (!input.employeeId && !input.employeeName) {
  throw new Error('Either employeeId or employeeName is required');
}

// Email validation regex
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Validate supervisor email if provided
if (input.supervisorEmail && !emailRegex.test(input.supervisorEmail)) {
  throw new Error('Invalid supervisor email format');
}

// Validate forwardee email if provided
if (input.forwardeeEmail && !emailRegex.test(input.forwardeeEmail)) {
  throw new Error('Invalid forwardee email format');
}

// Determine lookup strategy
const lookupStrategy = input.employeeId ? 'byId' : 'byName';
const lookupValue = input.employeeId || input.employeeName;

// Return validated and enriched data
return {
  json: {
    // Original input
    lookupStrategy: lookupStrategy,
    lookupValue: lookupValue,
    supervisorEmail: input.supervisorEmail || null,
    forwardeeEmail: input.forwardeeEmail || null,
    reason: input.reason || 'Not provided',
    ticketNumber: input.ticketNumber || 'None',

    // Workflow metadata
    workflowStartTime: new Date().toISOString(),
    validationCompleted: true
  }
};
```

4. **Test the Validation**

   **Test Case 1: Valid input with employee ID**
   - Input: `{"employeeId": "jdoe", "supervisorEmail": "manager@company.com"}`
   - Expected: Returns validated object with `lookupStrategy: "byId"`

   **Test Case 2: Valid input with employee name**
   - Input: `{"employeeName": "John Doe", "reason": "Terminated"}`
   - Expected: Returns validated object with `lookupStrategy: "byName"`

   **Test Case 3: Invalid - missing both ID and name**
   - Input: `{"supervisorEmail": "manager@company.com"}`
   - Expected: Throws error: "Either employeeId or employeeName is required"

   **Test Case 4: Invalid email**
   - Input: `{"employeeId": "jdoe", "supervisorEmail": "invalid-email"}`
   - Expected: Throws error: "Invalid supervisor email format"

5. **Configure Error Handling** (Settings tab)
   - Continue On Fail: `OFF` (we want errors to stop the workflow)
   - Error outputs will route to error handling nodes later

**Node Output Schema**:
```json
{
  "lookupStrategy": "byId | byName",
  "lookupValue": "the ID or name to search for",
  "supervisorEmail": "email@domain.com | null",
  "forwardeeEmail": "email@domain.com | null",
  "reason": "termination reason",
  "ticketNumber": "ticket reference",
  "workflowStartTime": "2025-10-23T10:00:00.000Z",
  "validationCompleted": true
}
```

**Validation Logic**:
- ✅ Checks for required fields (employeeId OR employeeName)
- ✅ Validates email format with regex
- ✅ Determines lookup strategy for subsequent nodes
- ✅ Provides defaults for optional fields
- ✅ Adds workflow metadata

**Common Issues**:
- **Syntax errors**: Check JavaScript syntax carefully
- **Undefined values**: Ensure $input.first().json is correct
- **Email validation too strict**: Adjust regex if needed for your organization

**Next Connection**:
This node will split into TWO parallel branches:
1. Connect to "Lookup User in M365" (Task 6)
2. Connect to "Lookup User in Active Directory" (Task 8)

**Note**: In n8n, you can connect one node output to multiple nodes by dragging from the output dot to each target node.

**Estimated Time**: 30 minutes

---

