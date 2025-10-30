# Manual Role Assignment for n8n Key Vault Access

## Issue
Azure CLI experiencing session errors when attempting to assign "Key Vault Secrets User" role to managed identity.

## Solution: Use Azure Portal

### Steps:

1. **Navigate to Key Vault**
   - Go to: https://portal.azure.com
   - Search for `iius-akv` in the top search bar
   - Click on the Key Vault

2. **Open Access Control**
   - Click **Access control (IAM)** in the left navigation menu

3. **Add Role Assignment**
   - Click **+ Add** button (top of page)
   - Select **Add role assignment**

4. **Select Role**
   - In the "Role" tab, search for: `Key Vault Secrets User`
   - Click on "Key Vault Secrets User" role
   - Click **Next** button

5. **Add Member**
   - In the "Members" tab:
     - Ensure "User, group, or service principal" is selected
     - Click **+ Select members**
     - In the search box, type: `n8n-keyvault-identity`
     - Click on the identity when it appears
     - Click **Select** button at the bottom
   - Click **Next**

6. **Review and Assign**
   - Review the details:
     - Role: Key Vault Secrets User
     - Scope: iius-akv
     - Member: n8n-keyvault-identity
   - Click **Review + assign**
   - Click **Review + assign** again (confirmation)

7. **Verify**
   - You should see a green notification: "Added role assignment"
   - The role should appear in the "Role assignments" tab

---

## Verification Command

After completing the portal steps, verify with:

```bash
az role assignment list \
  --scope "/subscriptions/a78954fe-f6fe-4279-8be0-2c748be2f266/resourceGroups/rg_prod/providers/Microsoft.KeyVault/vaults/iius-akv" \
  --query "[?principalId=='9c1b71c4-7355-47ad-8e17-49d1e49aeb65'].{Role:roleDefinitionName, Principal:principalType}" \
  -o table
```

Expected output:
```
Role                      Principal
------------------------  ----------------
Key Vault Secrets User    ServicePrincipal
```

---

## Details for Reference

- **Key Vault**: `iius-akv`
- **Managed Identity**: `n8n-keyvault-identity`
- **Principal ID**: `9c1b71c4-7355-47ad-8e17-49d1e49aeb65`
- **Client ID**: `0fe8a0d0-1aa7-4ce4-aaba-4a84bbd90769`
- **Role**: `Key Vault Secrets User`
- **Scope**: `/subscriptions/a78954fe-f6fe-4279-8be0-2c748be2f266/resourceGroups/rg_prod/providers/Microsoft.KeyVault/vaults/iius-akv`

---

## Next Steps

After role assignment:

1. Wait for n8n pod to restart (may need manual restart due to cluster resources)
2. Test token retrieval from pod
3. Test Key Vault secret access
4. Configure n8n workflow nodes

See: `KEYVAULT-SSH-WORKFLOW.md` for complete workflow configuration.
