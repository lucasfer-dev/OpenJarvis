#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$InstallDir = "$env:LOCALAPPDATA\LucasJarvis\OpenJarvis",
  [switch]$SkipWhatsApp
)
$ErrorActionPreference = "Stop"
$Repo = "https://github.com/lucasfer-dev/OpenJarvis.git"

function Step([string]$m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Has([string]$c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path {
  $machine=[Environment]::GetEnvironmentVariable("Path","Machine")
  $user=[Environment]::GetEnvironmentVariable("Path","User")
  $env:Path="$machine;$user;$env:USERPROFILE\.cargo\bin;$env:USERPROFILE\.local\bin"
}
function Winget([string]$id) {
  winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements
  Refresh-Path
}

if (-not (Has "winget")) {
  throw "Windows App Installer/winget nao encontrado. Atualize App Installer pela Microsoft Store e execute novamente."
}

Step "Instalando pre-requisitos ausentes"
if (-not (Has "git"))    { Winget "Git.Git" }
if (-not (Has "python")) { Winget "Python.Python.3.10" }
if (-not (Has "node"))   { Winget "OpenJS.NodeJS" }
if (-not (Has "ollama")) { Winget "Ollama.Ollama" }
if (-not (Has "rustup")) { Winget "Rustlang.Rustup" }
Refresh-Path

if (-not (Has "uv")) {
  Step "Instalando uv"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
  Refresh-Path
}
if (-not (Has "uv")) { throw "uv nao ficou disponivel no PATH." }

Step "Preparando compilador nativo"
$vswhere = Join-Path \${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$hasMsvc = $false
if (Test-Path $vswhere) {
  $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  $hasMsvc = [bool]$vs
}
if (-not $hasMsvc) {
  $bt = Join-Path $env:TEMP "vs_buildtools.exe"
  Invoke-WebRequest -UseBasicParsing "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile $bt
  $args = @("--quiet","--wait","--norestart","--nocache","--add","Microsoft.VisualStudio.Workload.VCTools","--includeRecommended")
  $p = Start-Process $bt -Verb RunAs -ArgumentList $args -Wait -PassThru
  if ($p.ExitCode -notin @(0,3010)) { throw "Visual Studio Build Tools falhou: $($p.ExitCode)" }
  if ($p.ExitCode -eq 3010) { Write-Warning "Build Tools pediu reinicializacao. Reinicie se a compilacao falhar." }
}

Step "Baixando Lucas Jarvis"
$parent = Split-Path $InstallDir -Parent
New-Item -ItemType Directory -Force $parent | Out-Null
if (Test-Path (Join-Path $InstallDir ".git")) {
  git -C $InstallDir fetch origin main
  git -C $InstallDir checkout main
  git -C $InstallDir pull --ff-only origin main
} elseif (Test-Path $InstallDir) {
  throw "$InstallDir ja existe e nao e um clone Git. Renomeie/remova essa pasta ou use -InstallDir."
} else {
  git clone --depth 1 $Repo $InstallDir
}

Set-Location $InstallDir
Step "Configurando backend, voz, memoria, modelo e Desktop"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\setup-lucas-jarvis-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\finish-lucas-jarvis.ps1"

Step "Teste de saude"
uv run python -c "import kokoro, openjarvis_rust; print('Kokoro OK'); print('Rust OK')"
uv run jarvis memory stats

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " JARVIS INSTALADO E PRONTO" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "Atalho: Area de Trabalho -> Jarvis"
Write-Host "Voz: configurada para iniciar com o Windows."
Write-Host "Modelo: qwen3.5:2b local."
Write-Host "Dados/memoria: $HOME\.openjarvis"
if (-not $SkipWhatsApp) {
  Write-Host ""
  Write-Host "WhatsApp requer apenas o QR inicial. Execute quando quiser:" -ForegroundColor Yellow
  Write-Host "  cd $InstallDir"
  Write-Host "  uv run jarvis channel login --channel-type whatsapp_baileys"
}
