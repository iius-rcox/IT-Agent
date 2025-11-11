# Production Deployment Configuration for n8n on AKS
# Run this to configure n8n with production-ready specifications

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "dev-rg",

    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "dev-aks",

    [Parameter(Mandatory=$false)]
    [string]$Namespace = "n8n",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Small", "Medium", "Large", "XLarge")]
    [string]$Size = "Medium",

    [switch]$Deploy,
    [switch]$ShowRecommendations,
    [switch]$EnableAutoScaling
)

Write-Host "`n=== n8n Production Deployment Configuration ===" -ForegroundColor Cyan
Write-Host "Configuring production-ready specifications for n8n" -ForegroundColor Gray

# Define resource profiles based on expected workload
$resourceProfiles = @{
    Small = @{
        Description = "Light workloads, <10 concurrent workflows, <100 executions/hour"
        Resources = @{
            RequestCPU = "250m"
            RequestMemory = "512Mi"
            LimitCPU = "500m"
            LimitMemory = "1Gi"
            NodeMemory = "768"
            Replicas = 1
        }
    }
    Medium = @{
        Description = "Standard workloads, <50 concurrent workflows, <500 executions/hour"
        Resources = @{
            RequestCPU = "500m"
            RequestMemory = "1Gi"
            LimitCPU = "1000m"
            LimitMemory = "2Gi"
            NodeMemory = "1536"
            Replicas = 1
        }
    }
    Large = @{
        Description = "Heavy workloads, <100 concurrent workflows, <1000 executions/hour"
        Resources = @{
            RequestCPU = "1000m"
            RequestMemory = "2Gi"
            LimitCPU = "2000m"
            LimitMemory = "4Gi"
            NodeMemory = "3072"
            Replicas = 2
        }
    }
    XLarge = @{
        Description = "Enterprise workloads, 100+ concurrent workflows, 1000+ executions/hour"
        Resources = @{
            RequestCPU = "2000m"
            RequestMemory = "4Gi"
            LimitCPU = "4000m"
            LimitMemory = "8Gi"
            NodeMemory = "6144"
            Replicas = 3
        }
    }
}

# Show recommendations
if ($ShowRecommendations) {
    Write-Host "`n=== Resource Profile Recommendations ===" -ForegroundColor Yellow

    foreach ($profile in $resourceProfiles.GetEnumerator()) {
        Write-Host "`n$($profile.Key) Profile:" -ForegroundColor Cyan
        Write-Host "  Description: $($profile.Value.Description)" -ForegroundColor White
        Write-Host "  CPU Request: $($profile.Value.Resources.RequestCPU)" -ForegroundColor Gray
        Write-Host "  CPU Limit: $($profile.Value.Resources.LimitCPU)" -ForegroundColor Gray
        Write-Host "  Memory Request: $($profile.Value.Resources.RequestMemory)" -ForegroundColor Gray
        Write-Host "  Memory Limit: $($profile.Value.Resources.LimitMemory)" -ForegroundColor Gray
        Write-Host "  Replicas: $($profile.Value.Resources.Replicas)" -ForegroundColor Gray
    }

    Write-Host "`n=== Production Best Practices ===" -ForegroundColor Green
    Write-Host "• Use external PostgreSQL/MySQL instead of SQLite"
    Write-Host "• Enable webhook authentication (N8N_WEBHOOK_JWT_AUTH)"
    Write-Host "• Set up proper backup strategy for database"
    Write-Host "• Configure monitoring with Azure Monitor or Prometheus"
    Write-Host "• Use Azure Key Vault for sensitive credentials"
    Write-Host "• Enable HTTPS with proper SSL certificates"
    Write-Host "• Configure autoscaling based on CPU/memory metrics"
    Write-Host "• Set up proper logging to Azure Log Analytics"

    return
}

# Deploy configuration
if ($Deploy) {
    Write-Host "`n=== Deploying n8n with $Size Profile ===" -ForegroundColor Yellow

    $profile = $resourceProfiles[$Size]
    Write-Host "Profile: $($profile.Description)" -ForegroundColor Cyan

    # Connect to AKS
    Write-Host "`nConnecting to AKS cluster..." -ForegroundColor Yellow
    az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing

    # Create production deployment manifest
    $deploymentYaml = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: $Namespace
spec:
  replicas: $($profile.Resources.Replicas)
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
        environment: production
        workload-identity: enabled
    spec:
      serviceAccountName: n8n-workload-identity
      containers:
      - name: n8n
        image: n8nio/n8n:latest
        ports:
        - containerPort: 5678
        env:
        - name: N8N_PORT
          value: "5678"
        - name: N8N_HOST
          value: "0.0.0.0"
        - name: NODE_ENV
          value: "production"
        - name: EXECUTIONS_PROCESS
          value: "main"
        - name: N8N_METRICS
          value: "true"
        - name: N8N_METRICS_INCLUDE_DEFAULT_METRICS
          value: "true"
        - name: N8N_LOG_LEVEL
          value: "info"
        - name: N8N_LOG_OUTPUT
          value: "console"
        - name: NODE_OPTIONS
          value: "--max-old-space-size=$($profile.Resources.NodeMemory)"
        - name: N8N_PERSONALIZATION_ENABLED
          value: "false"
        - name: N8N_VERSION_NOTIFICATIONS_ENABLED
          value: "true"
        - name: N8N_DIAGNOSTICS_ENABLED
          value: "false"
        - name: GENERIC_TIMEZONE
          value: "America/Los_Angeles"
        - name: N8N_DEFAULT_BINARY_DATA_MODE
          value: "filesystem"
        - name: N8N_PAYLOAD_SIZE_MAX
          value: "16"
        - name: N8N_METRICS_PREFIX
          value: "n8n_"
        - name: WEBHOOK_URL
          value: "https://your-domain.com/"
        - name: N8N_WEBHOOK_JWT_AUTH
          value: "true"
        resources:
          requests:
            memory: "$($profile.Resources.RequestMemory)"
            cpu: "$($profile.Resources.RequestCPU)"
          limits:
            memory: "$($profile.Resources.LimitMemory)"
            cpu: "$($profile.Resources.LimitCPU)"
        volumeMounts:
        - name: n8n-data
          mountPath: /home/node/.n8n
        - name: n8n-files
          mountPath: /files
        livenessProbe:
          httpGet:
            path: /healthz
            port: 5678
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /healthz
            port: 5678
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
      volumes:
      - name: n8n-data
        persistentVolumeClaim:
          claimName: n8n-data-pvc
      - name: n8n-files
        persistentVolumeClaim:
          claimName: n8n-files-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: n8n
  namespace: $Namespace
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 5678
    protocol: TCP
    name: http
  selector:
    app: n8n
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: n8n-data-pvc
  namespace: $Namespace
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: managed-premium
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: n8n-files-pvc
  namespace: $Namespace
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: managed-premium
  resources:
    requests:
      storage: 20Gi
"@

    # Save deployment file
    $deploymentFile = ".\n8n-production-deployment.yaml"
    $deploymentYaml | Out-File $deploymentFile -Encoding ASCII
    Write-Host "Deployment manifest saved to: $deploymentFile" -ForegroundColor Green

    # Apply deployment
    Write-Host "`nApplying deployment..." -ForegroundColor Cyan
    kubectl apply -f $deploymentFile

    # Wait for deployment
    Write-Host "`nWaiting for deployment to be ready..." -ForegroundColor Yellow
    kubectl wait --for=condition=available deployment/n8n -n $Namespace --timeout=300s

    Write-Host "`n✅ Deployment complete!" -ForegroundColor Green

    # Get service details
    Write-Host "`n=== Service Details ===" -ForegroundColor Cyan
    kubectl get service n8n -n $Namespace

    $externalIP = kubectl get service n8n -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    if ($externalIP) {
        Write-Host "`nn8n is accessible at: http://$externalIP" -ForegroundColor Green
    } else {
        Write-Host "`nWaiting for external IP assignment..." -ForegroundColor Yellow
        Write-Host "Run: kubectl get service n8n -n $Namespace" -ForegroundColor Gray
    }
}

# Enable autoscaling
if ($EnableAutoScaling) {
    Write-Host "`n=== Configuring Horizontal Pod Autoscaler ===" -ForegroundColor Yellow

    $hpaYaml = @"
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: n8n-hpa
  namespace: $Namespace
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: n8n
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
"@

    $hpaFile = ".\n8n-hpa.yaml"
    $hpaYaml | Out-File $hpaFile -Encoding ASCII

    kubectl apply -f $hpaFile
    Write-Host "✅ Autoscaling configured!" -ForegroundColor Green
    Write-Host "HPA will scale between 1 and 5 replicas based on CPU/Memory usage" -ForegroundColor Gray
}

# Display quick patch for existing deployment
if (!$Deploy -and !$ShowRecommendations -and !$EnableAutoScaling) {
    Write-Host "`n=== Quick Production Patch for Existing Deployment ===" -ForegroundColor Yellow

    $profile = $resourceProfiles[$Size]
    Write-Host "Patching with $Size profile: $($profile.Description)" -ForegroundColor Cyan

    # Connect to AKS
    az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing

    # Create production patch
    $patch = @"
{
  "spec": {
    "replicas": $($profile.Resources.Replicas),
    "template": {
      "spec": {
        "containers": [
          {
            "name": "n8n",
            "resources": {
              "requests": {
                "memory": "$($profile.Resources.RequestMemory)",
                "cpu": "$($profile.Resources.RequestCPU)"
              },
              "limits": {
                "memory": "$($profile.Resources.LimitMemory)",
                "cpu": "$($profile.Resources.LimitCPU)"
              }
            },
            "env": [
              {
                "name": "NODE_OPTIONS",
                "value": "--max-old-space-size=$($profile.Resources.NodeMemory)"
              },
              {
                "name": "NODE_ENV",
                "value": "production"
              },
              {
                "name": "N8N_LOG_LEVEL",
                "value": "info"
              }
            ]
          }
        ]
      }
    }
  }
}
"@

    Write-Host "`nApplying production patch..." -ForegroundColor Cyan
    $patch | kubectl patch deployment n8n -n $Namespace --type merge -p -

    Write-Host "`n✅ Production patch applied!" -ForegroundColor Green
    Write-Host "Pod will restart with new specifications" -ForegroundColor Gray

    # Monitor rollout
    Write-Host "`nMonitoring rollout status..." -ForegroundColor Yellow
    kubectl rollout status deployment/n8n -n $Namespace --timeout=300s

    # Show pod status
    Write-Host "`n=== Pod Status ===" -ForegroundColor Cyan
    kubectl get pods -n $Namespace -l app=n8n

    # Show resource usage after restart
    Start-Sleep -Seconds 10
    Write-Host "`n=== Resource Usage ===" -ForegroundColor Cyan
    kubectl top pod -n $Namespace -l app=n8n
}

Write-Host "`n=== Available Commands ===" -ForegroundColor Magenta
Write-Host "Show resource recommendations:" -ForegroundColor White
Write-Host "  .\deploy-n8n-production.ps1 -ShowRecommendations" -ForegroundColor Gray
Write-Host ""
Write-Host "Quick patch existing deployment:" -ForegroundColor White
Write-Host "  .\deploy-n8n-production.ps1 -Size Medium" -ForegroundColor Gray
Write-Host "  .\deploy-n8n-production.ps1 -Size Large" -ForegroundColor Gray
Write-Host ""
Write-Host "Full production deployment:" -ForegroundColor White
Write-Host "  .\deploy-n8n-production.ps1 -Deploy -Size Large" -ForegroundColor Gray
Write-Host ""
Write-Host "Enable autoscaling:" -ForegroundColor White
Write-Host "  .\deploy-n8n-production.ps1 -EnableAutoScaling" -ForegroundColor Gray