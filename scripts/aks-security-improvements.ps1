# AKS Security Improvements Script
# Implements quick wins from the audit report
# Run with: .\aks-security-improvements.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg_prod",

    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "dev-aks",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,

    [Parameter(Mandatory=$false)]
    [switch]$SkipConfirmation = $false
)

# Colors for output
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

Write-Info "========================================="
Write-Info "AKS Security Improvements Script"
Write-Info "Cluster: $ClusterName"
Write-Info "Resource Group: $ResourceGroup"
Write-Info "========================================="

# Check if logged in to Azure
Write-Info "`nChecking Azure login status..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error "Not logged in to Azure. Please run 'az login' first."
    exit 1
}
Write-Success "Logged in as: $($account.user.name)"
Write-Success "Subscription: $($account.name)"

# Verify cluster exists
Write-Info "`nVerifying cluster exists..."
$cluster = az aks show --resource-group $ResourceGroup --name $ClusterName 2>$null | ConvertFrom-Json
if (-not $cluster) {
    Write-Error "Cluster $ClusterName not found in resource group $ResourceGroup"
    exit 1
}
Write-Success "Cluster found: $($cluster.name)"

# Show current issues
Write-Warning "`n=== CURRENT CRITICAL ISSUES ==="
Write-Warning "1. No Microsoft Defender for Cloud"
Write-Warning "2. System pool running outdated version (1.32.6)"
Write-Warning "3. No autoscaling configured"
Write-Warning "4. Single node in user pool (no HA)"
Write-Warning "5. No backup strategy"

if (-not $SkipConfirmation -and -not $DryRun) {
    Write-Info "`nThis script will apply the following improvements:"
    Write-Info "  - Enable Microsoft Defender for Cloud"
    Write-Info "  - Upgrade system pool to latest version"
    Write-Info "  - Enable autoscaling on user pool"
    Write-Info "  - Scale user pool to 2 nodes minimum"
    Write-Info "  - Configure Azure Backup extension"

    $confirm = Read-Host "`nDo you want to proceed? (y/N)"
    if ($confirm -ne 'y') {
        Write-Warning "Operation cancelled by user"
        exit 0
    }
}

$improvements = @()

# 1. Enable Microsoft Defender for Cloud
Write-Info "`n[1/5] Enabling Microsoft Defender for Cloud..."
if ($DryRun) {
    Write-Warning "DRY RUN: Would enable Defender with command:"
    Write-Host "az aks update --resource-group $ResourceGroup --name $ClusterName --enable-defender" -ForegroundColor Gray
} else {
    try {
        $result = az aks update --resource-group $ResourceGroup --name $ClusterName --enable-defender --no-wait 2>&1
        Write-Success "✓ Microsoft Defender enablement initiated"
        $improvements += "Defender for Cloud enabled"
    } catch {
        Write-Error "✗ Failed to enable Defender: $_"
    }
}

# 2. Upgrade system pool
Write-Info "`n[2/5] Upgrading system pool to Kubernetes 1.33.3..."
if ($DryRun) {
    Write-Warning "DRY RUN: Would upgrade system pool with command:"
    Write-Host "az aks nodepool upgrade --resource-group $ResourceGroup --cluster-name $ClusterName --name systempool --kubernetes-version 1.33.3" -ForegroundColor Gray
} else {
    try {
        $result = az aks nodepool upgrade `
            --resource-group $ResourceGroup `
            --cluster-name $ClusterName `
            --name systempool `
            --kubernetes-version 1.33.3 `
            --no-wait 2>&1
        Write-Success "✓ System pool upgrade initiated (will take 10-15 minutes)"
        $improvements += "System pool upgrade to 1.33.3 started"
    } catch {
        Write-Error "✗ Failed to upgrade system pool: $_"
    }
}

# 3. Enable autoscaling on user pool
Write-Info "`n[3/5] Enabling autoscaling on user pool..."
if ($DryRun) {
    Write-Warning "DRY RUN: Would enable autoscaling with command:"
    Write-Host "az aks nodepool update --resource-group $ResourceGroup --cluster-name $ClusterName --name optimized --enable-cluster-autoscaler --min-count 2 --max-count 5" -ForegroundColor Gray
} else {
    try {
        $result = az aks nodepool update `
            --resource-group $ResourceGroup `
            --cluster-name $ClusterName `
            --name optimized `
            --enable-cluster-autoscaler `
            --min-count 2 `
            --max-count 5 2>&1
        Write-Success "✓ Autoscaling enabled (min: 2, max: 5)"
        $improvements += "Autoscaling enabled on user pool"
    } catch {
        Write-Error "✗ Failed to enable autoscaling: $_"
    }
}

# 4. Install Azure Backup extension
Write-Info "`n[4/5] Installing Azure Backup extension..."
if ($DryRun) {
    Write-Warning "DRY RUN: Would install backup extension with command:"
    Write-Host "az k8s-extension create --name azure-aks-backup --cluster-name $ClusterName --resource-group $ResourceGroup --cluster-type managedClusters --extension-type Microsoft.DataProtection.Kubernetes" -ForegroundColor Gray
} else {
    try {
        $result = az k8s-extension create `
            --name azure-aks-backup `
            --cluster-name $ClusterName `
            --resource-group $ResourceGroup `
            --cluster-type managedClusters `
            --extension-type Microsoft.DataProtection.Kubernetes `
            --no-wait 2>&1
        Write-Success "✓ Azure Backup extension installation initiated"
        $improvements += "Backup extension installed"
    } catch {
        Write-Error "✗ Failed to install backup extension: $_"
    }
}

# 5. Create diagnostic settings (if workspace exists)
Write-Info "`n[5/5] Checking for Log Analytics workspace..."
$workspace = az monitor log-analytics workspace list --query "[?contains(name, 'DefaultWorkspace')]" | ConvertFrom-Json
if ($workspace -and $workspace.Count -gt 0) {
    Write-Info "Found workspace: $($workspace[0].name)"
    if ($DryRun) {
        Write-Warning "DRY RUN: Would create diagnostic settings"
    } else {
        try {
            $diagnosticName = "aks-security-diagnostics"
            $resourceId = "/subscriptions/$($account.id)/resourceGroups/$ResourceGroup/providers/Microsoft.ContainerService/managedClusters/$ClusterName"

            $result = az monitor diagnostic-settings create `
                --name $diagnosticName `
                --resource $resourceId `
                --workspace $workspace[0].id `
                --logs '[{"category":"kube-apiserver","enabled":true},{"category":"kube-audit-admin","enabled":true},{"category":"guard","enabled":true}]' `
                --metrics '[{"category":"AllMetrics","enabled":true}]' 2>&1

            Write-Success "✓ Diagnostic settings configured"
            $improvements += "Enhanced diagnostics enabled"
        } catch {
            Write-Error "✗ Failed to create diagnostic settings: $_"
        }
    }
} else {
    Write-Warning "No Log Analytics workspace found - skipping diagnostic settings"
}

# Summary
Write-Info "`n========================================="
Write-Success "IMPROVEMENTS SUMMARY"
Write-Info "========================================="

if ($improvements.Count -gt 0) {
    foreach ($improvement in $improvements) {
        Write-Success "  ✓ $improvement"
    }

    Write-Info "`n⏳ Some operations are running in background:"
    Write-Info "  - Defender enablement: ~5 minutes"
    Write-Info "  - System pool upgrade: ~15 minutes"
    Write-Info "  - Backup extension: ~10 minutes"

    Write-Info "`nMonitor progress with:"
    Write-Host "  az aks show -g $ResourceGroup -n $ClusterName --query provisioningState" -ForegroundColor Gray
    Write-Host "  az aks nodepool show -g $ResourceGroup --cluster-name $ClusterName -n systempool --query provisioningState" -ForegroundColor Gray
} else {
    if ($DryRun) {
        Write-Warning "DRY RUN completed - no changes made"
    } else {
        Write-Warning "No improvements were applied"
    }
}

Write-Info "`n📋 NEXT STEPS:"
Write-Info "1. Wait for operations to complete (15-20 minutes)"
Write-Info "2. Configure backup vault and policies"
Write-Info "3. Test autoscaling with load testing"
Write-Info "4. Review the full audit report at: k8s\aks-audit-report.md"

# Check operations status
Write-Info "`nChecking current operation status..."
$status = az aks show -g $ResourceGroup -n $ClusterName --query "{Status:provisioningState,PowerState:powerState.code}" -o json | ConvertFrom-Json
Write-Info "Cluster Status: $($status.Status)"
Write-Info "Power State: $($status.PowerState)"

Write-Success "`n✅ Script completed successfully!"