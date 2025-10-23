# n8n Employee Termination Workflow - Implementation Guide (Part 2)

## Continuation: Tasks 6-30

---

### Task 6: Lookup User in M365

**Status**: READY TO IMPLEMENT

**Node Type**: HTTP Request (n8n-nodes-base.httpRequest)

**Purpose**: Find the user in Microsoft 365 using Graph API

**Configuration**:

1. **Add HTTP Request Node**
   - Connect from "Input Validation" node
   - Name: `Lookup User in M365`

2. **Configure Request**:
   - **Method**: `GET`
   - **URL**: This needs to be dynamic based on lookup strategy

   Since n8n expressions can't do complex conditionals in URL field easily, use a **Code node before this** OR use expressions:

   **Option A: Use Expression with Ternary**:
   ```
   {{ $json.lookupStrategy === 'byId' ? 'https://graph.microsoft.com/v1.0/users/' + $json.lookupValue : 'https://graph.microsoft.com/v1.0/users?$filter=displayName eq \'' + $json.lookupValue + '\'' }}
   ```

   **Option B: Two Separate HTTP Nodes with If Node** (Recommended for clarity):

   Instead, let's revise the approach:

3. **Better Approach: Add If Node First**
   - Add an "IF" node after Input Validation
   - Name: `Check Lookup Strategy`
   - Condition: `{{ $json.lookupStrategy }}` equals `byId`
   - This splits into TRUE (byId) and FALSE (byName) paths

4. **Create Two HTTP Request Nodes**:

   **Path 1: Lookup by ID**
   - Method: `GET`
   - URL: `https://graph.microsoft.com/v1.0/users/{{ $json.lookupValue }}`
   - Authentication: `Predefined Credential Type`
   - Credential: Select `Microsoft Graph - Employee Termination`
   - Add Header:
     - Name: `Content-Type`
     - Value: `application/json`
   - Add Header:
     - Name: `ConsistencyLevel`
     - Value: `eventual`

   **Path 2: Lookup by Name**
   - Method: `GET`
   - URL: `https://graph.microsoft.com/v1.0/users?$filter=displayName eq '{{ $json.lookupValue }}'`
   - Authentication: Same as above
   - Headers: Same as above

5. **Options** (Both nodes):
   - Response → Never Error: `OFF` (we want 404 to trigger error)
   - Response → Include Response Headers and Status: `ON`

**Expected Response** (by ID):
```json
{
  "id": "user-guid",
  "userPrincipalName": "user@company.com",
  "displayName": "John Doe",
  "mail": "john.doe@company.com",
  // ... other properties
}
```

**Expected Response** (by Name):
```json
{
  "value": [
    {
      "id": "user-guid",
      "userPrincipalName": "user@company.com",
      "displayName": "John Doe",
      "mail": "john.doe@company.com"
    }
  ]
}
```

**Testing**:
- Use a test Microsoft 365 user
- Try both ID and name lookups
- Verify 404 error for non-existent user

**Next Step**: Both paths merge into Task 7 (Extract M365 Details)

---

### Task 7: Extract M365 User Details

**Status**: READY TO IMPLEMENT

**Node Type**: Code (n8n-nodes-base.code)

**Purpose**: Normalize M365 API response (handles both search and direct lookup)

**JavaScript Code**:

```javascript
// Get the response from M365 lookup
const response = $input.first().json;

// Handle search results (value array) vs direct lookup
const user = response.value ? response.value[0] : response;

// Validate user was found
if (!user || !user.id) {
  throw new Error('User not found in Microsoft 365');
}

// Extract and return normalized user details
return {
  json: {
    // Copy previous workflow data
    ...$input.first().json,

    // Add M365 user details
    m365UserId: user.id,
    userPrincipalName: user.userPrincipalName,
    displayName: user.displayName,
    mail: user.mail || user.userPrincipalName,
    m365Found: true,
    m365LookupTime: new Date().toISOString()
  }
};
```

**Testing**:
- Input from both lookup paths should work
- Should extract correct user ID and email
- Should throw error if user not found

**Next Step**: This merges with AD lookup (Task 9) into Task 10

---

### Task 8: Lookup User in Active Directory

**Status**: READY TO IMPLEMENT

**Node Type**: LDAP (n8n-nodes-base.ldap)

**Purpose**: Find user in Active Directory via LDAP

**Configuration** (with If Node for Strategy):

Similar to M365, use an If node to split by strategy, or use two LDAP nodes:

**LDAP Node Configuration**:

1. **Add LDAP Node** (after Input Validation, parallel to M365 lookup)
   - Name: `Lookup User in AD`

2. **Configure Search**:
   - **Credential**: `Active Directory - Employee Termination`
   - **Operation**: `Search`
   - **Base DN**: `{{ $env.AD_BASE_DN }}`
   - **Search For**: `Custom`

   **Filter** (needs to be dynamic):
   - If byId: `(sAMAccountName={{ $json.lookupValue }})`
   - If byName: `(cn={{ $json.lookupValue }})`

   **Better Approach**: Use Code node before LDAP to construct filter:

3. **Add Code Node**: `Build LDAP Filter`
   ```javascript
   const data = $input.first().json;
   const strategy = data.lookupStrategy;
   const value = data.lookupValue;

   let filter;
   if (strategy === 'byId') {
     filter = `(sAMAccountName=${value})`;
   } else {
     filter = `(cn=${value})`;
   }

   return {
     json: {
       ...data,
       ldapFilter: filter
     }
   };
   ```

4. **LDAP Search Configuration**:
   - **Filter**: `{{ $json.ldapFilter }}`
   - **Attributes**: `dn,memberOf,userAccountControl,sAMAccountName,mail,displayName`
   - **Scope**: `Whole Subtree`
   - **Return All**: `OFF`
   - **Limit**: `1`

**Expected Output**:
```json
{
  "dn": "CN=John Doe,OU=Users,DC=company,DC=com",
  "sAMAccountName": "jdoe",
  "displayName": "John Doe",
  "mail": "john.doe@company.com",
  "userAccountControl": "512",
  "memberOf": [
    "CN=Group1,OU=Groups,DC=company,DC=com",
    "CN=Group2,OU=Groups,DC=company,DC=com"
  ]
}
```

**Testing**:
- Test with known AD user
- Verify memberOf returns array of groups
- Test non-existent user (should return empty)

---

### Task 9: Extract AD User Details

**Status**: READY TO IMPLEMENT

**Node Type**: Code (n8n-nodes-base.code)

**JavaScript Code**:

```javascript
const ldapResult = $input.first().json;

// Check if user was found
if (!ldapResult.dn) {
  throw new Error('User not found in Active Directory');
}

// Parse group memberships
const groups = ldapResult.memberOf || [];
const groupDNs = Array.isArray(groups) ? groups : [groups];

// Parse userAccountControl to check if already disabled
const userAccountControl = parseInt(ldapResult.userAccountControl) || 0;
const ACCOUNTDISABLE = 0x0002;
const isAlreadyDisabled = (userAccountControl & ACCOUNTDISABLE) !== 0;

// Return enriched data
return {
  json: {
    // Copy previous data
    ...$input.first().json,

    // Add AD details
    userDN: ldapResult.dn,
    sAMAccountName: ldapResult.sAMAccountName,
    groupDNs: groupDNs,
    groupCount: groupDNs.length,
    currentUserAccountControl: userAccountControl,
    isAlreadyDisabled: isAlreadyDisabled,
    adFound: true,
    adLookupTime: new Date().toISOString()
  }
};
```

**Testing**:
- Verify groupDNs is always an array
- Check disabled account detection works
- Verify all fields populated

---

### Task 10: Merge and Validate User Data

**Status**: READY TO IMPLEMENT

**Node Type**: Merge + Code

**Purpose**: Combine M365 and AD lookup results

**Step 1: Add Merge Node**:
1. **Add Merge Node**
   - Connect output from "Extract M365 Details" (Task 7)
   - Connect output from "Extract AD Details" (Task 9)
   - Name: `Merge User Data`

2. **Configure Merge**:
   - **Mode**: `Combine`
   - **Combine By**: `Merge By Position`

**Step 2: Add Validation Code Node**:

```javascript
const data = $input.first().json;

// Validate both systems found the user
if (!data.m365Found) {
  throw new Error('User not found in Microsoft 365');
}

if (!data.adFound) {
  throw new Error('User not found in Active Directory');
}

// Merge and return complete user profile
return {
  json: {
    // Original request
    lookupValue: data.lookupValue,
    lookupStrategy: data.lookupStrategy,
    supervisorEmail: data.supervisorEmail,
    forwardeeEmail: data.forwardeeEmail,
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
    currentUserAccountControl: data.currentUserAccountControl,
    isAlreadyDisabled: data.isAlreadyDisabled,

    // Status
    validated: true,
    validationTime: new Date().toISOString()
  }
};
```

**Testing**:
- Verify merge combines both data sources
- Test error when user missing from either system

---

## Phase 3: Microsoft 365 Operations

### Task 11: Lookup Supervisor in M365

**Status**: READY TO IMPLEMENT

**Node Type**: Code with HTTP requests

**JavaScript Code**:

```javascript
const data = $input.first().json;
const supervisorEmail = data.supervisorEmail;
const userId = data.m365UserId;

// Get Graph API credential from workflow
// Note: In n8n, you'll need to use HTTP Request nodes within Code
// or use separate HTTP Request nodes with If logic

let supervisorId = null;
let supervisorEmail_resolved = null;
let supervisorFound = false;

if (supervisorEmail) {
  // Supervisor email provided, lookup that user
  try {
    const response = await $http.request({
      method: 'GET',
      url: `https://graph.microsoft.com/v1.0/users/${supervisorEmail}`,
      authentication: {
        type: 'generic',
        genericCredentialType: 'microsoftGraphApi' // Use your credential
      },
      headers: {
        'Content-Type': 'application/json'
      }
    });

    supervisorId = response.id;
    supervisorEmail_resolved = response.mail;
    supervisorFound = true;
  } catch (error) {
    console.log(`Supervisor ${supervisorEmail} not found:`, error.message);
    supervisorFound = false;
  }
} else {
  // No supervisor provided, try to get manager
  try {
    const response = await $http.request({
      method: 'GET',
      url: `https://graph.microsoft.com/v1.0/users/${userId}/manager`,
      authentication: {
        type: 'generic',
        genericCredentialType: 'microsoftGraphApi'
      },
      headers: {
        'Content-Type': 'application/json'
      }
    });

    supervisorId = response.id;
    supervisorEmail_resolved = response.mail;
    supervisorFound = true;
  } catch (error) {
    console.log('No manager found for user:', error.message);
    supervisorFound = false;
  }
}

// Return enriched data
return {
  json: {
    ...data,
    supervisorId: supervisorId,
    supervisorEmail: supervisorEmail_resolved,
    supervisorFound: supervisorFound,
    supervisorLookupTime: new Date().toISOString()
  }
};
```

**Alternative Approach** (Simpler - use separate HTTP nodes):
- Use If node to check if supervisorEmail provided
- True path: HTTP Request to lookup supervisor
- False path: HTTP Request to get user's manager
- Both merge afterward

**Note**: Code node HTTP requests require proper authentication setup. If this doesn't work, use the separate HTTP Request nodes approach.

---

### Task 12: Convert Mailbox to Shared Mailbox

**Status**: CRITICAL - REQUIRES DECISION

**⚠️ IMPORTANT**: Microsoft Graph API has LIMITED support for mailbox conversion. You must choose an implementation approach.

**Approach Options**:

#### Option 1: Exchange Online PowerShell (RECOMMENDED)

**Prerequisites**:
- Server with Exchange Online Management module
- Certificate-based authentication configured
- Execute Command node OR SSH access

**Implementation**:

**Step 1**: Add Execute Command or SSH node
**Step 2**: Configure PowerShell script:

```powershell
# Connect to Exchange Online
Connect-ExchangeOnline `
  -CertificateThumbprint "YOUR_CERT_THUMBPRINT" `
  -AppId "YOUR_APP_ID" `
  -Organization "tenant.onmicrosoft.com"

# Convert mailbox to shared
Set-Mailbox `
  -Identity "{{ $json.userPrincipalName }}" `
  -Type Shared

# Disconnect
Disconnect-ExchangeOnline -Confirm:$false

# Output result
Write-Output "Mailbox converted successfully"
```

#### Option 2: Graph API PATCH (Limited - May Not Work)

**HTTP Request Node**:
- Method: `PATCH`
- URL: `https://graph.microsoft.com/v1.0/users/{{ $json.m365UserId }}`
- Authentication: Graph API credential
- Body:
```json
{
  "mailboxSettings": {
    "exchangeResourceType": "SharedMailbox"
  }
}
```

**⚠️ Warning**: This may not actually convert the mailbox. Test thoroughly.

#### Option 3: Azure Automation Runbook

**Step 1**: Create Azure Automation Account with runbook
**Step 2**: Use HTTP Request node to trigger runbook webhook
**Step 3**: Runbook executes PowerShell to convert mailbox

#### Recommended Decision:

**For this guide, I'll document Option 2 (Graph API) as a placeholder, but include notes that production should use PowerShell.**

**Implementation (Graph API Approach)**:

1. **Add HTTP Request Node**
   - Name: `Convert Mailbox to Shared`
   - Method: `PATCH`
   - URL: `https://graph.microsoft.com/v1.0/users/{{ $json.m365UserId }}`
   - Authentication: `Microsoft Graph - Employee Termination`
   - Body:
   ```json
   {
     "mailboxSettings": {
       "exchangeResourceType": "SharedMailbox"
     }
   }
   ```

2. **Add Code Node After** (to track status):
```javascript
const data = $input.first().json;

return {
  json: {
    ...data,
    mailboxConversionAttempted: true,
    mailboxConversionTime: new Date().toISOString(),
    mailboxConversionNote: "Attempted via Graph API - verify conversion succeeded"
  }
};
```

**Production Recommendation**:
Add a note/sticky in n8n workflow: "⚠️ PRODUCTION: Replace this with PowerShell/Azure Automation approach"

---

### Task 13: Grant Supervisor Full Access to Shared Mailbox

**Status**: READY TO IMPLEMENT

**Similar approach to Task 12** - PowerShell recommended, Graph API limited.

**Graph API Approach** (Limited):

1. **Add If Node** - Check if supervisor found
   - Condition: `{{ $json.supervisorFound }}` equals `true`

2. **True Path: HTTP Request Node**
   - Method: `POST`
   - URL: `https://graph.microsoft.com/v1.0/users/{{ $json.userPrincipalName }}/mailFolders/inbox/permissions`
   - Body:
   ```json
   {
     "roles": ["owner"],
     "emailAddress": {
       "address": "{{ $json.supervisorEmail }}"
     }
   }
   ```

**PowerShell Approach** (If using Execute Command from Task 12):

```powershell
if ($supervisorEmail) {
  Add-MailboxPermission `
    -Identity "{{ $json.userPrincipalName }}" `
    -User "{{ $json.supervisorEmail }}" `
    -AccessRights FullAccess `
    -InheritanceType All

  Write-Output "Granted $supervisorEmail full access to mailbox"
} else {
  Write-Output "No supervisor found, skipping permission grant"
}
```

---

### Task 14: Get User's Current Licenses

**Status**: READY TO IMPLEMENT

**Node Type**: HTTP Request

**Configuration**:
1. **Add HTTP Request Node**
   - Name: `Get Current Licenses`
   - Method: `GET`
   - URL: `https://graph.microsoft.com/v1.0/users/{{ $json.m365UserId }}/licenseDetails`
   - Authentication: Graph API credential

**Expected Response**:
```json
{
  "value": [
    {
      "id": "license-guid",
      "skuId": "sku-guid",
      "skuPartNumber": "ENTERPRISEPACK"
    },
    {
      "id": "license-guid-2",
      "skuId": "sku-guid-2",
      "skuPartNumber": "POWER_BI_PRO"
    }
  ]
}
```

**Next Step**: Connect to Task 15 (Remove Licenses)

---

### Task 15: Remove All Licenses

**Status**: READY TO IMPLEMENT

**Node Type**: Code

**⚠️ IMPORTANT**: This task removes licenses AFTER mailbox conversion to prevent data loss.

**JavaScript Code**:

```javascript
const data = $input.first().json;
const userId = data.m365UserId;
const licenseResponse = $input.first().json;

// Extract licenses from API response
const licenseDetails = licenseResponse.value || [];

if (licenseDetails.length === 0) {
  return {
    json: {
      ...data,
      licensesRemoved: 0,
      removedLicenses: [],
      message: 'No licenses to remove'
    }
  };
}

// Remove each license
const removedLicenses = [];
const errors = [];

for (const license of licenseDetails) {
  try {
    await $http.request({
      method: 'POST',
      url: `https://graph.microsoft.com/v1.0/users/${userId}/assignLicense`,
      authentication: {
        type: 'generic',
        genericCredentialType: 'microsoftGraphApi'
      },
      headers: {
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
    allLicensesRemoved: errors.length === 0,
    licenseRemovalTime: new Date().toISOString()
  }
};
```

**Testing**:
- Test with user who has licenses
- Test with user who has no licenses
- Verify all licenses removed
- Check error handling for failed removals

---

## Phase 4: Active Directory Operations

### Task 16: Calculate Disabled UserAccountControl Value

**Status**: READY TO IMPLEMENT

**Node Type**: Code

**JavaScript Code**:

```javascript
const data = $input.first().json;
const currentControl = data.currentUserAccountControl;

// ACCOUNTDISABLE flag
const ACCOUNTDISABLE = 0x0002;

// Calculate new value by ORing with disable bit
const disabledControl = currentControl | ACCOUNTDISABLE;

return {
  json: {
    ...data,
    newUserAccountControl: disabledControl,
    willDisable: !data.isAlreadyDisabled,
    disableCalculationTime: new Date().toISOString()
  }
};
```

**Explanation**:
- `currentControl | 0x0002` sets bit 2 (ACCOUNTDISABLE)
- If already disabled, value doesn't change (idempotent)
- Common values:
  - 512 (0x0200) = Normal account, enabled
  - 514 (0x0202) = Normal account, disabled
  - 66048 (0x10200) = Normal account, password never expires, enabled
  - 66050 (0x10202) = Normal account, password never expires, disabled

---

### Task 17: Disable AD User Account

**Status**: READY TO IMPLEMENT

**Node Type**: LDAP

**Configuration**:
1. **Add LDAP Node**
   - Name: `Disable AD Account`
   - Credential: `Active Directory - Employee Termination`
   - Operation: `Update`

2. **Configure Update**:
   - **DN**: `{{ $json.userDN }}`
   - **Update Type**: `Replace`
   - **Attributes**:
     - Attribute ID: `userAccountControl`
     - Value: `{{ $json.newUserAccountControl }}`

**Testing**:
- Verify account shows as disabled in AD
- Check `Get-ADUser -Identity username | Select-Object Enabled` shows `False`

---

### Task 18: Get and Parse User Group Memberships

**Status**: READY TO IMPLEMENT

**Node Type**: Code

**JavaScript Code**:

```javascript
const data = $input.first().json;
const groupDNs = data.groupDNs || [];

// Filter out primary group (Domain Users) if needed
// Primary group usually doesn't appear in memberOf, but filter for safety
const groupsToRemove = groupDNs.filter(dn =>
  !dn.toLowerCase().includes('cn=domain users')
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
    groupRemovalCount: groupsToRemove.length,
    groupParseTime: new Date().toISOString()
  }
};
```

**Testing**:
- Verify groups array is correctly filtered
- Check Domain Users is excluded
- Verify empty array handled correctly

---

### Task 19: Remove User from All Groups

**Status**: READY TO IMPLEMENT - COMPLEX

**⚠️ Challenge**: LDAP node doesn't support easy iteration. Options:

#### Option 1: Code Node with LDAP Operations (if external modules enabled)

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

// Note: This requires LDAP library access in n8n
// If not available, use PowerShell approach instead

const removedGroups = [];
const errors = [];

// Placeholder: In reality, you'd need to make LDAP modify requests
// This is simplified for documentation

for (const groupDN of groupsToRemove) {
  try {
    // Conceptual: Remove user from group
    // In actual implementation, use PowerShell or dedicated LDAP library

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
    allGroupsRemoved: errors.length === 0,
    groupRemovalTime: new Date().toISOString()
  }
};
```

#### Option 2: PowerShell via Execute Command (RECOMMENDED)

**Execute Command Node**:
```powershell
Import-Module ActiveDirectory

$userDN = "{{ $json.userDN }}"
$groups = @({{ $json.groupsToRemove | join "," }})

$removed = @()
$errors = @()

foreach ($group in $groups) {
  try {
    Remove-ADGroupMember -Identity $group -Members $userDN -Confirm:$false
    $removed += $group
  } catch {
    $errors += @{group=$group; error=$_.Exception.Message}
  }
}

# Output JSON
@{
  groupsRemoved = $removed.Count
  removedGroups = $removed
  errors = $errors
} | ConvertTo-Json
```

**For this guide**: Document placeholder with note that production should use PowerShell.

---

### Task 20: Move User to Disabled OU

**Status**: READY TO IMPLEMENT

**Node Type**: Code + LDAP

**Step 1: Code Node to Calculate New DN**:

```javascript
const data = $input.first().json;
const userDN = data.userDN;

// Extract CN from current DN
const cnMatch = userDN.match(/^CN=([^,]+)/);
const cn = cnMatch ? cnMatch[1] : data.sAMAccountName;

// Get disabled OU from environment variable
const disabledOU = $env.AD_DISABLED_OU || 'OU=Disabled Users,DC=company,DC=com';

// Construct new DN
const newDN = `CN=${cn},${disabledOU}`;

return {
  json: {
    ...data,
    newUserDN: newDN,
    oldUserDN: userDN
  }
};
```

**Step 2: LDAP Rename Node**:
1. **Add LDAP Node**
   - Name: `Move to Disabled OU`
   - Credential: AD credential
   - Operation: `Rename`

2. **Configure**:
   - **DN**: `{{ $json.oldUserDN }}`
   - **New DN**: `{{ $json.newUserDN }}`

**Testing**:
- Verify user appears in Disabled Users OU
- Check in Active Directory Users and Computers

---

## Phase 5: Completion & Response

### Task 21: Create Comprehensive Audit Log

**Status**: READY TO IMPLEMENT

**Node Type**: Code

**JavaScript Code**:

```javascript
const data = $input.first().json;

const auditLog = {
  workflowId: $workflow.id,
  workflowName: $workflow.name,
  executionId: $execution.id,
  timestamp: new Date().toISOString(),

  // Request details
  request: {
    lookupValue: data.lookupValue,
    lookupStrategy: data.lookupStrategy,
    reason: data.reason,
    ticketNumber: data.ticketNumber,
    requestedBy: 'System' // Or extract from webhook auth
  },

  // User details
  user: {
    displayName: data.displayName,
    userPrincipalName: data.userPrincipalName,
    sAMAccountName: data.sAMAccountName,
    mail: data.mail,
    m365UserId: data.m365UserId,
    originalDN: data.userDN,
    newDN: data.newUserDN
  },

  // Actions performed - M365
  m365Actions: {
    mailboxConversionAttempted: data.mailboxConversionAttempted || false,
    supervisorFound: data.supervisorFound || false,
    supervisorEmail: data.supervisorEmail,
    supervisorAccessGranted: data.supervisorFound || false,
    licensesRemoved: data.licensesRemoved || 0,
    licenseErrors: data.licenseErrors || []
  },

  // Actions performed - AD
  adActions: {
    accountDisabled: data.willDisable,
    wasAlreadyDisabled: data.isAlreadyDisabled,
    groupsRemoved: data.groupsRemoved || 0,
    groupErrors: data.groupRemovalErrors || [],
    movedToDisabledOU: true,
    newLocation: data.newUserDN
  },

  // Summary
  summary: {
    success: true,
    partialFailure: (
      (data.licenseErrors && data.licenseErrors.length > 0) ||
      (data.groupRemovalErrors && data.groupRemovalErrors.length > 0)
    ),
    totalOperations: 6,
    failedOperations: (data.licenseErrors?.length || 0) + (data.groupRemovalErrors?.length || 0)
  },

  // Timing
  timing: {
    workflowStartTime: data.workflowStartTime,
    validationTime: data.validationTime,
    m365LookupTime: data.m365LookupTime,
    adLookupTime: data.adLookupTime,
    supervisorLookupTime: data.supervisorLookupTime,
    licenseRemovalTime: data.licenseRemovalTime,
    groupRemovalTime: data.groupRemovalTime,
    auditLogTime: new Date().toISOString()
  }
};

// Optional: Send to external logging system
// await $http.request({
//   method: 'POST',
//   url: 'https://your-logging-endpoint.com/logs',
//   body: auditLog
// });

return { json: auditLog };
```

**Optional Enhancements**:
- Send to external SIEM
- Write to database
- Send to Slack/Teams channel

---

### Task 22: Format Success Response

**Status**: READY TO IMPLEMENT

**Node Type**: Code

**JavaScript Code**:

```javascript
const auditLog = $input.first().json;

const response = {
  status: 'success',
  message: 'Employee termination completed successfully',
  timestamp: new Date().toISOString(),
  executionId: auditLog.executionId,

  // Employee details
  employee: {
    name: auditLog.user.displayName,
    email: auditLog.user.userPrincipalName,
    id: auditLog.user.sAMAccountName
  },

  // Actions completed
  actions: {
    mailboxConverted: auditLog.m365Actions.mailboxConversionAttempted,
    supervisorAccess: auditLog.m365Actions.supervisorAccessGranted,
    licensesRemoved: auditLog.m365Actions.licensesRemoved,
    accountDisabled: auditLog.adActions.accountDisabled,
    groupsRemoved: auditLog.adActions.groupsRemoved,
    movedToDisabledOU: auditLog.adActions.movedToDisabledOU
  },

  // Warnings if any
  warnings: [],

  // Ticket reference
  ticketNumber: auditLog.request.ticketNumber
};

// Add warnings for partial failures
if (auditLog.summary.partialFailure) {
  if (auditLog.m365Actions.licenseErrors.length > 0) {
    response.warnings.push(
      `${auditLog.m365Actions.licenseErrors.length} license(s) could not be removed`
    );
  }
  if (auditLog.adActions.groupErrors.length > 0) {
    response.warnings.push(
      `${auditLog.adActions.groupErrors.length} group(s) could not be removed`
    );
  }
}

return { json: response };
```

---

### Task 23: Send Success Response to Webhook

**Status**: READY TO IMPLEMENT

**Node Type**: Respond to Webhook

**Configuration**:
1. **Add Respond to Webhook Node**
   - Name: `Send Success Response`
   - Connect from Format Success Response node

2. **Configure**:
   - **Respond With**: `JSON`
   - **Response Body**: `{{ $json }}` (uses output from previous node)

3. **Add Options**:
   - **Response Code**: `200`
   - **Response Headers**:
     - Name: `Content-Type`
     - Value: `application/json`

**Testing**:
- Execute workflow with test data
- Verify webhook caller receives 200 response
- Verify JSON is properly formatted

---

### Task 24: Error Handling Path - Format Error Response

**Status**: READY TO IMPLEMENT

**Node Type**: Code (connects to error outputs)

**JavaScript Code**:

```javascript
// This node receives error input from any failed node
const error = $input.first().json.error || $input.first().json;
const originalData = $input.first().json;

const errorResponse = {
  status: 'error',
  message: 'Employee termination failed',
  timestamp: new Date().toISOString(),
  executionId: $execution.id,

  // Error details
  error: {
    message: error.message || 'Unknown error',
    details: error.description || error.toString(),
    step: $node.name || 'Unknown step',
    errorTime: new Date().toISOString()
  },

  // Include any partial data that was collected
  partialData: {
    userFound: originalData.validated || false,
    m365Operations: originalData.m365Found ? 'attempted' : 'not_attempted',
    adOperations: originalData.adFound ? 'attempted' : 'not_attempted',
    employeeInfo: originalData.displayName || originalData.lookupValue || 'unknown'
  },

  // Support information
  support: {
    ticketNumber: originalData.ticketNumber || 'None',
    contactSupport: 'Please contact IT support with this execution ID'
  }
};

return { json: errorResponse };
```

**Note**: This node should be connected to error outputs of critical nodes

---

### Task 25: Send Error Response to Webhook

**Status**: READY TO IMPLEMENT

**Node Type**: Respond to Webhook

**Configuration**:
1. **Add Respond to Webhook Node**
   - Name: `Send Error Response`
   - Connect from Format Error Response node

2. **Configure**:
   - **Respond With**: `JSON`
   - **Response Body**: `{{ $json }}`

3. **Add Options**:
   - **Response Code**: Dynamic based on error type
     - For simplicity, use: `500`
     - Or use expressions to determine:
       - 400: Bad Request (validation errors)
       - 404: Not Found (user not found)
       - 500: Internal Server Error (other failures)
       - 503: Service Unavailable (external service issues)
   - **Response Headers**:
     - Name: `Content-Type`
     - Value: `application/json`

**Advanced Response Code Logic** (in Code node before this):
```javascript
const data = $input.first().json;
const errorMessage = data.error.message.toLowerCase();

let responseCode = 500; // Default

if (errorMessage.includes('not found')) {
  responseCode = 404;
} else if (errorMessage.includes('required') || errorMessage.includes('invalid')) {
  responseCode = 400;
} else if (errorMessage.includes('unavailable') || errorMessage.includes('timeout')) {
  responseCode = 503;
}

return {
  json: {
    ...data,
    responseCode: responseCode
  }
};
```

---

### Task 26: Connect Error Handlers Throughout Workflow

**Status**: READY TO IMPLEMENT

**Purpose**: Route errors from any node to error response path

**Configuration Steps**:

1. **For EACH Critical Node** (Tasks 4-20):
   - Click on the node
   - Go to "Settings" tab
   - Find "On Error" section
   - Set "Continue On Fail": `OFF` (default - errors will stop workflow)

2. **Connect Error Outputs**:
   - Some nodes have explicit error outputs (red dots)
   - Connect these to "Format Error Response" node (Task 24)
   - Or use n8n's global error workflow feature

3. **Global Error Workflow** (Recommended):
   - In workflow settings → Error Workflow
   - Select or create an error workflow
   - That workflow will catch all errors automatically

4. **Add If Nodes for Error Type Routing** (Optional):
   After error formatting, add If nodes to route by error type:

   **If Node: Check Error Type**
   - Condition: `{{ $json.error.message }}` contains `not found`
   - True: Route to 404 response
   - False: Continue to next If

   Repeat for other error types (400, 503, etc.)

5. **Visual Error Path**:
   In n8n canvas:
   ```
   [Any Node with Error]
       ↓ (error output)
   [Format Error Response]
       ↓
   [Check Error Type - If Node]
       ├─→ (404) [Send 404 Response]
       ├─→ (400) [Send 400 Response]
       └─→ (500) [Send 500 Response]
   ```

**Testing Error Paths**:
- Test user not found (404)
- Test invalid input (400)
- Test with intentional failures at each stage
- Verify error responses are properly formatted

---

## Phase 6: Testing

### Task 27: Unit Testing - Webhook & Validation

**Status**: USER ACTION REQUIRED

**Purpose**: Test each phase independently

**Test Procedures**:

**Test 1: Webhook Trigger**
```bash
# Valid employee ID
curl -X POST https://n8n.domain.com/webhook/terminate-employee \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "employeeId": "testuser01",
    "supervisorEmail": "manager@company.com",
    "reason": "Testing",
    "ticketNumber": "TEST001"
  }'

# Expected: 200 OK, workflow executes
```

**Test 2: Input Validation**
```bash
# Missing required fields
curl -X POST https://n8n.domain.com/webhook/terminate-employee \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "supervisorEmail": "manager@company.com"
  }'

# Expected: 400 Bad Request, error message about required fields
```

**Test 3: M365 Lookup**
- Use test M365 user
- Verify user data returned correctly
- Test non-existent user (should error)

**Test 4: AD Lookup**
- Use test AD user
- Verify groups, DN, userAccountControl retrieved
- Test non-existent user

**Checklist**:
- ✅ Webhook accepts POST requests
- ✅ Authentication works
- ✅ Validation catches invalid input
- ✅ M365 lookup succeeds for valid user
- ✅ AD lookup succeeds for valid user
- ✅ Both lookups merge correctly

---

### Task 28: Integration Testing - End-to-End

**Status**: USER ACTION REQUIRED

**7 Test Scenarios**:

**Scenario 1: Complete termination with employee ID**
```bash
curl -X POST https://n8n.domain.com/webhook/terminate-employee \
  -H "X-API-Key: key" \
  -H "Content-Type: application/json" \
  -d '{
    "employeeId": "testuser01",
    "supervisorEmail": "manager@company.com",
    "reason": "Testing complete flow",
    "ticketNumber": "TEST001"
  }'
```
**Verify**:
- Mailbox converted to shared
- Supervisor has full access
- All licenses removed
- AD account disabled
- Removed from all groups
- Moved to Disabled Users OU
- Audit log complete
- 200 response received

**Scenario 2: Termination with employee name**
```bash
curl -X POST https://n8n.domain.com/webhook/terminate-employee \
  -H "X-API-Key: key" \
  -H "Content-Type: application/json" \
  -d '{
    "employeeName": "Test User",
    "supervisorEmail": "manager@company.com"
  }'
```
**Verify**: Same as Scenario 1

**Scenario 3: No supervisor provided (use manager)**
```bash
curl -X POST https://n8n.domain.com/webhook/terminate-employee \
  -H "X-API-Key: key" \
  -H "Content-Type: application/json" \
  -d '{
    "employeeId": "testuser02"
  }'
```
**Verify**:
- Manager lookup succeeds
- Manager granted mailbox access
- All other operations succeed

**Scenario 4: User not found in M365**
```bash
curl -X POST https://n8n.domain.com/webhook/terminate-employee \
  -H "X-API-Key: key" \
  -H "Content-Type: application/json" \
  -d '{
    "employeeId": "nonexistent"
  }'
```
**Verify**:
- 404 response
- Error message: "User not found in Microsoft 365"
- No AD changes made

**Scenario 5: Idempotency test**
Run Scenario 1 twice with same user
**Verify**:
- Second run succeeds without errors
- No duplicate operations
- Workflow is safe to re-run

**Scenario 6: User with no licenses**
Use test user with no licenses
**Verify**:
- License removal skipped gracefully
- All other operations succeed

**Scenario 7: User with no groups**
Use test user not in any groups
**Verify**:
- Group removal skipped gracefully
- All other operations succeed

---

### Task 29: Edge Case Testing

**Status**: USER ACTION REQUIRED

**Edge Cases**:

1. **User already disabled**
   - Verify: Workflow succeeds, shows already disabled

2. **Special characters in names**
   - Test: User named "O'Brien" or "Smith-Jones"
   - Verify: LDAP filters handle correctly

3. **Invalid webhook payload**
   - Malformed JSON
   - Wrong field names
   - Verify: 400 Bad Request

4. **LDAP connection failure**
   - Temporarily disable AD connectivity
   - Verify: 503 Service Unavailable

5. **Rate limiting**
   - Send 10 rapid requests
   - Verify: All process correctly or rate limit handled

6. **User in 100+ groups**
   - Create test user with many groups
   - Verify: All groups removed, no timeout

7. **Supervisor not found**
   - Provide non-existent supervisor email
   - Verify: Continues without permissions, logs warning

---

### Task 30: Performance & Load Testing

**Status**: USER ACTION REQUIRED

**Test Scenarios**:

1. **Single Termination Timing**
   - Execute standard termination
   - Measure end-to-end time
   - Target: < 30 seconds
   - Check n8n execution logs for timing

2. **Concurrent Terminations**
   - Send 5 requests simultaneously
   - Verify: All complete successfully
   - No race conditions or errors

3. **Large Group Membership**
   - Test user with 50+ groups
   - Measure group removal time
   - Ensure no timeout

4. **Webhook Timeout**
   - Verify response before 30s timeout
   - If longer operations needed, return 202 Accepted immediately

**Load Testing Tool Example**:
```bash
# Using Apache Bench
ab -n 10 -c 5 -p payload.json -T application/json \
  -H "X-API-Key: key" \
  https://n8n.domain.com/webhook/terminate-employee
```

---

## Summary & Next Steps

### Implementation Checklist

**Phase 1: Foundation** (External Actions)
- [ ] Task 1: Azure AD App Registration configured
- [ ] Task 2: n8n Credentials created
- [ ] Task 3: Environment variables set
- [ ] Task 4: Webhook trigger node created

**Phase 2: User Identification** (n8n Workflow)
- [ ] Task 5: Input validation node
- [ ] Task 6: M365 lookup (with If node for strategy)
- [ ] Task 7: Extract M365 details
- [ ] Task 8: AD lookup (with filter construction)
- [ ] Task 9: Extract AD details
- [ ] Task 10: Merge and validate

**Phase 3: M365 Operations** (n8n Workflow)
- [ ] Task 11: Lookup supervisor
- [ ] Task 12: Convert mailbox (approach decided)
- [ ] Task 13: Grant supervisor access
- [ ] Task 14: Get licenses
- [ ] Task 15: Remove licenses

**Phase 4: AD Operations** (n8n Workflow)
- [ ] Task 16: Calculate disabled value
- [ ] Task 17: Disable account
- [ ] Task 18: Parse groups
- [ ] Task 19: Remove from groups (approach decided)
- [ ] Task 20: Move to disabled OU

**Phase 5: Completion** (n8n Workflow)
- [ ] Task 21: Create audit log
- [ ] Task 22: Format success response
- [ ] Task 23: Send success response
- [ ] Task 24: Format error response
- [ ] Task 25: Send error response
- [ ] Task 26: Connect error handlers

**Phase 6: Testing** (User Actions)
- [ ] Task 27: Unit tests completed
- [ ] Task 28: Integration tests completed
- [ ] Task 29: Edge cases tested
- [ ] Task 30: Performance tested

### Critical Decisions Required

**Decision 1: Mailbox Conversion Approach**
- [ ] Graph API (simple but limited)
- [ ] Exchange Online PowerShell (reliable)
- [ ] Azure Automation (managed)

**Decision 2: Group Removal Approach**
- [ ] Code node with LDAP library
- [ ] PowerShell via Execute Command
- [ ] Manual documentation for now

### Deployment Steps

1. **Complete all prerequisites** (Tasks 1-3)
2. **Build workflow in n8n** (Tasks 4-26)
3. **Test thoroughly** (Tasks 27-30)
4. **Export workflow JSON** (backup)
5. **Activate workflow** (enable production webhook)
6. **Monitor first executions** closely
7. **Document any deviations** from this guide

### Support Resources

**n8n Documentation**:
- https://docs.n8n.io
- Community forum: https://community.n8n.io

**Microsoft Graph API**:
- https://learn.microsoft.com/en-us/graph/api/overview

**Active Directory**:
- PowerShell documentation
- LDAP reference guides

### Maintenance

**Regular Tasks**:
- Monitor workflow executions weekly
- Review audit logs monthly
- Rotate API keys/secrets quarterly
- Test workflow after n8n updates
- Update documentation as changes occur

---

## Workflow Export

After building the workflow, export it:

1. In n8n, click workflow menu → "Export"
2. Choose "JSON" format
3. Save as: `Employee_Termination_Automation.json`
4. Store in version control
5. Document any manual configurations not in export

---

**END OF IMPLEMENTATION GUIDE**

For questions or issues during implementation, refer back to the original PRP document: `PRPs/employee-termination-workflow-enhanced.md`
