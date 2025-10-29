# SSH Configuration Guide for Windows Domain Controller

**Purpose**: Configure OpenSSH Server on Windows DC to enable remote PowerShell execution from n8n.

**Prerequisites**: Complete [PRE-IMPLEMENTATION-CHECKLIST.md](PRE-IMPLEMENTATION-CHECKLIST.md) first.

**Estimated Time**: 15-20 minutes

---

## Architecture Overview

```
┌─────────────────────────┐
│ n8n (Linux Container)   │
│ in Azure Kubernetes     │
└───────────┬─────────────┘
            │
            │ SSH (Port 22)
            │ Private Key Auth
            │
┌───────────▼─────────────┐
│ Windows Domain          │
│ Controller              │
│ ┌─────────────────────┐ │
│ │ OpenSSH Server      │ │
│ └──────────┬──────────┘ │
│            │             │
│ ┌──────────▼──────────┐ │
│ │ PowerShell Script   │ │
│ │ Terminate-          │ │
│ │ Employee.ps1        │ │
│ └─────────────────────┘ │
└─────────────────────────┘
```

---

## Phase 1: Install OpenSSH Server on Windows DC

### Step 1.1: Check if OpenSSH is Already Installed

```powershell
# Run as Administrator on Domain Controller
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
```

**Expected Output**:
- If **State: Installed** → Skip to Step 1.3
- If **State: NotPresent** → Continue to Step 1.2

### Step 1.2: Install OpenSSH Server

```powershell
# Install OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Verify installation
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
```

**Expected**: `State: Installed`

### Step 1.3: Start and Configure SSH Service

```powershell
# Start the sshd service
Start-Service sshd

# Set the service to start automatically
Set-Service -Name sshd -StartupType 'Automatic'

# Verify service is running
Get-Service sshd

# Optional: Start ssh-agent (for key management)
Start-Service ssh-agent
Set-Service -Name ssh-agent -StartupType 'Automatic'
```

**Expected**: `Status: Running` for sshd service

### Step 1.4: Configure Windows Firewall

```powershell
# Check if firewall rule exists
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue

# If rule doesn't exist, create it
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
                    -DisplayName 'OpenSSH Server (sshd)' `
                    -Enabled True `
                    -Direction Inbound `
                    -Protocol TCP `
                    -Action Allow `
                    -LocalPort 22 `
                    -Program '%SystemRoot%\System32\OpenSSH\sshd.exe'

# Verify rule is enabled
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' | Select-Object Name, Enabled, Direction, Action
```

**Expected**: Rule enabled with Action=Allow

---

## Phase 2: Generate and Configure SSH Keys

### Step 2.1: Generate SSH Key Pair (Run on your local machine)

You'll generate the key pair on your local machine (or any machine), then deploy the public key to the DC.

```bash
# On Linux/macOS or Windows with Git Bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/n8n_dc_automation -C "n8n-automation@ii-us.com"

# When prompted:
# Enter passphrase (empty for no passphrase): [Press Enter for no passphrase]
# Enter same passphrase again: [Press Enter]
```

**Output**: Two files created:
- `~/.ssh/n8n_dc_automation` (private key) ⚠️ **Keep secure!**
- `~/.ssh/n8n_dc_automation.pub` (public key)

**Alternative (Windows PowerShell)**:
```powershell
# On Windows PowerShell
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\n8n_dc_automation" -C "n8n-automation@ii-us.com"
```

### Step 2.2: View the Public Key

```bash
# Linux/macOS/Git Bash
cat ~/.ssh/n8n_dc_automation.pub

# Windows PowerShell
Get-Content "$env:USERPROFILE\.ssh\n8n_dc_automation.pub"
```

**Copy this entire output** - you'll need it in the next step.

Example output:
```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDExampleKeyContent... n8n-automation@ii-us.com
```

### Step 2.3: Deploy Public Key to Domain Controller

**On the Domain Controller**, run the following:

```powershell
# Create .ssh directory if it doesn't exist
$sshDir = "C:\ProgramData\ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -Path $sshDir -ItemType Directory -Force
}

# Create administrators_authorized_keys file
$authorizedKeysFile = Join-Path $sshDir "administrators_authorized_keys"

# Add your public key (replace with your actual public key from Step 2.2)
$publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDExampleKeyContent... n8n-automation@ii-us.com"

# Append to file (use Add-Content to preserve existing keys)
Add-Content -Path $authorizedKeysFile -Value $publicKey

# Verify file contents
Get-Content $authorizedKeysFile
```

### Step 2.4: Set Correct Permissions on authorized_keys

**Critical**: Windows OpenSSH requires specific ACL permissions:

```powershell
# Get the administrators_authorized_keys file
$authorizedKeysFile = "C:\ProgramData\ssh\administrators_authorized_keys"

# Remove inheritance
$acl = Get-Acl $authorizedKeysFile
$acl.SetAccessRuleProtection($true, $false)

# Remove all existing access rules
$acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }

# Add SYSTEM with Full Control
$systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
$systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $systemSid, "FullControl", "Allow"
)
$acl.AddAccessRule($systemRule)

# Add Administrators with Full Control
$adminsSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminsRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $adminsSid, "FullControl", "Allow"
)
$acl.AddAccessRule($adminsRule)

# Apply the ACL
Set-Acl -Path $authorizedKeysFile -AclObject $acl

# Verify permissions
Get-Acl $authorizedKeysFile | Format-List
```

**Expected**: Only SYSTEM and Administrators should have access.

### Step 2.5: Configure SSH Server for Key-Only Authentication (Optional but Recommended)

```powershell
# Edit sshd_config
$sshdConfig = "C:\ProgramData\ssh\sshd_config"

# Backup original config
Copy-Item $sshdConfig "$sshdConfig.backup"

# Ensure these settings are present (uncomment if commented)
# Use a text editor or PowerShell to modify:

# Open in notepad
notepad $sshdConfig

# Ensure these lines are present and uncommented:
# PubkeyAuthentication yes
# PasswordAuthentication no  # Optional: Disable password auth for security
# PermitRootLogin no
```

**Key Settings to Verify**:
```
PubkeyAuthentication yes
PasswordAuthentication no  # Set to 'no' to require keys only
PermitRootLogin no
StrictModes yes
```

### Step 2.6: Restart SSH Service

```powershell
# Restart sshd to apply changes
Restart-Service sshd

# Verify service is running
Get-Service sshd
```

---

## Phase 3: Test SSH Connection

### Step 3.1: Test from Local Machine

```bash
# Test SSH connection with private key
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME-OR-IP

# If prompted about host key fingerprint, type 'yes'
# You should connect without password prompt
```

**Expected**: You should get a PowerShell prompt on the DC without entering a password.

**Troubleshooting**: If connection fails:
```bash
# Test with verbose output
ssh -v -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME-OR-IP

# Check for:
# - "Permission denied (publickey)" → Check authorized_keys permissions
# - "Connection refused" → Check firewall/service running
# - "Host key verification failed" → Remove old key: ssh-keygen -R DC-HOSTNAME
```

### Step 3.2: Test PowerShell Command Execution

```bash
# Test running a simple PowerShell command
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME-OR-IP "powershell.exe -Command 'Write-Output Hello from DC'"

# Expected output: Hello from DC

# Test running PowerShell script
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME-OR-IP "powershell.exe -Command 'Get-Service sshd | Select-Object Name, Status'"

# Expected: Should show sshd service status
```

### Step 3.3: Test from n8n Pod (Kubernetes)

First, we need to add the private key to n8n pod (temporary test):

```bash
# Copy private key to n8n pod
kubectl cp ~/.ssh/n8n_dc_automation n8n-prod/REPLACE-WITH-POD-NAME:/tmp/ssh_key

# Exec into n8n pod
kubectl exec -it -n n8n-prod deployment/n8n -- /bin/bash

# Inside pod - set key permissions
chmod 600 /tmp/ssh_key

# Test SSH from pod
ssh -i /tmp/ssh_key -o StrictHostKeyChecking=no Administrator@DC-HOSTNAME-OR-IP "powershell.exe -Command 'Write-Output Testing from n8n pod'"

# Expected: "Testing from n8n pod"

# Test PowerShell script execution
ssh -i /tmp/ssh_key -o StrictHostKeyChecking=no Administrator@DC-HOSTNAME-OR-IP "powershell.exe -File C:\\Scripts\\Terminate-Employee.ps1 -EmployeeId TEST123 -SupervisorEmail test@example.com"

# Exit pod
exit
```

**Note**: The private key will be stored properly in n8n credentials in a later step. This is just for testing.

---

## Phase 4: Security Hardening (Optional but Recommended)

### Step 4.1: Restrict SSH Access by IP (Optional)

If you want to restrict SSH access to only your AKS cluster:

```powershell
# Get AKS egress IP address(es)
# Run this from a machine with kubectl access:
# kubectl run -it --rm test-pod --image=busybox --restart=Never -- wget -qO- ifconfig.me

# Update firewall rule to restrict source IP
$aksEgressIP = "20.51.X.X"  # Replace with your AKS egress IP

Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -RemoteAddress $aksEgressIP

# Verify rule
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' | Get-NetFirewallAddressFilter
```

### Step 4.2: Enable SSH Logging

```powershell
# Enable SSH server logging
$sshdConfig = "C:\ProgramData\ssh\sshd_config"

# Add/update these lines in sshd_config:
# LogLevel VERBOSE
# SyslogFacility AUTH

# Restart service
Restart-Service sshd

# View logs
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 50
```

### Step 4.3: Set Up Key Rotation Schedule

**Best Practice**: Rotate SSH keys every 90-180 days.

Create a reminder to:
1. Generate new SSH key pair
2. Add new public key to DC `administrators_authorized_keys`
3. Update n8n credentials with new private key
4. Test connection
5. Remove old public key from DC

---

## Phase 5: Configure n8n SSH Credentials

### Step 5.1: Prepare Private Key for n8n

n8n requires the private key in PEM format. Your key should already be in this format.

```bash
# View your private key
cat ~/.ssh/n8n_dc_automation

# It should start with:
# -----BEGIN OPENSSH PRIVATE KEY-----
# or
# -----BEGIN RSA PRIVATE KEY-----
```

**Copy the entire private key content** (including BEGIN and END lines).

### Step 5.2: Add Credentials in n8n UI

1. **Access n8n**: Navigate to your n8n instance (e.g., `https://n8n.ii-us.com`)

2. **Go to Credentials**: Click **Settings** → **Credentials**

3. **Create New Credential**:
   - Click **"Add Credential"**
   - Select **"SSH"** from the list
   - Enter the following:
     - **Name**: `DC-PowerShell-Automation`
     - **Host**: `YOUR-DC-HOSTNAME-OR-IP` (from checklist)
     - **Port**: `22`
     - **Authentication**: Select **"Private Key"**
     - **Username**: `Administrator`
     - **Private Key**: Paste your private key (from Step 5.1)
     - **Passphrase**: Leave empty (if you didn't set one)

4. **Test Connection**:
   - Click **"Test Connection"** (if available)
   - or proceed to create a test workflow

5. **Save Credential**

### Step 5.3: Test Credential in n8n Workflow

Create a simple test workflow:

1. Create new workflow in n8n
2. Add **SSH** node
3. Configure:
   - **Credentials**: Select `DC-PowerShell-Automation`
   - **Command**: `powershell.exe -Command "Write-Output 'Test from n8n'"`
4. Execute node
5. **Expected Output**: `Test from n8n`

---

## Verification Checklist

After completing all phases, verify:

- [ ] OpenSSH Server installed and running on DC
- [ ] SSH service set to auto-start
- [ ] Firewall rule allows SSH (port 22)
- [ ] SSH key pair generated
- [ ] Public key deployed to DC
- [ ] Permissions set correctly on `administrators_authorized_keys`
- [ ] SSH connection works from local machine
- [ ] PowerShell commands execute via SSH
- [ ] SSH connection works from n8n pod
- [ ] n8n SSH credentials configured
- [ ] Test workflow executes successfully

**All items checked**: Yes / No

---

## Troubleshooting Guide

### Issue: "Connection refused"

**Possible Causes**:
1. sshd service not running
2. Firewall blocking port 22
3. Incorrect hostname/IP

**Solutions**:
```powershell
# Check service
Get-Service sshd

# Check firewall
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'

# Check listening port
netstat -an | findstr ":22"
```

### Issue: "Permission denied (publickey)"

**Possible Causes**:
1. Incorrect permissions on `administrators_authorized_keys`
2. Wrong public key format
3. Key not in authorized_keys

**Solutions**:
```powershell
# Re-apply permissions (see Step 2.4)
# Verify key content
Get-Content C:\ProgramData\ssh\administrators_authorized_keys

# Check SSH logs
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 20 | Format-List
```

### Issue: "Host key verification failed"

**Solution**:
```bash
# Remove old host key
ssh-keygen -R DC-HOSTNAME-OR-IP

# Try connecting again
ssh -i ~/.ssh/n8n_dc_automation Administrator@DC-HOSTNAME-OR-IP
```

### Issue: PowerShell script doesn't execute

**Possible Causes**:
1. Incorrect script path
2. Execution policy restrictions
3. Script permissions

**Solutions**:
```powershell
# Check script exists
Test-Path C:\Scripts\Terminate-Employee.ps1

# Check execution policy
Get-ExecutionPolicy

# Set if needed
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine

# Check script permissions
Get-Acl C:\Scripts\Terminate-Employee.ps1
```

### Issue: SSH works but PowerShell times out

**Possible Causes**:
1. PowerShell script runs too long
2. SSH timeout settings
3. Script waiting for input

**Solutions**:
```powershell
# Edit sshd_config
$sshdConfig = "C:\ProgramData\ssh\sshd_config"

# Add/update these lines:
# ClientAliveInterval 60
# ClientAliveCountMax 3

# Restart service
Restart-Service sshd
```

---

## Next Steps

Once SSH configuration is complete and verified:

1. ✅ **Complete**: SSH setup
2. ➡️ **Next**: Deploy PowerShell script to DC (see deployment guide)
3. ➡️ **Next**: Update n8n workflow to use SSH node
4. ➡️ **Next**: Test end-to-end workflow

---

## Security Best Practices

1. **Key Management**:
   - Store private key securely (n8n credentials only)
   - Never commit keys to git
   - Rotate keys every 90-180 days
   - Use unique keys per application

2. **Access Control**:
   - Use dedicated service account instead of Administrator (optional)
   - Restrict SSH access by IP (firewall rules)
   - Enable SSH logging
   - Monitor SSH access logs

3. **Auditing**:
   - Review SSH logs weekly: `Get-WinEvent -LogName 'OpenSSH/Operational'`
   - Alert on failed authentication attempts
   - Document all SSH key deployments

4. **Maintenance**:
   - Keep OpenSSH updated: `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`
   - Review and remove unused keys
   - Test SSH connectivity monthly

---

## Reference Commands

### View SSH Service Status
```powershell
Get-Service sshd, ssh-agent | Select-Object Name, Status, StartType
```

### View SSH Logs
```powershell
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 50 | Format-List TimeCreated, Message
```

### List Authorized Keys
```powershell
Get-Content C:\ProgramData\ssh\administrators_authorized_keys
```

### Test SSH Locally (on DC)
```powershell
ssh localhost "powershell.exe -Command 'Get-Date'"
```

### Restart SSH Service
```powershell
Restart-Service sshd
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-28
**Related Documents**:
- [PRE-IMPLEMENTATION-CHECKLIST.md](PRE-IMPLEMENTATION-CHECKLIST.md) (previous step)
- [POWERSHELL-DEPLOYMENT-GUIDE.md](POWERSHELL-DEPLOYMENT-GUIDE.md) (next: script deployment)
- [N8N-WORKFLOW-SSH-UPDATE.md](N8N-WORKFLOW-SSH-UPDATE.md) (next: workflow update)
