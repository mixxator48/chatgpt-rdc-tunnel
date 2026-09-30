$ErrorActionPreference = "Stop"

$Base = $PSScriptRoot
$Tunnel = Join-Path $Base ".runtime\tunnel-client\tunnel-client.exe"
$Profiles = Join-Path $Base "profiles"
$LogDir = Join-Path $Base "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (-not (Test-Path $Tunnel)) {
    throw "tunnel-client is not installed. Run .\setup.ps1 first."
}
if (-not (Test-Path (Join-Path $Profiles "rdc-local.yaml"))) {
    throw "Tunnel profile is missing. Run .\setup.ps1 first."
}

function Wait-Url([string]$Url, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2
            if ($r.StatusCode -eq 200) { return $true }
        } catch {}
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Stop-Tree($Process) {
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
        }
    } catch {}
}

$tunnelProc = $null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tunnelOut = Join-Path $LogDir "tunnel-$stamp.log"
$tunnelErr = Join-Path $LogDir "tunnel-$stamp.err.log"

try {
    if (Get-NetTCPConnection -LocalPort 8788 -State Listen -ErrorAction SilentlyContinue) {
        throw "Port 8788 is already in use. tunnel-client may already be running."
    }

    Write-Host "Starting RDC Local (Desktop Commander via stdio)..." -ForegroundColor Cyan

    $tunnelProc = Start-Process -FilePath $Tunnel -ArgumentList @("run","--profile","rdc-local","--profile-dir",$Profiles) -PassThru -NoNewWindow -RedirectStandardOutput $tunnelOut -RedirectStandardError $tunnelErr

    if (-not (Wait-Url "http://127.0.0.1:8788/readyz" 20)) {
        throw "Secure MCP Tunnel did not become ready. See $tunnelErr"
    }

    Write-Host ""
    Write-Host "RDC LOCAL ONLINE" -ForegroundColor Green
    Write-Host "ChatGPT connector: RDC Local"
    Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Tunnel logs:" -ForegroundColor DarkGray
    Write-Host "  $tunnelOut" -ForegroundColor DarkGray
    Write-Host "  $tunnelErr" -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        Start-Sleep -Milliseconds 500
        if ($tunnelProc.HasExited) { throw "tunnel-client stopped unexpectedly. See $tunnelErr" }
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    # Ctrl+C
}
catch {
    Write-Host ""
    Write-Host ("RDC Local error: " + $_.Exception.Message) -ForegroundColor Red
}
finally {
    Write-Host ""
    Write-Host "Stopping RDC Local..." -ForegroundColor DarkYellow
    Stop-Tree $tunnelProc
    Write-Host "RDC LOCAL OFFLINE" -ForegroundColor DarkGray
}
