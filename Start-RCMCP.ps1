$ErrorActionPreference = "Stop"

$Base = $PSScriptRoot
$Tunnel = Join-Path $Base ".runtime\tunnel-client\tunnel-client.exe"
$Profiles = Join-Path $Base "profiles"

if (-not (Test-Path $Tunnel)) {
    throw "tunnel-client is not installed. Run .\setup.ps1 first."
}
if (-not (Test-Path (Join-Path $Profiles "rdc-local.yaml"))) {
    throw "Tunnel profile is missing. Run .\setup.ps1 first."
}

Write-Host "Starting Desktop Commander through OpenAI Secure MCP Tunnel..." -ForegroundColor Cyan
Write-Host "Keep this PowerShell window open. Press Ctrl+C to stop." -ForegroundColor Yellow
Write-Host ""

try {
    & $Tunnel run --profile rdc-local --profile-dir $Profiles
}
finally {
    Write-Host ""
    Write-Host "RDC tunnel stopped." -ForegroundColor DarkGray
}
