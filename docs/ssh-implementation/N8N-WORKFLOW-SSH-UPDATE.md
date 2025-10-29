# n8n Workflow Update Guide: SSH Execution

**Purpose**: Update employee termination workflow to execute PowerShell via SSH instead of local Execute Command.

**Prerequisites**:
- SSH configured on DC ([SSH-CONFIGURATION.md](SSH-CONFIGURATION.md))
- SSH credentials configured in n8n ([N8N-SSH-CREDENTIALS-GUIDE.md](N8N-SSH-CREDENTIALS-GUIDE.md))
- PowerShell script deployed to DC ([PS-SCRIPT-DC-DEPLOYMENT.md](PS-SCRIPT-DC-DEPLOYMENT.md))

**Estimated Time**: 15 minutes

---

## Overview

The employee termination workflow currently uses the **Execute Command** node to run PowerShell locally. Since n8n runs in a Linux container, we need to change it to use the **SSH** node to execute PowerShell remotely on the Windows Domain Controller.

### Changes Required

| Component | Before (Execute Command) | After (SSH) |
|-----------|-------------------------|-------------|
| **Node Type** | `n8n-nodes-base.executeCommand` | `n8n-nodes-base.ssh` |
| **Execution Location** | Local n8n container (Linux) | Remote DC via SSH (Windows) |
| **Credentials** | None (local execution) | SSH credentials |
| **Command Syntax** | Direct PowerShell path | `powershell.exe -File C:\Scripts\...` |
| **File Path** | Local path | DC path (`C:\Scripts\...`) |

---

## Option 1: Update via n8n UI (Recommended for Manual Changes)

### Step 1: Export Existing Workflow (Backup)

1. **Open n8n**: Navigate to your n8n instance
2. **Find Workflow**: Locate "Employee Termination" or similar workflow
3. **Export**:
   - Click workflow menu (three dots)
   - Click **"Download"** or **"Export"**
   - Save JSON file as backup

### Step 2: Locate Execute Command Node

1. **Open Workflow**: Click on the employee termination workflow
2. **Find Node**: Look for node named "Execute Termination Script" or similar
   - Node type: **Execute Command**
   - Icon: Terminal/command prompt icon
3. **Review Current Configuration**:
   - Command: `powershell.exe` or `C:\Scripts\Terminate-Employee.ps1`
   - Parameters: Employee ID, Supervisor Email, etc.

### Step 3: Replace with SSH Node

#### 3.1: Delete Old Node (Optional) or Disable It

**Option A - Disable** (safer, allows rollback):
1. Click on Execute Command node
2. Click settings (gear icon)
3. Check **"Disabled"** checkbox
4. Node will be skipped during execution

**Option B - Delete** (cleaner):
1. Click on Execute Command node
2. Press **Delete** key or click delete button

#### 3.2: Add SSH Node

1. Click **"+"** where Execute Command node was (or anywhere in workflow)
2. Search for **"SSH"**
3. Click **"SSH"** to add node
4. Rename node to: `Execute Termination Script via SSH`

#### 3.3: Configure SSH Node

**Credentials Section**:
- **Credentials**: Select `DC-PowerShell-Automation` (from dropdown)

**Command Section**:
```
powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId {{ $json.employeeId }} -SupervisorEmail {{ $json.supervisorEmail }} -Reason {{ $json.reason }} -TicketNumber {{ $json.ticketNumber }}
```

**Options Section** (expand if available):
- **Working Directory**: Leave empty (will use default)
- **Timeout**: `300000` (5 minutes in milliseconds) - optional

**Full Configuration**:
```json
{
  "credentials": {
    "ssh": {
      "id": "CREDENTIAL_ID",
      "name": "DC-PowerShell-Automation"
    }
  },
  "parameters": {
    "command": "=powershell.exe -File C:\\Scripts\\Terminate-Employee.ps1 -EmployeeId {{ $json.employeeId }} -SupervisorEmail {{ $json.supervisorEmail }} -Reason {{ $json.reason }} -TicketNumber {{ $json.ticketNumber }}"
  }
}
```

**Note**: Use double backslashes `\\` in file path if entering directly.

#### 3.4: Reconnect Nodes

If you deleted the old node, reconnect:
1. **Connect Input**: Drag from previous node (usually validation/code node) to SSH node
2. **Connect Output**: Drag from SSH node to next node (usually JSON parser/response node)

### Step 4: Update JSON Parser Node (if exists)

The SSH node returns output in a different format than Execute Command:

**SSH Output Structure**:
```json
{
  "stdout": "{...JSON from PowerShell script...}",
  "stderr": "",
  "exitCode": 0
}
```

**Update Parser Node**:
Find the node that processes the PowerShell output and update it:

**Before** (Execute Command):
```javascript
// Direct access to output
const result = $input.item.json;
return result;
```

**After** (SSH):
```javascript
// Parse stdout to get JSON
const sshOutput = $input.item.json;
const stdout = sshOutput.stdout || "";

// Parse the JSON from stdout
try {
  const result = JSON.parse(stdout);
  return result;
} catch (error) {
  return {
    success: false,
    error: "Failed to parse PowerShell output",
    rawOutput: stdout
  };
}
```

**Node Name**: Usually "Parse Results" or "Process Output"

### Step 5: Save and Test

1. **Save Workflow**: Click **"Save"** button (top-right)
2. **Execute Test**: Click **"Execute Workflow"** button
3. **Review Output**: Check execution results

**Expected**:
- SSH node shows successful execution
- stdout contains JSON output
- Next nodes process the results correctly

---

## Option 2: Update via n8n MCP Tools (Programmatic)

For programmatic updates using the n8n MCP server:

### Step 1: Get Current Workflow

```javascript
// List workflows to find ID
const workflows = await mcp__n8n-mcp__n8n_list_workflows();

// Get specific workflow
const workflow = await mcp__n8n-mcp__n8n_get_workflow({
  id: "WORKFLOW_ID"
});
```

### Step 2: Find Execute Command Node

```javascript
// Find the Execute Command node
const execCmdNode = workflow.nodes.find(
  node => node.type === "n8n-nodes-base.executeCommand"
);

console.log("Found node:", execCmdNode.id, execCmdNode.name);
```

### Step 3: Replace with SSH Node

```javascript
// Remove Execute Command node
await mcp__n8n-mcp__n8n_update_partial_workflow({
  id: "WORKFLOW_ID",
  operations: [
    {
      type: "removeNode",
      nodeId: execCmdNode.id
    }
  ]
});

// Add SSH node
await mcp__n8n-mcp__n8n_update_partial_workflow({
  id: "WORKFLOW_ID",
  operations: [
    {
      type: "addNode",
      node: {
        id: "ssh_execute_termination",
        name: "Execute Termination via SSH",
        type: "n8n-nodes-base.ssh",
        typeVersion: 1,
        position: execCmdNode.position,  // Same position as old node
        parameters: {
          command: "=powershell.exe -File C:\\\\Scripts\\\\Terminate-Employee.ps1 -EmployeeId {{ $json.employeeId }} -SupervisorEmail {{ $json.supervisorEmail }} -Reason {{ $json.reason }} -TicketNumber {{ $json.ticketNumber }}"
        },
        credentials: {
          ssh: {
            id: "YOUR_SSH_CREDENTIAL_ID",
            name: "DC-PowerShell-Automation"
          }
        }
      }
    }
  ]
});

// Update connections
await mcp__n8n-mcp__n8n_update_partial_workflow({
  id: "WORKFLOW_ID",
  operations: [
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "PREVIOUS_NODE_ID",
        sourceOutputIndex: 0,
        targetNodeId: "ssh_execute_termination",
        targetInputIndex: 0
      }
    },
    {
      type: "addConnection",
      connection: {
        sourceNodeId: "ssh_execute_termination",
        sourceOutputIndex: 0,
        targetNodeId: "NEXT_NODE_ID",
        targetInputIndex: 0
      }
    }
  ]
});
```

### Step 4: Update Output Parser

```javascript
// Find the output parser node
const parserNode = workflow.nodes.find(
  node => node.name.includes("Parse") || node.name.includes("Process Output")
);

// Update its code
await mcp__n8n-mcp__n8n_update_partial_workflow({
  id: "WORKFLOW_ID",
  operations: [
    {
      type: "updateNode",
      nodeId: parserNode.id,
      updates: {
        parameters: {
          jsCode: `
// Parse SSH output
const sshOutput = $input.item.json;
const stdout = sshOutput.stdout || "";

// Parse the JSON from stdout
try {
  const result = JSON.parse(stdout);
  return [{ json: result }];
} catch (error) {
  return [{
    json: {
      success: false,
      error: "Failed to parse PowerShell output",
      rawOutput: stdout
    }
  }];
}
          `.trim()
        }
      }
    }
  ]
});
```

### Step 5: Validate and Activate

```javascript
// Validate workflow
const validation = await mcp__n8n-mcp__n8n_validate_workflow({
  id: "WORKFLOW_ID"
});

console.log("Validation:", validation);

// If valid, activate workflow
if (validation.valid) {
  await mcp__n8n-mcp__n8n_update_partial_workflow({
    id: "WORKFLOW_ID",
    operations: [
      {
        type: "updateSettings",
        settings: {
          active: true
        }
      }
    ]
  });
}
```

---

## Detailed Node Configuration Examples

### SSH Node - Complete Configuration

```json
{
  "id": "ssh_execute_termination",
  "name": "Execute Termination via SSH",
  "type": "n8n-nodes-base.ssh",
  "typeVersion": 1,
  "position": [900, 300],
  "credentials": {
    "ssh": {
      "id": "1",
      "name": "DC-PowerShell-Automation"
    }
  },
  "parameters": {
    "command": "=powershell.exe -File C:\\Scripts\\Terminate-Employee.ps1 -EmployeeId {{ $json.employeeId }} -SupervisorEmail {{ $json.supervisorEmail }} -Reason {{ $json.reason }} -TicketNumber {{ $json.ticketNumber }}"
  }
}
```

### Output Parser Node - Complete Configuration

```json
{
  "id": "parse_results",
  "name": "Parse PowerShell Results",
  "type": "n8n-nodes-base.code",
  "typeVersion": 2,
  "position": [1100, 300],
  "parameters": {
    "language": "javaScript",
    "jsCode": "// Parse SSH output\nconst sshOutput = $input.item.json;\nconst stdout = sshOutput.stdout || \"\";\n\n// Parse the JSON from stdout\ntry {\n  const result = JSON.parse(stdout);\n  return [{ json: result }];\n} catch (error) {\n  return [{\n    json: {\n      success: false,\n      error: \"Failed to parse PowerShell output: \" + error.message,\n      rawOutput: stdout,\n      stderr: sshOutput.stderr\n    }\n  }];\n}"
  }
}
```

### Error Handling Node - Enhanced Version

```json
{
  "id": "error_handler",
  "name": "Handle Errors",
  "type": "n8n-nodes-base.code",
  "typeVersion": 2,
  "position": [1300, 300],
  "parameters": {
    "language": "javaScript",
    "jsCode": "const result = $input.item.json;\n\n// Check for SSH errors\nif ($input.item.json.exitCode && $input.item.json.exitCode !== 0) {\n  return [{\n    json: {\n      success: false,\n      error: \"PowerShell script failed with exit code: \" + $input.item.json.exitCode,\n      stderr: $input.item.json.stderr,\n      stdout: $input.item.json.stdout\n    }\n  }];\n}\n\n// Check for PowerShell script errors\nif (result.success === false) {\n  return [{\n    json: {\n      success: false,\n      error: \"Employee termination failed\",\n      details: result.errors || [],\n      operations: result.operations || {}\n    }\n  }];\n}\n\n// Success\nreturn [{ json: result }];"
  }
}
```

---

## Testing the Updated Workflow

### Test 1: Execute with Test Parameters

1. **Open Workflow**: Open the updated workflow in n8n
2. **Trigger Manually**:
   - Click webhook node (or manual trigger)
   - Click **"Execute node"**
3. **Provide Test Data**:
```json
{
  "employeeId": "TEST123",
  "supervisorEmail": "test@ii-us.com",
  "reason": "Testing",
  "ticketNumber": "TEST001"
}
```
4. **Review Results**: Check each node's output

### Test 2: Verify SSH Execution

Check the SSH node output:

**Expected Output**:
```json
{
  "stdout": "{\n  \"success\": false,\n  \"employeeId\": \"TEST123\",\n  \"employeeName\": null,\n  \"operations\": {...}\n}\n",
  "stderr": "",
  "exitCode": 0
}
```

### Test 3: Verify Parser Node

Check the parser node output:

**Expected Output**:
```json
{
  "success": false,
  "employeeId": "TEST123",
  "employeeName": null,
  "operations": {
    "adLookup": { "success": false, "message": "User not found in AD" },
    ...
  },
  "errors": ["User with Employee ID TEST123 not found in Active Directory"],
  "timestamp": "2025-10-28T16:50:00.000Z"
}
```

### Test 4: Test with Real User (if available)

If you have a test user created (Employee ID 999999):

```json
{
  "employeeId": "999999",
  "supervisorEmail": "your-email@ii-us.com",
  "reason": "Testing SSH execution",
  "ticketNumber": "TEST002"
}
```

**Expected**: All operations should succeed.

---

## Troubleshooting

### Issue: SSH Node Returns Empty Output

**Symptoms**: `stdout` is empty or missing

**Possible Causes**:
1. PowerShell script doesn't output JSON
2. Script path is wrong
3. Script has syntax errors

**Solutions**:
1. Test SSH connection manually:
   ```
   powershell.exe -Command "Write-Output test"
   ```
2. Verify script path:
   ```
   powershell.exe -Command "Test-Path C:\Scripts\Terminate-Employee.ps1"
   ```
3. Run script with error output:
   ```
   powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId TEST 2>&1
   ```

### Issue: Parser Node Fails

**Symptoms**: "Failed to parse PowerShell output" error

**Possible Causes**:
1. stdout contains non-JSON text (warnings, progress messages)
2. JSON is malformed

**Solutions**:
1. Check raw stdout in SSH node output
2. Add `-NoProfile` to PowerShell command:
   ```
   powershell.exe -NoProfile -File C:\Scripts\...
   ```
3. Suppress PowerShell progress messages in script:
   ```powershell
   $ProgressPreference = 'SilentlyContinue'
   ```

### Issue: Workflow Times Out

**Symptoms**: SSH node execution never completes

**Possible Causes**:
1. PowerShell script is waiting for input
2. Script is taking too long
3. SSH connection dropped

**Solutions**:
1. Add timeout to SSH command (in node parameters)
2. Check DC performance/resources
3. Review PowerShell script for blocking operations
4. Add SSH keepalive settings on DC

### Issue: "Permission Denied" Error

**Symptoms**: SSH connection fails with auth error

**Solutions**:
1. Verify SSH credentials are correct in n8n
2. Re-test SSH connection (see N8N-SSH-CREDENTIALS-GUIDE.md)
3. Check DC authorized_keys file permissions

### Issue: Exit Code != 0

**Symptoms**: `exitCode: 1` or other non-zero value

**Possible Causes**:
1. PowerShell script error
2. AD/M365 authentication failure
3. User not found

**Solutions**:
1. Check `stderr` output in SSH node
2. Run script manually on DC to see detailed errors
3. Verify environment variables on DC
4. Check certificate authentication

---

## Rollback Procedure

If you need to revert to the old Execute Command approach:

### Option 1: From UI

1. Re-enable old Execute Command node (if disabled)
2. Disable SSH node
3. Reconnect old node
4. Save workflow

### Option 2: From Backup

1. Import backed-up workflow JSON
2. Rename to avoid conflicts
3. Delete new SSH-based workflow
4. Activate restored workflow

---

## Workflow Comparison

### Before (Execute Command - Won't Work on Linux)

```
Webhook → Validate Input → Execute Command (Local) → Parse JSON → Respond
```

**Issues**:
- Execute Command runs on n8n container (Linux)
- No PowerShell available in Linux container
- Windows-specific paths don't exist

### After (SSH Execution)

```
Webhook → Validate Input → SSH (Remote DC) → Parse stdout → Respond
```

**Benefits**:
- Executes on Windows DC where PowerShell works
- Access to AD, Exchange, Graph modules
- Certificate authentication works
- Script can run on proper server

---

## Next Steps

Once workflow is updated and tested:

1. ✅ **Complete**: Workflow updated for SSH execution
2. ➡️ **Next**: Create comprehensive testing guide
3. ➡️ **Next**: Document production deployment
4. ➡️ **Next**: Set up monitoring and alerting

See [TESTING-VALIDATION-GUIDE.md](TESTING-VALIDATION-GUIDE.md) for full testing procedures.

---

## Quick Reference

### SSH Command Template
```
powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId {{ $json.employeeId }} -SupervisorEmail {{ $json.supervisorEmail }} -Reason {{ $json.reason }} -TicketNumber {{ $json.ticketNumber }}
```

### Output Parser Template
```javascript
const sshOutput = $input.item.json;
const stdout = sshOutput.stdout || "";
const result = JSON.parse(stdout);
return [{ json: result }];
```

### Error Handler Template
```javascript
if ($input.item.json.exitCode !== 0) {
  return [{ json: { success: false, error: "Script failed", stderr: $input.item.json.stderr } }];
}
return [{ json: $input.item.json }];
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-28
**Related Documents**:
- [SSH-CONFIGURATION.md](SSH-CONFIGURATION.md) (SSH setup)
- [N8N-SSH-CREDENTIALS-GUIDE.md](N8N-SSH-CREDENTIALS-GUIDE.md) (credentials setup)
- [PS-SCRIPT-DC-DEPLOYMENT.md](PS-SCRIPT-DC-DEPLOYMENT.md) (script deployment)
- [PRPs/employee-termination-workflow-enhanced.md](PRPs/employee-termination-workflow-enhanced.md) (original workflow)
