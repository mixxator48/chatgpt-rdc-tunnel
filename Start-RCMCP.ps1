$ErrorActionPreference = "Stop"

$Base = $PSScriptRoot
$Runtime = Join-Path $Base ".runtime"
$ClientDir = Join-Path $Runtime "tunnel-client"
$Tunnel = Join-Path $ClientDir "tunnel-client.exe"
$Cloudflared = Join-Path $ClientDir "cloudflared.exe"
$Profiles = Join-Path $Base "profiles"
$MediaServer = Join-Path $Base "media-server.mjs"
$MediaPort = 39127
$MediaSessionFile = Join-Path $Runtime "media-session.json"
$LogDir = Join-Path $Base "logs"

New-Item -ItemType Directory -Force -Path $Runtime, $LogDir | Out-Null

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

function Wait-CloudflareUrl([string[]]$Logs, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        foreach ($log in $Logs) {
            if (-not (Test-Path $log)) { continue }
            $text = Get-Content $log -Raw -ErrorAction SilentlyContinue
            if (-not $text) { continue }
            $match = [regex]::Match($text, 'https://[a-z0-9-]+\.trycloudflare\.com')
            if ($match.Success) { return $match.Value }
        }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

function Stop-Tree($Process) {
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
        }
    } catch {}
}

function Clear-StaleMediaServer {
    $listener = Get-NetTCPConnection -LocalPort $MediaPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $listener) { return }

    $ownerPid = $listener.OwningProcess
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$ownerPid" -ErrorAction SilentlyContinue
    $expected = [regex]::Escape($MediaServer)

    if ($proc -and $proc.CommandLine -match $expected) {
        Write-Host "Stopping stale RDC media server (PID $ownerPid)..." -ForegroundColor DarkYellow
        & taskkill.exe /PID $ownerPid /T /F 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
        return
    }

    throw "Port $MediaPort is already in use by another process (PID $ownerPid)."
}

function Trim-OldLogs {
    if (-not (Test-Path $LogDir)) { return }
    $groups = Get-ChildItem $LogDir -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    if ($groups.Count -gt 40) {
        $groups | Select-Object -Skip 40 | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

$tunnelProc = $null
$mediaProc = $null
$cloudflareProc = $null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tunnelOut = Join-Path $LogDir "tunnel-$stamp.log"
$tunnelErr = Join-Path $LogDir "tunnel-$stamp.err.log"
$mediaOut = Join-Path $LogDir "media-$stamp.log"
$mediaErr = Join-Path $LogDir "media-$stamp.err.log"
$cloudflareOut = Join-Path $LogDir "cloudflare-media-$stamp.log"
$cloudflareErr = Join-Path $LogDir "cloudflare-media-$stamp.err.log"

try {
    Trim-OldLogs

    if (-not (Test-Path $Tunnel)) {
        throw "tunnel-client is not installed. Run .\setup.ps1 first."
    }
    if (-not (Test-Path $Cloudflared)) {
        throw "cloudflared bundled with tunnel-client was not found. Run .\setup.ps1 again."
    }
    if (-not (Test-Path $MediaServer)) {
        throw "media-server.mjs is missing."
    }
    if (-not (Test-Path (Join-Path $Profiles "rdc-local.yaml"))) {
        throw "Tunnel profile is missing. Run .\setup.ps1 first."
    }
    if (Get-NetTCPConnection -LocalPort 8788 -State Listen -ErrorAction SilentlyContinue) {
        throw "Port 8788 is already in use. tunnel-client may already be running."
    }

    Clear-StaleMediaServer

    $secretBytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($secretBytes) } finally { $rng.Dispose() }
    $mediaSecret = -join ($secretBytes | ForEach-Object { $_.ToString("x2") })

    $env:RDC_MEDIA_PORT = [string]$MediaPort
    $env:RDC_MEDIA_REGISTER_SECRET = $mediaSecret

    Write-Host "Starting RDC media server..." -ForegroundColor Cyan
    $mediaProc = Start-Process -FilePath "node" -ArgumentList @($MediaServer) -PassThru -NoNewWindow -RedirectStandardOutput $mediaOut -RedirectStandardError $mediaErr

    if (-not (Wait-Url "http://127.0.0.1:$MediaPort/health" 10)) {
        throw "RDC media server did not become ready. See $mediaErr"
    }

    Write-Host "Starting temporary HTTPS media tunnel..." -ForegroundColor Cyan
    $cloudflareProc = Start-Process -FilePath $Cloudflared -ArgumentList @(
        "tunnel",
        "--url", "http://127.0.0.1:$MediaPort",
        "--no-autoupdate"
    ) -PassThru -NoNewWindow -RedirectStandardOutput $cloudflareOut -RedirectStandardError $cloudflareErr

    $mediaPublicBase = Wait-CloudflareUrl @($cloudflareOut, $cloudflareErr) 20
    if (-not $mediaPublicBase) {
        throw "Cloudflare media tunnel did not provide a public URL. See $cloudflareErr"
    }

    $mediaSession = @{
        localBase = "http://127.0.0.1:$MediaPort"
        publicBase = $mediaPublicBase
        registerSecret = $mediaSecret
        createdAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($MediaSessionFile, $mediaSession, [Text.UTF8Encoding]::new($false))

    Write-Host "Starting RC-MCP (Desktop Commander via stdio)..." -ForegroundColor Cyan
    $tunnelProc = Start-Process -FilePath $Tunnel -ArgumentList @(
        "run",
        "--profile", "rdc-local",
        "--profile-dir", $Profiles
    ) -PassThru -NoNewWindow -RedirectStandardOutput $tunnelOut -RedirectStandardError $tunnelErr

    if (-not (Wait-Url "http://127.0.0.1:8788/readyz" 20)) {
        throw "Secure MCP Tunnel did not become ready. See $tunnelErr"
    }

    Write-Host ""
    Write-Host "RC-MCP ONLINE" -ForegroundColor Green
    Write-Host "ChatGPT connector: rdc-local"
    Write-Host ("Media tunnel: " + $mediaPublicBase) -ForegroundColor DarkCyan
    Write-Host "Press Ctrl+C or close this console to stop." -ForegroundColor Yellow
    Write-Host ""

    while ($true) {
        Start-Sleep -Milliseconds 500

        if ($tunnelProc.HasExited) {
            throw "tunnel-client stopped unexpectedly. See $tunnelErr"
        }
        if ($mediaProc.HasExited) {
            throw "RDC media server stopped unexpectedly. See $mediaErr"
        }
        if ($cloudflareProc.HasExited) {
            throw "Cloudflare media tunnel stopped unexpectedly. See $cloudflareErr"
        }
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    # Ctrl+C
}
catch {
    Write-Host ""
    Write-Host ("RC-MCP error: " + $_.Exception.Message) -ForegroundColor Red
}
finally {
    Write-Host ""
    Write-Host "Stopping RC-MCP..." -ForegroundColor DarkYellow

    Stop-Tree $tunnelProc
    Stop-Tree $cloudflareProc
    Stop-Tree $mediaProc

    Remove-Item $MediaSessionFile -Force -ErrorAction SilentlyContinue
    Remove-Item Env:RDC_MEDIA_REGISTER_SECRET -ErrorAction SilentlyContinue
    Remove-Item Env:RDC_MEDIA_PORT -ErrorAction SilentlyContinue

    Write-Host "RC-MCP OFFLINE" -ForegroundColor DarkGray
}
