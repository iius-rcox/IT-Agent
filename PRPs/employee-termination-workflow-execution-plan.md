# Execution Plan: Employee Termination Automation Workflow

## Overview

This execution plan implements a fully automated employee termination workflow in n8n using **programmatic workflow creation via the n8n MCP server**. The workflow processes terminations via webhook, handles M365 and Active Directory operations, and provides comprehensive audit logging.

**Approach**: PowerShell-first implementation using Execute Command nodes (based on proven production script)

**MCP Server**: All workflow creation, updates, and management will be done using n8n MCP server tools (`mcp__n8n-mcp__*`)

**Estimated Total Time**: 12-16 hours (implementation) + 8 hours (testing)

---

## n8n MCP Server Workflow

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

**Before starting implementation, verify n8n MCP server is connected:**
```bash
# Use this to check n8n connectivity
mcp__n8n-mcp__n8n_health_check()
```

---

## Prerequisites (User Completes First)

Before AI can create the workflow, the user must:

### 1. Azure AD App Registration ✅
- **App ID**: `73b82823-d860-4bf6-938b-74deabeebab7`
- **Tenant ID**: `953922e6-5370-4a01-a3d5-773a30df726b`
- **Certificate Thumbprint**: `DE0FF14C5EABA90BA328030A59662518A3673009`
- **Permissions Granted**: User.ReadWrite.All, Directory.ReadWrite.All, Group.ReadWrite.All

### 2. n8n Credentials Configured ✅
Configure in n8n UI → Credentials:

**Microsoft Graph OAuth2**:
- Name: `Microsoft Graph - Termination`
- Type: OAuth2 API
- Grant Type: Client Credentials
- Client ID: `73b82823-d860-4bf6-938b-74deabeebab7`
- Token URL: `https://login.microsoftonline.com/953922e6-5370-4a01-a3d5-773a30df726b/oauth2/v2.0/token`
- Scope: `https://graph.microsoft.com/.default`

**LDAP Credentials**:
- Name: `Active Directory - Termination`
- Type: LDAP
- Host: [Your DC hostname]
- Port: 636 (LDAPS)
- Bind DN: [Service account DN]

**Webhook Auth**:
- Name: `Webhook - Termination API`
- Type: Header Auth
- Header Name: `X-API-Key`
- Value: [Generate secure key]

### 3. Environment Variables Set ✅
```bash
AD_BASE_DN=DC=insulationsinc,DC=local
AD_DISABLED_OU=OU=Disabled Users,DC=insulationsinc,DC=local
AZURE_TENANT_ID=953922e6-5370-4a01-a3d5-773a30df726b
AZURE_APP_ID=73b82823-d860-4bf6-938b-74deabeebab7
CERT_THUMBPRINT=DE0FF14C5EABA90BA328030A59662518A3673009
ORGANIZATION_DOMAIN=ii-us.com
```

### 4. PowerShell Environment Ready ✅
- Microsoft.Graph module installed
- ExchangeOnlineManagement module installed
- ActiveDirectory module installed (or RSAT)
- Certificate installed on server running PowerShell
- n8n can execute PowerShell (SSH or local Execute Command node)

---

## Implementation Tasks

### Phase 1: Workflow Foundation (2 hours)

#### Task 1: Create Base Workflow Structure
**Description**: Create the main workflow container with metadata and initial configuration using n8n MCP server

**Implementation**:
Use `mcp__n8n-mcp__n8n_create_workflow` tool:

```javascript
// MCP tool call parameters
{
  name: "Employee Termination Automation",
  nodes: [],
  connections: {},
  settings: {
    executionOrder: "v1",
    saveManualExecutions: true,
    saveExecutionProgress: true,
    errorWorkflow: ""
  }
}
```

**MCP Tool**: `mcp__n8n-mcp__n8n_create_workflow`

**Validation**:
- Workflow created successfully (check return value for workflow ID)
- Workflow appears in n8n UI
- Use `mcp__n8n-mcp__n8n_get_workflow` to verify

**Estimated Time**: 30 minutes

---

#### Task 2: Add Webhook Trigger Node
**Description**: Add webhook endpoint to receive termination requests using n8n MCP server

**Implementation**:
Use `mcp__n8n-mcp__n8n_update_partial_workflow` tool with `addNode` operation:

**Node Configuration**:
```json
{
  "id": "webhook-trigger",
  "name": "Webhook Trigger - Termination Request",
  "type": "n8n-nodes-base.webhook",
  "typeVersion": 2,
  "position": [240, 300],
  "parameters": {
    "httpMethod": "POST",
    "path": "terminate-employee",
    "responseMode": "responseNode",
    "options": {
      "ignoreBots": true,
      "rawBody": true
    }
  },
  "credentials": {
    "httpHeaderAuth": {
      "id": "{{WEBHOOK_CREDENTIAL_ID}}",
      "name": "Webhook - Termination API"
    }
  }
}
```

**MCP Tool**: `mcp__n8n-mcp__n8n_update_partial_workflow`

**Operation**:
```javascript
{
  operations: [
    {
      type: "addNode",
      node: { /* node config above */ }
    }
  ]
}
```

**Expected Input**:
```json
{
  "employeeId": "785389",
  "supervisorEmail": "manager@ii-us.com",
  "reason": "Termination",
  "ticketNumber": "HR-12345"
}
```

**Validation**:
- Test with curl: `curl -X POST https://n8n.../webhook/terminate-employee -H "X-API-Key: ..." -d '{"employeeId":"test"}'`
- Should receive 200 OK (later will return actual data)

**Estimated Time**: 30 minutes

---

#### Task 3: Add Input Validation Node
**Description**: Add input validation node using n8n MCP server to validate webhook payload and prepare data for processing

**MCP Tool**: `mcp__n8n-mcp__n8n_update_partial_workflow` with `addNode` operation

**Node Configuration**:
```json
{
  "name": "Validate Input & Prepare Data",
  "type": "n8n-nodes-base.code",
  "typeVersion": 2,
  "position": [460, 300],
  "parameters": {
    "mode": "runOnceForAllItems",
    "jsCode": "// See code below"
  }
}
```

**JavaScript Code**:
```javascript
const input = $input.first().json;

// Validation
if (!input.employeeId && !input.employeeName) {
  throw new Error('Either employeeId or employeeName is required');
}

// Email validation if provided
if (input.supervisorEmail) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(input.supervisorEmail)) {
    throw new Error('Invalid supervisor email format');
  }
}

// Prepare PowerShell parameters
const psParams = {
  employeeId: input.employeeId || null,
  employeeName: input.employeeName || null,
  supervisorEmail: input.supervisorEmail || null,
  forwardeeEmail: input.forwardeeEmail || input.supervisorEmail || null,
  reason: input.reason || 'Not specified',
  ticketNumber: input.ticketNumber || 'WEBHOOK-AUTO',
  requestedBy: input.requestedBy || 'API',
  requestedDate: new Date().toISOString(),

  // Configuration from environment
  disabledOU: $env.AD_DISABLED_OU,
  tenantId: $env.AZURE_TENANT_ID,
  appId: $env.AZURE_APP_ID,
  certThumbprint: $env.CERT_THUMBPRINT,
  organizationDomain: $env.ORGANIZATION_DOMAIN
};

return [{
  json: psParams
}];
```

**Output Schema**:
```json
{
  "employeeId": "785389",
  "supervisorEmail": "manager@ii-us.com",
  "reason": "Termination",
  "ticketNumber": "HR-12345",
  "requestedDate": "2025-10-23T...",
  "disabledOU": "OU=Disabled Users,DC=...",
  "tenantId": "...",
  "appId": "...",
  "certThumbprint": "...",
  "organizationDomain": "ii-us.com"
}
```

**Validation**:
- Test with valid input → Should pass
- Test with missing employeeId/employeeName → Should throw error
- Test with invalid email → Should throw error

**Estimated Time**: 30 minutes

---

#### Task 4: Add PowerShell Termination Script Node
**Description**: Add Execute Command node using n8n MCP server to execute the production-proven PowerShell script

**MCP Tool**: `mcp__n8n-mcp__n8n_update_partial_workflow` with `addNode` operation

**Node Configuration**:
```json
{
  "name": "Execute Termination Script",
  "type": "n8n-nodes-base.executeCommand",
  "typeVersion": 1,
  "position": [680, 300],
  "parameters": {
    "command": "powershell.exe",
    "arguments": "-File C:\\Scripts\\Terminate-Employee.ps1 -EmployeeId {{$json.employeeId}} -SupervisorEmail {{$json.supervisorEmail}}",
    "options": {
      "cwd": "C:\\Scripts"
    }
  }
}
```

**PowerShell Script** (`C:\Scripts\Terminate-Employee.ps1`):
```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$EmployeeId,

    [Parameter(Mandatory=$false)]
    [string]$SupervisorEmail,

    [Parameter(Mandatory=$false)]
    [string]$Reason = "Not specified",

    [Parameter(Mandatory=$false)]
    [string]$TicketNumber = "NONE"
)

# Configuration (from environment or hardcoded)
$disabledOU = $env:AD_DISABLED_OU
$tenantId = $env:AZURE_TENANT_ID
$appId = $env:AZURE_APP_ID
$certThumbprint = $env:CERT_THUMBPRINT
$organizationDomain = $env:ORGANIZATION_DOMAIN

# Results object
$results = @{
    success = $false
    employeeId = $EmployeeId
    employeeName = $null
    userPrincipalName = $null
    operations = @{
        adLookup = @{ success = $false; message = "" }
        m365Lookup = @{ success = $false; message = "" }
        licenseRemoval = @{ success = $false; licensesRemoved = 0; message = "" }
        mailboxConversion = @{ success = $false; message = "" }
        supervisorAccess = @{ success = $false; message = "" }
        adDisable = @{ success = $false; message = "" }
        groupRemoval = @{ success = $false; groupsRemoved = 0; message = "" }
        ouMove = @{ success = $false; message = "" }
    }
    errors = @()
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
}

try {
    # 1. Connect to Microsoft Graph
    Write-Host "Connecting to Microsoft Graph..."
    Connect-MgGraph -ClientId $appId -TenantId $tenantId -CertificateThumbprint $certThumbprint -NoWelcome

    # 2. Connect to Exchange Online
    Write-Host "Connecting to Exchange Online..."
    Connect-ExchangeOnline -AppId $appId -Organization $organizationDomain -CertificateThumbprint $certThumbprint -ShowBanner:$false

    # 3. Find user in local AD
    Write-Host "Looking up user in Active Directory..."
    $user = Get-ADUser -Filter {employeeID -eq $EmployeeId} -Properties EmployeeID, DistinguishedName, UserPrincipalName, DisplayName, memberOf

    if (-not $user) {
        $results.operations.adLookup.message = "User not found in AD"
        $results.errors += "User with Employee ID $EmployeeId not found in Active Directory"
        throw "User not found in AD"
    }

    $results.operations.adLookup.success = $true
    $results.operations.adLookup.message = "User found: $($user.DisplayName)"
    $results.employeeName = $user.DisplayName
    $results.userPrincipalName = $user.UserPrincipalName
    $upn = $user.UserPrincipalName

    # 4. Find user in Azure AD
    Write-Host "Looking up user in Azure AD..."
    try {
        $graphUser = Get-MgUser -Filter "userPrincipalName eq '$upn'"
        $results.operations.m365Lookup.success = $true
        $results.operations.m365Lookup.message = "User found in M365"
    } catch {
        $results.operations.m365Lookup.message = "User not found in M365: $_"
        $results.errors += "Failed to find user in M365"
    }

    # 5. Remove all licenses (if M365 user found)
    if ($graphUser) {
        Write-Host "Fetching and removing licenses..."
        try {
            $licenseDetails = Get-MgUserLicenseDetail -UserId $graphUser.Id
            $licensesToRemove = @()

            foreach ($license in $licenseDetails) {
                $licensesToRemove += $license.SkuId
            }

            if ($licensesToRemove.Count -gt 0) {
                Set-MgUserLicense -UserId $graphUser.Id -RemoveLicenses $licensesToRemove -AddLicenses @{}
                $results.operations.licenseRemoval.success = $true
                $results.operations.licenseRemoval.licensesRemoved = $licensesToRemove.Count
                $results.operations.licenseRemoval.message = "Removed $($licensesToRemove.Count) licenses"
            } else {
                $results.operations.licenseRemoval.success = $true
                $results.operations.licenseRemoval.message = "No licenses to remove"
            }
        } catch {
            $results.operations.licenseRemoval.message = "Failed to remove licenses: $_"
            $results.errors += "License removal failed"
        }
    }

    # 6. Convert mailbox to shared
    Write-Host "Converting mailbox to shared..."
    try {
        Set-Mailbox -Identity $upn -Type Shared
        $results.operations.mailboxConversion.success = $true
        $results.operations.mailboxConversion.message = "Mailbox converted to shared"
    } catch {
        $results.operations.mailboxConversion.message = "Failed to convert mailbox: $_"
        $results.errors += "Mailbox conversion failed"
    }

    # 7. Grant supervisor access (if provided)
    if ($SupervisorEmail) {
        Write-Host "Granting supervisor access to mailbox..."
        try {
            Add-MailboxPermission -Identity $upn -User $SupervisorEmail -AccessRights FullAccess -InheritanceType All
            $results.operations.supervisorAccess.success = $true
            $results.operations.supervisorAccess.message = "Granted $SupervisorEmail full access"
        } catch {
            $results.operations.supervisorAccess.message = "Failed to grant supervisor access: $_"
            $results.errors += "Supervisor access grant failed"
        }
    } else {
        $results.operations.supervisorAccess.message = "No supervisor email provided, skipped"
    }

    # 8. Disable AD account
    Write-Host "Disabling AD account..."
    try {
        Disable-ADAccount -Identity $user
        $results.operations.adDisable.success = $true
        $results.operations.adDisable.message = "Account disabled"
    } catch {
        $results.operations.adDisable.message = "Failed to disable account: $_"
        $results.errors += "Account disable failed"
    }

    # 9. Remove from all groups
    Write-Host "Removing from all groups..."
    try {
        $groups = $user.memberOf
        $groupsRemoved = 0

        if ($groups) {
            foreach ($groupDN in $groups) {
                try {
                    Remove-ADGroupMember -Identity $groupDN -Members $user.DistinguishedName -Confirm:$false
                    $groupsRemoved++
                } catch {
                    # Continue on error
                }
            }
        }

        $results.operations.groupRemoval.success = $true
        $results.operations.groupRemoval.groupsRemoved = $groupsRemoved
        $results.operations.groupRemoval.message = "Removed from $groupsRemoved groups"
    } catch {
        $results.operations.groupRemoval.message = "Failed to remove from groups: $_"
        $results.errors += "Group removal failed"
    }

    # 10. Move to disabled OU
    Write-Host "Moving to disabled OU..."
    try {
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $disabledOU
        $results.operations.ouMove.success = $true
        $results.operations.ouMove.message = "Moved to $disabledOU"
    } catch {
        $results.operations.ouMove.message = "Failed to move to disabled OU: $_"
        $results.errors += "OU move failed"
    }

    # 11. Sync Azure AD
    Write-Host "Triggering Azure AD sync..."
    try {
        Start-ADSyncSyncCycle -PolicyType Delta
    } catch {
        # Non-critical, continue
    }

    # Success if no critical errors
    if ($results.operations.adDisable.success -and $results.operations.ouMove.success) {
        $results.success = $true
    }

} catch {
    $results.errors += $_.Exception.Message
} finally {
    # Cleanup connections
    try { Disconnect-ExchangeOnline -Confirm:$false } catch {}
    try { Disconnect-MgGraph } catch {}
}

# Output JSON for n8n to parse
$results | ConvertTo-Json -Depth 10
```

**Expected Output**:
```json
{
  "success": true,
  "employeeId": "785389",
  "employeeName": "John Doe",
  "userPrincipalName": "jdoe@ii-us.com",
  "operations": {
    "adLookup": { "success": true, "message": "User found: John Doe" },
    "m365Lookup": { "success": true, "message": "User found in M365" },
    "licenseRemoval": { "success": true, "licensesRemoved": 2, "message": "Removed 2 licenses" },
    "mailboxConversion": { "success": true, "message": "Mailbox converted to shared" },
    "supervisorAccess": { "success": true, "message": "Granted manager@ii-us.com full access" },
    "adDisable": { "success": true, "message": "Account disabled" },
    "groupRemoval": { "success": true, "groupsRemoved": 5, "message": "Removed from 5 groups" },
    "ouMove": { "success": true, "message": "Moved to OU=Disabled Users,DC=..." }
  },
  "errors": [],
  "timestamp": "2025-10-23T15:30:00Z"
}
```

**Validation**:
- Test with test user
- Verify all operations succeeded
- Check M365 admin center and AD for changes

**Estimated Time**: 1 hour (including script creation and testing)

---

#### Task 5: Add Parse PowerShell Results Node
**Description**: Add Code node using n8n MCP server to parse PowerShell JSON output and prepare for response

**MCP Tool**: `mcp__n8n-mcp__n8n_update_partial_workflow` with `addNode` operation

**Node Configuration**:
```json
{
  "name": "Parse Termination Results",
  "type": "n8n-nodes-base.code",
  "typeVersion": 2,
  "position": [900, 300],
  "parameters": {
    "mode": "runOnceForAllItems",
    "jsCode": "// See code below"
  }
}
```

**JavaScript Code**:
```javascript
const input = $input.first().json;

// Parse PowerShell output (may be in stdout)
let psResults;
try {
  // If Execute Command node returns stdout as string
  if (typeof input.stdout === 'string') {
    psResults = JSON.parse(input.stdout);
  } else {
    psResults = input;
  }
} catch (error) {
  throw new Error(`Failed to parse PowerShell output: ${error.message}`);
}

// Create comprehensive audit log
const auditLog = {
  workflowId: $workflow.id,
  executionId: $execution.id,
  timestamp: new Date().toISOString(),

  // Employee details
  employee: {
    name: psResults.employeeName,
    id: psResults.employeeId,
    upn: psResults.userPrincipalName
  },

  // Operations performed
  operations: psResults.operations,

  // Overall success
  success: psResults.success,
  errors: psResults.errors || [],

  // Summary stats
  summary: {
    licensesRemoved: psResults.operations.licenseRemoval?.licensesRemoved || 0,
    groupsRemoved: psResults.operations.groupRemoval?.groupsRemoved || 0,
    partialFailure: psResults.errors.length > 0 && psResults.success,
    totalErrors: psResults.errors.length
  }
};

return [{
  json: auditLog
}];
```

**Output Schema**:
```json
{
  "workflowId": "123",
  "executionId": "456",
  "timestamp": "2025-10-23T...",
  "employee": {
    "name": "John Doe",
    "id": "785389",
    "upn": "jdoe@ii-us.com"
  },
  "operations": { ... },
  "success": true,
  "errors": [],
  "summary": {
    "licensesRemoved": 2,
    "groupsRemoved": 5,
    "partialFailure": false,
    "totalErrors": 0
  }
}
```

**Estimated Time**: 30 minutes

---

#### Task 6: Add Success Response Node
**Description**: Add Respond to Webhook node using n8n MCP server to return success response to webhook caller

**MCP Tool**: `mcp__n8n-mcp__n8n_update_partial_workflow` with `addNode` operation

**Node Configuration**:
```json
{
  "name": "Respond Success",
  "type": "n8n-nodes-base.respondToWebhook",
  "typeVersion": 1,
  "position": [1120, 240],
  "parameters": {
    "options": {
      "responseCode": 200,
      "responseData": "={{$json}}"
    }
  }
}
```

**Expected Response**:
```json
{
  "status": "success",
  "message": "Employee termination completed",
  "employee": {
    "name": "John Doe",
    "id": "785389",
    "upn": "jdoe@ii-us.com"
  },
  "operations": {
    "mailboxConverted": true,
    "licensesRemoved": 2,
    "accountDisabled": true,
    "groupsRemoved": 5,
    "movedToDisabledOU": true
  },
  "executionId": "456",
  "timestamp": "2025-10-23T..."
}
```

**Estimated Time**: 15 minutes

---

#### Task 7: Add Error Response Node & Connect All Nodes
**Description**: Add error handling node using n8n MCP server and connect all nodes to complete the workflow

**MCP Tools**:
- `mcp__n8n-mcp__n8n_update_partial_workflow` with `addNode` operation (for error response node)
- `mcp__n8n-mcp__n8n_update_partial_workflow` with `addConnection` operations (to wire nodes together)

**Error Response Node Configuration**:
```json
{
  "name": "Respond Error",
  "type": "n8n-nodes-base.respondToWebhook",
  "typeVersion": 1,
  "position": [1120, 360],
  "parameters": {
    "options": {
      "responseCode": 500,
      "responseData": "={{$json}}"
    }
  }
}
```

**JavaScript Code** (in preceding Code node):
```javascript
const error = $input.first().json.error || {};
const psResults = $input.first().json || {};

const errorResponse = {
  status: "error",
  message: "Employee termination failed",
  timestamp: new Date().toISOString(),
  executionId: $execution.id,

  error: {
    message: error.message || "Unknown error",
    details: psResults.errors || [],
    step: error.node || "Unknown"
  },

  partialCompletion: {
    operationsCompleted: psResults.operations || {},
    success: psResults.success || false
  }
};

return [{ json: errorResponse }];
```

**Node Connections to Add**:
Use `mcp__n8n-mcp__n8n_update_partial_workflow` with multiple `addConnection` operations:

```javascript
{
  operations: [
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "webhook-trigger",
        sourceOutputIndex: 0,
        targetNodeId: "validate-input",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "validate-input",
        sourceOutputIndex: 0,
        targetNodeId: "execute-termination",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "execute-termination",
        sourceOutputIndex: 0,
        targetNodeId: "parse-results",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "parse-results",
        sourceOutputIndex: 0,
        targetNodeId: "respond-success",
        targetInputIndex: 0
      }
    },
    // Error path connections
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "validate-input",
        sourceOutputIndex: 0,
        targetNodeId: "respond-error",
        targetInputIndex: 0,
        onError: true
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "execute-termination",
        sourceOutputIndex: 0,
        targetNodeId: "respond-error",
        targetInputIndex: 0,
        onError: true
      }
    }
  ]
}
```

**Validation**:
- Use `mcp__n8n-mcp__n8n_validate_workflow` to check for errors
- Verify all nodes are connected properly
- Check that error paths are configured

**Estimated Time**: 45 minutes

---

### Phase 2: Testing & Validation (3 hours)

#### Task 8: Unit Testing
**Description**: Test each component individually using n8n MCP server tools

**MCP Tools for Testing**:
- `mcp__n8n-mcp__n8n_validate_workflow` - Validate workflow structure
- `mcp__n8n-mcp__n8n_trigger_webhook_workflow` - Trigger webhook for testing
- `mcp__n8n-mcp__n8n_get_execution` - Get execution results
- `mcp__n8n-mcp__n8n_list_executions` - List all executions

**Test Cases**:
1. **Webhook validation**
   ```bash
   # Valid request
   curl -X POST https://n8n.../webhook/terminate-employee \
     -H "X-API-Key: your-key" \
     -H "Content-Type: application/json" \
     -d '{"employeeId":"testuser","supervisorEmail":"test@domain.com"}'

   # Invalid request (missing ID)
   curl -X POST https://n8n.../webhook/terminate-employee \
     -H "X-API-Key: your-key" \
     -H "Content-Type: application/json" \
     -d '{"supervisorEmail":"test@domain.com"}'
   # Expected: 400 error
   ```

2. **Input validation**
   - Test with valid employeeId → Should pass
   - Test with valid employeeName → Should pass
   - Test with both → Should use employeeId
   - Test with neither → Should error
   - Test with invalid email → Should error

3. **PowerShell execution**
   - Test with existing test user
   - Verify all operations succeed
   - Check M365 admin center
   - Check Active Directory

4. **Error handling**
   - Test with non-existent user → Should return detailed error
   - Test with invalid credentials → Should return auth error

**Validation Checklist**:
- [ ] Webhook accepts valid requests
- [ ] Webhook rejects invalid requests
- [ ] Input validation works correctly
- [ ] PowerShell script executes successfully
- [ ] All M365 operations complete
- [ ] All AD operations complete
- [ ] Success response returns correct data
- [ ] Error response returns helpful information

**Estimated Time**: 2 hours

---

#### Task 9: Integration Testing
**Description**: Test complete end-to-end workflow using n8n MCP server

**Testing Approach**:
1. Use `mcp__n8n-mcp__n8n_trigger_webhook_workflow` to trigger the workflow
2. Use `mcp__n8n-mcp__n8n_get_execution` to retrieve results (with mode='summary' or mode='full')
3. Verify execution success and data correctness
4. Check execution logs for errors

**Test Scenarios**:

**Scenario 1: Complete Success**
```bash
curl -X POST https://n8n.../webhook/terminate-employee \
  -H "X-API-Key: your-key" \
  -H "Content-Type: application/json" \
  -d '{
    "employeeId": "testuser01",
    "supervisorEmail": "supervisor@ii-us.com",
    "reason": "Testing",
    "ticketNumber": "TEST-001"
  }'
```
**Expected**:
- 200 OK response
- All operations successful
- User disabled in AD
- User in disabled OU
- Mailbox converted to shared
- Licenses removed
- Supervisor has mailbox access

**Scenario 2: User Not Found**
```bash
curl -X POST https://n8n.../webhook/terminate-employee \
  -H "X-API-Key: your-key" \
  -H "Content-Type: application/json" \
  -d '{"employeeId": "nonexistent"}'
```
**Expected**:
- 500 error response
- Detailed error message
- No changes made

**Scenario 3: Partial Failure**
- Simulate M365 connection failure
- Expected: AD operations succeed, M365 operations fail, detailed report

**Validation**:
- [ ] End-to-end workflow completes in < 30 seconds
- [ ] All operations execute in correct order
- [ ] Error handling works for all failure points
- [ ] Audit log contains all necessary information

**Estimated Time**: 1 hour

---

### Phase 3: Enhancement - AI Email Handler (Future) (8 hours)

This phase is documented in detail in the main PRP but is OPTIONAL for initial implementation.

**Summary**: Create a second workflow that monitors an email inbox, uses AI (Claude/GPT-4) to detect termination requests, extracts employee data, and calls this termination workflow via webhook.

**Status**: Documented, not implemented in this execution plan

---

## Success Criteria

### Functional Requirements
- [ ] Accepts employee ID via webhook
- [ ] Validates input data
- [ ] Looks up user in M365 and AD
- [ ] Converts mailbox to shared type
- [ ] Removes all M365 licenses
- [ ] Disables AD account
- [ ] Removes user from all AD groups
- [ ] Moves user to disabled OU
- [ ] Returns detailed audit log
- [ ] Handles errors gracefully

### Non-Functional Requirements
- [ ] Response time < 30 seconds
- [ ] Idempotent (safe to re-run)
- [ ] Comprehensive error messages
- [ ] Secure credential management
- [ ] Audit logging

### Security Requirements
- [ ] API key authentication on webhook
- [ ] No credentials in workflow JSON
- [ ] Certificate-based auth for M365/Exchange
- [ ] LDAPS for AD connections
- [ ] Audit trail for compliance

---

## Files to Create/Modify

### New Files
1. **PowerShell Script**: `C:\Scripts\Terminate-Employee.ps1`
   - Production termination script
   - Handles all M365 and AD operations
   - Returns JSON results

2. **n8n Workflow JSON**: Created via MCP tools
   - Webhook trigger
   - Input validation
   - Execute PowerShell script
   - Parse results
   - Response nodes

### Environment Setup
1. **n8n Credentials**: Configure in UI
2. **Environment Variables**: Set in n8n settings
3. **PowerShell Environment**: Ensure modules installed

---

## Dependencies

### External Services
- Microsoft Graph API v1.0
- Exchange Online PowerShell
- Active Directory (LDAP/LDAPS)
- Azure AD

### PowerShell Modules
- Microsoft.Graph
- ExchangeOnlineManagement
- ActiveDirectory (or RSAT)

### n8n Nodes
- n8n-nodes-base.webhook (v2.1+)
- n8n-nodes-base.code
- n8n-nodes-base.executeCommand
- n8n-nodes-base.respondToWebhook

---

## Risk Mitigation

### Risk: PowerShell Execution Failure
**Mitigation**:
- Test PowerShell script independently first
- Implement comprehensive error handling
- Log all operations
- Return detailed error messages

### Risk: Partial Completion
**Mitigation**:
- Track each operation separately in results
- Return detailed status for each operation
- Document manual remediation steps
- Idempotent design allows re-run

### Risk: Security
**Mitigation**:
- Certificate-based authentication
- Webhook API key
- No credentials in code
- LDAPS for AD
- Audit logging

---

## Rollback Plan

If termination needs to be reversed:

1. **Manually Re-enable Account**:
   ```powershell
   Enable-ADAccount -Identity "CN=User,OU=Disabled Users,DC=..."
   ```

2. **Move Back to Original OU**:
   ```powershell
   Move-ADObject -Identity "CN=User,OU=Disabled Users,DC=..." -TargetPath "OU=Users,DC=..."
   ```

3. **Re-add Licenses** (if within grace period):
   ```powershell
   Set-MgUserLicense -UserId $userId -AddLicenses @{SkuId="..."} -RemoveLicenses @()
   ```

4. **Convert Mailbox Back** (if needed):
   ```powershell
   Set-Mailbox -Identity "user@domain.com" -Type Regular
   ```

**Note**: Shared mailbox conversion should NOT be reversed in most cases. Coordinate with IT team.

---

## Timeline

**Week 1**: Foundation & Core Workflow
- Day 1: Prerequisites verification, PowerShell script creation
- Day 2: n8n workflow creation, webhook setup
- Day 3: Integration and testing
- Day 4: Bug fixes and optimization
- Day 5: Documentation and handoff

**Future Enhancement**: AI Email Handler (Week 2+)

---

## Final Workflow Activation

**Before activating the workflow**:

1. **Final Validation**:
   ```javascript
   // Use MCP tool to validate
   mcp__n8n-mcp__n8n_validate_workflow(id="workflow-id")
   ```

2. **Review Workflow Structure**:
   ```javascript
   // Get workflow to review
   mcp__n8n-mcp__n8n_get_workflow(id="workflow-id")
   ```

3. **Activate Workflow**:
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

4. **Verify Activation**:
   ```javascript
   // List workflows and check active status
   mcp__n8n-mcp__list_workflows()
   ```

---

## Next Steps

1. **Verify Prerequisites**: Ensure all Azure AD, n8n credentials, and PowerShell environment are ready
2. **Check n8n MCP Connection**: Run `mcp__n8n-mcp__n8n_health_check()` to verify connectivity
3. **Create PowerShell Script**: Build and test `Terminate-Employee.ps1` independently on the server
4. **Build n8n Workflow Programmatically**:
   - Use `mcp__n8n-mcp__n8n_create_workflow` to create base workflow
   - Use `mcp__n8n-mcp__n8n_update_partial_workflow` to add all nodes
   - Use `mcp__n8n-mcp__n8n_update_partial_workflow` to connect nodes
   - Use `mcp__n8n-mcp__n8n_validate_workflow` to check for errors
5. **Test Thoroughly**:
   - Use `mcp__n8n-mcp__n8n_trigger_webhook_workflow` for testing
   - Use `mcp__n8n-mcp__n8n_get_execution` to review results
   - Unit tests, integration tests, edge cases
6. **Deploy to Production**:
   - After successful testing, activate workflow using MCP tools
   - Set `active: true` via `n8n_update_partial_workflow`
7. **Monitor**:
   - Use `mcp__n8n-mcp__n8n_list_executions` to watch executions
   - Use `mcp__n8n-mcp__n8n_get_execution` to review detailed results
8. **Document**: Update runbooks with any learnings

---

## MCP Tool Quick Reference

**Workflow Lifecycle**:
```javascript
// Create
mcp__n8n-mcp__n8n_create_workflow(name, nodes, connections)

// Add nodes
mcp__n8n-mcp__n8n_update_partial_workflow(id, operations=[{type:"addNode",...}])

// Connect nodes
mcp__n8n-mcp__n8n_update_partial_workflow(id, operations=[{type:"addConnection",...}])

// Validate
mcp__n8n-mcp__n8n_validate_workflow(id)

// Test
mcp__n8n-mcp__n8n_trigger_webhook_workflow(webhookUrl, data, httpMethod)

// Get results
mcp__n8n-mcp__n8n_get_execution(id, mode="summary")

// Activate
mcp__n8n-mcp__n8n_update_partial_workflow(id, operations=[{type:"updateSettings", settings:{active:true}}])

// Monitor
mcp__n8n-mcp__n8n_list_executions(workflowId, status, limit)
```

---

*This execution plan is ready for implementation with n8n MCP server tools and Archon task tracking. Use `/execute-plan PRPs/employee-termination-workflow-execution-plan.md` to begin.*
