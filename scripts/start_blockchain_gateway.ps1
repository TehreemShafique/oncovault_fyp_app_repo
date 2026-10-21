# scripts/start_blockchain_gateway.ps1
# OncoVault — Local Blockchain Gateway Launcher

$repoRoot = Split-Path -Parent $PSScriptRoot
$gatewayDir = Join-Path $repoRoot "fabric\gateway"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " OncoVault — Hyperledger Fabric Gateway (Port 5001)" -ForegroundColor Cyan
Write-Host " Ready for Vercel Web App & Local Blockchain Verification" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Set-Location $gatewayDir

# Check if node_modules exists
if (-not (Test-Path "node_modules")) {
    Write-Host "[*] Installing dependencies..." -ForegroundColor Yellow
    npm install
}

# Check if dist/index.js exists
if (-not (Test-Path "dist\index.js")) {
    Write-Host "[*] Building TypeScript..." -ForegroundColor Yellow
    npm run build
}

Write-Host "[+] Launching OncoVault Fabric Gateway on http://127.0.0.1:5001..." -ForegroundColor Green
Write-Host "    Press Ctrl+C to stop the gateway anytime.`n" -ForegroundColor DarkGray

node dist/index.js
