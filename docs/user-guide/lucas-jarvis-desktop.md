# Jarvis pessoal no Windows

Este preset transforma o checkout do OpenJarvis em um aplicativo desktop local para o ambiente do Lucas.

## Finalização

No PowerShell, dentro de `E:\jarvis\OpenJarvis`:

```powershell
git pull
powershell -ExecutionPolicy Bypass -File scripts\finish-lucas-jarvis.ps1
```

O script grava um TOML válido, preserva backup da configuração anterior, usa Ollama com `qwen3.5:2b`, seleciona `orchestrator`, mantém apenas as ferramentas pessoais configuradas, valida a extensão Rust e memória, compila o Tauri Desktop, cria `Jarvis.lnk` na Área de Trabalho e na pasta Startup e abre o aplicativo.

O Desktop já fornece interface gráfica, bandeja do sistema e microfone pela interface. A etapa de wake word contínua e a autenticação QR do WhatsApp/Baileys são integrações separadas; QR exige interação humana na primeira autenticação.
