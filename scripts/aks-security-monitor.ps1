# AKS Security Posture Monitoring Script
# Tracks security improvements and compliance status

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg_prod",

    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "dev-aks",

    [Parameter(Mandatory=$false)]
    [switch]$Continuous = $false,

    [Parameter(Mandatory=$false)]
    [int]$IntervalSeconds = 60
)

function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

function Get-SecurityScore {
    param($cluster, $nodepools)

    $score = 0
    $maxScore = 100
    $findings = @()

    # Check each security control (10 points each)

    # 1. Private cluster
    if ($cluster.apiServerAccessProfile.enablePrivateCluster) {
        $score += 10
        $findings += "[OK] Private cluster enabled"
    } else {
        $findings += "[X] Public API server exposed"
    }

    # 2. RBAC
    if ($cluster.enableRbac) {
        $score += 10
        $findings += "[OK] RBAC enabled"
    } else {
        $findings += "[X] RBAC disabled"
    }

    # 3. Azure AD integration
    if ($cluster.aadProfile.managed) {
        $score += 10
        $findings += "[OK] Azure AD integrated"
    } else {
        $findings += "[X] No Azure AD integration"
    }

    # 4. Network policy
    if ($cluster.networkProfile.networkPolicy) {
        $score += 10
        $findings += "[OK] Network policy configured ($($cluster.networkProfile.networkPolicy))"
    } else {
        $findings += "[X] No network policy"
    }

    # 5. Workload identity
    if ($cluster.securityProfile.workloadIdentity.enabled) {
        $score += 10
        $findings += "[OK] Workload identity enabled"
    } else {
        $findings += "[X] Workload identity disabled"
    }

    # 6. Defender for Cloud
    if ($cluster.securityProfile.defender) {
        $score += 10
        $findings += "[OK] Microsoft Defender enabled"
    } else {
        $findings += "[X] Microsoft Defender disabled"
    }

    # 7. Key Vault integration
    if ($cluster.addonProfiles.azureKeyvaultSecretsProvider.enabled) {
        $score += 10
        $findings += "[OK] Key Vault secrets provider enabled"
    } else {
        $findings += "[X] No Key Vault integration"
    }

    # 8. Autoscaling
    $hasAutoscaling = $false
    foreach ($pool in $nodepools) {
        if ($pool.enableAutoScaling) {
            $hasAutoscaling = $true
            break
        }
    }
    if ($hasAutoscaling) {
        $score += 10
        $findings += "[OK] Autoscaling configured"
    } else {
        $findings += "[X] No autoscaling"
    }

    # 9. High availability (multiple nodes)
    $totalNodes = 0
    foreach ($pool in $nodepools) {
        $totalNodes += $pool.count
    }
    if ($totalNodes -ge 3) {
        $score += 10
        $findings += "[OK] High availability ($totalNodes nodes)"
    } else {
        $findings += "[X] Low availability ($totalNodes nodes)"
    }

    # 10. Latest Kubernetes version
    $latestVersion = "1.33"
    if ($cluster.kubernetesVersion.StartsWith($latestVersion)) {
        $score += 10
        $findings += "[OK] Latest Kubernetes version ($($cluster.kubernetesVersion))"
    } else {
        $findings += "[X] Outdated Kubernetes ($($cluster.kubernetesVersion))"
    }

    return @{
        Score = $score
        MaxScore = $maxScore
        Percentage = [math]::Round(($score / $maxScore) * 100, 1)
        Findings = $findings
    }
}

function Get-RiskLevel {
    param($percentage)

    if ($percentage -ge 90) { return "LOW", "Green" }
    elseif ($percentage -ge 70) { return "MEDIUM", "Yellow" }
    elseif ($percentage -ge 50) { return "HIGH", "DarkYellow" }
    else { return "CRITICAL", "Red" }
}

function Show-Dashboard {
    param($cluster, $nodepools, $extensions)

    Clear-Host
    Write-Info "================================================================"
    Write-Info "             AKS SECURITY POSTURE DASHBOARD                    "
    Write-Info "================================================================"
    Write-Host ""

    # Basic info
    Write-Info "CLUSTER INFORMATION"
    Write-Host "  Name:              $($cluster.name)"
    Write-Host "  Resource Group:    $($cluster.resourceGroup)"
    Write-Host "  Location:          $($cluster.location)"
    Write-Host "  Kubernetes:        $($cluster.kubernetesVersion)"
    Write-Host "  Provisioning:      $($cluster.provisioningState)"
    Write-Host ""

    # Security score
    $security = Get-SecurityScore -cluster $cluster -nodepools $nodepools
    $riskLevel, $riskColor = Get-RiskLevel -percentage $security.Percentage

    Write-Info "SECURITY SCORE"
    Write-Host "  Score:             " -NoNewline
    Write-Host "$($security.Score)/$($security.MaxScore) ($($security.Percentage)%)" -ForegroundColor $riskColor
    Write-Host "  Risk Level:        " -NoNewline
    Write-Host $riskLevel -ForegroundColor $riskColor
    Write-Host ""

    # Security findings
    Write-Info "SECURITY CONTROLS"
    foreach ($finding in $security.Findings) {
        if ($finding.StartsWith("[OK]")) {
            Write-Success "  $finding"
        } else {
            Write-Error "  $finding"
        }
    }
    Write-Host ""

    # Node pools status
    Write-Info "NODE POOLS"
    foreach ($pool in $nodepools) {
        Write-Host "  $($pool.name):" -NoNewline
        Write-Host " $($pool.count) nodes" -NoNewline
        Write-Host " ($($pool.vmSize))" -NoNewline

        if ($pool.enableAutoScaling) {
            Write-Host " [Autoscaling: $($pool.minCount)-$($pool.maxCount)]" -ForegroundColor Green -NoNewline
        } else {
            Write-Host " [No autoscaling]" -ForegroundColor Yellow -NoNewline
        }

        if ($pool.orchestratorVersion -eq $cluster.kubernetesVersion) {
            Write-Host " [OK]" -ForegroundColor Green
        } else {
            Write-Host " [WARN] v$($pool.orchestratorVersion)" -ForegroundColor Yellow
        }
    }
    Write-Host ""

    # Extensions
    Write-Info "EXTENSIONS & ADDONS"
    $backupFound = $false
    foreach ($ext in $extensions) {
        if ($ext.name -eq "azure-aks-backup") {
            $backupFound = $true
            Write-Success "  [OK] Azure Backup: $($ext.provisioningState)"
        }
    }
    if (-not $backupFound) {
        Write-Error "  [X] Azure Backup: Not configured"
    }

    if ($cluster.addonProfiles.omsAgent.enabled) {
        Write-Success "  [OK] Azure Monitor: Enabled"
    } else {
        Write-Error "  [X] Azure Monitor: Disabled"
    }

    if ($cluster.addonProfiles.azurepolicy.enabled) {
        Write-Success "  [OK] Azure Policy: Enabled"
    } else {
        Write-Error "  [X] Azure Policy: Disabled"
    }

    Write-Host ""

    # Recommendations
    if ($security.Percentage -lt 100) {
        Write-Warning "TOP RECOMMENDATIONS"

        $recommendations = @()
        if (-not $cluster.securityProfile.defender) {
            $recommendations += "Enable Microsoft Defender for Cloud"
        }
        if (-not $hasAutoscaling) {
            $recommendations += "Configure cluster autoscaling"
        }
        if ($totalNodes -lt 3) {
            $recommendations += "Add more nodes for high availability"
        }
        if (-not $backupFound) {
            $recommendations += "Configure Azure Backup for AKS"
        }

        $i = 1
        foreach ($rec in $recommendations | Select-Object -First 3) {
            Write-Warning "  $i. $rec"
            $i++
        }
    }

    Write-Host ""
    Write-Info "----------------------------------------------------------------"
    Write-Host "Last updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
}

# Main monitoring loop
do {
    try {
        # Get cluster info
        $cluster = az aks show --resource-group $ResourceGroup --name $ClusterName 2>$null | ConvertFrom-Json
        if (-not $cluster) {
            Write-Error "Failed to get cluster information"
            exit 1
        }

        # Get node pools
        $nodepools = az aks nodepool list --resource-group $ResourceGroup --cluster-name $ClusterName 2>$null | ConvertFrom-Json

        # Get extensions
        $extensions = az k8s-extension list --cluster-name $ClusterName --resource-group $ResourceGroup --cluster-type managedClusters 2>$null | ConvertFrom-Json

        # Display dashboard
        Show-Dashboard -cluster $cluster -nodepools $nodepools -extensions $extensions

        if ($Continuous) {
            Write-Host "Refreshing in $IntervalSeconds seconds... (Press Ctrl+C to stop)" -ForegroundColor DarkGray
            Start-Sleep -Seconds $IntervalSeconds
        }
    } catch {
        Write-Error "Error: $_"
        if ($Continuous) {
            Write-Host "Retrying in $IntervalSeconds seconds..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $IntervalSeconds
        } else {
            exit 1
        }
    }
} while ($Continuous)

# Export option
Write-Host ""
$export = Read-Host "Export detailed report to file? (y/N)"
if ($export -eq 'y') {
    $reportPath = ".\aks-security-status-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

    $report = @{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Cluster = $cluster.name
        ResourceGroup = $cluster.resourceGroup
        SecurityScore = $security
        RiskLevel = $riskLevel
        NodePools = $nodepools
        Extensions = $extensions
    }

    $report | ConvertTo-Json -Depth 10 | Out-File $reportPath
    Write-Success "Report exported to: $reportPath"
}