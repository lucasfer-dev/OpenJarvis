# Lucas Jarvis - finalizador completo para Windows
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root
Write-Host "== Jarvis: instalacao final ==" -ForegroundColor Cyan

$configDir = Join-Path $HOME ".openjarvis"
$configPath = Join-Path $configDir "config.toml"
New-Item -ItemType Directory -Force $configDir | Out-Null
if (Test-Path $configPath) { Copy-Item $configPath "$configPath.before-lucas-final.bak" -Force }

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

[speech]
backend = "faster-whisper"
model = "base"
language = "pt"
device = "cpu"
compute_type = "int8"
tts_backend = "kokoro"
voice_id = "pf_dora"
voice_speed = 1.0

[channel]
default_channel = "whatsapp_baileys"

[channel.whatsapp_baileys]
assistant_name = "Jarvis"
assistant_has_own_number = false
'@
[System.IO.File]::WriteAllText($configPath, $configText, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "[1/7] Dependencias..." -ForegroundColor Yellow
uv sync --extra desktop --extra voice --group desktop-native
uv run python -c "from openjarvis.core.config import load_config; load_config(); print('config OK')"
if ($LASTEXITCODE -ne 0) { throw "config.toml invalido." }
uv run python -c "import openjarvis_rust; print('rust OK')"

Write-Host "[2/7] Modelo local..." -ForegroundColor Yellow
ollama pull qwen3.5:2b

Write-Host "[3/7] Validando voz..." -ForegroundColor Yellow
uv run python -c "import sounddevice, soundfile; from openjarvis.speech._discovery import get_speech_backend; from openjarvis.core.config import load_config; assert get_speech_backend(load_config()) is not None; print('STT OK')"

Write-Host "[4/7] Validando memoria e ferramentas..." -ForegroundColor Yellow
uv run jarvis memory stats
uv run jarvis skill list | Select-String "tech-fast-track" | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Warning "tech-fast-track nao apareceu na listagem de skills." }

Write-Host "[5/7] Instalando frontend..." -ForegroundColor Yellow
Push-Location (Join-Path $root "frontend")
$npmMajor = [int]((& npm.cmd --version).Split(".")[0])
$npmMinor = [int]((& npm.cmd --version).Split(".")[1])
if ($npmMajor -lt 11 -or ($npmMajor -eq 11 -and $npmMinor -lt 19)) {
  Write-Host "Atualizando npm para >=11.19 <12..." -ForegroundColor Yellow
  & npm.cmd install -g npm@11
  if ($LASTEXITCODE -ne 0) { throw "Falha ao atualizar npm." }
}
& npm.cmd install --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw "Falha ao instalar dependencias do frontend." }
Write-Host "[6/7] Compilando Desktop..." -ForegroundColor Yellow
& npm.cmd run tauri build
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Falha ao compilar o Desktop Tauri." }
Pop-Location

$exe = Join-Path $root "frontend\src-tauri\target\release\openjarvis-desktop.exe"
if (!(Test-Path $exe)) {
  $exe = Get-ChildItem (Join-Path $root "frontend\src-tauri\target\release") -Filter "*.exe" -File |
    Where-Object { $_.Name -notmatch "build-script|deps" } |
    Select-Object -First 1 -ExpandProperty FullName
}
if (!$exe -or !(Test-Path $exe)) { throw "Desktop compilou, mas o executavel nao foi localizado." }

Write-Host "[7/7] Atalhos e voz no login..." -ForegroundColor Yellow
$ws = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcut = $ws.CreateShortcut((Join-Path $desktop "Jarvis.lnk"))
$shortcut.TargetPath = $exe
$shortcut.WorkingDirectory = $root
$shortcut.IconLocation = "$exe,0"
$shortcut.Save()

# Start the voice listener silently at login using the uv environment.
$startup = [Environment]::GetFolderPath("Startup")
$voiceVbs = Join-Path $configDir "start-jarvis-voice.vbs"
$voiceCmd = 'cd /d "' + $root + '" && uv run jarvis voice-assistant >> "' + (Join-Path $configDir "voice.log") + '" 2>&1'
$vbs = 'Set WshShell = CreateObject("WScript.Shell")' + [Environment]::NewLine +
       'WshShell.Run "cmd /c ' + ($voiceCmd -replace '"','""') + '", 0, False'
Set-Content -Path $voiceVbs -Value $vbs -Encoding ASCII
$auto = $ws.CreateShortcut((Join-Path $startup "Jarvis Voice.lnk"))
$auto.TargetPath = "wscript.exe"
$auto.Arguments = '"' + $voiceVbs + '"'
$auto.WorkingDirectory = $root
$auto.Save()

Write-Host ""
Write-Host "JARVIS INSTALADO." -ForegroundColor Green
Write-Host "Desktop: $exe" -ForegroundColor Green
Write-Host "Voz: inicia automaticamente no proximo login." -ForegroundColor Green
Write-Host "Para testar agora: uv run jarvis voice-assistant --once" -ForegroundColor Cyan
Write-Host "WhatsApp (uma vez): uv run jarvis channel login --channel-type whatsapp_baileys" -ForegroundColor Cyan
Start-Process $exe
