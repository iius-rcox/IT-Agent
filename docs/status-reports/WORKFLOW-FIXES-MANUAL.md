# Manual Workflow Fixes Guide
# Employee Termination Automation

**Workflow ID**: FzQHthFrHGlkovq0
**Workflow Name**: Employee Termination Automation

## Overview

The n8n workflow is fully built but has 5 validation errors that need to be fixed. This guide provides step-by-step instructions to fix them manually through the n8n UI when the server stabilizes.

**Current Issue**: n8n API is returning 502/503 errors on update operations, preventing automated fixes via MCP.

---

## Validation Errors to Fix

### Error 1 & 2: Incorrect Error Output Connections

**Problem**: Error handler connections are on the wrong output (main[0] instead of main[1])

**Nodes Affected**:
- "Validate Input & Prepare Data"
- "Execute Termination Script"

**How to Fix in n8n UI**:

1. **Open the workflow** in n8n UI
2. **For "Validate Input & Prepare Data" node**:
   - Click the node to select it
   - Look at the connections going to "Respond Error"
   - You'll see "Respond Error" is connected to the MAIN output (output 0)
   - **Delete this connection** (click the connection line, press Delete)
   - Click the small **red dot** on "Validate Input & Prepare Data" (this is the ERROR output, output 1)
   - Drag from the red dot to "Respond Error" node
   - This creates the error connection on the correct output

3. **For "Execute Termination Script" node**:
   - Repeat the same process:
   - Delete connection from main output (green dot) to "Respond Error"
   - Connect from error output (red dot) to "Respond Error"

4. **For "Parse Termination Results" node**:
   - This node doesn't have an error connection yet
   - Click the node settings (gear icon)
   - Under "Settings" → "On Error", select **"Continue (Error Output)"**
   - Save the node
   - Connect the red dot (error output) to "Respond Error"

**Visual Reference**:
```
BEFORE (WRONG):
┌─────────────────────────────┐
│ Validate Input & Prepare    │
│                             │
├─────────────────────────────┤ main[0] (green)
│ ┌─────────────┐             │───────────→ Execute Termination Script
│ │   ❌ WRONG  │             │───────────→ Respond Error (WRONG!)
│ └─────────────┘             │
├─────────────────────────────┤ main[1] (red) - EMPTY
└─────────────────────────────┘

AFTER (CORRECT):
┌─────────────────────────────┐
│ Validate Input & Prepare    │
│                             │
├─────────────────────────────┤ main[0] (green)
│                             │───────────→ Execute Termination Script
│                             │
├─────────────────────────────┤ main[1] (red) - ERROR OUTPUT
│                             │───────────→ Respond Error (CORRECT!)
└─────────────────────────────┘
```

---

### Error 3: Expression Syntax Error in Execute Command

**Problem**: The arguments parameter has invalid nested expression syntax

**Node Affected**: "Execute Termination Script"

**Current (Wrong)**:
```
Command: powershell.exe
Arguments: =-File C:\Scripts\Terminate-Employee.ps1 -EmployeeId {{$json.employeeId}} -SupervisorEmail {{$json.supervisorEmail}}
```

**How to Fix in n8n UI**:

1. Click on **"Execute Termination Script"** node
2. Find the **"Arguments"** field
3. Change from:
   ```
   =-File C:\Scripts\Terminate-Employee.ps1 -EmployeeId {{$json.employeeId}} -SupervisorEmail {{$json.supervisorEmail}}
   ```
4. To (remove the `=` at the beginning):
   ```
   -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId {{$json.employeeId}} -SupervisorEmail {{$json.supervisorEmail}}
   ```
5. **Add spaces around the curly braces** for better expression parsing:
   ```
   -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId {{ $json.employeeId }} -SupervisorEmail {{ $json.supervisorEmail }}
   ```
6. Click **Save**

---

### Error 4, 5, 6: Outdated TypeVersions

**Problem**: Three nodes are using outdated typeVersions

**Nodes Affected**:
- "Webhook Trigger - Termination Request" (v2 → v2.1)
- "Respond Success" (v1 → v1.4)
- "Respond Error" (v1 → v1.4)

**How to Fix in n8n UI**:

Unfortunately, typeVersions cannot be changed directly in the UI. However:

1. **These are warnings, not errors** - The workflow will still function correctly
2. **They'll be updated automatically** when you edit the nodes in the future
3. **Optional**: If you want to update them now:
   - Delete the node
   - Add it back (will use latest version)
   - Reconfigure with same settings
   - Reconnect

**Note**: I recommend leaving these as-is for now. They're cosmetic and don't affect functionality.

---

## Verification Steps

After making the fixes, verify the workflow is correct:

### 1. Visual Check

Your workflow should look like this:

```
┌──────────────────┐
│ Webhook Trigger  │
└────────┬─────────┘
         │ main[0]
         ▼
┌──────────────────────┐
│ Validate Input       │
├──────────────────────┤
│ main[0] ──────────┐  │
│ main[1] (error) ──┼──┼───┐
└──────────────────────┘  │   │
         │                │   │
         ▼                │   │
┌──────────────────────┐  │   │
│ Execute Termination  │  │   │
├──────────────────────┤  │   │
│ main[0] ──────────┐  │  │   │
│ main[1] (error) ──┼──┼──┼───┤
└──────────────────────┘  │  │   │
         │                │  │   │
         ▼                │  │   │
┌──────────────────────┐  │  │   │
│ Parse Results        │  │  │   │
├──────────────────────┤  │  │   │
│ main[0] ──────────┐  │  │  │   │
│ main[1] (error) ──┼──┼──┼──┼───┤
└──────────────────────┘  │  │  │   │
         │                │  │  │   │
         ▼                │  │  │   │
┌──────────────────┐      │  │  │   │
│ Respond Success  │◄─────┘  │  │   │
└──────────────────┘         │  │   │
                             │  │   │
┌──────────────────┐         │  │   │
│ Respond Error    │◄────────┴──┴───┘
└──────────────────┘
```

**Key Points**:
- ✅ Main flow goes through all nodes sequentially
- ✅ Error outputs from Validate, Execute, and Parse all connect to "Respond Error"
- ✅ Success output from Parse connects to "Respond Success"

### 2. Test Execution

After fixes are applied:

1. **Save the workflow**
2. **Click "Execute Workflow"** button (top right)
3. **Provide test input**:
   ```json
   {
     "employeeId": "999999",
     "supervisorEmail": "test@ii-us.com"
   }
   ```
4. **Expected**: Should execute without errors (may fail on PowerShell script if not deployed yet, but workflow structure should work)

### 3. Activate Workflow

Once all fixes are verified:

1. Click the **toggle switch** at the top (changes from gray to green)
2. Workflow status changes to **"Active"**
3. Webhook becomes accessible at: `https://n8n.ii-us.com/webhook/terminate-employee`

---

## Testing the Webhook

Once activated, test with curl:

```bash
curl -X POST https://n8n.ii-us.com/webhook/terminate-employee \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "employeeId": "999999",
    "supervisorEmail": "manager@ii-us.com",
    "reason": "Testing",
    "ticketNumber": "TEST-001"
  }'
```

**Expected Response** (after PowerShell script is deployed):
```json
{
  "workflowId": "FzQHthFrHGlkovq0",
  "executionId": "...",
  "timestamp": "2025-10-28T...",
  "employee": {
    "name": "Test User",
    "id": "999999",
    "upn": "testuser@ii-us.com"
  },
  "operations": {
    "adLookup": {"success": true, "message": "User found: Test User"},
    "m365Lookup": {"success": true, "message": "User found in M365"},
    "licenseRemoval": {"success": true, "licensesRemoved": 2, "message": "Removed 2 licenses"},
    "mailboxConversion": {"success": true, "message": "Mailbox converted to shared"},
    "supervisorAccess": {"success": true, "message": "Granted manager@ii-us.com full access"},
    "adDisable": {"success": true, "message": "Account disabled"},
    "groupRemoval": {"success": true, "groupsRemoved": 5, "message": "Removed from 5 groups"},
    "ouMove": {"success": true, "message": "Moved to OU=Disabled Users,DC=..."}
  },
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

---

## Troubleshooting

### Issue: Can't see error outputs (red dots)

**Solution**:
- Click on the node
- Go to **Settings** tab (gear icon)
- Under **"On Error"**, select **"Continue (Error Output)"**
- This enables the error output connection point

### Issue: Connections won't delete

**Solution**:
- Click the connection line (it should highlight)
- Press **Delete** key or **Backspace**
- Or right-click and select "Delete"

### Issue: Can't drag connections

**Solution**:
- Make sure you're in **Edit mode** (not View mode)
- Click and hold on the connection dot
- Drag to the target node
- Release mouse button

### Issue: Changes won't save

**Solution**:
- Click **Save** button (top right)
- If save fails, n8n API might be down
- Wait a few minutes and try again

---

## Summary of Changes

| Node | Change | Difficulty |
|------|--------|-----------|
| Validate Input & Prepare Data | Move error connection to main[1] | Easy |
| Execute Termination Script | Move error connection to main[1] | Easy |
| Execute Termination Script | Fix arguments (remove `=`) | Easy |
| Parse Termination Results | Add error output & connection | Easy |
| Webhook Trigger | Update typeVersion (optional) | Medium |
| Respond Success | Update typeVersion (optional) | Medium |
| Respond Error | Update typeVersion (optional) | Medium |

**Total Time**: 10-15 minutes

---

## Next Steps After Fixes

1. ✅ **Manual fixes applied** (this document)
2. ⏳ **Deploy PowerShell script** (see `POWERSHELL-DEPLOYMENT-GUIDE.md`)
3. ⏳ **Test workflow** (use test employee ID)
4. ⏳ **Activate workflow** (flip the switch)
5. ⏳ **Test via webhook** (use curl or Postman)
6. ⏳ **Monitor executions** (check n8n execution logs)

---

## Support

If you encounter issues:
1. Check the n8n execution logs (sidebar → Executions)
2. Review `POWERSHELL-DEPLOYMENT-GUIDE.md` for PowerShell issues
3. Check `IMPLEMENTATION-STATUS-UPDATED.md` for overall status

**Workflow should be fully functional once these fixes are applied!** 🎉
