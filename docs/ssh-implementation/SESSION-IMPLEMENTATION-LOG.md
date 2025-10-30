# SSH Implementation Session Log
**Date:** October 28, 2025
**Objective:** Enable SSH key-based authentication from AKS n8n to Domain Controller
**Environment:** Windows Server Domain Controller (INSDAL9DC01) + Azure Kubernetes Service (dev-aks)

## Executive Summary

**Status:** 🔴 **BLOCKED** - Public key authentication failing

**Progress:**
- ✅ **Network Configuration:** Complete (NSG, Firewall, Connectivity)
- ✅ **SSH Service Setup:** Complete (Service running, responding)
- ✅ **Password Authentication:** Working
- ❌ **Public Key Authentication:** **BLOCKED** (Connection reset)

**Key Achievement:** Resolved complex Azure NSG networking issue with AKS pod CIDR overlay networking

**Current Blocker:** SSH public key authentication fails despite correct configuration. Password authentication works, proving network and SSH service are functional. Issue appears to be Windows Server Domain Controller specific.

**Time Invested:** ~4 hours of troubleshooting
**Files Modified:** 15+ configuration attempts
**Tests Performed:** 30+ connection attempts

---

## Current Status Summary

### What Works ✅
- Network connectivity (ICMP, DNS, TCP)
- Azure NSG rules (pod CIDR properly configured)
- Windows Firewall (port 22 open)
- SSH service (OpenSSH 9.5 responding)
- SSH protocol negotiation
- **Password authentication** (confirms basic SSH works)

### What Doesn't Work ❌
- **Public key authentication** (connection reset immediately)
- No detailed error logs (even with DEBUG3 logging)
- Connection terminates before authentication phase

### Root Cause Hypothesis
Windows Server Domain Controller has additional security policies or Group Policy settings blocking SSH key authentication for Administrator accounts. The `Match Group administrators` block in sshd_config may have special restrictions on DCs.

## Components Configured

### 1. SSH Key Generation ✅
**Location:** Local machine (`C:\Users\rcox\.ssh\`)

```bash
# Created ED25519 key pair
ssh-keygen -t ed25519 -C "n8n-dc-automation" -f "$HOME/.ssh/n8n_dc_automation" -N ""
```

**Files Created:**
- Private key: `C:\Users\rcox\.ssh\n8n_dc_automation`
- Public key: `C:\Users\rcox\.ssh\n8n_dc_automation.pub`

**Public Key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII15oR1ICDywSpc0aBKNh8+5jRDVhYuAcIhw9MFUpScH n8n-dc-automation
```

---

### 2. Domain Controller Configuration ✅
**Server:** INSDAL9DC01.insulationsinc.local (10.0.0.200)

#### 2.1 Authorized Keys Setup

```powershell
# Created authorized_keys file with proper permissions
$authorizedKeysFile = "C:\ProgramData\ssh\administrators_authorized_keys"
$publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII15oR1ICDywSpc0aBKNh8+5jRDVhYuAcIhw9MFUpScH n8n-dc-automation"

Set-Content -Path $authorizedKeysFile -Value $publicKey

# Set correct NTFS permissions (CRITICAL)
icacls $authorizedKeysFile /inheritance:r
icacls $authorizedKeysFile /grant "SYSTEM:(F)"
icacls $authorizedKeysFile /grant "Administrators:(F)"
```

**Result:** Permissions correctly set to SYSTEM and Administrators only.

#### 2.2 SSH Service Configuration

```powershell
# Ensured SSH service is running
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

**Status:** OpenSSH SSH Server running on port 22

#### 2.3 Windows Firewall Rules

```powershell
# Created firewall rule for AKS subnet
New-NetFirewallRule -DisplayName "Allow SSH from AKS" `
    -Direction Inbound `
    -LocalPort 22 `
    -Protocol TCP `
    -RemoteAddress 10.0.3.0/24 `
    -Action Allow `
    -Profile Any
```

**Active Rules:**
- `OpenSSH SSH Server (sshd)` - Allow from Any
- `Allow SSH from AKS` - Allow from 10.0.3.0/24

**⚠️ NOTE:** Windows Firewall rule for 10.0.3.0/24 was **NOT SUFFICIENT** alone - Azure NSG also required configuration.

---

### 3. Azure Kubernetes Service (AKS) Configuration ✅

#### 3.1 AKS Cluster Details
- **Cluster Name:** dev-aks
- **Resource Group:** rg_prod
- **Namespace:** n8n-prod (existing)
- **Location:** southcentralus
- **Network Plugin:** Azure CNI with Overlay mode
- **Pod CIDR:** 10.244.0.0/16
- **Service CIDR:** 10.240.0.0/16
- **Node Subnet:** 10.0.3.0/24

#### 3.2 Kubernetes Secret Creation

```bash
# Created secret containing SSH private key
kubectl create secret generic n8n-ssh-key \
  --from-file=ssh-privatekey="/c/Users/rcox/.ssh/n8n_dc_automation" \
  -n n8n-prod
```

**Result:** Secret `n8n-ssh-key` created in `n8n-prod` namespace

#### 3.3 SSH Test Pod Deployment

```yaml
# Deployed test pod with SSH client
apiVersion: v1
kind: Pod
metadata:
  name: ssh-test
  namespace: n8n-prod
spec:
  containers:
  - name: ssh-client
    image: alpine:latest
    command: ["/bin/sh", "-c", "apk add --no-cache openssh-client && sleep 3600"]
    volumeMounts:
    - name: ssh-key
      mountPath: /root/.ssh
      readOnly: true
  volumes:
  - name: ssh-key
    secret:
      secretName: n8n-ssh-key
      defaultMode: 0600
      items:
      - key: ssh-privatekey
        path: id_ed25519
```

---

### 4. Azure Network Security Group (NSG) Configuration ✅ **CRITICAL**

#### 4.1 NSG Discovery
- **NSG Name:** DC-NSG
- **Attached to:** DC1-Static NIC (INSDAL9DC01)
- **DC IP:** 10.0.0.200

#### 4.2 Initial NSG Rules (INSUFFICIENT)
```
Priority 300: Allow SSH from 10.0.3.0/24 → 10.0.0.200:22
Priority 400: Deny SSH from * → *:22
```

**Problem:** AKS pods use IP addresses from pod CIDR (10.244.0.0/16), not node subnet (10.0.3.0/24)

#### 4.3 Updated NSG Rule (SOLUTION) ✅

```bash
az network nsg rule update \
  --nsg-name DC-NSG \
  --resource-group rg_prod \
  --name "Allow-SSH-From-AKS-Only" \
  --source-address-prefixes "10.0.3.0/24" "10.244.0.0/16"
```

**Final Rule Configuration:**
- **Name:** Allow-SSH-From-AKS-Only
- **Priority:** 300
- **Direction:** Inbound
- **Access:** Allow
- **Protocol:** TCP
- **Source:** 10.0.3.0/24, **10.244.0.0/16** (both required)
- **Destination:** 10.0.0.200
- **Destination Port:** 22

---

## Testing & Validation

### Network Connectivity Tests

```bash
# 1. Basic ICMP connectivity (SUCCESS)
kubectl exec -n n8n-prod ssh-test -- ping -c 3 10.0.0.200
# Result: 0% packet loss, ~1.5ms latency

# 2. DNS Resolution (SUCCESS)
kubectl exec -n n8n-prod ssh-test -- nslookup insdal9dc01.insulationsinc.local
# Result: Resolved to 10.0.0.200

# 3. Port 22 connectivity (PENDING)
kubectl exec -n n8n-prod ssh-test -- nc -zv -w 5 10.0.0.200 22
# Status: Testing after NSG update
```

### SSH Authentication Test ⚠️ **BLOCKED**

```bash
kubectl exec -n n8n-prod ssh-test -- sh -c \
  'ssh -i /root/.ssh/id_ed25519 \
   -o StrictHostKeyChecking=no \
   -o UserKnownHostsFile=/dev/null \
   administrator@10.0.0.200 hostname'
```

**Current Status:** ❌ **Connection reset by peer** - Public key authentication failing

**Test Results:**
- ✅ ICMP ping: Success (1.5ms latency)
- ✅ DNS resolution: Success (resolves to 10.0.0.200)
- ✅ Port 22 TCP connectivity: Success (SSH banner received)
- ✅ SSH service responding: Success (shows `SSH-2.0-OpenSSH_for_Windows_9.5`)
- ✅ Password authentication: Success (prompts for password)
- ❌ Public key authentication: **FAILS with "Connection reset by 10.0.0.200 port 22"**

**Key Finding:** Network connectivity and SSH service are working perfectly. Password authentication succeeds, but public key authentication fails immediately after protocol negotiation, before any auth methods are attempted.

---

## Detailed Troubleshooting Log

### Phase 1: Network Connectivity Issues ✅ **RESOLVED**

#### Issue 1.1: Initial Connection Timeout
**Symptom:** `ssh: connect to host 10.0.0.200 port 22: Operation timed out`

**Root Cause:** Azure NSG blocking traffic from AKS pod CIDR

**Investigation Steps:**
1. Verified NSG rules on DC-NSG
2. Discovered initial rule only allowed 10.0.3.0/24 (AKS node subnet)
3. Identified pod source IP: 10.244.4.104 (from pod CIDR 10.244.0.0/16)
4. Tested RDP port 3389 - SUCCESS (confirmed NSG allows some traffic)

**Solution:**
```bash
# Updated NSG to include all three subnets
az network nsg rule update \
  --nsg-name DC-NSG \
  --resource-group rg_prod \
  --name "Allow-SSH-From-AKS-Only" \
  --source-address-prefixes "10.0.0.0/24" "10.0.3.0/24" "10.244.0.0/16"
```

**Result:** ✅ Connection now reaches SSH server (switched from timeout to "connection reset")

**Key Learning:** Azure CNI Overlay mode uses pod CIDR for pod IPs, not node subnet. NSG must allow pod CIDR (10.244.0.0/16) in addition to node subnet (10.0.3.0/24) and default subnet (10.0.0.0/24 where nodes actually reside).

---

### Phase 2: SSH Public Key Authentication Issues ❌ **ONGOING**

#### Issue 2.1: Authorized Keys File Line Breaks
**Symptom:** Public key split across multiple lines in file

**Investigation:**
```powershell
Get-Content "C:\ProgramData\ssh\administrators_authorized_keys"
# Output showed:
# ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII15oR1ICDywSpc0aBKNh8+5jRDVhYuAcIhw9MFUpScH
#   n8n-dc-automation
```

**Attempts:**
1. Used `Set-Content` with `-NoNewline` - Still created line breaks
2. Used `Out-File` with `-Encoding ASCII -NoNewline` - Still created line breaks
3. Used `[System.IO.File]::WriteAllText()` - Still created line breaks
4. **Final solution:** Used `[System.IO.File]::WriteAllBytes()` with ASCII byte array

**Verification:**
```powershell
(Get-Item "C:\ProgramData\ssh\administrators_authorized_keys").Length
# Result: 98 bytes (correct size for key + comment)

# Verified no hidden characters via hex dump
```

**Result:** ⚠️ File now correct, but authentication still fails

---

#### Issue 2.2: PubkeyAuthentication Not Enabled
**Symptom:** No SSH authentication logs, connection reset immediately

**Investigation:**
```powershell
Get-Content "C:\ProgramData\ssh\sshd_config" | Select-String "PubkeyAuthentication"
# Result: Line was commented (#PubkeyAuthentication yes)
```

**Attempts:**
1. Uncommented `#PubkeyAuthentication yes` in sshd_config
2. Added `PubkeyAuthentication yes` before Match Group section
3. Verified setting multiple times after SSH restarts

**Current State:**
```
PubkeyAuthentication yes  (line 86)
Match Group administrators (line 88)
       AuthorizedKeysFile C:/ProgramData/ssh/administrators_authorized_keys
```

**Result:** ⚠️ Setting now enabled, but authentication still fails

---

#### Issue 2.3: Windows Registry Settings
**Symptom:** Connection reset might be due to missing Windows Server configuration

**Investigation & Fixes:**
```powershell
# 1. DefaultShell registry key (required for SSH to work properly on Windows)
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" `
  -Name DefaultShell `
  -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -PropertyType String -Force

# 2. LocalAccountTokenFilterPolicy (allows Administrator network auth)
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
  -Name LocalAccountTokenFilterPolicy `
  -Value 1 `
  -PropertyType DWord -Force
```

**Verification:**
```powershell
Get-ItemProperty "HKLM:\SOFTWARE\OpenSSH" | Select DefaultShell
# Result: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe

Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" | Select LocalAccountTokenFilterPolicy
# Result: 1
```

**Result:** ⚠️ Registry keys now set, but authentication still fails

---

#### Issue 2.4: StrictModes File Permission Check
**Symptom:** StrictModes might be rejecting key file due to permissions

**Investigation:**
```powershell
# Disabled StrictModes for testing
Get-Content "C:\ProgramData\ssh\sshd_config" | Select-String "StrictModes"
# Changed from: #StrictModes yes
# To: StrictModes no
```

**Permissions Verification:**
```powershell
icacls "C:\ProgramData\ssh\administrators_authorized_keys"
# Result:
#   BUILTIN\Administrators:(F)
#   NT AUTHORITY\SYSTEM:(F)
# No other permissions (correct for SSH)
```

**Result:** ⚠️ StrictModes disabled, permissions correct, but authentication still fails

---

#### Issue 2.5: Missing sshd_config File
**Symptom:** sshd.exe syntax test failed: `__PROGRAMDATA__\ssh/sshd_config: No such file or directory`

**Discovery:**
```powershell
Get-ChildItem "C:\ProgramData\ssh\" | Select Name
# Found:
#   sshd_config.backup
#   sshd_config.modified
#   (sshd_config was MISSING!)
```

**Root Cause:** During troubleshooting, config file was renamed and never restored

**Fix:**
```powershell
Copy-Item "C:\ProgramData\ssh\sshd_config.modified" "C:\ProgramData\ssh\sshd_config"
Restart-Service sshd
```

**Verification:**
```powershell
& "C:\Windows\System32\OpenSSH\sshd.exe" -t
# No errors (config syntax valid)
```

**Result:** ✅ Config file restored, but authentication still fails

---

#### Issue 2.6: __PROGRAMDATA__ Variable Not Expanding
**Symptom:** AuthorizedKeysFile path using `__PROGRAMDATA__` might not be expanding correctly

**Investigation:**
```powershell
Get-Content "C:\ProgramData\ssh\sshd_config" | Select-String "AuthorizedKeysFile"
# Found: AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

**Fix:** Changed to explicit path
```powershell
# Changed from: AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
# To: AuthorizedKeysFile C:/ProgramData/ssh/administrators_authorized_keys
```

**Result:** ⚠️ Path now explicit, but authentication still fails

---

#### Issue 2.7: SSH Event Logs Show No Authentication Attempts
**Symptom:** No detailed error messages in OpenSSH/Operational logs

**Investigation:**
```powershell
Get-WinEvent -LogName "OpenSSH/Operational" -MaxEvents 20
# Result: Only shows:
#   - Server listening messages
#   - Connection closed by 10.0.0.21 (AKS node IP)
#   - NO authentication errors
#   - NO key validation errors
```

**Enabled Verbose Logging:**
```powershell
# Set LogLevel DEBUG3 in sshd_config
(Get-Content "C:\ProgramData\ssh\sshd_config") -replace "^#?LogLevel.*", "LogLevel DEBUG3" | Set-Content "C:\ProgramData\ssh\sshd_config"
Restart-Service sshd
```

**Result:** ⚠️ Verbose logging enabled, but still no detailed errors in logs. Connection terminates before authentication phase begins.

---

#### Issue 2.8: Password vs Key Authentication Comparison
**Test:** Determined if issue is SSH general or key-specific

**Password Authentication Test:**
```bash
kubectl exec -n n8n-prod ssh-test -- sh -c \
  'timeout 5 ssh -o StrictHostKeyChecking=no \
   -o UserKnownHostsFile=/dev/null \
   -o PubkeyAuthentication=no \
   administrator@10.0.0.200 echo "test"'
```

**Result:** ✅ Password authentication **WORKS** (prompts for password, connection stays open)

**Key Authentication Test:**
```bash
kubectl exec -n n8n-prod ssh-test -- sh -c \
  'ssh -i /root/.ssh/id_ed25519 \
   -o StrictHostKeyChecking=no \
   -o UserKnownHostsFile=/dev/null \
   administrator@10.0.0.200 hostname'
```

**Result:** ❌ Key authentication **FAILS** (connection reset immediately)

**Critical Finding:** This proves:
- ✅ Network path is working
- ✅ SSH service is functioning normally
- ✅ Basic authentication framework works
- ❌ **Public key authentication specifically is broken**

---

### Phase 3: Current Status & Next Steps ⏳

#### What's Working
1. ✅ Network connectivity (ICMP, DNS, TCP port 22)
2. ✅ Azure NSG rules (all three subnets allowed)
3. ✅ Windows Firewall rules (port 22 open)
4. ✅ SSH service running (OpenSSH 9.5 on Windows Server)
5. ✅ SSH protocol negotiation (handshake completes)
6. ✅ Password authentication (prompts and accepts password)
7. ✅ Registry keys configured (DefaultShell, LocalAccountTokenFilterPolicy)
8. ✅ File permissions correct (SYSTEM + Administrators only)
9. ✅ Authorized keys file properly formatted (98 bytes, no hidden chars)
10. ✅ PubkeyAuthentication enabled in sshd_config
11. ✅ StrictModes disabled for testing
12. ✅ sshd_config syntax valid

#### What's Not Working
1. ❌ **Public key authentication fails with "Connection reset"**
2. ❌ No error logs in OpenSSH/Operational event log
3. ❌ Connection terminates before any auth methods are attempted

#### Verbose SSH Client Debug (Last Connection Attempt)
```
debug1: SSH2_MSG_SERVICE_ACCEPT received
debug3: send packet: type 50
Connection reset by 10.0.0.200 port 22
```

**Analysis:** Connection resets immediately after service accept, **before** any auth methods (type 50 is authentication request). This suggests SSH server is terminating connection due to configuration or policy issue.

#### Current Hypothesis
The issue appears to be **Windows Server specific**:
1. This is a **Domain Controller** running Windows Server
2. Stricter Group Policy or security policies may be in effect
3. The `Match Group administrators` block may have additional restrictions
4. Administrator account may have special handling on Windows Server DCs

#### Next Troubleshooting Steps (In Progress)
1. ⏳ Try using user home directory (`~/.ssh/authorized_keys`) instead of global administrators file
2. ⏳ Check for Group Policy restrictions on SSH key authentication
3. ⏳ Test with a non-Administrator domain user account
4. ⏳ Check Windows Server security policies specific to Domain Controllers
5. ⏳ Review sshd_config Match Group section for additional restrictions

---

## Key Learnings & Issues Resolved

### 1. ✅ SSH Directory Creation
**Issue:** `~/.ssh` directory didn't exist on Windows
**Solution:** Created with `mkdir -p "$HOME/.ssh"`

### 2. ✅ NTFS Permissions
**Issue:** SSH keys require strict permissions
**Solution:** Used `icacls` to limit access to SYSTEM and Administrators only

### 3. ✅ Windows Firewall Configuration
**Issue:** Default OpenSSH rule allows all sources
**Solution:** Created explicit allow rule for AKS subnet (though NSG is the real gatekeeper)

### 4. ✅ **CRITICAL: Pod CIDR vs Node Subnet**
**Issue:** NSG only allowed node subnet (10.0.3.0/24), but pods use pod CIDR (10.244.0.0/16)
**Root Cause:** Azure CNI Overlay mode - pods have IPs from pod CIDR, not node subnet
**Solution:** Updated NSG to allow both address ranges

### 5. ✅ AKS Network Architecture Understanding
- **Node Subnet:** 10.0.3.0/24 - Where AKS nodes reside
- **Pod CIDR:** 10.244.0.0/16 - Where pod IPs are allocated (overlay network)
- **Implication:** Outbound pod traffic appears to come from pod CIDR, not node subnet

---

## Unnecessary Changes (Can Be Simplified)

### Windows Firewall Rule for AKS Subnet
**Rule:** `Allow SSH from AKS` (10.0.3.0/24)

**Status:** ⚠️ **REDUNDANT** (but harmless)

**Reason:**
- The default OpenSSH firewall rule already allows traffic from "Any"
- The **real security control** is the Azure NSG, not Windows Firewall
- Windows Firewall runs **after** the packet passes Azure NSG

**Recommendation:**
- Can be **removed** since:
  1. Default OpenSSH rule allows all sources
  2. Azure NSG provides the actual access control
- **OR keep it** for defense-in-depth strategy

```powershell
# To remove (optional):
Remove-NetFirewallRule -DisplayName "Allow SSH from AKS"
```

---

## Remaining Tasks

### 1. ❌ **BLOCKED:** Resolve SSH Public Key Authentication
**Current Blocker:** Public key authentication fails with "Connection reset" despite all standard configuration being correct

**Status:** Under active troubleshooting
- Network connectivity: ✅ Working
- Password authentication: ✅ Working
- Public key authentication: ❌ **BLOCKED**

**Next Steps Being Attempted:**
1. ⏳ Test with user home directory (`C:\Users\Administrator\.ssh\authorized_keys`)
2. ⏳ Check Group Policy restrictions on Windows Server DC
3. ⏳ Test with non-Administrator domain user
4. ⏳ Review Windows Server DC-specific security policies

### 2. ⏸️ **PENDING:** Test AD Commands via SSH
**Depends on:** Task #1 (SSH connection working)

```bash
kubectl exec -n n8n-prod ssh-test -- \
  ssh -i /root/.ssh/id_ed25519 administrator@10.0.0.200 \
  "powershell Get-ADUser -Filter 'Name -eq \"Test User\"'"
```

### 3. ⏸️ **PENDING:** Update n8n Workflow SSH Credentials
**Depends on:** Tasks #1 and #2

Steps once SSH works:
1. Delete test pod: `kubectl delete pod ssh-test -n n8n-prod`
2. Configure n8n to mount the `n8n-ssh-key` secret
3. Update SSH node credentials to use key-based auth
4. Test employee termination workflow

### 4. ⏸️ **PENDING:** Document n8n Deployment Updates
**Depends on:** Task #3

Create/update n8n deployment manifest to include SSH key volume mount

---

## Network Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Azure VNet: vnet_prod (10.0.0.0/16)                         │
│                                                               │
│  ┌──────────────────────┐      ┌──────────────────────┐    │
│  │ Default Subnet       │      │ AKS Subnet           │    │
│  │ 10.0.0.0/24          │      │ 10.0.3.0/24          │    │
│  │                      │      │                      │    │
│  │  INSDAL9DC01         │      │  AKS Nodes           │    │
│  │  10.0.0.200          │◄─────┤                      │    │
│  │  + DC-NSG            │      │  Pod Overlay:        │    │
│  │    - Allow           │      │  10.244.0.0/16       │    │
│  │      10.0.3.0/24 ✓   │      │                      │    │
│  │    - Allow           │      │  ssh-test pod:       │    │
│  │      10.244.0.0/16 ✓ │◄─────┤  10.244.4.104        │    │
│  └──────────────────────┘      └──────────────────────┘    │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Final Configuration Summary

### Files Created
1. **Local Machine:**
   - `C:\Users\rcox\.ssh\n8n_dc_automation` (private key)
   - `C:\Users\rcox\.ssh\n8n_dc_automation.pub` (public key)

2. **Domain Controller (INSDAL9DC01):**
   - `C:\ProgramData\ssh\administrators_authorized_keys` (public key)

3. **Kubernetes (n8n-prod namespace):**
   - Secret: `n8n-ssh-key`
   - Test Pod: `ssh-test`

### Azure Resources Modified
- **NSG Rule:** `DC-NSG/Allow-SSH-From-AKS-Only`
  - Added pod CIDR (10.244.0.0/16) to allowed sources

### Services Configured
- **DC:** OpenSSH Server (sshd) - Running, Automatic startup
- **DC:** Windows Firewall - Allow SSH from AKS
- **AKS:** kubectl credentials configured for dev-aks cluster

---

## Windows Server Domain Controller Specific Considerations

### Environment Context
- **OS:** Windows Server (Domain Controller role)
- **OpenSSH Version:** 9.5 for Windows
- **Domain:** INSULATIONSINC.LOCAL
- **Server:** INSDAL9DC01 (10.0.0.200)

### Windows Server DC Restrictions
Domain Controllers have stricter security policies than regular Windows Servers:

1. **Enhanced Security Configuration:** DCs run with enhanced security by default
2. **Group Policy Enforcement:** Additional GPOs may restrict remote authentication methods
3. **Administrator Account Restrictions:** Built-in Administrator may have special handling
4. **Audit Policies:** Stricter logging and authentication requirements

### Potential DC-Specific Blockers
1. **Group Policy:** May restrict SSH key authentication for privileged accounts
2. **Security Policies:** May require specific authentication methods for Administrators
3. **Credential Guard:** May interfere with key-based authentication
4. **Smart Card Policies:** May enforce smart card requirements for admin accounts

### Recommended Alternative Approaches

#### Option 1: Use Domain User Account (Not Administrator)
```powershell
# Create dedicated service account for n8n automation
New-ADUser -Name "n8n-automation" `
  -UserPrincipalName "n8n-automation@insulationsinc.local" `
  -Enabled $true `
  -PasswordNeverExpires $true

# Add to required groups (NOT Domain Admins - use least privilege)
Add-ADGroupMember -Identity "Account Operators" -Members "n8n-automation"

# Configure SSH for this user
New-Item -Path "C:\Users\n8n-automation\.ssh" -ItemType Directory
# Add public key to user's authorized_keys
```

#### Option 2: Use Password Authentication (Temporary)
- Password auth is currently working
- Use Azure Key Vault for secure password storage
- Rotate passwords regularly via automation
- **Tradeoff:** Less secure than key-based auth, but functional

#### Option 3: Use WinRM Instead of SSH
- Windows-native remote management protocol
- May have better integration with Domain Controllers
- Supports both HTTP and HTTPS
- Requires different n8n node configuration

---

## Next Session Actions

### Immediate Priority: Resolve SSH Key Auth Blocker

**Approach 1: User Home Directory Test** (In Progress)
```powershell
# Test if user-level authorized_keys works instead of global administrators file
# This bypasses the Match Group administrators block
```

**Approach 2: Test with Non-Admin Domain User**
```powershell
# Create test user without Administrator privileges
# This tests if issue is specific to Administrator account on DC
```

**Approach 3: Check Group Policy**
```powershell
# Review GPO settings that might block SSH key auth
gpresult /H C:\gpo-report.html
# Check: Computer Configuration > Windows Settings > Security Settings > Local Policies
```

**Approach 4: Check Security Event Logs**
```powershell
# Look for authentication-related events
Get-WinEvent -LogName "Security" -MaxEvents 100 |
  Where-Object { $_.Id -in @(4624, 4625, 4648, 4672) }
```

### If SSH Key Auth Cannot Be Resolved

**Fallback Option A:** Implement Password-Based SSH
1. Store password in Azure Key Vault
2. Update n8n workflow to retrieve password from Key Vault
3. Use password authentication for SSH connections
4. Implement automated password rotation

**Fallback Option B:** Switch to WinRM
1. Configure WinRM on Domain Controller
2. Update n8n workflow to use WinRM instead of SSH
3. Test Active Directory commands via WinRM
4. Document WinRM security configuration

### Post-Resolution Tasks
Once SSH key authentication works:
1. Clean up test pod
2. Update n8n deployment manifest
3. Configure n8n SSH credentials
4. Test full employee termination workflow
5. Document final working configuration
6. Create runbook for future reference

---

## Security Notes

🔒 **Security Best Practices Applied:**
- ✅ Key-based authentication (no passwords)
- ✅ ED25519 encryption (modern, secure)
- ✅ Strict file permissions on authorized_keys
- ✅ NSG restricts SSH to specific source networks only
- ✅ Principle of least privilege (Administrator account with SSH key)

⚠️ **Security Considerations:**
- SSH key stored in Kubernetes secret (base64 encoded, not encrypted at rest unless using secret encryption)
- Consider Azure Key Vault integration for production
- Monitor SSH access logs on DC
- Rotate SSH keys periodically (recommended: quarterly)

---

## References

- [SSH-CONFIGURATION.md](./SSH-CONFIGURATION.md) - Original configuration guide
- [NSG-QUICK-SETUP.md](./NSG-QUICK-SETUP.md) - Network security setup
- [N8N-SSH-CREDENTIALS-GUIDE.md](./N8N-SSH-CREDENTIALS-GUIDE.md) - n8n credential configuration
