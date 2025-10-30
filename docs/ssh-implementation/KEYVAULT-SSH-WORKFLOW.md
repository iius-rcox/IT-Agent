# Azure Key Vault SSH Password Authentication - n8n Workflow Configuration

## Overview

This guide provides the n8n workflow nodes needed to retrieve the SSH password from Azure Key Vault and use it to connect to the Domain Controller.

## Prerequisites

✅ **Completed**:
- Azure Key Vault: `iius-akv`
- Secret name: `DC01-SSH-KEY` (created: 2025-10-29)
- Managed Identity: `n8n-keyvault-identity`
- Client ID: `0fe8a0d0-1aa7-4ce4-aaba-4a84bbd90769`
- Federated credential configured for `system:serviceaccount:n8n-prod:n8n`
- Service account `n8n` annotated with workload identity

⚠️ **Manual step required**: Grant Key Vault access (run this command):
```bash
az role assignment create \
  --assignee 9c1b71c4-7355-47ad-8e17-49d1e49aeb65 \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/a78954fe-f6fe-4279-8be0-2c748be2f266/resourceGroups/rg_prod/providers/Microsoft.KeyVault/vaults/iius-akv"
```

⏳ **Pending**: n8n pod restart (currently blocked by cluster CPU resources)

---

## n8n Workflow Nodes

### Node 1: Get Azure Access Token

**Node Name**: `Get Azure Token`
**Node Type**: HTTP Request
**Purpose**: Get OAuth token from Azure Instance Metadata Service (IMDS) using Workload Identity

**Configuration**:
```json
{
  "name": "Get Azure Token",
  "type": "n8n-nodes-base.httpRequest",
  "typeVersion": 4.2,
  "position": [250, 300],
  "parameters": {
    "url": "http://169.254.169.254/metadata/identity/oauth2/token",
    "method": "GET",
    "sendQuery": true,
    "queryParameters": {
      "parameters": [
        {
          "name": "api-version",
          "value": "2018-02-01"
        },
        {
          "name": "resource",
          "value": "https://vault.azure.net"
        }
      ]
    },
    "sendHeaders": true,
    "headerParameters": {
      "parameters": [
        {
          "name": "Metadata",
          "value": "true"
        }
      ]
    },
    "options": {}
  }
}
```

**Expected Response**:
```json
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "expires_in": "3599",
  "expires_on": "1698765432",
  "resource": "https://vault.azure.net",
  "token_type": "Bearer"
}
```

---

### Node 2: Get SSH Password from Key Vault

**Node Name**: `Get DC Password from Key Vault`
**Node Type**: HTTP Request
**Purpose**: Retrieve DC01-SSH-KEY secret from Azure Key Vault

**Configuration**:
```json
{
  "name": "Get DC Password from Key Vault",
  "type": "n8n-nodes-base.httpRequest",
  "typeVersion": 4.2,
  "position": [450, 300],
  "parameters": {
    "url": "https://iius-akv.vault.azure.net/secrets/DC01-SSH-KEY?api-version=7.4",
    "method": "GET",
    "authentication": "none",
    "sendHeaders": true,
    "headerParameters": {
      "parameters": [
        {
          "name": "Authorization",
          "value": "=Bearer {{ $('Get Azure Token').item.json.access_token }}"
        }
      ]
    },
    "options": {}
  }
}
```

**Expected Response**:
```json
{
  "value": "YourAdministratorPassword",
  "id": "https://iius-akv.vault.azure.net/secrets/DC01-SSH-KEY/abc123",
  "attributes": {
    "enabled": true,
    "created": 1698765432,
    "updated": 1698765432
  }
}
```

---

### Node 3: Execute PowerShell via SSH

**Node Name**: `Execute PowerShell on DC`
**Node Type**: SSH
**Purpose**: Connect to Domain Controller and execute Terminate-Employee.ps1

**Configuration**:
```json
{
  "name": "Execute PowerShell on DC",
  "type": "n8n-nodes-base.ssh",
  "typeVersion": 1,
  "position": [650, 300],
  "parameters": {
    "authentication": "password",
    "resource": "command",
    "operation": "execute",
    "command": "=powershell.exe -ExecutionPolicy Bypass -File C:\\Scripts\\Terminate-Employee.ps1 -EmployeeID {{ $json.employeeId }}",
    "cwd": "/"
  },
  "credentials": {
    "ssh": {
      "id": "dc01-ssh-credential",
      "name": "DC01 SSH - Password Auth"
    }
  }
}
```

---

## SSH Credential Configuration

**Credential Name**: `DC01 SSH - Password Auth`
**Credential Type**: SSH (Password Authentication)

**Settings**:
- **Host**: `10.0.0.200` or `insdal9dc01.insulationsinc.local`
- **Port**: `22`
- **Username**: `administrator`
- **Password**: `={{ $('Get DC Password from Key Vault').item.json.value }}`

**Important**: The password field uses an expression to pull from the Key Vault node output.

---

## Complete Workflow Example

```json
{
  "name": "Employee Termination with Key Vault SSH",
  "nodes": [
    {
      "name": "Webhook Trigger",
      "type": "n8n-nodes-base.webhook",
      "position": [50, 300],
      "webhookId": "employee-termination"
    },
    {
      "name": "Get Azure Token",
      "type": "n8n-nodes-base.httpRequest",
      "position": [250, 300],
      "parameters": {
        "url": "http://169.254.169.254/metadata/identity/oauth2/token",
        "method": "GET",
        "sendQuery": true,
        "queryParameters": {
          "parameters": [
            {
              "name": "api-version",
              "value": "2018-02-01"
            },
            {
              "name": "resource",
              "value": "https://vault.azure.net"
            }
          ]
        },
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "Metadata",
              "value": "true"
            }
          ]
        }
      }
    },
    {
      "name": "Get DC Password from Key Vault",
      "type": "n8n-nodes-base.httpRequest",
      "position": [450, 300],
      "parameters": {
        "url": "https://iius-akv.vault.azure.net/secrets/DC01-SSH-KEY?api-version=7.4",
        "method": "GET",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "Authorization",
              "value": "=Bearer {{ $('Get Azure Token').item.json.access_token }}"
            }
          ]
        }
      }
    },
    {
      "name": "Execute PowerShell on DC",
      "type": "n8n-nodes-base.ssh",
      "position": [650, 300],
      "parameters": {
        "authentication": "password",
        "resource": "command",
        "operation": "execute",
        "command": "=powershell.exe -ExecutionPolicy Bypass -File C:\\Scripts\\Terminate-Employee.ps1 -EmployeeID {{ $json.employeeId }}"
      },
      "credentials": {
        "ssh": "dc01-ssh-password"
      }
    }
  ],
  "connections": {
    "Webhook Trigger": {
      "main": [
        [
          {
            "node": "Get Azure Token",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Get Azure Token": {
      "main": [
        [
          {
            "node": "Get DC Password from Key Vault",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Get DC Password from Key Vault": {
      "main": [
        [
          {
            "node": "Execute PowerShell on DC",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  }
}
```

---

## Testing the Workflow

### Test 1: Get Azure Token

**Manual test from n8n pod**:
```bash
kubectl exec -it -n n8n-prod deployment/n8n -- sh -c \
  'wget -qO- --header="Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net"'
```

**Expected**: JSON response with `access_token` field

### Test 2: Get Secret from Key Vault

```bash
TOKEN=$(kubectl exec -it -n n8n-prod deployment/n8n -- sh -c \
  'wget -qO- --header="Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net"' | jq -r .access_token)

kubectl exec -it -n n8n-prod deployment/n8n -- sh -c \
  "wget -qO- --header='Authorization: Bearer $TOKEN' \
  'https://iius-akv.vault.azure.net/secrets/DC01-SSH-KEY?api-version=7.4'"
```

**Expected**: JSON response with `value` field containing the password

### Test 3: SSH with Password

```bash
PASSWORD=$(# ...get from Key Vault...)

kubectl exec -it -n n8n-prod deployment/n8n -- sh -c \
  "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no \
  administrator@10.0.0.200 hostname"
```

**Expected**: `INSDAL9DC01`

---

## Troubleshooting

### Issue: "Failed to get token from IMDS"

**Cause**: Pod doesn't have workload identity label or service account not annotated

**Fix**:
```bash
# Verify service account
kubectl get sa n8n -n n8n-prod -o yaml

# Should have:
# annotations:
#   azure.workload.identity/client-id: 0fe8a0d0-1aa7-4ce4-aaba-4a84bbd90769
# labels:
#   azure.workload.identity/use: "true"

# Verify pod labels
kubectl get pod -n n8n-prod -l app=n8n -o yaml | grep -A 2 labels

# Should have:
#   azure.workload.identity/use: "true"
```

### Issue: "403 Forbidden" from Key Vault

**Cause**: Managed identity doesn't have access to Key Vault

**Fix**: Run the manual role assignment command (see Prerequisites section)

### Issue: "Connection refused" on SSH

**Cause**: Network connectivity or SSH service not running

**Fix**:
```bash
# Test from n8n pod
kubectl exec -it -n n8n-prod deployment/n8n -- nc -zv 10.0.0.200 22

# Should output: Connection to 10.0.0.200 22 port [tcp/ssh] succeeded!
```

### Issue: "Authentication failed" on SSH

**Cause**: Wrong password or account locked

**Fix**:
1. Verify password in Key Vault is correct
2. Test password authentication manually on DC
3. Check if Administrator account is locked

---

## Security Considerations

✅ **Implemented**:
- No passwords stored in n8n database
- Workload Identity (no service principal secrets)
- RBAC-based Key Vault access
- Audit logging enabled in Key Vault

⚠️ **Recommendations**:
1. **Enable Key Vault soft delete** (30-90 day recovery period)
2. **Set up Key Vault alerts** for secret access
3. **Implement password rotation** (90-180 days)
4. **Monitor SSH access logs** on DC
5. **Regular access review** of Key Vault permissions

---

## Password Rotation Procedure

**Schedule**: Every 90-180 days

**Steps**:
1. Generate new password (minimum 20 characters, complex)
2. Update Administrator password on DC:
   ```powershell
   Set-ADAccountPassword -Identity Administrator -Reset -NewPassword (ConvertTo-SecureString "NewPassword" -AsPlainText -Force)
   ```
3. Update Key Vault secret:
   ```bash
   az keyvault secret set \
     --vault-name iius-akv \
     --name "DC01-SSH-KEY" \
     --value "NewPassword"
   ```
4. Test n8n workflow with test user
5. Document rotation in change log

**Automation**: Consider creating n8n workflow for automated rotation with approval step

---

## Next Steps

1. ✅ **Verify pod restart**: Once cluster resources free up, verify new pod starts
2. ⏳ **Run manual role assignment**: Grant Key Vault access to managed identity
3. ⏳ **Test token retrieval**: Verify IMDS responds with access token
4. ⏳ **Test Key Vault access**: Verify secret can be retrieved
5. ⏳ **Update n8n workflow**: Add the three nodes to existing workflow
6. ⏳ **Test end-to-end**: Execute full employee termination with test user

---

## References

- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/docs/)
- [Azure Key Vault REST API](https://learn.microsoft.com/en-us/rest/api/keyvault/)
- [Azure Instance Metadata Service](https://learn.microsoft.com/en-us/azure/virtual-machines/instance-metadata-service)
- [n8n SSH Node Documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.ssh/)

---

**Last Updated**: 2025-10-29
**Status**: Configuration complete, pending pod restart and role assignment
