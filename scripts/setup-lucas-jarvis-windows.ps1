#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SkipModel)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

function Step($m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Has($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }

if (-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core") { throw "Este instalador e exclusivo para Windows." }
if (-not (Has "winget")) { throw "winget nao encontrado. Instale/atualize o App Installer da Microsoft Store." }

Step "Verificando Git, Python, uv, Node e Ollama"
$packages = @(
  @{ cmd="git"; id="Git.Git" },
  @{ cmd="python"; id="Python.Python.3.10" },
  @{ cmd="node"; id="OpenJS.NodeJS" },
  @{ cmd="ollama"; id="Ollama.Ollama" }
)
foreach ($p in $packages) {
  if (-not (Has $p.cmd)) {
    winget install --id $p.id -e --accept-package-agreements --accept-source-agreements
  } else { Write-Host "OK: $($p.cmd)" }
}
if (-not (Has "uv")) {
  powershell -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex"
  $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
}
if (-not (Has "uv")) { throw "uv foi instalado, mas ainda nao esta no PATH. Feche o PowerShell, abra novamente e execute este script de novo." }

Step "Instalando/atualizando Rust"
if (-not (Has "rustup")) {
  winget install --id Rustlang.Rustup -e --accept-package-agreements --accept-source-agreements
  $env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
}
if (-not (Has "rustup")) { throw "Rustup foi instalado, mas ainda nao esta no PATH. Feche o PowerShell, abra novamente e execute este script de novo." }
rustup update stable
rustup default stable
$rustVersion = (& rustc --version)
Write-Host $rustVersion

Step "Garantindo Microsoft C++ Build Tools para o Rust"
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\\Installer\\vswhere.exe"
$linkFound = Get-Command link.exe -ErrorAction SilentlyContinue
if (-not $linkFound) {
  $hasCppTools = $false
  if (Test-Path $vswhere) {
    $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($installPath) { $hasCppTools = $true }
  }
  if (-not $hasCppTools) {
    Write-Host "Instalando Visual Studio Build Tools (C++). Pode abrir uma janela/UAC."
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" --accept-package-agreements --accept-source-agreements
  } else { Write-Host "OK: Visual C++ Build Tools ja instalado" }
}

# Carrega o ambiente MSVC no processo atual para que Cargo encontre link.exe.
if (Test-Path $vswhere) {
  $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if ($installPath) {
    $devCmd = Join-Path $installPath "Common7\\Tools\\VsDevCmd.bat"
    if (Test-Path $devCmd) {
      $envDump = cmd /s /c "`"`"$devCmd`" -arch=x64 -host_arch=x64 >nul && set`""
      foreach ($line in $envDump) {
        if ($line -match "^([^=]+)=(.*)$") { Set-Item -Path "Env:$($matches[1])" -Value $matches[2] }
      }
    }
  }
}
if (-not (Get-Command link.exe -ErrorAction SilentlyContinue)) {
  throw "Microsoft C++ linker (link.exe) ainda nao esta disponivel. Reinicie o PowerShell e execute o setup novamente."
}

Step "Sincronizando dependencias do OpenJarvis + desktop/voz"
uv sync --extra desktop

Step "Compilando extensao nativa openjarvis_rust"
uv run maturin develop -m rust/crates/openjarvis-python/Cargo.toml
$rustOk = uv run python -c "from openjarvis._rust_bridge import RUST_AVAILABLE; print(RUST_AVAILABLE)"
if (($rustOk | Out-String).Trim() -ne "True") { throw "openjarvis_rust nao ficou disponivel." }

Step "Garantindo Ollama e modelo local"
try { Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 3 | Out-Null }
catch {
  Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
  Start-Sleep -Seconds 4
}
if (-not $SkipModel) {
  $models = (& ollama list | Out-String)
  if ($models -notmatch "qwen3\.5:2b") { ollama pull qwen3.5:2b } else { Write-Host "OK: qwen3.5:2b ja instalado" }
}

Step "Configurando OpenJarvis"
$configDir = Join-Path $env:USERPROFILE ".openjarvis"
$configPath = Join-Path $configDir "config.toml"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
if (Test-Path $configPath) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  Copy-Item $configPath "$configPath.backup-$stamp"
}
@'
[engine]
default = "ollama"

[engine.ollama]
host = "http://localhost:11434"

[intelligence]
default_model = "qwen3.5:2b"

[agent]
default_agent = "orchestrator"

[tools]
enabled = [
  "code_interpreter", "web_search", "file_read", "file_write", "apply_patch",
  "shell_exec", "git_status", "git_diff", "git_log", "git_commit",
  "memory_search", "memory_store", "memory_retrieve", "memory_manage",
  "user_profile_manage", "audio_transcribe", "text_to_speech",
  "windows_open_app", "windows_open_project", "windows_open_url", "skill_manage"
]

[security]
profile = "personal"
'@ | Set-Content -Path $configPath -Encoding UTF8

Step "Validando memoria, skill e ferramentas"
uv run jarvis memory stats
$skills = uv run jarvis skill list | Out-String
if ($skills -notmatch "tech-fast-track") { Write-Warning "tech-fast-track nao apareceu em 'jarvis skill list'." }
$tools = uv run jarvis tool list | Out-String
foreach ($t in @("windows_open_app","windows_open_project","windows_open_url","text_to_speech","audio_transcribe")) {
  if ($tools -notmatch $t) { Write-Warning "Ferramenta nao registrada: $t" }
}

Step "Diagnostico final"
uv run jarvis doctor

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host " Lucas Jarvis: setup base concluido" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host "Teste: uv run jarvis ask \"Abra o VS Code\""
Write-Host "GUI:   uv run jarvis gui"
Write-Host ""
Write-Host "WhatsApp/QR e wake word ficam fora deste setup ate serem validados ponta a ponta no fork."
