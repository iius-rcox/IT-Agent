# Fix AKS Resource Constraints for n8n Pod
# Quickest path to get workload identity enabled

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "dev-rg",

    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "dev-aks",

    [Parameter(Mandatory=$false)]
    [string]$Namespace = "n8n",

    [switch]$QuickFix,
    [switch]$ScaleNodes,
    [switch]$CleanupPods
)

Write-Host "`n=== AKS Resource Fix for n8n Pod ===" -ForegroundColor Cyan
Write-Host "Goal: Free up resources to restart n8n pod with workload identity" -ForegroundColor Gray

# Connect to AKS
Write-Host "`nConnecting to AKS cluster..." -ForegroundColor Yellow
az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing

# Option 1: Quick Fix - Remove resource limits temporarily
if ($QuickFix) {
    Write-Host "`n=== QUICK FIX: Patch n8n Deployment ===" -ForegroundColor Yellow
    Write-Host "Setting production-ready resource specifications..." -ForegroundColor Cyan

    # Production-ready specifications for n8n
    # n8n can be memory intensive with large workflows and concurrent executions
    $patch = @'
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "n8n",
            "resources": {
              "requests": {
                "memory": "1Gi",
                "cpu": "500m"
              },
              "limits": {
                "memory": "2Gi",
                "cpu": "1000m"
              }
            },
            "env": [
              {
                "name": "NODE_OPTIONS",
                "value": "--max-old-space-size=1536"
              }
            ]
          }
        ]
      }
    }
  }
}
'@

    # Apply patch
    $patch | kubectl patch deployment n8n -n $Namespace --type merge -p -

    Write-Host "Deployment patched. Pod will restart automatically..." -ForegroundColor Green
    Write-Host "Waiting for pod to be ready..." -ForegroundColor Cyan

    kubectl wait --for=condition=ready pod -l app=n8n -n $Namespace --timeout=300s

    Write-Host "`nPod restarted successfully!" -ForegroundColor Green
    Write-Host "Workload identity should now be active." -ForegroundColor Green

    # Verify workload identity
    Write-Host "`nVerifying workload identity..." -ForegroundColor Cyan
    $podName = kubectl get pods -n $Namespace -l app=n8n -o jsonpath='{.items[0].metadata.name}'

    kubectl exec -n $Namespace $podName -- sh -c 'curl -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" | head -c 100'

    Write-Host "`n`nIf you see a token above, workload identity is working!" -ForegroundColor Green
    return
}

# Option 2: Scale nodes
if ($ScaleNodes) {
    Write-Host "`n=== SCALE NODES: Add More Capacity ===" -ForegroundColor Yellow

    # Get current node count
    $nodepool = az aks nodepool show --resource-group $ResourceGroup --cluster-name $ClusterName --name systempool --query "count" -o tsv
    Write-Host "Current node count: $nodepool" -ForegroundColor Cyan

    $newCount = [int]$nodepool + 1
    Write-Host "Scaling to $newCount nodes..." -ForegroundColor Yellow

    az aks nodepool scale --resource-group $ResourceGroup --cluster-name $ClusterName --name systempool --node-count $newCount

    Write-Host "Node scaling initiated. This will take 3-5 minutes..." -ForegroundColor Green
    Write-Host "Run with -QuickFix after scaling completes to restart pod." -ForegroundColor Yellow
    return
}

# Option 3: Cleanup unused pods
if ($CleanupPods) {
    Write-Host "`n=== CLEANUP: Remove Unused Workloads ===" -ForegroundColor Yellow

    Write-Host "`nCurrent resource usage:" -ForegroundColor Cyan
    kubectl top nodes

    Write-Host "`nAll pods across namespaces:" -ForegroundColor Cyan
    kubectl get pods --all-namespaces -o wide | Format-Table

    Write-Host "`nPods using most CPU:" -ForegroundColor Cyan
    kubectl top pods --all-namespaces | Sort-Object -Property "CPU(cores)" -Descending | Select-Object -First 10

    Write-Host "`nCompleted/Failed pods (can be deleted):" -ForegroundColor Yellow
    kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Pending

    Write-Host "`nTo delete completed pods:" -ForegroundColor Green
    Write-Host '  kubectl delete pods --all-namespaces --field-selector=status.phase=Succeeded'
    Write-Host '  kubectl delete pods --all-namespaces --field-selector=status.phase=Failed'

    Write-Host "`nTo delete specific namespace:" -ForegroundColor Green
    Write-Host '  kubectl delete namespace <namespace-name>'

    return
}

# Default: Show current status and options
Write-Host "`n=== Current Cluster Status ===" -ForegroundColor Yellow

# Check cluster status
Write-Host "`nNode Status:" -ForegroundColor Cyan
kubectl get nodes

Write-Host "`nNode Resource Usage:" -ForegroundColor Cyan
kubectl top nodes

Write-Host "`nn8n Pod Status:" -ForegroundColor Cyan
kubectl get pods -n $Namespace

Write-Host "`nn8n Pod Events:" -ForegroundColor Cyan
kubectl describe pod -l app=n8n -n $Namespace | Select-String -Pattern "Events:" -Context 0,20

Write-Host "`n=== Available Options ===" -ForegroundColor Green
Write-Host "1. QUICKEST FIX (Recommended):" -ForegroundColor Cyan
Write-Host "   .\fix-aks-resources.ps1 -QuickFix" -ForegroundColor White
Write-Host "   This patches the deployment to reduce CPU requirements temporarily" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Add more nodes (if QuickFix fails):" -ForegroundColor Cyan
Write-Host "   .\fix-aks-resources.ps1 -ScaleNodes" -ForegroundColor White
Write-Host "   Adds another node to the cluster (takes 3-5 minutes)" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Cleanup unused resources:" -ForegroundColor Cyan
Write-Host "   .\fix-aks-resources.ps1 -CleanupPods" -ForegroundColor White
Write-Host "   Shows what can be deleted to free resources" -ForegroundColor Gray

Write-Host "`n=== Next Steps After Pod Restart ===" -ForegroundColor Magenta
Write-Host "1. Test Key Vault access from n8n"
Write-Host "2. Configure n8n SSH node with password from Key Vault"
Write-Host "3. Run employee termination workflow"
Write-Host "4. If successful, document the solution"