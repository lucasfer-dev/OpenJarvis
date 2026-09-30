# Lucas Jarvis — personal setup

This fork adds a small personal-assistant layer on top of OpenJarvis.

## Included in V1

- `tech-fast-track` instructional skill for programming study.
- Windows tools:
  - `windows_open_app`
  - `windows_open_project`
  - `windows_open_url`
- Uses OpenJarvis' existing code assistant, memory, speech, browser and WhatsApp channels.
- WhatsApp sending remains confirmation-gated through the existing channel tool security model.

## Important discovery

OpenJarvis already ships two WhatsApp options:

1. `whatsapp`: send-only adapter using the official WhatsApp Cloud API.
2. `whatsapp_baileys`: bidirectional adapter that starts a bundled Node/Baileys bridge, handles QR authentication, sends messages, and forwards incoming messages.

For a personal desktop assistant, `whatsapp_baileys` is the most direct option. It requires Node.js 22+.

## Suggested configuration

Enable the tools below in your local `~/.openjarvis/config.toml`:

```toml
[agent]
default_agent = "orchestrator"
max_turns = 12

[tools]
enabled = [
  "think",
  "calculator",
  "file_read",
  "file_write",
  "shell_exec",
  "code_interpreter",
  "git",
  "memory_manage",
  "channel_send",
  "windows_open_app",
  "windows_open_project",
  "windows_open_url"
]

[skills]
enabled = true
```

The exact Git tool registry name may differ by OpenJarvis release; run `jarvis tools list` and adjust the entry if needed.

## WhatsApp

For a personal WhatsApp account:

```bash
node --version
jarvis connect whatsapp_baileys
```

On first connection, scan the QR code with WhatsApp.

Use OpenJarvis interactively so sensitive actions can request confirmation before tool execution. Do not disable confirmation for `channel_send`.

Example:

> Manda para o Kauã: "corrigi aqui, testa agora"

The intended flow is: resolve recipient -> prepare text -> show confirmation -> send.

## Study

Install or expose the workspace skill directory according to OpenJarvis' skill discovery rules, then verify:

```bash
jarvis skill list
jarvis skill info tech-fast-track
```

Then:

```text
Jarvis, vamos continuar JavaScript de onde parei.
```

The skill tells the orchestrator to retrieve prior progress, use active recall, teach one exercise at a time, and persist a session summary.

## Coding

OpenJarvis already has a code-assistant preset with file I/O, shell execution and code execution.

Examples:

```text
Abre C:\\dev\\envista no VS Code.
Roda os testes e me explica o primeiro erro.
Não corrija ainda: quero tentar resolver.
```

or:

```text
Leia o erro, corrija o bug, rode os testes de novo e me mostre exatamente o que mudou.
```

## Safety defaults

Recommended:
- opening trusted apps: no confirmation;
- reading files: no confirmation inside explicitly selected project directories;
- writing files: confirmation or review when outside the current project;
- WhatsApp send: always confirmation;
- delete files: always confirmation;
- git push/deploy: always confirmation;
- arbitrary shell commands: keep interactive confirmation for risky/destructive commands.

## Next steps

V2 can add:
- contact-name resolution for WhatsApp;
- wake word ("Jarvis");
- speech-to-text / text-to-speech profile tuned for pt-BR;
- project aliases ("abre o Envista");
- startup daemon on Windows;
- daily study planning and reminders.
