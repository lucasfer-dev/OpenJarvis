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
# Uma janela elevada pode nao herdar o PATH atualizado do usuario.
$cargoBin = Join-Path $env:USERPROFILE ".cargo\\bin"
if (Test-Path $cargoBin) {
  $env:Path = "$cargoBin;$env:Path"
}
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

function Import-MsvcEnvironment {
  if (-not (Test-Path $vswhere)) { return $false }
  $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $installPath) { return $false }
  $devCmd = Join-Path $installPath "Common7\\Tools\\VsDevCmd.bat"
  if (-not (Test-Path $devCmd)) { return $false }
  # Import the complete Developer Command Prompt environment.  PATH alone is
  # not enough: Rust also needs INCLUDE/LIB/LIBPATH from the Windows SDK.
  $devCmdLine = '"' + $devCmd + '" -arch=x64 -host_arch=x64 && set'
  $envDump = cmd /c $devCmdLine
  foreach ($line in $envDump) {
    if ($line -match "^([^=]+)=(.*)$") {
      Set-Item -Path "Env:$($matches[1])" -Value $matches[2]
    }
  }
  $link = Get-Command link.exe -ErrorAction SilentlyContinue
  $cl = Get-Command cl.exe -ErrorAction SilentlyContinue
  $kernel32 = $null
  if ($env:WindowsSdkDir) {
    $sdkLib = Join-Path $env:WindowsSdkDir "Lib"
    if (Test-Path $sdkLib) {
      $kernel32 = Get-ChildItem $sdkLib -Filter kernel32.lib -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\um\\x64\\kernel32\.lib$" } |
        Select-Object -First 1
    }
  }
  return [bool]($link -and $cl -and $kernel32)
}

$linkReady = Import-MsvcEnvironment
if (-not $linkReady) {
  # Microsoft's CLI install examples require elevation. Relaunch this setup as Administrator once.
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host "O C++ Build Tools precisa de elevacao. Instalando apenas essa dependencia como Administrador..."
    $bootstrapper = Join-Path $env:TEMP "vs_buildtools.exe"
    Invoke-WebRequest -UseBasicParsing -Uri "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile $bootstrapper
    $installPath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\\2022\\BuildTools"
    $adminArgs = @(
      "--quiet", "--wait", "--norestart", "--nocache",
      "--installPath", "`"$installPath`"",
      "--add", "Microsoft.VisualStudio.Workload.VCTools",
      "--includeRecommended"
    )
    $p = Start-Process -FilePath $bootstrapper -Verb RunAs -ArgumentList $adminArgs -Wait -PassThru
    if ($p.ExitCode -notin @(0,3010)) {
      throw "Visual Studio Build Tools falhou com codigo $($p.ExitCode). Logs do instalador: $env:TEMP\\dd_*"
    }
    if ($p.ExitCode -eq 3010) { Write-Warning "Build Tools instalado; o Windows recomenda reinicializacao." }
    $linkReady = Import-MsvcEnvironment
    if (-not $linkReady) {
      throw "Build Tools foi executado, mas link.exe ainda nao foi localizado. Reinicie o Windows e rode o setup novamente."
    }
  } else {

  $bootstrapper = Join-Path $env:TEMP "vs_buildtools.exe"
  Write-Host "Baixando bootstrapper oficial do Visual Studio Build Tools..."
  Invoke-WebRequest -UseBasicParsing -Uri "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile $bootstrapper
  $installPath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\\2022\\BuildTools"
  $vsArgs = @(
    "--quiet", "--wait", "--norestart", "--nocache",
    "--installPath", "`"$installPath`"",
    "--add", "Microsoft.VisualStudio.Workload.VCTools",
    "--includeRecommended"
  )
  $p = Start-Process -FilePath $bootstrapper -ArgumentList $vsArgs -Wait -PassThru
  if ($p.ExitCode -notin @(0,3010)) {
    throw "Visual Studio Build Tools falhou com codigo $($p.ExitCode). Abra Visual Studio Installer e verifique logs em %TEMP%\\dd_*."
  }
  if ($p.ExitCode -eq 3010) { Write-Warning "Build Tools instalado; o Windows recomenda reinicializacao." }
  $linkReady = Import-MsvcEnvironment
  }
}
if (-not $linkReady) {
  throw "Build Tools terminou, mas link.exe nao foi localizado. Reinicie o Windows e execute este setup novamente."
}

Step "Sincronizando dependencias do OpenJarvis + desktop/voz"
uv sync --extra desktop

Step "Validando extensao nativa openjarvis_rust"
$rustOk = uv run python -c "from openjarvis._rust_bridge import RUST_AVAILABLE; print(RUST_AVAILABLE)" 2>$null
if (($rustOk | Out-String).Trim() -ne "True") {
  Step "Compilando extensao nativa openjarvis_rust"
  if (-not (Import-MsvcEnvironment)) {
    throw "MSVC/Windows SDK nao estao prontos para compilar: link.exe, cl.exe ou kernel32.lib ausente."
  }
  uv run maturin develop -m rust/crates/openjarvis-python/Cargo.toml
  $rustOk = uv run python -c "from openjarvis._rust_bridge import RUST_AVAILABLE; print(RUST_AVAILABLE)"
  if (($rustOk | Out-String).Trim() -ne "True") { throw "openjarvis_rust nao ficou disponivel." }
} else {
  Write-Host "OK: openjarvis_rust ja instalado"
}

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
$configText = @'
[engine]
default = "ollama"

[engine.ollama]
host = "http://localhost:11434"

[intelligence]
default_model = "qwen3.5:2b"

[agent]
default_agent = "orchestrator"
context_from_memory = true

[memory]
enabled = true
default_backend = "sqlite"
backend = "local"
extraction_model = "qwen3.5:2b"
context_top_k = 8
context_min_score = 0.0
context_max_tokens = 2048

[tools]
enabled = "code_interpreter,web_search,file_read,file_write,apply_patch,shell_exec,git_status,git_diff,git_log,git_commit,memory_search,memory_store,memory_retrieve,memory_manage,user_profile_manage,audio_transcribe,text_to_speech,windows_open_app,windows_open_project,windows_open_url,skill_manage"

[security]
profile = "personal"
'@
[System.IO.File]::WriteAllText($configPath, $configText, (New-Object System.Text.UTF8Encoding($false)))
uv run python -c "from openjarvis.core.config import load_config; load_config(); print('config OK')"
if ($LASTEXITCODE -ne 0) { throw "config.toml invalido." }

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
