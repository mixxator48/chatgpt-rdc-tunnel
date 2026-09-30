$ErrorActionPreference = "Stop"

$Base = $PSScriptRoot
$Runtime = Join-Path $Base ".runtime"
$ClientDir = Join-Path $Runtime "tunnel-client"
$Profiles = Join-Path $Base "profiles"
$Secrets = Join-Path $Base ".secrets"
$KeyFile = Join-Path $Secrets "control-plane.key"
$ProfileFile = Join-Path $Profiles "rdc-local.yaml"

$TunnelVersion = "0.0.15"
$TunnelZip = "tunnel-client-v$TunnelVersion-windows-amd64.zip"
$TunnelUrl = "https://github.com/openai/tunnel-client/releases/download/v$TunnelVersion/$TunnelZip"
$TunnelSha256 = "3B53133A1E24D43F63088D843860CB1701A4C3ED6390DE2E19F69089E43BDDC1"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

Require-Command "node"
Require-Command "npm"

Write-Host "Installing Desktop Commander..." -ForegroundColor Cyan
Push-Location $Base
try {
    npm install
}
finally {
    Pop-Location
}

New-Item -ItemType Directory -Force -Path $Runtime, $ClientDir, $Profiles, $Secrets | Out-Null

$TunnelExe = Join-Path $ClientDir "tunnel-client.exe"
if (-not (Test-Path $TunnelExe)) {
    $ZipPath = Join-Path $Runtime $TunnelZip
    Write-Host "Downloading OpenAI tunnel-client v$TunnelVersion..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $TunnelUrl -OutFile $ZipPath

    $ActualSha = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($ActualSha -ne $TunnelSha256) {
        Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
        throw "SHA256 mismatch for tunnel-client archive."
    }

    Expand-Archive -Path $ZipPath -DestinationPath $ClientDir -Force
    Remove-Item $ZipPath -Force
}

if (-not (Test-Path $TunnelExe)) {
    throw "tunnel-client.exe was not found after extraction."
}
$TunnelId = Read-Host "Enter your OpenAI tunnel_id"
if ($TunnelId -notmatch '^tunnel_[A-Za-z0-9]+$') {
    throw "Tunnel ID must look like tunnel_..."
}

$SecureKey = Read-Host "Enter your OpenAI Runtime API key" -AsSecureString
$Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
try {
    $PlainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
    if ([string]::IsNullOrWhiteSpace($PlainKey)) {
        throw "Runtime API key cannot be empty."
    }
    [IO.File]::WriteAllText($KeyFile, $PlainKey, [Text.UTF8Encoding]::new($false))
}
finally {
    if ($Bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
    }
}

$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $Secrets /inheritance:r | Out-Null
& icacls.exe $Secrets /grant:r "${Identity}:(OI)(CI)F" "SYSTEM:(OI)(CI)F" | Out-Null
$DcEntry = (Join-Path $Base "node_modules\@wonderwhy-er\desktop-commander\dist\index.js").Replace("\", "/")
$KeyRef = $KeyFile.Replace("\", "/")

$Yaml = @"
config_version: 1
control_plane:
  base_url: "https://api.openai.com"
  tunnel_id: "$TunnelId"
  api_key: "file:$KeyRef"
health:
  listen_addr: "127.0.0.1:8788"
admin_ui:
  open_browser: false
log:
  level: info
  format: json
mcp:
  commands:
    - channel: main
      command: "node $DcEntry"
"@

[IO.File]::WriteAllText($ProfileFile, $Yaml, [Text.UTF8Encoding]::new($false))

Write-Host "Validating tunnel profile..." -ForegroundColor Cyan
& $TunnelExe doctor --profile rdc-local --profile-dir $Profiles --explain
if ($LASTEXITCODE -ne 0) {
    throw "tunnel-client doctor failed. Fix the error above and rerun setup."
}
$ProfileDir = Split-Path -Parent $PROFILE
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

$MarkerStart = "# BEGIN chatgpt-rdc-tunnel"
$MarkerEnd = "# END chatgpt-rdc-tunnel"
$Existing = ""
if (Test-Path $PROFILE) {
    $Existing = Get-Content $PROFILE -Raw
    $Pattern = "(?s)" + [regex]::Escape($MarkerStart) + ".*?" + [regex]::Escape($MarkerEnd) + "\s*"
    $Existing = [regex]::Replace($Existing, $Pattern, "")
}

$LauncherEscaped = (Join-Path $Base "Start-RCMCP.ps1").Replace("'", "''")
$Block = @"
$MarkerStart
function rc-mcp {
    & '$LauncherEscaped'
}
$MarkerEnd
"@

$NewProfile = ($Existing.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $Block).TrimStart()
[IO.File]::WriteAllText($PROFILE, $NewProfile, [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host "Open a NEW PowerShell window and run: rc-mcp" -ForegroundColor Yellow
Write-Host "Then create a ChatGPT developer-mode app using Connection = Tunnel and your tunnel_id."
