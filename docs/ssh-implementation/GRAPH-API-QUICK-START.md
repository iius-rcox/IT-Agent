# 🚀 Microsoft Graph API Quick Start

## Your 15-Minute Setup

### Step 1: Check Prerequisites (2 min)
```powershell
cd "C:\Users\rcox\Documents\Cursor Projects\IT-Agent\docs\ssh-implementation"
.\setup-graph-api.ps1 -CheckOnly
```

### Step 2: Auto-Setup (5 min)
```powershell
.\setup-graph-api.ps1 -AutoSetup
```
This will:
- ✅ Create Azure App Registration
- ✅ Set up permissions
- ✅ Generate credentials
- ✅ Test the connection

### Step 3: Configure n8n (3 min)

1. Open n8n web interface
2. Go to **Credentials** → **Add Credential**
3. Search for **"Microsoft OAuth2 API"**
4. Copy values from `graph-api-credentials.txt`:

```yaml
Grant Type: Client Credentials
Client ID: [from file]
Client Secret: [from file]
Access Token URL: [from file]
Scope: https://graph.microsoft.com/.default
```

5. Click **Save**

### Step 4: Test Connection (2 min)

Run the test script:
```powershell
.\test-graph-api-connection.ps1 `
  -TenantId "YOUR-TENANT-ID" `
  -ClientId "YOUR-CLIENT-ID" `
  -ClientSecret "YOUR-CLIENT-SECRET"
```

### Step 5: Import Test Workflow (3 min)

1. Open n8n
2. Create new workflow
3. Import from: `n8n-workflow-examples.json`
4. Select: **"Test - List AD Users"**
5. Execute workflow

---

## ✅ Success Indicators

You'll know it's working when:
1. Test script shows "✅ Can list users"
2. n8n workflow returns user list
3. No permission errors

---

## 🎯 Your First Real Workflow

### Employee Disable Workflow
```json
{
  "name": "Disable Employee",
  "nodes": [
    {
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "disable-employee",
        "method": "POST"
      },
      "position": [250, 300]
    },
    {
      "name": "Disable in Azure AD",
      "type": "n8n-nodes-base.microsoftEntra",
      "parameters": {
        "resource": "user",
        "operation": "update",
        "userId": "={{ $json.employeeEmail }}",
        "updateFields": {
          "accountEnabled": false
        }
      },
      "position": [450, 300]
    }
  ]
}
```

Test with:
```json
POST /webhook/disable-employee
{
  "employeeEmail": "testuser@company.com"
}
```

---

## ⏱️ Sync Timing

- **Azure AD**: Changes immediate
- **On-premises AD**: Syncs in ~30 minutes
- **Force sync**: Run on DC: `Start-ADSyncSyncCycle -PolicyType Delta`

---

## 🔧 Troubleshooting

### "Insufficient privileges"
```powershell
# Re-grant admin consent
az ad app permission admin-consent --id YOUR-CLIENT-ID
```

### "User not found"
```powershell
# Check if user is synced to Azure AD
Get-AzureADUser -Filter "userPrincipalName eq 'user@domain.com'"
```

### "Invalid client secret"
```powershell
# Generate new secret
az ad app credential reset --id YOUR-CLIENT-ID
```

---

## 📞 Next Steps

1. ✅ Setup complete - test with real user
2. ⏳ Create production workflows
3. ⏳ Set up error handling
4. ⏳ Add audit logging
5. ⏳ Schedule secret rotation reminder

---

## 🗑️ Cleanup

After setup is working:
```powershell
# Delete credentials file (contains secrets!)
Remove-Item .\graph-api-credentials.txt
```

---

**Total Setup Time: ~15 minutes**
**Complexity: Low**
**Security: High**

Ready to go! 🎉