#!/bin/bash

# Script to clean up executions for the Email Cleaner workflow
# Workflow ID: Wi1V4uQWYJO2jPkG

echo "=========================================="
echo "N8N Email Cleaner Workflow Execution Cleanup"
echo "=========================================="

# Configuration
RESOURCE_GROUP="rg_prod"
CLUSTER_NAME="dev-aks"
NAMESPACE="n8n-prod"
POD_NAME="n8n-f87d558fc-z4b9s"
WORKFLOW_ID="Wi1V4uQWYJO2jPkG"

echo "Target Workflow: Email Cleaner (ID: $WORKFLOW_ID)"
echo ""

# Step 1: Check current database size
echo "Step 1: Checking current database size..."
az aks command invoke --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
  --command "kubectl exec -n $NAMESPACE $POD_NAME -- ls -lah /home/node/.n8n/database.sqlite" \
  --no-wait false

# Step 2: Count executions for this workflow
echo ""
echo "Step 2: Counting executions for Email Cleaner workflow..."
echo "This may take a moment due to the large database size..."

# Create a temporary SQL script in the pod
az aks command invoke --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
  --command "kubectl exec -n $NAMESPACE $POD_NAME -- sh -c 'cat > /tmp/count_executions.sql << EOF
SELECT
  \"Email Cleaner Executions:\" as Label,
  COUNT(*) as Count
FROM execution_entity
WHERE workflowId = \"$WORKFLOW_ID\";
EOF'"

# Run the count query using n8n's built-in sqlite
az aks command invoke --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
  --command "kubectl exec -n $NAMESPACE $POD_NAME -- sh -c 'cd /home/node/.n8n && node -e \"
const Database = require(\047better-sqlite3\047);
const db = new Database(\047database.sqlite\047, { readonly: true });
const result = db.prepare(\047SELECT COUNT(*) as count FROM execution_entity WHERE workflowId = ?\047).get(\047$WORKFLOW_ID\047);
console.log(\047Email Cleaner executions to delete: \047 + result.count);
db.close();
\" 2>/dev/null || echo \"Could not count executions - database may be locked\"'" \
  --no-wait false

# Step 3: Backup warning
echo ""
echo "⚠️  WARNING: This will permanently delete all executions for the Email Cleaner workflow!"
echo "It's recommended to backup the database first."
echo ""
read -p "Do you want to proceed with deletion? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Operation cancelled."
    exit 1
fi

# Step 4: Delete executions for this workflow
echo ""
echo "Step 3: Deleting Email Cleaner executions..."
echo "This may take several minutes..."

# Create deletion SQL script
az aks command invoke --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
  --command "kubectl exec -n $NAMESPACE $POD_NAME -- sh -c 'cat > /tmp/delete_executions.sql << EOF
-- Delete execution data for Email Cleaner workflow
DELETE FROM execution_entity WHERE workflowId = \"$WORKFLOW_ID\";
VACUUM;
EOF'"

# Execute deletion using n8n's database connection
az aks command invoke --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
  --command "kubectl exec -n $NAMESPACE $POD_NAME -- sh -c 'cd /home/node/.n8n && node -e \"
const Database = require(\047better-sqlite3\047);
const db = new Database(\047database.sqlite\047);
console.log(\047Starting deletion...\047);
try {
  const stmt = db.prepare(\047DELETE FROM execution_entity WHERE workflowId = ?\047);
  const info = stmt.run(\047$WORKFLOW_ID\047);
  console.log(\047Deleted \047 + info.changes + \047 executions\047);
  console.log(\047Running VACUUM to reclaim space...\047);
  db.exec(\047VACUUM\047);
  console.log(\047VACUUM completed\047);
} catch(e) {
  console.error(\047Error: \047 + e.message);
}
db.close();
\"'" \
  --no-wait false

# Step 5: Check new database size
echo ""
echo "Step 4: Checking new database size..."
az aks command invoke --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
  --command "kubectl exec -n $NAMESPACE $POD_NAME -- ls -lah /home/node/.n8n/database.sqlite" \
  --no-wait false

# Step 6: Check disk usage
echo ""
echo "Step 5: Checking disk usage..."
az aks command invoke --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
  --command "kubectl exec -n $NAMESPACE $POD_NAME -- df -h /home/node/.n8n" \
  --no-wait false

echo ""
echo "=========================================="
echo "Cleanup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Monitor the n8n logs to ensure it's working properly"
echo "2. Consider deactivating the Email Cleaner workflow if it's causing issues"
echo "3. Set up automatic execution pruning in n8n environment variables"