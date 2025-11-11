# n8n API Configuration Helper

Write-Host "n8n API Setup Instructions" -ForegroundColor Green
Write-Host "=========================" -ForegroundColor Green
Write-Host ""
Write-Host "1. Open n8n at: https://n8n.ii-us.com"
Write-Host "2. Create your owner account (if not done already)"
Write-Host "3. Go to Settings -> API Settings"
Write-Host "4. Click 'Generate API Key' and copy it"
Write-Host ""

$apiKey = Read-Host "Paste your n8n API key here"

if ($apiKey) {
    # Set environment variable for current session
    $env:N8N_API_KEY = $apiKey

    # Option to set it permanently (user level)
    $setPermanent = Read-Host "Set API key permanently? (Y/N)"
    if ($setPermanent -eq 'Y') {
        [System.Environment]::SetEnvironmentVariable("N8N_API_KEY", $apiKey, [System.EnvironmentVariableTarget]::User)
        Write-Host "API key saved to user environment variables" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "API key configured for this session!" -ForegroundColor Green
    Write-Host "You can now use the n8n MCP server with this key." -ForegroundColor Green

    # Test the connection
    Write-Host ""
    Write-Host "To test the connection, restart Claude Desktop and check if MCP tools work." -ForegroundColor Yellow
} else {
    Write-Host "No API key provided. Please generate one in n8n first." -ForegroundColor Red
}