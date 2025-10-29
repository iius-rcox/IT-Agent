# n8n SSH Credentials Configuration Guide

**Purpose**: Quick reference for configuring SSH credentials in n8n UI.

**Prerequisites**: SSH keys generated and deployed to DC (see [SSH-CONFIGURATION.md](SSH-CONFIGURATION.md))

**Estimated Time**: 5 minutes

---

## Step 1: Prepare SSH Private Key

Your private key should be in OpenSSH format. Locate the file:

**Linux/macOS**: `~/.ssh/n8n_dc_automation`
**Windows**: `%USERPROFILE%\.ssh\n8n_dc_automation`

### View Private Key Content

```bash
# Linux/macOS
cat ~/.ssh/n8n_dc_automation

# Windows PowerShell
Get-Content "$env:USERPROFILE\.ssh\n8n_dc_automation"
```

**Expected format**:
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAACFwAAAAdzc2gtcn
...many lines of base64...
-----END OPENSSH PRIVATE KEY-----
```

or

```
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA1234567890abcdef...
...many lines of base64...
-----END RSA PRIVATE KEY-----
```

**Copy the entire key** including the BEGIN and END lines.

---

## Step 2: Access n8n Credentials

1. **Log in to n8n**: Navigate to your n8n instance
   - URL: `https://YOUR-N8N-HOSTNAME` (e.g., `https://n8n.ii-us.com`)
   - Enter your credentials

2. **Navigate to Credentials**:
   - Click **Settings** (gear icon in bottom-left or menu)
   - Click **Credentials**
   - You'll see the credentials management page

---

## Step 3: Create SSH Credential

### 3.1: Start New Credential

1. Click **"Add Credential"** button (top-right)
2. In the search box, type: `SSH`
3. Select **"SSH"** from the results

### 3.2: Configure Credential

Fill in the following fields:

| Field | Value | Notes |
|-------|-------|-------|
| **Credential Name** | `DC-PowerShell-Automation` | Descriptive name for this credential |
| **Host** | `YOUR-DC-HOSTNAME-OR-IP` | From PRE-IMPLEMENTATION-CHECKLIST |
| **Port** | `22` | Default SSH port |
| **Username** | `Administrator` | Or service account if using one |
| **Authentication** | `Private Key` | Select from dropdown |
| **Private Key** | `[paste key]` | Entire private key with BEGIN/END lines |
| **Passphrase** | `[leave empty]` | Only if you set a passphrase during key generation |

**Example**:
```
Credential Name: DC-PowerShell-Automation
Host: dc01.insulationsinc.local
Port: 22
Username: Administrator
Authentication: Private Key
Private Key:
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAACFwAAAAdzc2gtcn
...
-----END OPENSSH PRIVATE KEY-----
Passphrase: [empty]
```

### 3.3: Test Connection (if available)

Some n8n versions have a **"Test Connection"** button:
- Click it to verify SSH connectivity
- **Expected**: "Connection successful" or similar message

If no test button:
- Click **"Save"** and test in a workflow (next step)

### 3.4: Save Credential

1. Click **"Save"** button
2. Credential appears in your credentials list

---

## Step 4: Test Credential in Workflow

### 4.1: Create Test Workflow

1. **Go to Workflows**: Click **Workflows** in left menu
2. **Create New**: Click **"Add Workflow"** button
3. **Name it**: "SSH Test" or similar

### 4.2: Add SSH Node

1. Click **"+"** to add a node
2. Search for **"SSH"**
3. Click **"SSH"** node to add it

### 4.3: Configure SSH Node

1. **Credentials**: Click credential dropdown
2. **Select**: `DC-PowerShell-Automation` (your credential)
3. **Command**: Enter test command:
   ```
   powershell.exe -Command "Write-Output 'SSH test from n8n successful'"
   ```

### 4.4: Execute Test

1. Click **"Test node"** or **"Execute Node"** button
2. **Expected output**:
   ```json
   {
     "stdout": "SSH test from n8n successful\n",
     "stderr": "",
     "exitCode": 0
   }
   ```

3. **If successful**: ✅ Credential is working!
4. **If failed**: See Troubleshooting section below

---

## Step 5: Test PowerShell Script Execution

Once basic SSH works, test PowerShell script execution:

### 5.1: Update SSH Node Command

Change command to:
```
powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId TEST123 -SupervisorEmail test@ii-us.com
```

### 5.2: Execute

1. Click **"Execute Node"**
2. **Expected**: JSON output with operation results
3. **Look for**: `"employeeId": "TEST123"` in output

Example output:
```json
{
  "stdout": "{\n  \"success\": false,\n  \"employeeId\": \"TEST123\",\n  \"operations\": {...}\n}\n",
  "stderr": "",
  "exitCode": 0
}
```

### 5.3: Verify JSON Structure

The `stdout` field should contain JSON with:
- `success`: boolean
- `employeeId`: string
- `operations`: object with each operation status
- `errors`: array of error messages
- `timestamp`: ISO 8601 timestamp

---

## Troubleshooting

### Issue: "Host key verification failed"

**Solution**:
```bash
# Remove old host key from n8n pod
kubectl exec -it -n n8n-prod deployment/n8n -- /bin/bash
ssh-keygen -R DC-HOSTNAME
exit

# Or configure SSH to skip host key checking (less secure)
# In SSH node, add to Command:
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ...
```

### Issue: "Permission denied (publickey)"

**Possible Causes**:
1. Wrong private key format
2. Private key doesn't match public key on DC
3. Permissions on DC `administrators_authorized_keys` file

**Solutions**:
1. Verify key format (must include BEGIN/END lines)
2. Verify public key is on DC:
   ```powershell
   Get-Content C:\ProgramData\ssh\administrators_authorized_keys
   ```
3. Re-apply permissions on DC (see SSH-CONFIGURATION.md Step 2.4)

### Issue: "Connection refused"

**Possible Causes**:
1. Wrong hostname/IP
2. SSH service not running on DC
3. Firewall blocking port 22

**Solutions**:
```powershell
# On DC - verify SSH service
Get-Service sshd

# Verify firewall rule
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'

# Test connectivity from n8n pod
kubectl exec -it -n n8n-prod deployment/n8n -- /bin/bash
telnet DC-IP 22
```

### Issue: "Connection timeout"

**Possible Causes**:
1. Network connectivity issue
2. Firewall blocking traffic
3. NSG rules (Azure)

**Solutions**:
1. Verify AKS can reach DC network:
   ```bash
   kubectl exec -it -n n8n-prod deployment/n8n -- /bin/bash
   ping DC-HOSTNAME
   curl -v telnet://DC-HOSTNAME:22
   ```
2. Check Azure NSG rules if using Azure
3. Verify DC firewall allows traffic from AKS subnet

### Issue: "Authentication error" or "Invalid private key"

**Solutions**:
1. **Check key format**: Must be complete key with headers
2. **Check for extra characters**: No extra spaces or newlines
3. **Regenerate if needed**:
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/n8n_dc_automation_new
   # Then redeploy public key to DC
   ```

### Issue: Command executes but no output

**Possible Causes**:
1. PowerShell script doesn't output anything
2. Script is waiting for input
3. Output encoding issue

**Solutions**:
1. Test with simple command first:
   ```
   powershell.exe -Command "Write-Output test"
   ```
2. Verify script ends with output statement:
   ```powershell
   $results | ConvertTo-Json -Depth 10
   ```
3. Add `-NoProfile` flag:
   ```
   powershell.exe -NoProfile -File C:\Scripts\...
   ```

---

## Security Best Practices

1. **Credential Access**:
   - Limit who can view/edit credentials in n8n
   - Use n8n RBAC if available (Enterprise)

2. **Key Rotation**:
   - Rotate SSH keys every 90-180 days
   - Update n8n credential after rotation

3. **Audit**:
   - Review credential usage in n8n
   - Monitor SSH logs on DC

4. **Backup**:
   - Export n8n credentials backup
   - Store encrypted in secure location

---

## Quick Reference

### Credential Settings
```
Type: SSH
Name: DC-PowerShell-Automation
Host: [DC-HOSTNAME-OR-IP]
Port: 22
User: Administrator
Auth: Private Key
Key: [Full private key with BEGIN/END]
Passphrase: [empty or your passphrase]
```

### Test Commands

**Simple test**:
```
powershell.exe -Command "Write-Output test"
```

**Date test**:
```
powershell.exe -Command "Get-Date"
```

**Script test**:
```
powershell.exe -File C:\Scripts\Terminate-Employee.ps1 -EmployeeId TEST -SupervisorEmail test@example.com
```

---

## Next Steps

Once SSH credentials are configured and tested:

1. ✅ **Complete**: SSH credentials configured
2. ➡️ **Next**: Update employee termination workflow to use SSH node
3. ➡️ **Next**: Test full workflow end-to-end

See [N8N-WORKFLOW-SSH-UPDATE.md](N8N-WORKFLOW-SSH-UPDATE.md) for workflow update instructions.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-28
**Related Documents**:
- [SSH-CONFIGURATION.md](SSH-CONFIGURATION.md) (SSH setup on DC)
- [PRE-IMPLEMENTATION-CHECKLIST.md](PRE-IMPLEMENTATION-CHECKLIST.md) (prerequisites)
- [N8N-WORKFLOW-SSH-UPDATE.md](N8N-WORKFLOW-SSH-UPDATE.md) (next: workflow update)
