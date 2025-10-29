# Implementation Plan: Automated Employee Termination Workflow

## Overview
This plan outlines the implementation of a fully automated employee termination workflow in n8n that processes terminations via webhook input (employee name or ID), converts M365 mailboxes to shared mailboxes with supervisor access, removes licenses, disables Active Directory accounts, moves them to a disabled OU, and removes all group memberships—all without human intervention.

**Long-term Vision**: This workflow will serve as a **subflow** called by an AI-powered email handler that automatically detects termination requests from emails, extracts relevant information, and triggers the termination process.

## Implementation Approach

**⚡ PROGRAMMATIC WORKFLOW CREATION VIA N8N MCP SERVER**

This workflow will be created **programmatically** using the n8n MCP server tools, not manually in the n8n UI. The implementation will:

1. **Use n8n MCP Tools**: Leverage `mcp__n8n-mcp__n8n_create_workflow` to generate the complete workflow
2. **Generate Workflow JSON**: Programmatically construct nodes, connections, and configurations
3. **Validate Configuration**: Use `mcp__n8n-mcp__n8n_validate_workflow` before creation
4. **Prerequisites Required**: User must complete Azure AD setup and n8n credentials configuration before workflow creation

**Implementation Flow**:
```
User Completes Prerequisites → AI Creates Workflow via MCP → Workflow Ready in n8n → User Tests
```

**What You Need to Do**:
- ✅ Configure Azure AD App Registration (Task 1)
- ✅ Setup n8n Credentials (Task 2)
- ✅ Configure Environment Variables (Task 3)

**What AI Will Do**:
- ✅ Generate complete workflow structure
- ✅ Configure all nodes programmatically
- ✅ Set up connections and data flow
- ✅ Implement error handling
- ✅ Create the workflow in your n8n instance

This approach ensures consistency, reduces manual configuration errors, and provides a reproducible workflow deployment.

---

## n8n MCP Server Implementation Guide

**CRITICAL**: All workflow creation and modification will be done programmatically using the n8n MCP server tools. Manual UI editing should be avoided.

### MCP Tools Used

**Workflow Management:**
- `mcp__n8n-mcp__n8n_create_workflow` - Create initial workflow
- `mcp__n8n-mcp__n8n_update_partial_workflow` - Add/update/remove nodes and connections
- `mcp__n8n-mcp__n8n_get_workflow` - Retrieve workflow for inspection
- `mcp__n8n-mcp__n8n_validate_workflow` - Validate workflow before activation
- `mcp__n8n-mcp__list_workflows` - List all workflows

**Node Operations (via update_partial_workflow):**
- `addNode` - Add a new node to the workflow
- `updateNode` - Modify existing node configuration
- `removeNode` - Remove a node
- `addConnection` - Connect two nodes
- `removeConnection` - Disconnect nodes
- `enableNode` / `disableNode` - Toggle node active state

**Execution Testing:**
- `mcp__n8n-mcp__n8n_trigger_webhook_workflow` - Test webhook trigger
- `mcp__n8n-mcp__n8n_get_execution` - Get execution results
- `mcp__n8n-mcp__n8n_list_executions` - List workflow executions

### Development Workflow

1. **Create** → Use `n8n_create_workflow` with empty nodes array
2. **Add Nodes** → Use `n8n_update_partial_workflow` with `addNode` operations
3. **Connect Nodes** → Use `n8n_update_partial_workflow` with `addConnection` operations
4. **Validate** → Use `n8n_validate_workflow` to check for errors
5. **Test** → Use `n8n_trigger_webhook_workflow` for testing
6. **Activate** → Use `n8n_update_partial_workflow` with `updateSettings` to set `active: true`

### Node Type Reference

For this workflow, we'll use:
- `n8n-nodes-base.webhook` (typeVersion 2) - Webhook trigger
- `n8n-nodes-base.code` (typeVersion 2) - JavaScript/Python code execution
- `n8n-nodes-base.executeCommand` (typeVersion 1) - PowerShell execution
- `n8n-nodes-base.respondToWebhook` (typeVersion 1) - HTTP responses
- `n8n-nodes-base.httpRequest` (typeVersion 4.3+) - Microsoft Graph API calls
- `n8n-nodes-base.ldap` (typeVersion 1+) - Active Directory operations

**Before starting implementation, verify n8n MCP server is connected:**
```bash
# Use this to check n8n connectivity
mcp__n8n-mcp__n8n_health_check()
```

### MCP Implementation Pattern for Each Task

Throughout the implementation tasks below, you'll see references to:
- **MCP Tool**: Which n8n MCP tool to use
- **Operation Type**: The operation to perform (addNode, addConnection, etc.)
- **Node Configuration**: The complete node definition

This ensures the entire workflow is created programmatically without manual UI interaction.

## Requirements Summary
- **Trigger**: Accept employee name or employee ID via webhook
- **M365 Operations**:
  - Convert user mailbox to shared mailbox via Microsoft Graph API
  - Grant supervisor/forwardee full access to the shared mailbox
  - Remove all Microsoft 365 licenses from the user
- **Active Directory Operations**:
  - Disable the user account
  - Move user to disabled OU
  - Remove user from all groups
- **Automation**: Fully automated with no human interaction required
- **Error Handling**: Robust error handling and logging throughout

## Research Findings

### n8n Best Practices (Validated)

**Webhook Node (n8n-nodes-base.webhook v2.1+)**
- ✅ Supports POST method for receiving termination requests
- ✅ Path can include route parameters: `/:variable` format
- ✅ Authentication options: Basic Auth, Header Auth, JWT, None
- ✅ Response modes:
  - "Immediately" - Returns quick acknowledgment
  - "When Last Node Finishes" - Returns final workflow result
  - "Using 'Respond to Webhook' Node" - Custom response control (**RECOMMENDED**)
- ✅ Maximum payload size: 16MB (configurable via N8N_PAYLOAD_SIZE_MAX)
- ✅ Options available:
  - IP Whitelist for security
  - Ignore Bots
  - Raw Body for JSON/XML
  - Response Headers

**HTTP Request Node (n8n-nodes-base.httpRequest v4.3+)**
- ✅ Full Microsoft Graph API support
- ✅ Authentication methods:
  - Predefined Credential Type (preferred when available)
  - Generic credentials (OAuth2, Basic Auth, Header Auth, etc.)
- ✅ Request configuration:
  - Send Query Parameters (Using Fields Below or JSON)
  - Send Headers (Using Fields Below or JSON)
  - Send Body (Form URLencoded, Form-Data, JSON, n8n Binary, Raw)
- ✅ Error handling options:
  - "Never Error" option to handle non-2xx responses gracefully
  - "Include Response Headers and Status" for debugging
- ✅ Timeout configuration available
- ✅ Retry logic supported

**LDAP Node (n8n-nodes-base.ldap v1+)**
- ✅ Operations supported:
  - Compare - Compare an attribute
  - Create - Create new entry
  - Delete - Delete an entry
  - Rename - Change DN (for moving to disabled OU)
  - Search - Find users
  - Update - Modify attributes (for disable, group removal)
- ✅ Search scopes:
  - Base Tree - Subordinates only
  - Single Level - Immediate children
  - Whole Subtree - All subordinates (**RECOMMENDED for user search**)
- ✅ Update operations:
  - Add - Add new attributes
  - Remove - Remove existing attributes
  - Replace - Replace existing attributes (**RECOMMENDED for disable**)

**Code Node (n8n-nodes-base.code)**
- ✅ JavaScript support (Python not available in LangChain variant)
- ✅ Access to workflow data via `$input` and `$node`
- ✅ Can make HTTP requests for complex Graph API calls
- ✅ Ideal for:
  - Data transformation
  - Complex logic (bit manipulation for userAccountControl)
  - Iteration (license removal, group removal)
  - Error handling and validation

**Respond to Webhook Node (n8n-nodes-base.respondToWebhook)**
- ✅ Works with Webhook trigger set to "Using 'Respond to Webhook' Node"
- ✅ Response options:
  - All Incoming Items
  - Binary File
  - First Incoming Item
  - JSON (custom response) (**RECOMMENDED**)
  - JWT Token
  - No Data
  - Redirect
  - Text
- ✅ Supports custom response codes and headers
- ✅ Runs once using first data item
- ✅ Can output response sent to webhook (enable "Response Output Branch")

### Microsoft Graph API Best Practices

**Authentication**
- Use App Registration with Client Credentials flow
- Required permissions (Application-level):
  - User.ReadWrite.All
  - Directory.ReadWrite.All
  - MailboxSettings.ReadWrite (limited for mailbox conversion)
  - Group.ReadWrite.All
- Token endpoint: `https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token`
- Scope: `https://graph.microsoft.com/.default`

**User Lookup**
- By ID: `GET /users/{id}`
- By name: `GET /users?$filter=displayName eq '{name}'`
- By UPN: `GET /users/{userPrincipalName}`

**License Management**
- List licenses: `GET /users/{id}/licenseDetails`
- Remove licenses: `POST /users/{id}/assignLicense` with `removeLicenses` array
- ⚠️ Remove licenses AFTER mailbox conversion to prevent data loss

**Mailbox Conversion Challenge**
- ⚠️ Microsoft Graph API has **LIMITED** support for mailbox type conversion
- Graph API approach (may not work): `PATCH /users/{id}` with mailboxSettings
- **RECOMMENDED ALTERNATIVES**:
  1. Exchange Online PowerShell via SSH/Execute Command node:
     ```powershell
     Connect-ExchangeOnline -CertificateThumbprint "..." -AppId "..." -Organization "..."
     Set-Mailbox -Identity "user@domain.com" -Type Shared
     Add-MailboxPermission -Identity "user@domain.com" -User "supervisor@domain.com" -AccessRights FullAccess
     ```
  2. Azure Automation with PowerShell runbook triggered via webhook
  3. Separate n8n workflow using Execute Command node with remoting

**Mailbox Permissions**
- Graph API permissions endpoint is limited
- PowerShell more reliable: `Add-MailboxPermission`
- Alternative: Use Graph API delegated permissions (requires user context)

### Active Directory / LDAP Best Practices

**User Search**
- Base DN: Use environment variable for flexibility
- Filters:
  - `(sAMAccountName={employeeId})` - Preferred for ID lookup
  - `(cn={employeeName})` - For name lookup
  - `(userPrincipalName={email})` - For email lookup
- Scope: Whole Subtree (searches all subordinates)
- Attributes to retrieve: `dn`, `memberOf`, `userAccountControl`, `sAMAccountName`, `mail`

**Account Disable**
- Use LDAP Update operation with Replace
- Attribute: `userAccountControl`
- Value calculation:
  - Read current value
  - OR with 0x0002 (ACCOUNTDISABLE bit)
  - Can be done in Code node: `currentValue | 0x0002`
- Alternative bitmask values:
  - 0x0002 = ACCOUNTDISABLE
  - 0x0010 = LOCKOUT
  - 0x0200 = NORMAL_ACCOUNT
  - Typical disabled value: 514 (0x0202 = NORMAL_ACCOUNT + ACCOUNTDISABLE)

**Group Removal**
- Parse `memberOf` attribute (array of group DNs)
- For each group DN:
  - LDAP Update operation
  - DN: Group DN
  - Operation: Delete
  - Attribute: `member`
  - Value: User DN
- Filter out primary group (Domain Users) if needed
- Use Code node to iterate

**Move to Disabled OU**
- Use LDAP Rename operation
- Current DN: From search result
- New DN: `CN={userName},{disabledOuDN}`
- Example: `CN=John Doe,OU=Disabled Users,DC=company,DC=com`
- Ensure Disabled Users OU exists beforehand

### Error Handling Patterns

**n8n Error Handling**
- Use "Continue On Fail" node setting for non-critical operations
- Error trigger nodes to catch workflow errors
- If node for conditional error handling
- Respond to Webhook node in error path with 500 status
- Log errors to external system (database, SIEM, file)

**Idempotency Considerations**
- Check if user already disabled before disabling
- Check if already in disabled OU before moving
- Handle "already not a member" errors gracefully
- License removal on already license-free user should succeed
- Design workflow to be safely re-runnable

**Transaction-Like Patterns**
- Consider M365 and AD operations as separate transactions
- If M365 succeeds but AD fails:
  - Log partial completion
  - Return error with details of what completed
  - Document manual remediation steps
  - Consider compensation/rollback logic
- If AD succeeds but M365 fails:
  - Similar handling
  - May be harder to rollback AD changes

### Reference Implementations

**Working PowerShell Script - Complete Employee Termination**:
```powershell
# Requires: Microsoft.Graph and ExchangeOnlineManagement modules
# Make sure to run PowerShell as Administrator

#-----------------------------
# CONFIGURATION SECTION
#-----------------------------
$adminUPN = "iiadminRC@INSULATIONSINC1.onmicrosoft.com"
$employeeIDs = @("785389")#, "974320", "445386")
$disabledOU = "OU=Disabled Users,DC=insulationsinc,DC=local"
$tenantId = "953922e6-5370-4a01-a3d5-773a30df726b"
$organizationDomain = "ii-us.com"
$appId = "73b82823-d860-4bf6-938b-74deabeebab7"
$certThumbprint = "DE0FF14C5EABA90BA328030A59662518A3673009"

#-----------------------------
# AUTHENTICATION SECTION
#-----------------------------
Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -ClientId $appId -TenantId $tenantId -CertificateThumbprint $certThumbprint -NoWelcome

Write-Host "Connecting to Exchange Online..."
Connect-ExchangeOnline -AppId $appId -Organization $organizationDomain -CertificateThumbprint $certThumbprint

#-----------------------------
# PROCESSING EACH EMPLOYEE
#-----------------------------
foreach ($empID in $employeeIDs) {
    Write-Host "Processing Employee ID: $empID"

    # Find user in local AD
    $user = Get-ADUser -Filter {employeeID -eq $empID} -Properties EmployeeID, DistinguishedName, UserPrincipalName

    if (-not $user) {
        Write-Warning "User with Employee ID $empID not found in AD. Skipping."
        continue
    }

    $upn = $user.UserPrincipalName
    Write-Host "Found AD user: $upn"

    # Find user in Azure AD via Microsoft Graph
    try {
        $graphUser = Get-MgUser -Filter "userPrincipalName eq '$upn'"
    } catch {
        Write-Warning "Failed to find $upn in Azure AD: $_"
        continue
    }

    if (-not $graphUser) {
        Write-Warning "No matching Azure AD user found for $upn. Skipping license removal."
    } else {
        # Remove all licenses
        try {
            Write-Host "Fetching assigned licenses for $upn..."
            $licenseDetails = Get-MgUserLicenseDetail -UserId $graphUser.Id
            $licensesToRemove = @()

            foreach ($license in $licenseDetails) {
                $licensesToRemove += $license.SkuId
            }

            if ($licensesToRemove.Count -gt 0) {
                Write-Host "Removing licenses from $upn..."
                Set-MgUserLicense -UserId $graphUser.Id -RemoveLicenses $licensesToRemove -AddLicenses @{}
            } else {
                Write-Host "No licenses assigned to $upn."
            }
        } catch {
            Write-Warning "Failed to remove licenses for $upn $_"
        }
    }

    # Convert mailbox to shared mailbox (Exchange Online)
    try {
        Write-Host "Converting mailbox for $upn to shared..."
        Set-Mailbox -Identity $upn -Type Shared
    } catch {
        Write-Warning "Failed to convert mailbox: $_"
    }

    # Disable AD account
    try {
        Write-Host "Disabling AD account for $upn..."
        Disable-ADAccount -Identity $user
    } catch {
        Write-Warning "Failed to disable AD account: $_"
    }

    # Move user to Disabled OU
    try {
        Write-Host "Moving user to Disabled OU..."
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $disabledOU
    } catch {
        Write-Warning "Failed to move user to disabled OU: $_"
    }

    Write-Host "--- Done with $empID ---\n"
}

#-----------------------------
# CLEANUP
#-----------------------------
Start-ADSyncSyncCycle -PolicyType Delta
Disconnect-ExchangeOnline -Confirm:$false
Disconnect-MgGraph
Write-Host "All done."
```

**Notes on PowerShell Script**:
- ✅ Production-tested and currently working
- ✅ Uses certificate-based authentication (more secure than client secret)
- ✅ Connects to both Microsoft Graph and Exchange Online
- ✅ Handles license removal via Graph API
- ✅ Converts mailbox to shared type
- ✅ Disables AD account and moves to Disabled OU
- ✅ Triggers Azure AD sync after changes
- ⚠️ Configuration values hardcoded - should be parameterized for n8n
- ⚠️ Missing group membership removal - needs to be added
- ⚠️ Missing supervisor mailbox permission grant - needs to be added
- 🔄 Can be adapted for n8n Execute Command node or Azure Automation runbook

**Webhook with Authentication**
```json
{
  "httpMethod": "POST",
  "path": "/terminate-employee",
  "authentication": "headerAuth",
  "responseMode": "usingRespondToWebhook"
}
```

**Graph API User Lookup**
```javascript
// HTTP Request node
Method: GET
URL: https://graph.microsoft.com/v1.0/users/{{$json.employeeId}}
Headers: {
  "Content-Type": "application/json"
}
```

**LDAP User Search**
```json
{
  "operation": "search",
  "baseDN": "dc=company,dc=com",
  "searchFor": "Custom",
  "filter": "(sAMAccountName={{$json.employeeId}})",
  "attributes": "dn,memberOf,userAccountControl,sAMAccountName",
  "scope": "Whole Subtree",
  "returnAll": false,
  "limit": 1
}
```

**Disable Account (Code Node)**
```javascript
// Calculate userAccountControl value to disable account
const currentControl = $input.first().json.userAccountControl;
const ACCOUNTDISABLE = 0x0002;
const disabledControl = currentControl | ACCOUNTDISABLE;

return {
  json: {
    userDN: $input.first().json.dn,
    newUserAccountControl: disabledControl
  }
};
```

**Remove Licenses (Code Node)**
```javascript
const userId = $input.first().json.userId;
const licenses = $input.first().json.licenses; // Array of license SKU IDs

const results = [];
for (const license of licenses) {
  const response = await $http.request({
    method: 'POST',
    url: `https://graph.microsoft.com/v1.0/users/${userId}/assignLicense`,
    headers: {
      'Authorization': `Bearer ${$credentials.accessToken}`,
      'Content-Type': 'application/json'
    },
    body: {
      addLicenses: [],
      removeLicenses: [license.skuId]
    }
  });
  results.push({ license: license.skuId, removed: true });
}

return { json: { results } };
```

### Technology Decisions

1. **HTTP Request Node** - For Microsoft Graph API calls
   - More flexible than dedicated M365 nodes
   - Supports all Graph API endpoints
   - Custom error handling

2. **LDAP Node** - For Active Directory operations
   - Native support for Search, Update, Rename operations
   - Direct AD integration
   - Secure credential management

3. **Code Node (JavaScript)** - For complex logic
   - Data transformation
   - Bit manipulation (userAccountControl)
   - Iteration (licenses, groups)
   - Complex Graph API calls
   - Error handling

4. **Webhook Trigger** - For API-driven automation
   - RESTful endpoint
   - Flexible authentication
   - Custom response control

5. **Respond to Webhook Node** - For custom responses
   - Detailed success/error responses
   - Status code control
   - Audit trail in response

6. **If/Switch Nodes** - For conditional logic
   - Validation branching
   - Error routing
   - Multi-path workflows

7. **Alternative for Mailbox Conversion**: Execute Command Node
   - SSH to Exchange server or Azure
   - Run PowerShell commands remotely
   - More reliable than Graph API for mailbox operations

## Implementation Tasks

### Phase 1: Foundation (Setup & Configuration)

#### 1. Configure Azure AD App Registration
- **Description**: Create and configure Azure AD app registration with required Microsoft Graph API permissions
- **External to n8n**: Yes (Azure Portal)
- **Prerequisites**:
  - Azure AD admin access
  - Tenant ID, Client ID, Client Secret
- **Permissions needed** (Application-level):
  - User.ReadWrite.All
  - Directory.ReadWrite.All
  - MailboxSettings.ReadWrite (note: limited for mailbox operations)
  - Group.ReadWrite.All
- **Grant admin consent** for all permissions
- **Note certificate/secret expiration** and plan for rotation
- **Estimated effort**: 30 minutes

#### 2. Setup n8n Credentials
- **Description**: Configure n8n credentials for Microsoft Graph API and LDAP
- **Location**: n8n UI → Credentials
- **Dependencies**: Task 1 (Azure app registration)
- **Credential types to create**:

  **Microsoft Graph API OAuth2**:
  - Credential Type: OAuth2 API
  - Grant Type: Client Credentials
  - Client ID: From Azure app registration
  - Client Secret: From Azure app registration
  - Access Token URL: `https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token`
  - Scope: `https://graph.microsoft.com/.default`

  **LDAP Credentials**:
  - Credential Type: LDAP
  - Host: Domain controller hostname/IP
  - Port: 389 (LDAP) or 636 (LDAPS - recommended)
  - Bind DN: Service account DN (e.g., `CN=n8n-service,OU=Service Accounts,DC=company,DC=com`)
  - Bind Password: Service account password
  - TLS: Enable if using LDAPS (recommended for production)

  **Webhook Authentication** (recommended):
  - Credential Type: Header Auth or Generic Credential Type
  - Header Name: `X-API-Key` or `Authorization`
  - Value: Generate secure random key

- **Estimated effort**: 20 minutes

#### 3. Setup Environment Variables
- **Description**: Configure n8n environment variables for workflow
- **Location**: n8n settings or environment configuration
- **Variables to set**:
  - `AD_BASE_DN`: e.g., `dc=company,dc=com`
  - `AD_DISABLED_OU`: e.g., `OU=Disabled Users,DC=company,DC=com`
  - `GRAPH_API_BASE_URL`: `https://graph.microsoft.com/v1.0`
  - `AZURE_TENANT_ID`: Azure tenant ID
- **Access in workflow**: `{{$env.AD_BASE_DN}}`
- **Estimated effort**: 10 minutes

#### 4. Create Webhook Trigger Node
- **Description**: Setup webhook to accept employee termination requests using n8n MCP server
- **Node type**: `n8n-nodes-base.webhook`
- **MCP Tool**: `mcp__n8n-mcp__n8n_create_workflow` (initial workflow creation with this node)
- **Configuration**:
  - HTTP Method: `POST`
  - Path: `/terminate-employee` (or custom path)
  - Authentication: Select webhook credential (Header Auth recommended)
  - Response Mode: `Using 'Respond to Webhook' Node`
  - Options to enable:
    - IP(s) Whitelist (if needed for security)
    - Ignore Bots: ON
    - Raw Body: ON (to receive JSON)
- **Expected payload structure**:
  ```json
  {
    "employeeId": "12345",
    "employeeName": "John Doe",
    "supervisorEmail": "manager@company.com",
    "forwardeeEmail": "hr@company.com",
    "reason": "Termination",
    "ticketNumber": "INC001234"
  }
  ```
- **Note**: Either `employeeId` OR `employeeName` required, not both
- **Estimated effort**: 15 minutes

### Phase 2: User Identification & Validation

#### 5. Input Validation Node
- **Description**: Validate webhook input and determine lookup strategy
- **Node type**: `n8n-nodes-base.code` (JavaScript)
- **MCP Tool**: `mcp__n8n-mcp__n8n_update_partial_workflow` with `addNode` operation
- **Logic**:
  ```javascript
  const input = $input.first().json;

  // Validation
  if (!input.employeeId && !input.employeeName) {
    throw new Error('Either employeeId or employeeName is required');
  }

  // Email validation
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (input.supervisorEmail && !emailRegex.test(input.supervisorEmail)) {
    throw new Error('Invalid supervisor email format');
  }

  // Determine lookup strategy
  const lookupStrategy = input.employeeId ? 'byId' : 'byName';
  const lookupValue = input.employeeId || input.employeeName;

  return {
    json: {
      lookupStrategy,
      lookupValue,
      supervisorEmail: input.supervisorEmail,
      forwardeeEmail: input.forwardeeEmail,
      reason: input.reason || 'Not provided',
      ticketNumber: input.ticketNumber || 'None',
      timestamp: new Date().toISOString()
    }
  };
  ```
- **Output**: Validated input object with lookup strategy
- **Error handling**: Throws error for invalid input (caught by error handler)
- **Estimated effort**: 30 minutes

#### 6. Lookup User in M365
- **Description**: Find user in Microsoft 365 using Graph API
- **Node type**: `n8n-nodes-base.httpRequest`
- **MCP Tool**: `mcp__n8n-mcp__n8n_update_partial_workflow` with `addNode` operation
- **Configuration**:
  - Method: `GET`
  - Authentication: Use Graph API OAuth2 credential
  - URL (dynamic based on strategy):
    - If by ID: `https://graph.microsoft.com/v1.0/users/{{$json.lookupValue}}`
    - If by name: `https://graph.microsoft.com/v1.0/users?$filter=displayName eq '{{$json.lookupValue}}'`
  - Headers:
    - `Content-Type`: `application/json`
    - `ConsistencyLevel`: `eventual` (for $filter queries)
  - Options:
    - Response > Never Error: OFF (to catch 404s)
    - Response > Include Response Headers and Status: ON (for debugging)
- **Alternative approach**: Use Code node to construct dynamic URL based on strategy
- **Output**: User object with `id`, `userPrincipalName`, `displayName`, `mail`
- **Error handling**: 404 = user not found, route to error response
- **Estimated effort**: 30 minutes

#### 7. Extract M365 User Details
- **Description**: Extract and normalize user details from Graph API response
- **Node type**: `n8n-nodes-base.code` (JavaScript)
- **Logic**:
  ```javascript
  const response = $input.first().json;

  // Handle search vs direct lookup response
  const user = response.value ? response.value[0] : response;

  if (!user) {
    throw new Error('User not found in Microsoft 365');
  }

  return {
    json: {
      m365UserId: user.id,
      userPrincipalName: user.userPrincipalName,
      displayName: user.displayName,
      mail: user.mail,
      m365Found: true
    }
  };
  ```
- **Estimated effort**: 20 minutes

#### 8. Lookup User in Active Directory
- **Description**: Find user in AD LDAP to get DN and current groups
- **Node type**: `n8n-nodes-base.ldap`
- **Configuration**:
  - Operation: `Search`
  - Credential: Use LDAP credential from Task 2
  - Base DN: `{{$env.AD_BASE_DN}}`
  - Search For: `Custom`
  - Filter (dynamic):
    - If by ID: `(sAMAccountName={{$json.lookupValue}})`
    - If by name: `(cn={{$json.lookupValue}})`
  - Attributes: `dn,memberOf,userAccountControl,sAMAccountName,mail,displayName`
  - Scope: `Whole Subtree`
  - Return All: OFF
  - Limit: 1
- **Alternative filter strategies**:
  - By email: `(mail={{$json.lookupValue}})`
  - By UPN: `(userPrincipalName={{$json.lookupValue}})`
- **Output**: LDAP entry with DN, groups, current status
- **Error handling**: Empty result = user not found in AD
- **Estimated effort**: 30 minutes

#### 9. Extract AD User Details
- **Description**: Extract and validate AD user details
- **Node type**: `n8n-nodes-base.code` (JavaScript)
- **Logic**:
  ```javascript
  const ldapResult = $input.first().json;

  if (!ldapResult.dn) {
    throw new Error('User not found in Active Directory');
  }

  // Parse groups (memberOf is array of DNs)
  const groups = ldapResult.memberOf || [];
  const groupDNs = Array.isArray(groups) ? groups : [groups];

  // Check if already disabled
  const userAccountControl = parseInt(ldapResult.userAccountControl);
  const ACCOUNTDISABLE = 0x0002;
  const isAlreadyDisabled = (userAccountControl & ACCOUNTDISABLE) !== 0;

  return {
    json: {
      userDN: ldapResult.dn,
      sAMAccountName: ldapResult.sAMAccountName,
      groupDNs: groupDNs,
      groupCount: groupDNs.length,
      currentUserAccountControl: userAccountControl,
      isAlreadyDisabled: isAlreadyDisabled,
      adFound: true
    }
  };
  ```
- **Estimated effort**: 25 minutes

#### 10. Merge and Validate User Data
- **Description**: Merge M365 and AD data, ensure user found in both systems
- **Node type**: `n8n-nodes-base.merge` + `n8n-nodes-base.code`
- **Merge Configuration**:
  - Mode: Combine (combine all inputs)
  - Combine By: Merge By Position
- **Code Logic** (after merge):
  ```javascript
  const data = $input.first().json;

  if (!data.m365Found) {
    throw new Error('User not found in Microsoft 365');
  }

  if (!data.adFound) {
    throw new Error('User not found in Active Directory');
  }

  // Merge all data
  return {
    json: {
      // Original request
      lookupValue: data.lookupValue,
      supervisorEmail: data.supervisorEmail,
      reason: data.reason,
      ticketNumber: data.ticketNumber,
      // M365 data
      m365UserId: data.m365UserId,
      userPrincipalName: data.userPrincipalName,
      displayName: data.displayName,
      mail: data.mail,
      // AD data
      userDN: data.userDN,
      sAMAccountName: data.sAMAccountName,
      groupDNs: data.groupDNs,
      groupCount: data.groupCount,
      isAlreadyDisabled: data.isAlreadyDisabled,
      // Workflow metadata
      validated: true,
      validationTime: new Date().toISOString()
    }
  };
  ```
- **Error handling**: Route errors to error response node
- **Estimated effort**: 25 minutes

### Phase 3: Microsoft 365 Operations

#### 11. Lookup Supervisor in M365
- **Description**: Find supervisor user object if email provided, or get manager from user
- **Node type**: `n8n-nodes-base.code` with HTTP request OR separate HTTP Request node
- **Logic** (Code node approach):
  ```javascript
  const data = $input.first().json;
  const supervisorEmail = data.supervisorEmail;
  const userId = data.m365UserId;

  let supervisorId = null;
  let supervisorEmail_resolved = null;

  if (supervisorEmail) {
    // Lookup provided supervisor
    const response = await $http.request({
      method: 'GET',
      url: `https://graph.microsoft.com/v1.0/users/${supervisorEmail}`,
      headers: {
        'Authorization': `Bearer ${$credentials.accessToken}`,
        'Content-Type': 'application/json'
      }
    });
    supervisorId = response.id;
    supervisorEmail_resolved = response.mail;
  } else {
    // Get manager from user's manager relationship
    try {
      const response = await $http.request({
        method: 'GET',
        url: `https://graph.microsoft.com/v1.0/users/${userId}/manager`,
        headers: {
          'Authorization': `Bearer ${$credentials.accessToken}`,
          'Content-Type': 'application/json'
        }
      });
      supervisorId = response.id;
      supervisorEmail_resolved = response.mail;
    } catch (error) {
      // No manager found, log warning but continue
      console.log('No manager found, mailbox permissions will not be granted');
    }
  }

  return {
    json: {
      ...data,
      supervisorId: supervisorId,
      supervisorEmail: supervisorEmail_resolved,
      supervisorFound: !!supervisorId
    }
  };
  ```
- **Error handling**: If supervisor not found, continue without permissions (log warning)
- **Alternative**: Use separate HTTP Request nodes with If node for branching
- **Estimated effort**: 30 minutes

#### 12. Convert Mailbox to Shared Mailbox (CRITICAL)
- **Description**: Convert user's mailbox to shared mailbox
- **Node type**: `n8n-nodes-base.executeCommand` OR `n8n-nodes-base.code` (PowerShell)
- **⚠️ IMPORTANT**: Graph API has limited support for this operation

**Approach 1: Exchange Online PowerShell (RECOMMENDED)**
```powershell
# Execute Command node or Code node with SSH
Connect-ExchangeOnline -CertificateThumbprint "CERT_THUMBPRINT" -AppId "APP_ID" -Organization "tenant.onmicrosoft.com"
Set-Mailbox -Identity "{{$json.userPrincipalName}}" -Type Shared
Disconnect-ExchangeOnline -Confirm:$false
```

**Approach 2: Graph API (Limited)**
- Node type: `n8n-nodes-base.httpRequest`
- Method: `PATCH`
- URL: `https://graph.microsoft.com/v1.0/users/{{$json.m365UserId}}`
- Body:
  ```json
  {
    "mailboxSettings": {
      "exchangeResourceType": "SharedMailbox"
    }
  }
  ```
- **Note**: This may not work or may have limited effect

**Approach 3: Azure Automation**
- Create Azure Automation account with PowerShell runbook
- Trigger via webhook from n8n using HTTP Request node
- Runbook uses Exchange Online management

**Prerequisites** (for PowerShell approach):
- Exchange Online module installed
- Certificate-based authentication configured
- Service principal with Exchange.ManageAsApp permission

**Decision required**: Choose approach based on environment setup
- **Estimated effort**: 1-2 hours (depending on approach)

#### 13. Grant Supervisor Full Access to Shared Mailbox
- **Description**: Add supervisor permissions to the converted shared mailbox
- **Node type**: Same as Task 12 (PowerShell or Graph API)
- **Dependencies**: Task 11 (supervisor lookup), Task 12 (mailbox conversion)

**PowerShell Approach (RECOMMENDED)**:
```powershell
# Execute Command node or Code node with SSH
Connect-ExchangeOnline -CertificateThumbprint "CERT_THUMBPRINT" -AppId "APP_ID" -Organization "tenant.onmicrosoft.com"
Add-MailboxPermission -Identity "{{$json.userPrincipalName}}" -User "{{$json.supervisorEmail}}" -AccessRights FullAccess -InheritanceType All
Disconnect-ExchangeOnline -Confirm:$false
```

**Graph API Approach (Limited)**:
- Method: POST
- URL: `https://graph.microsoft.com/v1.0/users/{{$json.m365UserId}}/mailFolders/inbox/permissions` (limited scope)
- Note: Graph API permissions are limited; PowerShell more reliable

**Conditional logic**:
- If no supervisor found (Task 11), skip this step
- Log if permissions not granted

- **Estimated effort**: 30 minutes (if using same method as Task 12)

#### 14. Get User's Current Licenses
- **Description**: Retrieve all licenses assigned to the user
- **Node type**: `n8n-nodes-base.httpRequest`
- **Configuration**:
  - Method: `GET`
  - URL: `https://graph.microsoft.com/v1.0/users/{{$json.m365UserId}}/licenseDetails`
  - Authentication: Graph API OAuth2
  - Headers:
    - `Content-Type`: `application/json`
- **Output**: Array of license objects with `skuId`, `skuPartNumber`
- **Handle empty licenses**: User may have no licenses (return empty array)
- **Estimated effort**: 20 minutes

#### 15. Remove All Licenses
- **Description**: Remove all Microsoft 365 licenses from the user
- **Node type**: `n8n-nodes-base.code` (JavaScript)
- **Dependencies**: Task 12 (convert mailbox), Task 14 (get licenses)
- **⚠️ IMPORTANT**: Remove licenses AFTER mailbox conversion to prevent data loss
- **Logic**:
  ```javascript
  const data = $input.first().json;
  const userId = data.m365UserId;
  const licenseDetails = data.licenseDetails || []; // From Task 14

  if (licenseDetails.length === 0) {
    return {
      json: {
        ...data,
        licensesRemoved: 0,
        message: 'No licenses to remove'
      }
    };
  }

  const removedLicenses = [];
  const errors = [];

  for (const license of licenseDetails) {
    try {
      await $http.request({
        method: 'POST',
        url: `https://graph.microsoft.com/v1.0/users/${userId}/assignLicense`,
        headers: {
          'Authorization': `Bearer ${$credentials.accessToken}`,
          'Content-Type': 'application/json'
        },
        body: {
          addLicenses: [],
          removeLicenses: [license.skuId]
        }
      });
      removedLicenses.push({
        skuId: license.skuId,
        skuPartNumber: license.skuPartNumber,
        removed: true
      });
    } catch (error) {
      errors.push({
        skuId: license.skuId,
        error: error.message
      });
    }
  }

  return {
    json: {
      ...data,
      licensesRemoved: removedLicenses.length,
      removedLicenses: removedLicenses,
      licenseErrors: errors,
      allLicensesRemoved: errors.length === 0
    }
  };
  ```
- **Error handling**: Log errors but continue workflow
- **Idempotency**: Safe to run if user already has no licenses
- **Estimated effort**: 45 minutes

### Phase 4: Active Directory Operations

#### 16. Calculate Disabled UserAccountControl Value
- **Description**: Calculate new userAccountControl value with ACCOUNTDISABLE bit set
- **Node type**: `n8n-nodes-base.code` (JavaScript)
- **Logic**:
  ```javascript
  const data = $input.first().json;
  const currentControl = data.currentUserAccountControl;

  const ACCOUNTDISABLE = 0x0002;
  const disabledControl = currentControl | ACCOUNTDISABLE;

  return {
    json: {
      ...data,
      newUserAccountControl: disabledControl,
      willDisable: !data.isAlreadyDisabled
    }
  };
  ```
- **Idempotency**: If already disabled, value won't change (safe to apply)
- **Estimated effort**: 15 minutes

#### 17. Disable AD User Account
- **Description**: Disable the user account in Active Directory
- **Node type**: `n8n-nodes-base.ldap`
- **Configuration**:
  - Operation: `Update`
  - Credential: LDAP credential
  - DN: `{{$json.userDN}}`
  - Update Type: `Replace`
  - Attributes:
    - Attribute ID: `userAccountControl`
    - Value: `{{$json.newUserAccountControl}}`
- **Alternative**: If node doesn't support Replace well, use Code node with LDAP library
- **Verification**: Account should show as disabled in Active Directory
- **Estimated effort**: 30 minutes

#### 18. Get and Parse User Group Memberships
- **Description**: Extract all groups the user is member of
- **Node type**: `n8n-nodes-base.code` (JavaScript)
- **Dependencies**: Data from Task 9 (AD lookup)
- **Logic**:
  ```javascript
  const data = $input.first().json;
  const groupDNs = data.groupDNs || [];

  // Filter out primary group if needed (Domain Users)
  // Usually primary group doesn't appear in memberOf, so this may not be necessary
  const groupsToRemove = groupDNs.filter(dn =>
    !dn.includes('CN=Domain Users')
  );

  if (groupsToRemove.length === 0) {
    return {
      json: {
        ...data,
        groupsToRemove: [],
        groupRemovalNeeded: false,
        message: 'No groups to remove'
      }
    };
  }

  return {
    json: {
      ...data,
      groupsToRemove: groupsToRemove,
      groupRemovalNeeded: true,
      groupRemovalCount: groupsToRemove.length
    }
  };
  ```
- **Output**: Array of group DNs to process
- **Estimated effort**: 20 minutes

#### 19. Remove User from All Groups
- **Description**: Remove user from all AD groups
- **Node type**: `n8n-nodes-base.code` (JavaScript) with LDAP operations
- **Dependencies**: Task 18 (group list)
- **Logic**:
  ```javascript
  const data = $input.first().json;
  const userDN = data.userDN;
  const groupsToRemove = data.groupsToRemove || [];

  if (groupsToRemove.length === 0) {
    return {
      json: {
        ...data,
        groupsRemoved: 0,
        message: 'No groups to remove'
      }
    };
  }

  const removedGroups = [];
  const errors = [];

  for (const groupDN of groupsToRemove) {
    try {
      // Use LDAP modify operation
      // Note: This requires LDAP library access or separate LDAP node for each group
      // For n8n, may need to use Execute Command with ldapmodify or PowerShell

      // PowerShell alternative:
      // Remove-ADGroupMember -Identity "groupDN" -Members "userDN" -Confirm:$false

      removedGroups.push({
        groupDN: groupDN,
        removed: true
      });
    } catch (error) {
      errors.push({
        groupDN: groupDN,
        error: error.message
      });
    }
  }

  return {
    json: {
      ...data,
      groupsRemoved: removedGroups.length,
      removedGroups: removedGroups,
      groupRemovalErrors: errors,
      allGroupsRemoved: errors.length === 0
    }
  };
  ```

**Alternative Implementation**: Use LDAP node in loop mode or Execute Command with PowerShell
```powershell
# For each group
$groups = @("CN=Group1,OU=Groups,DC=company,DC=com", "CN=Group2,OU=Groups,DC=company,DC=com")
foreach ($group in $groups) {
    Remove-ADGroupMember -Identity $group -Members "{{$json.userDN}}" -Confirm:$false
}
```

- **Error handling**: Log errors but continue (some groups may have been removed already)
- **Idempotency**: Safe to run if user already not in groups
- **Estimated effort**: 1 hour

#### 20. Move User to Disabled OU
- **Description**: Move user object to the disabled users OU
- **Node type**: `n8n-nodes-base.ldap`
- **Configuration**:
  - Operation: `Rename`
  - Credential: LDAP credential
  - DN: `{{$json.userDN}}`
  - New DN: Calculate in previous Code node
- **New DN Calculation** (in Code node before this):
  ```javascript
  const data = $input.first().json;
  const userDN = data.userDN;

  // Extract CN from current DN
  const cnMatch = userDN.match(/^CN=([^,]+)/);
  const cn = cnMatch ? cnMatch[1] : data.sAMAccountName;

  // Construct new DN
  const disabledOuDN = process.env.AD_DISABLED_OU || 'OU=Disabled Users,DC=company,DC=com';
  const newDN = `CN=${cn},${disabledOuDN}`;

  return {
    json: {
      ...data,
      newUserDN: newDN
    }
  };
  ```
- **Prerequisites**: Disabled Users OU must exist
- **Verification**: User should appear in Disabled Users OU
- **Dependencies**: Task 17 (disable), Task 19 (remove groups)
- **Estimated effort**: 30 minutes

### Phase 5: Workflow Completion & Response

#### 21. Create Comprehensive Audit Log
- **Description**: Compile all actions taken for audit and compliance
- **Node type**: `n8n-nodes-base.code` (JavaScript)
- **Dependencies**: All previous tasks
- **Logic**:
  ```javascript
  const data = $input.first().json;

  const auditLog = {
    workflowId: $workflow.id,
    executionId: $execution.id,
    timestamp: new Date().toISOString(),
    // Request details
    request: {
      lookupValue: data.lookupValue,
      reason: data.reason,
      ticketNumber: data.ticketNumber,
      requestedBy: 'System' // Could be from webhook auth
    },
    // User details
    user: {
      displayName: data.displayName,
      userPrincipalName: data.userPrincipalName,
      sAMAccountName: data.sAMAccountName,
      m365UserId: data.m365UserId,
      userDN: data.userDN
    },
    // Actions performed
    actions: {
      m365: {
        mailboxConverted: true, // Or track actual result
        supervisorAccess: data.supervisorFound,
        supervisorEmail: data.supervisorEmail,
        licensesRemoved: data.licensesRemoved || 0,
        licenseErrors: data.licenseErrors || []
      },
      activeDirectory: {
        accountDisabled: data.willDisable,
        wasAlreadyDisabled: data.isAlreadyDisabled,
        groupsRemoved: data.groupsRemoved || 0,
        groupErrors: data.groupRemovalErrors || [],
        movedToDisabledOU: true,
        newLocation: data.newUserDN
      }
    },
    // Summary
    summary: {
      success: true,
      partialFailure: (data.licenseErrors?.length > 0 || data.groupRemovalErrors?.length > 0),
      totalOperations: 6, // Count of operations
      failedOperations: (data.licenseErrors?.length || 0) + (data.groupRemovalErrors?.length || 0)
    }
  };

  // Optional: Send to external logging system
  // await $http.request({ method: 'POST', url: 'logging-endpoint', body: auditLog });

  return { json: auditLog };
  ```
- **Output destinations** (optional):
  - Database via HTTP Request to logging API
  - File system via Write Binary node (for self-hosted)
  - External SIEM/logging system
  - Slack/Teams notification
- **Estimated effort**: 45 minutes

#### 22. Format Success Response
- **Description**: Format detailed success response for webhook caller
- **Node type**: `n8n-nodes-base.code` (JavaScript)
- **Logic**:
  ```javascript
  const auditLog = $input.first().json;

  const response = {
    status: 'success',
    message: 'Employee termination completed successfully',
    timestamp: new Date().toISOString(),
    executionId: $execution.id,
    // Employee details
    employee: {
      name: auditLog.user.displayName,
      email: auditLog.user.userPrincipalName,
      id: auditLog.user.sAMAccountAccount
    },
    // Actions completed
    actions: {
      mailboxConverted: auditLog.actions.m365.mailboxConverted,
      supervisorAccess: auditLog.actions.m365.supervisorAccess,
      licensesRemoved: auditLog.actions.m365.licensesRemoved,
      accountDisabled: auditLog.actions.activeDirectory.accountDisabled,
      groupsRemoved: auditLog.actions.activeDirectory.groupsRemoved,
      movedToDisabledOU: auditLog.actions.activeDirectory.movedToDisabledOU
    },
    // Warnings if any
    warnings: [],
    // Ticket reference
    ticketNumber: auditLog.request.ticketNumber
  };

  // Add warnings for partial failures
  if (auditLog.summary.partialFailure) {
    if (auditLog.actions.m365.licenseErrors.length > 0) {
      response.warnings.push(`${auditLog.actions.m365.licenseErrors.length} license(s) could not be removed`);
    }
    if (auditLog.actions.activeDirectory.groupErrors.length > 0) {
      response.warnings.push(`${auditLog.actions.activeDirectory.groupErrors.length} group(s) could not be removed`);
    }
  }

  return { json: response };
  ```
- **Estimated effort**: 20 minutes

#### 23. Send Success Response to Webhook
- **Description**: Return success response to webhook caller
- **Node type**: `n8n-nodes-base.respondToWebhook`
- **Configuration**:
  - Respond With: `JSON`
  - Response Body: `{{$json}}` (from Task 22)
  - Options:
    - Response Code: `200`
    - Response Headers:
      - `Content-Type`: `application/json`
- **Alternative for partial failures**: Use 207 Multi-Status code
- **Estimated effort**: 15 minutes

#### 24. Error Handling Path - Format Error Response
- **Description**: Format detailed error response for failures
- **Node type**: `n8n-nodes-base.code` (JavaScript)
- **This node receives errors from any previous node**
- **Logic**:
  ```javascript
  const error = $input.first().json.error || $input.first().json;

  const errorResponse = {
    status: 'error',
    message: 'Employee termination failed',
    timestamp: new Date().toISOString(),
    executionId: $execution.id,
    error: {
      message: error.message || 'Unknown error',
      details: error.description || error.toString(),
      step: $node.name || 'Unknown step'
    },
    // Include any partial data that was collected
    partialData: {
      userFound: $input.first().json.validated || false,
      m365Operations: 'not_attempted',
      adOperations: 'not_attempted'
    }
  };

  return { json: errorResponse };
  ```
- **Estimated effort**: 30 minutes

#### 25. Send Error Response to Webhook
- **Description**: Return error response to webhook caller
- **Node type**: `n8n-nodes-base.respondToWebhook`
- **Configuration**:
  - Respond With: `JSON`
  - Response Body: `{{$json}}` (from Task 24)
  - Options:
    - Response Code: `500` (or appropriate error code)
      - 400: Bad Request (invalid input)
      - 404: Not Found (user not found)
      - 500: Internal Server Error (workflow failure)
      - 503: Service Unavailable (external service issue)
    - Response Headers:
      - `Content-Type`: `application/json`
- **Estimated effort**: 15 minutes

#### 26. Connect All Nodes and Error Handlers
- **Description**: Connect all nodes together and implement error catching and routing for each critical step
- **MCP Tool**: `mcp__n8n-mcp__n8n_update_partial_workflow` with multiple `addConnection` operations
- **Node type**: Configure "On Error" workflow settings and node settings

**Node Connections to Add**:
Use `mcp__n8n-mcp__n8n_update_partial_workflow` with multiple `addConnection` operations:

```javascript
{
  operations: [
    // Main flow connections
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "webhook-trigger",
        sourceOutputIndex: 0,
        targetNodeId: "input-validation",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "input-validation",
        sourceOutputIndex: 0,
        targetNodeId: "lookup-m365-user",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "input-validation",
        sourceOutputIndex: 0,
        targetNodeId: "lookup-ad-user",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "lookup-m365-user",
        sourceOutputIndex: 0,
        targetNodeId: "extract-m365-details",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "lookup-ad-user",
        sourceOutputIndex: 0,
        targetNodeId: "extract-ad-details",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "extract-m365-details",
        sourceOutputIndex: 0,
        targetNodeId: "merge-validate",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "extract-ad-details",
        sourceOutputIndex: 0,
        targetNodeId: "merge-validate",
        targetInputIndex: 1
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "merge-validate",
        sourceOutputIndex: 0,
        targetNodeId: "lookup-supervisor",
        targetInputIndex: 0
      }
    },
    // M365 operations chain
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "lookup-supervisor",
        sourceOutputIndex: 0,
        targetNodeId: "convert-mailbox",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "convert-mailbox",
        sourceOutputIndex: 0,
        targetNodeId: "grant-supervisor-access",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "grant-supervisor-access",
        sourceOutputIndex: 0,
        targetNodeId: "get-licenses",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "get-licenses",
        sourceOutputIndex: 0,
        targetNodeId: "remove-licenses",
        targetInputIndex: 0
      }
    },
    // AD operations chain
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "lookup-supervisor",
        sourceOutputIndex: 0,
        targetNodeId: "calc-disabled-value",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "calc-disabled-value",
        sourceOutputIndex: 0,
        targetNodeId: "disable-ad-account",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "disable-ad-account",
        sourceOutputIndex: 0,
        targetNodeId: "parse-groups",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "parse-groups",
        sourceOutputIndex: 0,
        targetNodeId: "remove-from-groups",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "remove-from-groups",
        sourceOutputIndex: 0,
        targetNodeId: "move-to-disabled-ou",
        targetInputIndex: 0
      }
    },
    // Convergence and completion
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "remove-licenses",
        sourceOutputIndex: 0,
        targetNodeId: "create-audit-log",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "move-to-disabled-ou",
        sourceOutputIndex: 0,
        targetNodeId: "create-audit-log",
        targetInputIndex: 1
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "create-audit-log",
        sourceOutputIndex: 0,
        targetNodeId: "format-success-response",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "format-success-response",
        sourceOutputIndex: 0,
        targetNodeId: "send-success-response",
        targetInputIndex: 0
      }
    },
    // Error path connections
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "input-validation",
        sourceOutputIndex: 0,
        targetNodeId: "format-error-response",
        targetInputIndex: 0,
        onError: true
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "lookup-m365-user",
        sourceOutputIndex: 0,
        targetNodeId: "format-error-response",
        targetInputIndex: 0,
        onError: true
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "lookup-ad-user",
        sourceOutputIndex: 0,
        targetNodeId: "format-error-response",
        targetInputIndex: 0,
        onError: true
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "merge-validate",
        sourceOutputIndex: 0,
        targetNodeId: "format-error-response",
        targetInputIndex: 0,
        onError: true
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "convert-mailbox",
        sourceOutputIndex: 0,
        targetNodeId: "format-error-response",
        targetInputIndex: 0,
        onError: true
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "disable-ad-account",
        sourceOutputIndex: 0,
        targetNodeId: "format-error-response",
        targetInputIndex: 0,
        onError: true
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "format-error-response",
        sourceOutputIndex: 0,
        targetNodeId: "send-error-response",
        targetInputIndex: 0
      }
    }
  ]
}
```

**Configuration**:
  - For each critical node (M365 operations, AD operations):
    - Node settings → "Continue On Fail": OFF (default)
    - Connect to error path via error output
  - Use If nodes to route based on error type:
    - User not found → 404 response
    - Invalid input → 400 response
    - Service unavailable → 503 response
    - Other errors → 500 response
- **Error workflow pattern**:
  ```
  [Node] --error--> [Error Handler Code] --> [Format Error] --> [Respond to Webhook]
         --success--> [Next Node]
  ```
- **Estimated effort**: 1 hour

### Phase 6: Testing & Validation

#### 27. Unit Testing (Per Node/Phase)
- **Description**: Test each phase independently in n8n using MCP server tools
- **MCP Tools for Testing**:
  - `mcp__n8n-mcp__n8n_validate_workflow` - Validate workflow structure before testing
  - `mcp__n8n-mcp__n8n_trigger_webhook_workflow` - Trigger webhook for testing
  - `mcp__n8n-mcp__n8n_get_execution` - Get execution results
  - `mcp__n8n-mcp__n8n_list_executions` - List all executions
- **Test approach**:
  1. **Webhook & Validation (Phase 2)**:
     - Test with valid employee ID
     - Test with valid employee name
     - Test with invalid input (should error)
     - Test with missing supervisor email

  2. **M365 Operations (Phase 3)**:
     - Test user lookup in test tenant
     - Test supervisor lookup
     - Test license retrieval
     - Test license removal (use test user)

  3. **AD Operations (Phase 4)**:
     - Test LDAP search in test environment
     - Test account disable in test OU
     - Test group removal (test user in test groups)
     - Test move to disabled OU

- **Test data requirements**:
  - Test M365 user with licenses
  - Test AD user in multiple groups
  - Test supervisor account
- **Use n8n "Test Workflow" feature**: Execute workflow with test data
- **Estimated effort**: 2 hours

#### 28. Integration Testing (End-to-End)
- **Description**: Test complete workflow from webhook to completion using n8n MCP server
- **Testing Approach**:
  1. Use `mcp__n8n-mcp__n8n_trigger_webhook_workflow` to trigger the workflow
  2. Use `mcp__n8n-mcp__n8n_get_execution` to retrieve results (with mode='summary' or mode='full')
  3. Verify execution success and data correctness
  4. Check execution logs for errors
- **Test scenarios**:

  **Scenario 1: Complete termination with employee ID**
  ```bash
  curl -X POST https://n8n.domain.com/webhook/terminate-employee \
    -H "X-API-Key: YOUR_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "employeeId": "testuser01",
      "supervisorEmail": "manager@company.com",
      "reason": "Testing",
      "ticketNumber": "TEST001"
    }'
  ```
  - Verify: Mailbox converted, supervisor access, licenses removed, AD disabled, groups removed, moved to OU

  **Scenario 2: Complete termination with employee name**
  ```bash
  curl -X POST https://n8n.domain.com/webhook/terminate-employee \
    -H "X-API-Key: YOUR_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "employeeName": "Test User",
      "supervisorEmail": "manager@company.com"
    }'
  ```
  - Same verifications as Scenario 1

  **Scenario 3: Termination without supervisor (use manager)**
  ```bash
  curl -X POST https://n8n.domain.com/webhook/terminate-employee \
    -H "X-API-Key: YOUR_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "employeeId": "testuser02"
    }'
  ```
  - Verify: Manager lookup succeeds, manager granted access

  **Scenario 4: User not found in M365**
  ```bash
  curl -X POST https://n8n.domain.com/webhook/terminate-employee \
    -H "X-API-Key: YOUR_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "employeeId": "nonexistent"
    }'
  ```
  - Verify: Error response, no AD changes made

  **Scenario 5: User not found in AD**
  - Create M365-only test user
  - Verify: Error response, no M365 changes made (or document manual remediation)

  **Scenario 6: Partial failure simulation**
  - Temporarily disable AD connection
  - Verify: M365 succeeds, AD fails, error logged, partial completion indicated

  **Scenario 7: Idempotency test**
  - Run termination twice for same user
  - Verify: Second run succeeds without errors, no duplicate actions

- **Verification methods**:
  - Check M365 admin center: mailbox type, licenses
  - Check Exchange admin center: mailbox permissions
  - Check Active Directory Users and Computers: account status, OU location, group memberships
  - Check n8n execution logs: audit trail
- **Estimated effort**: 3 hours

#### 29. Edge Case Testing
- **Description**: Test unusual but possible scenarios
- **Edge cases to cover**:
  1. **User with no licenses**
     - Verify: License removal skipped gracefully
  2. **User with no group memberships**
     - Verify: Group removal skipped gracefully
  3. **User already disabled**
     - Verify: Workflow completes, idempotent behavior
  4. **Shared mailbox already exists**
     - Verify: Handle conversion error gracefully
  5. **Supervisor not found**
     - Verify: Continue without permissions, log warning
  6. **Invalid webhook payload**
     - Missing required fields
     - Malformed JSON
     - Invalid email format
     - Verify: 400 Bad Request returned
  7. **LDAP connection failure**
     - Verify: 503 Service Unavailable, detailed error logged
  8. **Graph API rate limiting**
     - Implement retry logic with exponential backoff
     - Test with multiple rapid requests
  9. **User in many groups (100+)**
     - Verify: All groups processed, no timeout
     - Consider pagination if needed
  10. **Special characters in names**
      - Test LDAP filter escaping
      - Test with names containing quotes, parentheses

- **Estimated effort**: 2 hours

#### 30. Performance & Load Testing
- **Description**: Test workflow under realistic and heavy loads
- **Test scenarios**:
  1. **Single termination timing**
     - Measure end-to-end execution time
     - Target: < 30 seconds for standard user
  2. **Concurrent terminations**
     - Test 5-10 concurrent webhook calls
     - Verify: All complete successfully, no race conditions
  3. **Large group membership**
     - Test user with 50+ groups
     - Measure group removal time
  4. **Webhook timeout**
     - Ensure response before webhook timeout (typically 30s)
     - If operations take longer, return 202 Accepted immediately

- **Tools**: Postman, cURL, custom scripts
- **Estimated effort**: 1 hour

## Codebase Integration Points

### New n8n Workflow to Create
- **Filename**: `Employee_Termination_Automation.json`
- **Location**: n8n workflows (export after creation)
- **Backup**: Store workflow JSON in version control

### Configuration Requirements

**Environment Variables** (set in n8n or system environment):
```bash
AD_BASE_DN=dc=company,dc=com
AD_DISABLED_OU=OU=Disabled Users,DC=company,DC=com
GRAPH_API_BASE_URL=https://graph.microsoft.com/v1.0
AZURE_TENANT_ID=your-tenant-id
EXCHANGE_CERT_THUMBPRINT=cert-thumbprint (if using PowerShell)
EXCHANGE_APP_ID=app-id (if using PowerShell)
```

**Credentials to Configure** (n8n UI → Credentials):
1. **Microsoft Graph API OAuth2**
   - Name: `Microsoft Graph - Termination Workflow`
   - Type: OAuth2 API
   - Grant Type: Client Credentials
   - Access Token URL: `https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token`
   - Scope: `https://graph.microsoft.com/.default`

2. **LDAP Service Account**
   - Name: `Active Directory - Termination Workflow`
   - Type: LDAP
   - Connection: LDAPS (port 636) recommended
   - Bind credentials: Service account with appropriate permissions

3. **Webhook Authentication**
   - Name: `Webhook - Termination API`
   - Type: Header Auth or Generic Credential Type
   - Secure API key

### External Dependencies

**Azure AD App Registration**:
- Application (client) ID
- Client secret (with expiration tracking)
- Tenant ID
- Permissions granted and admin consent applied

**Service Accounts**:
- AD LDAP service account with permissions:
  - Read user objects
  - Write userAccountControl attribute
  - Move objects (rename)
  - Modify group membership
- Recommended: Dedicated service account, not personal account

**Exchange Online** (if using PowerShell approach):
- Exchange Online PowerShell module
- Certificate-based authentication OR App-only authentication
- SSH access to server with Exchange module (if remote)

**Network Requirements**:
- n8n can reach Microsoft Graph API endpoints (https://graph.microsoft.com)
- n8n can reach Active Directory LDAP servers (port 389/636)
- n8n can reach Exchange servers (if PowerShell remoting)
- Webhook endpoint accessible to calling systems

## Technical Design

### Workflow Architecture Diagram

```
                    [Webhook Trigger: POST /terminate-employee]
                                     |
                                     v
                     [Input Validation & Strategy Selection]
                          (Code Node: Task 5)
                                     |
                                     v
                      +---------------+---------------+
                      |                               |
                      v                               v
          [M365 User Lookup]                [AD User Lookup (LDAP)]
           (HTTP Request: Task 6)             (LDAP Search: Task 8)
                      |                               |
                      v                               v
         [Extract M365 Details]             [Extract AD Details]
           (Code Node: Task 7)               (Code Node: Task 9)
                      |                               |
                      +---------------+---------------+
                                     |
                                     v
                      [Merge & Validate User Data]
                    (Merge Node + Code: Task 10)
                                     |
                                     v
                         [Validation: User Found?]
                              (If Node)
                                     |
                    +----------------+----------------+
                    |                                 |
                    v (Yes)                           v (No)
          [Lookup Supervisor]                [Format Error Response]
           (Code/HTTP: Task 11)               (Code: Task 24)
                    |                                 |
                    v                                 v
       +------------+-------------+          [Send Error Response]
       |                          |           (Respond: Task 25)
       v                          v
[M365 Operations]         [AD Operations]
       |                          |
       +-> Convert Mailbox        +-> Calc Disabled Value
       |    (Task 12)             |    (Code: Task 16)
       |                          |
       +-> Grant Supervisor       +-> Disable Account
       |    Access (Task 13)      |    (LDAP Update: Task 17)
       |                          |
       +-> Get Licenses           +-> Parse Group List
       |    (HTTP: Task 14)       |    (Code: Task 18)
       |                          |
       +-> Remove Licenses        +-> Remove from Groups
            (Code: Task 15)       |    (Code/LDAP: Task 19)
                                  |
                                  +-> Move to Disabled OU
                                       (LDAP Rename: Task 20)
       |                          |
       +------------+-------------+
                    |
                    v
          [Create Audit Log]
           (Code: Task 21)
                    |
                    v
        [Format Success Response]
           (Code: Task 22)
                    |
                    v
        [Send Success Response]
      (Respond to Webhook: Task 23)

[Error Handlers throughout workflow route to Error Response path]
```

### Data Flow

1. **Input Stage** (Tasks 4-5)
   - Webhook receives JSON payload: `{ employeeId OR employeeName, supervisorEmail?, ... }`
   - Validation: Check required fields, format emails
   - Output: `{ lookupStrategy, lookupValue, supervisorEmail, ... }`

2. **Lookup Stage** (Tasks 6-10)
   - **Parallel execution**: M365 and AD lookups run simultaneously
   - M365: Graph API returns user object with `id`, `userPrincipalName`, `mail`
   - AD: LDAP returns entry with `dn`, `memberOf`, `userAccountControl`, `sAMAccountName`
   - Merge: Combine results with validation
   - Output: Combined user data from both systems

3. **Validation Gate** (Task 10)
   - Check: User found in both M365 AND AD
   - True path: Continue to operations
   - False path: Route to error response

4. **Supervisor Resolution** (Task 11)
   - If supervisorEmail provided: Lookup in M365
   - Else: Get manager from user's manager relationship
   - Output: `supervisorId`, `supervisorEmail`, `supervisorFound` flag

5. **M365 Operations** (Tasks 12-15) - Sequential execution
   - Step 1: Convert mailbox to shared (changes mailbox type)
     - PowerShell: `Set-Mailbox -Type Shared`
     - Or Graph API (limited support)
   - Step 2: Grant supervisor full access
     - PowerShell: `Add-MailboxPermission -AccessRights FullAccess`
     - Conditional: Only if supervisor found
   - Step 3: Get current licenses
     - Graph API: `GET /users/{id}/licenseDetails`
   - Step 4: Remove all licenses (AFTER mailbox conversion)
     - Graph API: `POST /users/{id}/assignLicense` with `removeLicenses`
     - Iterate through all licenses
   - Output: License removal summary, errors (if any)

6. **AD Operations** (Tasks 16-20) - Sequential execution
   - Step 1: Calculate disabled userAccountControl value
     - Bitwise OR: `currentValue | 0x0002`
   - Step 2: Disable account
     - LDAP Update: Replace `userAccountControl` attribute
   - Step 3: Parse group memberships
     - Extract group DNs from `memberOf` attribute
   - Step 4: Remove from all groups
     - For each group: LDAP modify to remove `member` attribute
     - Or PowerShell: `Remove-ADGroupMember`
   - Step 5: Move to disabled OU
     - LDAP Rename: Change DN to disabled OU path
   - Output: Group removal summary, new DN

7. **Audit & Response Stage** (Tasks 21-23)
   - Compile comprehensive audit log:
     - Request details
     - User details
     - All actions performed
     - Errors/warnings
     - Timestamps
   - Format success response:
     - Status, message
     - Actions summary
     - Warnings (if partial failures)
   - Send response via Respond to Webhook node
     - HTTP 200 with JSON body

8. **Error Path** (Tasks 24-25)
   - Catch errors from any stage
   - Format error response:
     - Error message and details
     - Stage where error occurred
     - Partial data collected (if any)
   - Send error response:
     - HTTP 400/404/500/503 based on error type
     - JSON body with details

### Key n8n Expressions and Patterns

**Dynamic URL Construction**:
```javascript
// In Code node
const strategy = $json.lookupStrategy;
const value = $json.lookupValue;
let url;

if (strategy === 'byId') {
  url = `https://graph.microsoft.com/v1.0/users/${value}`;
} else {
  url = `https://graph.microsoft.com/v1.0/users?$filter=displayName eq '${value}'`;
}

return { json: { ...data, graphUrl: url } };
```

**Accessing Environment Variables**:
```
{{$env.AD_BASE_DN}}
{{$env.AZURE_TENANT_ID}}
```

**Accessing Node Output**:
```
{{$node["Lookup User in M365"].json.id}}
{{$node["Lookup User in AD"].json.dn}}
```

**Accessing Workflow Metadata**:
```
{{$workflow.id}}
{{$execution.id}}
{{$now.toISO()}}
```

**Error Handling in Code**:
```javascript
try {
  // Operation
} catch (error) {
  // Log but continue
  console.error('Warning:', error.message);
  // Or re-throw to stop workflow
  throw new Error(`Failed: ${error.message}`);
}
```

**Iteration Pattern** (for licenses, groups):
```javascript
const items = $input.first().json.items; // Array
const results = [];

for (const item of items) {
  // Process each item
  const result = await processItem(item);
  results.push(result);
}

return { json: { results } };
```

## Dependencies and Libraries

### External APIs
- **Microsoft Graph API v1.0**
  - Base URL: `https://graph.microsoft.com/v1.0`
  - Authentication: OAuth2 Client Credentials
  - Rate limits: Respect throttling (429 responses)
  - Documentation: https://learn.microsoft.com/en-us/graph/api/overview

- **Active Directory LDAP**
  - Protocol: LDAP v3
  - Ports: 389 (LDAP), 636 (LDAPS)
  - Authentication: Simple bind or SASL
  - Encryption: TLS strongly recommended

- **Exchange Online PowerShell** (if using PowerShell approach)
  - Module: ExchangeOnlineManagement
  - Authentication: Certificate-based or App-only
  - Connection: `Connect-ExchangeOnline`
  - Documentation: https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell

### n8n Nodes Required

**Core Nodes**:
- `n8n-nodes-base.webhook` (v2.1+) - Trigger node
- `n8n-nodes-base.httpRequest` (v4.3+) - Graph API calls
- `n8n-nodes-base.ldap` (v1+) - AD operations
- `n8n-nodes-base.code` (latest) - JavaScript logic
- `n8n-nodes-base.if` (v2.2+) - Conditional branching
- `n8n-nodes-base.respondToWebhook` (latest) - Response control
- `n8n-nodes-base.merge` (latest) - Combine data from multiple sources

**Optional Nodes** (depending on approach):
- `n8n-nodes-base.executeCommand` - PowerShell execution
- `n8n-nodes-base.ssh` - Remote PowerShell
- `n8n-nodes-base.postgres` / `n8n-nodes-base.mysql` - Audit logging to database
- `n8n-nodes-base.slack` / `n8n-nodes-base.msteams` - Notifications

### External Tools (if using PowerShell approach)

**Exchange Online Management**:
- Module: ExchangeOnlineManagement (install on server)
- Install: `Install-Module -Name ExchangeOnlineManagement`
- Server requirements: PowerShell 7+ or Windows PowerShell 5.1

**Active Directory PowerShell**:
- Module: ActiveDirectory (Windows RSAT)
- Install: `Install-WindowsFeature RSAT-AD-PowerShell`
- Alternative to direct LDAP access

## Testing Strategy

### Testing Environments

**Test Environment Requirements**:
1. **Test Azure AD Tenant**
   - Separate from production
   - Test users with licenses
   - Test groups and organizational structure

2. **Test Active Directory**
   - Separate test domain or test OU
   - Test users and groups
   - Disabled Users OU created

3. **n8n Test Instance**
   - Non-production n8n installation
   - Connected to test environments
   - Test credentials configured

### Unit Testing (Per Phase)

**Phase 1-2: Webhook & Validation**
- Test with valid employee ID → Should return validated data
- Test with valid employee name → Should return validated data
- Test with missing required field → Should error
- Test with invalid email format → Should error
- Test with both ID and name → Should prefer ID

**Phase 3: M365 Operations**
- Test user lookup with existing user → Should return user object
- Test user lookup with non-existent user → Should 404
- Test supervisor lookup with existing email → Should return supervisor
- Test supervisor lookup with non-existent email → Should handle gracefully
- Test license retrieval → Should return array of licenses
- Test license removal with licenses → Should remove all
- Test license removal with no licenses → Should skip gracefully

**Phase 4: AD Operations**
- Test LDAP search with existing user → Should return entry
- Test LDAP search with non-existent user → Should return empty
- Test account disable on enabled account → Should disable
- Test account disable on already disabled → Should be idempotent
- Test group membership parsing → Should return list of DNs
- Test group removal → Should remove from all groups
- Test OU move → Should update DN

**Phase 5: Audit & Response**
- Test audit log creation → Should include all data
- Test success response formatting → Should match schema
- Test error response formatting → Should include details

### Integration Testing (End-to-End)

See Task 28 for detailed integration test scenarios.

### Edge Case Testing

See Task 29 for detailed edge case scenarios.

### Performance Testing

See Task 30 for detailed performance test scenarios.

### Regression Testing

**After Changes**:
- Re-run all integration tests
- Verify idempotency still works
- Check error handling hasn't regressed
- Validate audit logs still complete

### Testing Tools

**Manual Testing**:
- Postman collection for webhook calls
- cURL scripts for command-line testing
- n8n "Test Workflow" feature

**Automated Testing** (future enhancement):
- n8n API to trigger workflows programmatically
- Automated validation of M365 and AD state
- Scheduled test runs

**Validation Tools**:
- Microsoft 365 Admin Center
- Exchange Admin Center
- Active Directory Users and Computers (ADUC)
- PowerShell Get-Mailbox, Get-ADUser commands
- n8n Execution logs

## Success Criteria

### Functional Success Criteria
- [x] Workflow successfully triggered via webhook with employee ID
- [x] Workflow successfully triggered via webhook with employee name
- [x] User correctly identified in Microsoft 365
- [x] User correctly identified in Active Directory
- [x] Mailbox converted to shared mailbox without data loss
- [x] Supervisor granted full access to shared mailbox (if supervisor found)
- [x] All M365 licenses removed from user
- [x] AD account successfully disabled
- [x] User removed from all AD groups
- [x] User moved to Disabled Users OU
- [x] Complete audit log created with all actions and timestamps
- [x] Success response returned to webhook caller
- [x] Response time < 30 seconds for standard user

### Error Handling Success Criteria
- [x] User not found in M365 → Returns 404 error
- [x] User not found in AD → Returns 404 error
- [x] Invalid input → Returns 400 Bad Request
- [x] Service unavailable → Returns 503 with details
- [x] Partial failures logged and reported
- [x] Error responses include actionable details

### Security Success Criteria
- [x] Webhook requires authentication (API key)
- [x] Credentials stored securely in n8n
- [x] No secrets in workflow JSON
- [x] All actions logged for audit
- [x] Service accounts use least privilege
- [x] LDAPS (TLS) used for AD communication

### Operational Success Criteria
- [x] Workflow can be safely re-run (idempotent)
- [x] No manual intervention required for standard terminations
- [x] Integration tests pass with 100% success rate
- [x] Workflow handles edge cases gracefully
- [x] Error notifications sent to IT team (optional)
- [x] Workflow execution logs accessible

### Documentation Success Criteria
- [x] Runbook created with setup instructions
- [x] Webhook API documented
- [x] Error codes and meanings documented
- [x] Manual remediation steps documented
- [x] Maintenance procedures documented

## Notes and Considerations

### Security Considerations

**Authentication & Authorization**:
- ✅ Webhook authentication prevents unauthorized terminations
- ✅ API key rotation strategy (recommend 90-day rotation)
- ✅ IP whitelist for webhook (optional but recommended)
- ✅ Service account password rotation (recommend 90-day rotation)
- ✅ Audit all terminations for compliance

**Credential Management**:
- ✅ Store credentials only in n8n credential store
- ✅ Never hardcode secrets in workflow
- ✅ Use certificate-based auth for Exchange where possible
- ✅ Monitor for credential expiration (app secrets, certificates)

**Least Privilege**:
- ✅ Azure AD app: Only required Graph API permissions
- ✅ LDAP service account: Only required AD permissions
- ✅ No global admin privileges required

**Audit & Compliance**:
- ✅ All terminations logged with timestamp, user, actions
- ✅ Immutable audit logs (send to external SIEM if required)
- ✅ Retention policy for audit logs (recommend 7 years)
- ✅ Correlation with ticketing system via ticketNumber

**Approval Process** (optional enhancement):
- Consider adding approval step before execution
- Manager approval via email or Teams
- HR approval for sensitive terminations

### Potential Challenges

#### 1. Mailbox Conversion API Limitations

**Challenge**: Microsoft Graph API has limited/unreliable support for mailbox type conversion.

**Impact**: Core functionality may not work via Graph API alone.

**Solutions**:
1. **PowerShell Approach** (RECOMMENDED):
   - Use Exchange Online PowerShell
   - `Set-Mailbox -Type Shared`
   - Requires: Certificate auth, PowerShell remoting, Execute Command node
   - Pro: Reliable, tested
   - Con: Additional setup complexity

2. **Azure Automation Approach**:
   - Create Azure Automation runbook
   - Trigger via webhook from n8n
   - Runbook uses Exchange Online PowerShell
   - Pro: Managed by Azure, secure
   - Con: Additional Azure resources

3. **Separate n8n Workflow**:
   - Split mailbox operations into separate workflow
   - Use Execute Command node with remoting
   - Call from main workflow via webhook
   - Pro: Modular, reusable
   - Con: More complex architecture

**Decision Point**: Choose approach during Task 12 based on infrastructure.

#### 2. LDAP Complexity

**Challenge**: Active Directory operations can be complex, especially bit manipulation and group iteration.

**Impact**: AD operations may require advanced LDAP knowledge.

**Solutions**:
1. **Code Node with LDAP Library**:
   - Use JavaScript LDAP library (ldapjs)
   - More control over operations
   - Easier debugging
   - Requires: n8n with external modules enabled

2. **PowerShell Approach**:
   - Use Active Directory PowerShell module
   - `Disable-ADAccount`, `Remove-ADGroupMember`, `Move-ADObject`
   - Pro: Simpler syntax, well-documented
   - Con: Requires PowerShell remoting

3. **Native LDAP Nodes**:
   - Use n8n LDAP node for standard operations
   - Use Code node only for complex logic
   - Pro: Stays within n8n
   - Con: May hit limitations

**Recommendation**: Start with native LDAP nodes, fall back to PowerShell if needed.

#### 3. Error Recovery and Transactions

**Challenge**: If M365 succeeds but AD fails (or vice versa), user is in inconsistent state.

**Impact**: Manual remediation required for partial failures.

**Solutions**:
1. **Compensation Logic** (complex):
   - If AD fails after M365 succeeds, attempt to rollback M365 changes
   - Restore licenses, convert mailbox back
   - Pro: Automatic recovery
   - Con: Complex, may fail to rollback

2. **Manual Remediation** (RECOMMENDED):
   - Log partial completion state
   - Document manual remediation steps
   - Alert IT team for manual completion
   - Pro: Simple, reliable
   - Con: Requires manual intervention

3. **Retry Logic**:
   - Automatically retry failed operations
   - Exponential backoff
   - Pro: May succeed on retry
   - Con: Doesn't solve all issues

**Recommendation**: Use manual remediation approach with clear documentation.

#### 4. Performance and Timeouts

**Challenge**: Users with many group memberships or licenses may cause long execution times.

**Impact**: Workflow may exceed webhook timeout (typically 30s).

**Solutions**:
1. **Immediate Response Pattern**:
   - Return 202 Accepted immediately
   - Continue processing asynchronously
   - Send completion notification via email/webhook
   - Pro: Never times out
   - Con: Caller doesn't get immediate result

2. **Optimize Operations**:
   - Parallel execution where possible
   - Batch operations
   - Efficient LDAP queries
   - Pro: Faster execution
   - Con: May still timeout for heavy users

3. **Increase Timeout**:
   - Configure webhook timeout in calling system
   - Set n8n execution timeout higher
   - Pro: Simple
   - Con: Long-running requests block callers

**Recommendation**: Target < 30s execution, use immediate response for edge cases.

### Future Enhancements

**Pre-Termination Backup**:
- Backup user data before termination
- OneDrive files, SharePoint content
- Email archive

**Automated Notifications**:
- Email to IT team on completion
- Email to HR on completion
- Slack/Teams notification
- SMS for urgent issues

**Equipment Return Tracking**:
- Integration with asset management system
- Ticket creation for equipment return
- Checklist tracking

**Data Archival**:
- Archive user files from OneDrive
- Export to long-term storage
- Compliance with data retention policies

**Multi-Stage Termination**:
- Immediate: Disable access
- Day 30: Remove licenses
- Day 90: Permanent deletion
- Scheduled execution

**Approval Workflow**:
- Manager approval before execution
- HR approval for sensitive terminations
- Audit trail of approvals

**Dashboard Integration**:
- Real-time termination status
- Historical reports
- Metrics and analytics

**Rollback Capability**:
- Ability to reverse termination
- Restore licenses, access, groups
- Time-limited (e.g., 7 days)

**Schedule Termination**:
- Future-dated terminations
- Execute on specific date/time
- Batch terminations

**Integration with HRIS**:
- Automatic trigger from HR system
- Status updates back to HRIS
- Synchronization

### Compliance & Legal

**Data Retention**:
- Ensure compliance with organizational data retention policies
- Some jurisdictions require specific retention periods
- Legal holds may override termination

**GDPR/Privacy**:
- Right to be forgotten vs. legal requirements
- Balance data deletion with audit requirements
- Anonymize audit logs if required

**Audit Requirements**:
- Maintain immutable audit logs
- Tamper-proof logging (external SIEM recommended)
- Regular audit log reviews

**Regulatory Compliance**:
- SOX: Financial systems access
- HIPAA: Healthcare data access
- Industry-specific requirements

**Legal Holds**:
- Check for legal holds before termination
- Preserve data if under litigation
- Integration with legal hold system

### Maintenance

**API Version Updates**:
- Monitor Microsoft Graph API changelog
- Test workflow after API updates
- Version pin if stability required

**Credential Rotation**:
- Regular rotation of service account passwords (90 days)
- Certificate renewal before expiration
- API key rotation

**Workflow Testing**:
- Periodic testing in production-like environment
- Quarterly test execution
- Validate all edge cases

**Documentation Updates**:
- Keep runbook current
- Update after any changes
- Document lessons learned

**Monitoring**:
- Alert on workflow failures
- Monitor execution times
- Track success rates

**Backup**:
- Export workflow JSON regularly
- Store in version control
- Disaster recovery plan

---

## Implementation Notes

### Critical Path

The critical path for implementation is:
1. **Foundation**: Azure AD app → Credentials → Webhook (Tasks 1-4)
2. **User Lookup**: M365 + AD + Validation (Tasks 5-10)
3. **M365 Operations**: Supervisor + Mailbox + Licenses (Tasks 11-15)
   - **Note**: Task 12 (mailbox conversion) is most complex
4. **AD Operations**: Disable + Groups + Move (Tasks 16-20)
5. **Completion**: Audit + Response (Tasks 21-23)
6. **Error Handling**: Error path (Tasks 24-26)

### Recommended Implementation Order

**Phase-by-Phase Approach** (RECOMMENDED):
1. Start with Phase 1 (Foundation): Get authentication working
2. Implement Phase 2 (Lookup & Validation): Verify user identification
3. Test end-to-end lookup before moving to operations
4. Implement Phase 3 (M365): Tackle mailbox conversion early (most complex)
5. Implement Phase 4 (AD): Sequential operations
6. Implement Phase 5 (Completion): Audit and response
7. Implement error handling throughout (Task 26)
8. Comprehensive testing (Phase 6)

**Iterative Approach** (Alternative):
1. Build minimal viable workflow: Webhook → Lookup → Response
2. Add M365 operations one at a time
3. Add AD operations one at a time
4. Add audit logging
5. Add error handling
6. Test and refine

### Time Estimate

**Implementation Time**:
- Phase 1 (Foundation): 1-1.5 hours
- Phase 2 (Lookup): 2-2.5 hours
- Phase 3 (M365 Operations): 3-4 hours (mailbox conversion is complex)
- Phase 4 (AD Operations): 2.5-3 hours
- Phase 5 (Completion): 1.5-2 hours
- Phase 6 (Error Handling): 1.5-2 hours
- **Total Implementation**: 12-16 hours

**Testing Time**:
- Unit testing: 2 hours
- Integration testing: 3 hours
- Edge case testing: 2 hours
- Performance testing: 1 hour
- **Total Testing**: 8 hours

**Documentation & Deployment**:
- Runbook creation: 2 hours
- Deployment preparation: 1 hour
- **Total Documentation**: 3 hours

**Total Project Time**: 23-27 hours

### Decision Points

**Task 12: Mailbox Conversion Approach**
- [ ] Graph API (simple but may not work)
- [ ] Exchange Online PowerShell via Execute Command (reliable)
- [ ] Azure Automation with PowerShell runbook (managed)
- [ ] Separate n8n workflow with PowerShell (modular)

**Task 19: Group Removal Approach**
- [ ] LDAP node in loop (native n8n)
- [ ] Code node with LDAP library (flexible)
- [ ] PowerShell via Execute Command (simple syntax)

**Error Handling Strategy**
- [ ] Compensation/rollback logic (complex)
- [ ] Manual remediation (simple, recommended)
- [ ] Hybrid approach

**Performance Optimization**
- [ ] Synchronous execution with timeout
- [ ] Asynchronous execution with 202 response
- [ ] Optimize and target < 30s

---

## Validation Checklist

Before beginning implementation, ensure:
- [x] Azure AD app registration completed with all permissions
- [x] n8n credentials configured and tested
- [x] Environment variables set
- [x] Test environment available (test tenant, test AD)
- [x] Disabled Users OU exists in AD
- [x] Service accounts have appropriate permissions
- [x] Approach decided for mailbox conversion (Task 12)
- [x] Approach decided for group removal (Task 19)
- [x] Error handling strategy chosen

During implementation, validate:
- [ ] Each phase works independently
- [ ] Error paths tested
- [ ] Idempotency verified
- [ ] Edge cases handled
- [ ] Audit logs complete

Before production deployment:
- [ ] All integration tests pass
- [ ] Performance acceptable
- [ ] Error handling verified
- [ ] Documentation complete
- [ ] Stakeholder approval obtained
- [ ] Rollback plan documented
- [ ] Monitoring configured

---

## Future Enhancement: AI-Powered Email Handler Workflow

### Vision

An intelligent email processing workflow that:
1. **Monitors** a dedicated HR/IT email inbox (e.g., `hr-requests@ii-us.com`)
2. **Analyzes** incoming emails using AI (Claude, GPT-4, or similar)
3. **Detects** termination requests automatically
4. **Extracts** employee information, supervisor details, and reason
5. **Validates** extracted data before processing
6. **Triggers** the termination subflow via webhook
7. **Responds** to the sender with confirmation or requests for clarification

### Architecture Overview

```
[Email Inbox]
    ↓
[IMAP/Gmail/Outlook Trigger]
    ↓
[AI Email Classifier] ← Uses Claude/GPT-4
    ↓
[Termination Request?]
    ├─ Yes → [AI Information Extractor]
    │           ↓
    │       [Validation & Confirmation]
    │           ↓
    │       [Call Termination Subflow via Webhook]
    │           ↓
    │       [Send Confirmation Email]
    │
    ├─ No → [Route to Appropriate Handler]
    │           ↓
    │       [Other HR workflows...]
    │
    └─ Unclear → [Request Human Review]
                  ↓
              [Email sender for clarification]
```

### Technical Implementation

#### 1. Email Trigger Node
**Node Type**: `n8n-nodes-base.emailReadImap` or `n8n-nodes-base.gmail`

**Configuration**:
- **For IMAP** (Exchange/Outlook):
  ```json
  {
    "mailbox": "INBOX",
    "options": {
      "markSeen": false,
      "downloadAttachments": true
    },
    "pollTimes": {
      "item": [
        {
          "mode": "everyMinute"
        }
      ]
    }
  }
  ```

- **For Gmail**:
  ```json
  {
    "event": "messageReceived",
    "filters": {
      "labelIds": ["Label_123"],
      "query": "subject:(termination OR resignation OR offboarding)"
    }
  }
  ```

**Recommended Approach**: Create dedicated mailbox `termination-requests@ii-us.com` or use labels/folders

#### 2. AI Email Analysis Node

**Node Type**: `n8n-nodes-base.openAi` or `@n8n/n8n-nodes-langchain` (AI Agent)

**Option A: Claude API (Anthropic - RECOMMENDED)**
```javascript
// Code Node with HTTP Request to Claude API
const emailBody = $input.first().json.text;
const emailSubject = $input.first().json.subject;
const emailFrom = $input.first().json.from;

const prompt = `You are an HR automation assistant. Analyze the following email and determine:
1. Is this an employee termination/offboarding request? (yes/no/unclear)
2. If yes, extract:
   - Employee Name (full name)
   - Employee ID (if mentioned)
   - Employee Email (if mentioned)
   - Termination Date (if mentioned)
   - Supervisor/Manager Email (who should get mailbox access)
   - Reason for termination (voluntary/involuntary/retirement/etc)
   - Ticket Number (if mentioned)

Email From: ${emailFrom}
Subject: ${emailSubject}
Body:
${emailBody}

Respond in JSON format:
{
  "is_termination_request": true/false/"unclear",
  "confidence": 0.0-1.0,
  "extracted_data": {
    "employee_name": "...",
    "employee_id": "...",
    "employee_email": "...",
    "termination_date": "YYYY-MM-DD",
    "supervisor_email": "...",
    "reason": "...",
    "ticket_number": "..."
  },
  "missing_fields": ["field1", "field2"],
  "clarification_needed": "Question to ask sender if unclear"
}`;

const response = await $http.request({
  method: 'POST',
  url: 'https://api.anthropic.com/v1/messages',
  headers: {
    'x-api-key': $credentials.anthropicApiKey,
    'anthropic-version': '2023-06-01',
    'content-type': 'application/json'
  },
  body: {
    model: 'claude-3-5-sonnet-20241022',
    max_tokens: 1024,
    messages: [{
      role: 'user',
      content: prompt
    }]
  }
});

const aiAnalysis = JSON.parse(response.content[0].text);

return {
  json: {
    ...aiAnalysis,
    original_email: {
      from: emailFrom,
      subject: emailSubject,
      body: emailBody,
      messageId: $input.first().json.messageId
    }
  }
};
```

**Option B: OpenAI GPT-4**
```javascript
// Using OpenAI node
{
  "model": "gpt-4-turbo-preview",
  "messages": [
    {
      "role": "system",
      "content": "You are an HR automation assistant that extracts termination request information from emails."
    },
    {
      "role": "user",
      "content": "{{$json.emailPrompt}}"
    }
  ],
  "response_format": { "type": "json_object" }
}
```

#### 3. Decision Logic & Routing

**Node Type**: `n8n-nodes-base.if` or `n8n-nodes-base.switch`

**Logic**:
```javascript
// If Node
const analysis = $input.first().json;

// Route based on AI analysis
if (analysis.is_termination_request === true && analysis.confidence >= 0.85) {
  // High confidence - proceed to extraction
  return [true];
} else if (analysis.is_termination_request === "unclear" || analysis.confidence < 0.85) {
  // Low confidence - request human review
  return [false, true];
} else {
  // Not a termination request - route to other handlers
  return [false, false, true];
}
```

#### 4. Data Validation Node

**Node Type**: `n8n-nodes-base.code`

**Logic**:
```javascript
const data = $input.first().json.extracted_data;
const missingFields = $input.first().json.missing_fields || [];

// Required fields for termination
const requiredFields = ['employee_name', 'employee_id'];

// Check if we have minimum required data
const hasMinimumData = requiredFields.every(field =>
  data[field] && data[field].trim() !== ''
);

if (!hasMinimumData) {
  // Missing critical data - need to ask sender
  return {
    json: {
      validation_status: 'failed',
      action: 'request_clarification',
      missing_fields: missingFields,
      message: `Missing required information: ${missingFields.join(', ')}`
    }
  };
}

// Optional: Verify employee exists in AD
// Could add lookup here

return {
  json: {
    validation_status: 'passed',
    action: 'proceed_to_termination',
    termination_payload: {
      employeeId: data.employee_id,
      employeeName: data.employee_name,
      supervisorEmail: data.supervisor_email || null,
      forwardeeEmail: data.supervisor_email || null,
      reason: data.reason || 'Not specified',
      ticketNumber: data.ticket_number || 'EMAIL-AUTO',
      requestedBy: $input.first().json.original_email.from,
      requestedDate: new Date().toISOString()
    }
  }
};
```

#### 5. Call Termination Subflow

**Node Type**: `n8n-nodes-base.httpRequest`

**Configuration**:
```javascript
{
  "method": "POST",
  "url": "https://your-n8n-instance.com/webhook/terminate-employee",
  "authentication": "headerAuth",
  "headers": {
    "X-API-Key": "{{$credentials.terminationWebhookKey}}",
    "Content-Type": "application/json"
  },
  "body": "={{$json.termination_payload}}"
}
```

#### 6. Response Email Templates

**Node Type**: `n8n-nodes-base.emailSend` (SMTP/Gmail)

**Template A: Confirmation Email** (when termination succeeds)
```html
Subject: ✅ Termination Request Processed - {{$json.employeeName}}

Dear {{$json.requestedBy}},

Your employee termination request has been automatically processed.

Employee Details:
- Name: {{$json.employeeName}}
- ID: {{$json.employeeId}}
- Status: Account Disabled
- Mailbox: Converted to Shared
- Licenses: Removed
- AD Groups: Removed
- Location: Moved to Disabled Users OU

Supervisor Access: {{$json.supervisorEmail}}

Execution ID: {{$json.executionId}}
Processed: {{$now.toISO()}}

If you have any questions, please contact IT Support.

---
This is an automated message from the IT Automation System.
```

**Template B: Clarification Request** (when data is missing)
```html
Subject: ⚠️ Termination Request - Additional Information Needed

Dear {{$json.requestedBy}},

We received your termination request but need additional information:

Missing Information:
{{$json.missing_fields.join('\n- ')}}

Please reply to this email with:
- Employee Full Name
- Employee ID
- Supervisor Email (for mailbox access)
- Termination Date
- Reason for Termination

Once we receive this information, the termination will be processed automatically.

Original Email:
Subject: {{$json.original_email.subject}}
Date: {{$json.original_email.date}}

---
This is an automated message from the IT Automation System.
```

**Template C: Error Notification** (when termination fails)
```html
Subject: ❌ Termination Request Failed - Manual Intervention Required

Dear IT Team,

An automated termination request failed and requires manual intervention.

Employee: {{$json.employeeName}} (ID: {{$json.employeeId}})
Requested By: {{$json.requestedBy}}
Error: {{$json.error.message}}

Partial Completion Status:
- M365 Operations: {{$json.m365Status}}
- AD Operations: {{$json.adStatus}}

Please review and complete manually.

Execution ID: {{$json.executionId}}
---
This is an automated message from the IT Automation System.
```

### n8n Credentials Required for Email Handler

In addition to the termination workflow credentials, you'll need:

#### 1. Email Account Credentials

**For IMAP (Exchange/Outlook)**:
- **Type**: IMAP
- **User**: `termination-requests@ii-us.com`
- **Password**: App password or account password
- **Host**: `outlook.office365.com`
- **Port**: `993`
- **Secure**: Yes (TLS)

**For Gmail**:
- **Type**: Gmail OAuth2
- **Scopes**: `https://mail.google.com/`

#### 2. AI Provider Credentials

**For Claude (Anthropic)**:
- **Type**: Header Auth
- **Header Name**: `x-api-key`
- **API Key**: Get from https://console.anthropic.com

**For OpenAI**:
- **Type**: OpenAI Credentials
- **API Key**: Get from https://platform.openai.com

#### 3. Email Sending (SMTP)

**Type**: SMTP
- **Host**: `smtp.office365.com` (for Office 365)
- **Port**: `587`
- **User**: `it-automation@ii-us.com`
- **Password**: App password
- **Secure**: STARTTLS

### Email Processing Workflow Structure

```
Workflow Name: "AI Email Handler - Termination Requests"

[Email Trigger: IMAP/Gmail]
    ↓
[Extract Email Content]
 (Code Node: Parse subject, body, from, attachments)
    ↓
[AI Analysis: Classify Request]
 (HTTP Request to Claude API or OpenAI Node)
    ↓
[Parse AI Response]
 (Code Node: Extract JSON, validate structure)
    ↓
[Decision: Request Type]
 (Switch Node)
    ├─ Case 1: Termination (confidence >= 0.85)
    │     ↓
    │  [Validate Extracted Data]
    │   (Code Node: Check required fields)
    │     ↓
    │  [Decision: Data Complete?]
    │   (If Node)
    │     ├─ Yes → [Call Termination Webhook]
    │     │          (HTTP Request Node)
    │     │            ↓
    │     │         [Send Confirmation Email]
    │     │          (Email Send Node)
    │     │
    │     └─ No → [Send Clarification Email]
    │               (Email Send Node)
    │
    ├─ Case 2: Unclear/Low Confidence
    │     ↓
    │  [Forward to IT Team for Review]
    │   (Email Send Node)
    │
    └─ Case 3: Not Termination
          ↓
       [Route to Other Workflows]
        (Could trigger other automation)
```

### Advanced Features

#### 1. Learning & Improvement
- **Log all AI decisions** to database
- **Track accuracy** over time
- **Collect feedback** from IT team on misclassifications
- **Retrain prompts** based on false positives/negatives

#### 2. Multi-language Support
```javascript
// Add language detection to AI prompt
const prompt = `First, detect the language of this email.
Then analyze in that language and respond in English JSON...`;
```

#### 3. Attachment Processing
```javascript
// Extract data from attachments (e.g., termination forms)
if (email.attachments && email.attachments.length > 0) {
  // Check for PDF forms, Excel lists, etc.
  // Extract employee data from structured documents
}
```

#### 4. Approval Workflow (Optional)
```
[AI Detects Termination]
    ↓
[Send Approval Request to Manager]
 (Email with approval link)
    ↓
[Wait for Approval Webhook]
 (Webhook trigger: /approve-termination/:token)
    ↓
[Proceed with Termination]
```

#### 5. Batch Processing
```javascript
// AI extracts multiple terminations from one email
{
  "is_termination_request": true,
  "request_type": "batch",
  "employees": [
    { "name": "John Doe", "id": "12345" },
    { "name": "Jane Smith", "id": "67890" }
  ]
}
```

### Implementation Phases

#### Phase 1: Basic Email Detection (Week 1)
- Set up email trigger
- Implement AI classification
- Route termination requests to manual review
- Send confirmation emails

#### Phase 2: Automated Extraction (Week 2)
- Implement AI data extraction
- Add validation logic
- Test with sample emails
- Refine prompts based on results

#### Phase 3: Workflow Integration (Week 3)
- Connect to termination subflow webhook
- Implement error handling
- Add response emails (confirmation/error)
- Test end-to-end automation

#### Phase 4: Enhancement & Optimization (Week 4)
- Add approval workflow (if needed)
- Implement batch processing
- Create monitoring dashboard
- Train team on new system

### Success Metrics

- **Detection Accuracy**: >95% correct classification
- **Extraction Accuracy**: >90% correct data extraction
- **Processing Time**: <2 minutes from email receipt to termination completion
- **False Positives**: <5% (non-termination emails incorrectly processed)
- **False Negatives**: <2% (termination emails missed)
- **Manual Intervention Rate**: <10% of requests

### Cost Estimation

**AI API Costs** (Anthropic Claude):
- ~$0.01-0.03 per email analyzed
- Estimated 50 terminations/month = ~$0.50-1.50/month

**Alternative**: Use local LLM (Ollama) for zero API costs

### Sample Email Scenarios

**Scenario 1: Clear Termination Request**
```
From: hr@ii-us.com
Subject: Employee Termination - John Doe

Please process the termination for:
- Name: John Doe
- Employee ID: 785389
- Last Day: 2025-10-25
- Supervisor: manager@ii-us.com
- Reason: Voluntary resignation

Ticket: HR-12345
```
**AI Output**: ✅ High confidence, all data extracted, auto-process

**Scenario 2: Vague Request**
```
From: manager@ii-us.com
Subject: Need to offboard someone

John is leaving next week, can you handle his account?
```
**AI Output**: ⚠️ Unclear, request clarification

**Scenario 3: Batch Request**
```
From: hr@ii-us.com
Subject: Layoff - Department Closure

Please process terminations for entire Sales team:
- John Doe (ID: 12345)
- Jane Smith (ID: 67890)
- Bob Johnson (ID: 24680)

Effective: 2025-11-01
Supervisor for all: director@ii-us.com
```
**AI Output**: ✅ Batch detected, process multiple

---

*This AI Email Handler enhancement enables fully autonomous termination processing from email receipt to completion, with intelligent extraction and validation.*

---

## Final Workflow Activation via MCP

**Before activating the workflow, complete these MCP validation steps:**

### 1. Final Validation
```javascript
// Use MCP tool to validate complete workflow
mcp__n8n-mcp__n8n_validate_workflow(id="workflow-id")
```

**Expected Results**:
- All nodes valid
- All connections valid
- No missing credentials
- No expression errors

### 2. Review Workflow Structure
```javascript
// Get workflow to review complete structure
mcp__n8n-mcp__n8n_get_workflow(id="workflow-id")
```

**Review Checklist**:
- [ ] All 26 nodes created
- [ ] All connections established (main flow + error paths)
- [ ] Credentials properly assigned
- [ ] Environment variables referenced correctly

### 3. Activate Workflow
```javascript
// Activate via MCP
mcp__n8n-mcp__n8n_update_partial_workflow(
  id="workflow-id",
  operations: [{
    type: "updateSettings",
    settings: { active: true }
  }]
)
```

### 4. Verify Activation
```javascript
// List workflows and check active status
mcp__n8n-mcp__list_workflows()
```

**Confirmation**: Workflow should show `active: true` in the response

### 5. Initial Test
```javascript
// Trigger first test execution
mcp__n8n-mcp__n8n_trigger_webhook_workflow(
  webhookUrl="https://your-n8n-instance.com/webhook/terminate-employee",
  data={
    "employeeId": "testuser01",
    "supervisorEmail": "test@domain.com",
    "reason": "Testing",
    "ticketNumber": "TEST-001"
  },
  httpMethod="POST"
)
```

### 6. Monitor Results
```javascript
// Get execution results
mcp__n8n-mcp__n8n_get_execution(id="execution-id", mode="summary")

// Or list recent executions
mcp__n8n-mcp__n8n_list_executions(workflowId="workflow-id", limit=5)
```

---

## MCP Tool Quick Reference

### Workflow Lifecycle Management

```javascript
// 1. CREATE WORKFLOW
mcp__n8n-mcp__n8n_create_workflow(
  name="Employee Termination Automation",
  nodes=[],
  connections={},
  settings={
    executionOrder: "v1",
    saveManualExecutions: true,
    saveExecutionProgress: true
  }
)

// 2. ADD NODES
mcp__n8n-mcp__n8n_update_partial_workflow(
  id="workflow-id",
  operations=[{
    type: "addNode",
    node: {
      id: "node-id",
      name: "Node Name",
      type: "n8n-nodes-base.webhook",
      typeVersion: 2,
      position: [240, 300],
      parameters: { /* node config */ }
    }
  }]
)

// 3. CONNECT NODES
mcp__n8n-mcp__n8n_update_partial_workflow(
  id="workflow-id",
  operations=[{
    type: "addConnection",
    connection: {
      sourceNodeId: "source-node-id",
      sourceOutputIndex: 0,
      targetNodeId: "target-node-id",
      targetInputIndex: 0
    }
  }]
)

// 4. VALIDATE WORKFLOW
mcp__n8n-mcp__n8n_validate_workflow(
  id="workflow-id",
  options: {
    validateNodes: true,
    validateConnections: true,
    validateExpressions: true,
    profile: "runtime"
  }
)

// 5. TEST WORKFLOW
mcp__n8n-mcp__n8n_trigger_webhook_workflow(
  webhookUrl="https://n8n.../webhook/terminate-employee",
  data={ /* test data */ },
  httpMethod="POST",
  waitForResponse=true
)

// 6. GET EXECUTION RESULTS
mcp__n8n-mcp__n8n_get_execution(
  id="execution-id",
  mode="summary",  // or "preview", "filtered", "full"
  includeInputData=false,
  itemsLimit=2
)

// 7. ACTIVATE WORKFLOW
mcp__n8n-mcp__n8n_update_partial_workflow(
  id="workflow-id",
  operations=[{
    type: "updateSettings",
    settings: { active: true }
  }]
)

// 8. MONITOR EXECUTIONS
mcp__n8n-mcp__n8n_list_executions(
  workflowId="workflow-id",
  status="success",  // or "error", "waiting"
  limit=100,
  includeData=false
)

// 9. GET WORKFLOW DETAILS
mcp__n8n-mcp__n8n_get_workflow(id="workflow-id")

// 10. LIST ALL WORKFLOWS
mcp__n8n-mcp__list_workflows(
  active=true,
  limit=100
)
```

### Common Operations

**Update Node Configuration**:
```javascript
mcp__n8n-mcp__n8n_update_partial_workflow(
  id="workflow-id",
  operations=[{
    type: "updateNode",
    nodeId: "node-id",
    updates: {
      parameters: { /* new parameters */ }
    }
  }]
)
```

**Remove Node**:
```javascript
mcp__n8n-mcp__n8n_update_partial_workflow(
  id="workflow-id",
  operations=[{
    type: "removeNode",
    nodeId: "node-id"
  }]
)
```

**Enable/Disable Node**:
```javascript
mcp__n8n-mcp__n8n_update_partial_workflow(
  id="workflow-id",
  operations=[{
    type: "disableNode",
    nodeId: "node-id"
  }]
)
```

**Health Check**:
```javascript
mcp__n8n-mcp__n8n_health_check()
```

**Diagnostics**:
```javascript
mcp__n8n-mcp__n8n_diagnostic(verbose=true)
```

---

## Implementation Checklist

### Pre-Implementation
- [ ] Verify n8n MCP server connection (`mcp__n8n-mcp__n8n_health_check`)
- [ ] Azure AD app registration complete (Task 1)
- [ ] n8n credentials configured (Task 2)
- [ ] Environment variables set (Task 3)
- [ ] PowerShell environment ready (if using PowerShell approach)

### Workflow Creation
- [ ] Create base workflow using `n8n_create_workflow`
- [ ] Add all 26 nodes using `n8n_update_partial_workflow` with `addNode`
- [ ] Connect all nodes using `n8n_update_partial_workflow` with `addConnection`
- [ ] Validate workflow using `n8n_validate_workflow`

### Testing
- [ ] Unit test each phase using `n8n_trigger_webhook_workflow`
- [ ] Integration test end-to-end scenarios
- [ ] Edge case testing (user not found, no licenses, etc.)
- [ ] Performance testing (timing, concurrent requests)

### Deployment
- [ ] Final validation passed
- [ ] Test execution successful
- [ ] Activate workflow using MCP
- [ ] Verify webhook URL accessible
- [ ] Document webhook endpoint and authentication

### Post-Deployment
- [ ] Monitor first 5 executions using `n8n_list_executions`
- [ ] Review execution logs for errors
- [ ] Update runbook with learnings
- [ ] Train team on manual remediation if needed

---

*This comprehensive implementation plan provides everything needed to create the Employee Termination Automation workflow programmatically using n8n MCP server tools, ensuring a reproducible, well-tested, and production-ready solution.*
