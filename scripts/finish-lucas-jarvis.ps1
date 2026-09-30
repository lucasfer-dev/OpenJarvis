# Lucas Jarvis - finalizador do Windows
# Executar a partir de E:\jarvis\OpenJarvis:
# powershell -ExecutionPolicy Bypass -File scripts\finish-lucas-jarvis.ps1
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root
Write-Host "== Jarvis: finalizando aplicativo Windows ==" -ForegroundColor Cyan

# Preset local: preserve existing config as backup and write valid TOML.
$configDir = Join-Path $HOME ".openjarvis"
$configPath = Join-Path $configDir "config.toml"
New-Item -ItemType Directory -Force $configDir | Out-Null
if (Test-Path $configPath) {
  Copy-Item $configPath "$configPath.before-lucas-final.bak" -Force
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
  "code_interpreter",
  "web_search",
  "file_read",
  "file_write",
  "apply_patch",
  "shell_exec",
  "git_status",
  "git_diff",
  "git_log",
  "git_commit",
  "memory_search",
  "memory_store",
  "memory_retrieve",
  "memory_manage",
  "user_profile_manage",
  "audio_transcribe",
  "text_to_speech",
  "windows_open_app",
  "windows_open_project",
  "windows_open_url",
  "skill_manage"
]

[security]
profile = "personal"

[speech]
backend = "faster-whisper"
'@ | Set-Content -Encoding UTF8 $configPath

Write-Host "[1/6] Sincronizando backend..." -ForegroundColor Yellow
uv sync --extra desktop --group desktop-native
Write-Host "[2/6] Validando extensao nativa e memoria..." -ForegroundColor Yellow
uv run python -c "import openjarvis_rust; print('openjarvis_rust OK')"
uv run jarvis memory stats

Write-Host "[3/6] Garantindo modelo local..." -ForegroundColor Yellow
ollama pull qwen3.5:2b

Write-Host "[4/6] Instalando frontend..." -ForegroundColor Yellow
Push-Location (Join-Path $root "frontend")
npm install --no-audit --no-fund

Write-Host "[5/6] Compilando OpenJarvis Desktop..." -ForegroundColor Yellow
npm run tauri build
Pop-Location

$exe = Join-Path $root "frontend\src-tauri\target\release\openjarvis-desktop.exe"
if (!(Test-Path $exe)) {
  $exe = Get-ChildItem (Join-Path $root "frontend\src-tauri\target\release") -Filter "*.exe" -File |
    Where-Object { $_.Name -notmatch "build-script|deps" } |
    Select-Object -First 1 -ExpandProperty FullName
}
if (!$exe -or !(Test-Path $exe)) { throw "Desktop compilou, mas o executavel nao foi localizado." }

Write-Host "[6/6] Criando atalho e inicializacao automatica..." -ForegroundColor Yellow
$ws = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcut = $ws.CreateShortcut((Join-Path $desktop "Jarvis.lnk"))
$shortcut.TargetPath = $exe
$shortcut.WorkingDirectory = $root
$shortcut.IconLocation = "$exe,0"
$shortcut.Save()

$startup = [Environment]::GetFolderPath("Startup")
$auto = $ws.CreateShortcut((Join-Path $startup "Jarvis.lnk"))
$auto.TargetPath = $exe
$auto.WorkingDirectory = $root
$auto.IconLocation = "$exe,0"
$auto.Save()

Write-Host ""
Write-Host "JARVIS DESKTOP PRONTO: $exe" -ForegroundColor Green
Write-Host "Atalho criado na Area de Trabalho e no Startup do Windows." -ForegroundColor Green
Start-Process $exe
