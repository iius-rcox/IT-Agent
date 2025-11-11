# SSH Public Key Authentication Solution for Windows Domain Controller

## Problem Summary
SSH public key authentication fails on Windows Domain Controller (INSDAL9DC01) with "connection reset by peer [preauth]" errors, while password authentication works. This is due to Windows-specific handling of Administrator accounts in OpenSSH.

## Root Cause
Windows OpenSSH uses a special global authorized keys file (`C:\ProgramData\ssh\administrators_authorized_keys`) for any account in the Administrators group, instead of the user's profile authorized_keys file. This causes several complications:

1. **Special file location**: Admin keys must be in `administrators_authorized_keys`
2. **Strict ACLs required**: Only SYSTEM and Administrators can have access
3. **File encoding issues**: Must be ASCII/UTF-8 (no UTF-16 BOM)
4. **No credential delegation**: SSH key sessions don't get Kerberos tickets for AD operations

## Recommended Solution: Non-Admin Service Account

### Why This Approach Works Best
- **Avoids admin restrictions**: Uses standard `~\.ssh\authorized_keys` file
- **Better security**: Limited permissions, principle of least privilege
- **Simpler setup**: No special file locations or ACL complications
- **Reliable**: Standard SSH key auth works as expected

### Implementation Steps

#### 1. Run Diagnostic Script First
```powershell
# On INSDAL9DC01, run the diagnostic script to understand current state
.\diagnose-ssh-key-auth.ps1 -CheckACLs
```

#### 2. Create Service Account
```powershell
# Create non-admin service account with delegated permissions
.\setup-service-account-ssh.ps1 -CreateAccount
```
This creates `svc-n8n-ssh` account with:
- Permissions to disable AD accounts
- Permissions to reset passwords
- Member of "Remote Management Users"
- Member of "Employee Termination Operators" (custom group)

#### 3. Deploy SSH Key
```powershell
# Copy your n8n pod's public key to the DC
# From n8n pod:
kubectl exec -n n8n <pod-name> -- cat /home/node/.ssh/id_rsa.pub > n8n-pod.pub

# Transfer to DC at C:\temp\n8n-pod.pub, then:
.\setup-service-account-ssh.ps1 -ConfigureSSH
```

#### 4. Test Connection
```powershell
# Verify SSH key auth works
.\setup-service-account-ssh.ps1 -TestConnection
```

#### 5. Update n8n Configuration
In n8n, update the SSH credential:
- **Host**: `10.0.0.200` (INSDAL9DC01)
- **Port**: `22`
- **Username**: `INSIGHTFUL\svc-n8n-ssh`
- **Private Key**: (paste private key from n8n pod)

## Alternative Solutions (If Service Account Not Viable)

### Option 1: Fix Admin Key Auth (Current Approach)
```powershell
# Try disabling admin match rule
.\diagnose-ssh-key-auth.ps1 -DisableAdminMatch

# Or fix the administrators_authorized_keys file
.\diagnose-ssh-key-auth.ps1 -FixKeyFile

# Run debug mode to see exact failure
.\diagnose-ssh-key-auth.ps1 -RunDebugMode
```

### Option 2: Password Auth with Azure Key Vault (90% Complete)
- Store admin password in Key Vault
- n8n retrieves password at runtime
- Requires fixing AKS resource constraints for pod restart
- Provides full AD credentials in session

### Option 3: PowerShell JEA Endpoint
- Create constrained PowerShell endpoint
- Use certificate authentication
- Native Windows approach
- No SSH required

## Credential Delegation Workaround

For AD operations in SSH key sessions (which lack network credentials):

```powershell
# In your Terminate-Employee.ps1 script, add:
$cred = Get-Credential -UserName "INSIGHTFUL\svc-n8n-ssh" -Message "Service account"
# Or retrieve from secure storage

# Use -Credential parameter for AD cmdlets
Disable-ADAccount -Identity $targetUser -Credential $cred
Set-ADUser -Identity $targetUser -Description "Terminated $(Get-Date)" -Credential $cred
```

## Verification Commands

### Check SSH Logs
```powershell
Get-WinEvent -LogName "OpenSSH/Operational" -MaxEvents 10 |
    Where-Object {$_.Message -match "svc-n8n-ssh"} |
    Format-Table TimeCreated, Message -Wrap
```

### Test from n8n Pod
```bash
# In n8n pod
ssh INSIGHTFUL\\svc-n8n-ssh@10.0.0.200 'powershell -c "whoami; Get-ADUser -Identity Guest | Select Name"'
```

## Security Considerations

1. **Key Management**:
   - Rotate SSH keys periodically
   - Store private key securely in n8n
   - Monitor key usage in logs

2. **Account Security**:
   - Service account has minimal required permissions
   - Password set to never expire (document in Key Vault)
   - Account activity logged in Security event log

3. **Audit Trail**:
   - All SSH connections logged in OpenSSH/Operational
   - AD changes logged with service account attribution
   - Enable PowerShell transcription for command logging

## Rollback Plan

If issues arise:
1. Disable service account: `Disable-ADAccount -Identity svc-n8n-ssh`
2. Revert to password auth: Use existing Azure Key Vault implementation
3. Remove SSH access: `Stop-Service sshd; Set-Service sshd -StartupType Disabled`

## Success Metrics

- ✅ SSH key authentication works reliably
- ✅ No "connection reset by peer" errors
- ✅ Employee termination script executes successfully
- ✅ Audit logs show clear attribution
- ✅ No elevated privileges beyond requirements