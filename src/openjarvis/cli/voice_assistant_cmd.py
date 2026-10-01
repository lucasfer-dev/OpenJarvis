"""Always-on local voice assistant loop for Lucas Jarvis.

This deliberately uses the existing OpenJarvis STT/TTS stack.  The microphone is
processed locally; only utterances beginning with the wake word are dispatched.
"""
from __future__ import annotations

import json
import re
import subprocess
import urllib.error
import urllib.request
import sys
import time
import click
from rich.console import Console

from openjarvis.cli._voice_chat import VoiceSession, record_voice, speak


def _extract_command(text: str, wake_word: str) -> str | None:
    """Return text after the wake word, or None when it was not addressed to us."""
    cleaned = text.strip()
    pattern = rf"^\s*(?:ei\s+|hey\s+|ok\s+)?{re.escape(wake_word)}\b[\s,;:.-]*(.*)$"
    match = re.match(pattern, cleaned, flags=re.IGNORECASE)
    if not match:
        return None
    return match.group(1).strip()


def _run_via_server(command: str) -> str | None:
    """Use the already-running Desktop API to avoid a Python cold start per phrase."""
    from openjarvis.core.config import load_config

    model = load_config().intelligence.default_model
    payload = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": command}],
            "stream": False,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        "http://127.0.0.1:8000/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = json.loads(response.read().decode("utf-8"))
        return body["choices"][0]["message"]["content"].strip()
    except (OSError, KeyError, IndexError, TypeError, ValueError, urllib.error.URLError):
        return None


def _run_jarvis(command: str) -> str:
    """Prefer the warm Desktop server; fall back to the normal CLI ask path."""
    warm_answer = _run_via_server(command)
    if warm_answer is not None:
        return warm_answer

    proc = subprocess.run(
        [sys.executable, "-m", "openjarvis.cli", "--quiet", "ask", command],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()
        raise RuntimeError(detail or f"jarvis ask exited with {proc.returncode}")
    return proc.stdout.strip()


@click.command("voice-assistant")
@click.option("--wake-word", default="jarvis", show_default=True)
@click.option("--once", is_flag=True, help="Handle one addressed command and exit.")
def voice_assistant(wake_word: str, once: bool) -> None:
    """Continuously listen for JARVIS, execute the command, and answer by voice."""
    console = Console(stderr=True)
    session = VoiceSession()
    console.print(
        f"[bold green]Jarvis por voz ativo.[/bold green] "
        f"Diga [cyan]{wake_word}[/cyan] seguido do comando. Ctrl+C encerra."
    )

    # Warm STT/TTS discovery before the loop. Model loading remains cached.
    if session.get_stt_backend() is None:
        raise click.ClickException("Nenhum backend de reconhecimento de voz disponivel.")

    while True:
        try:
            heard = record_voice(console, session)
            if not isinstance(heard, str) or not heard.strip():
                time.sleep(0.15)
                continue
            command = _extract_command(heard, wake_word)
            if command is None:
                console.print("[dim]Ignorado: a fala nao comecou com a palavra de ativacao.[/dim]")
                continue
            if not command:
                speak("Sim?", console, session)
                continue
            if command.casefold() in {"sair", "encerrar", "desligar jarvis", "tchau jarvis"}:
                speak("Ate mais.", console, session)
                return

            console.print(f"[bold cyan]Comando:[/bold cyan] {command}")
            try:
                answer = _run_jarvis(command)
            except Exception as exc:
                console.print(f"[red]Falha ao executar:[/red] {exc}")
                speak("Tive um problema ao executar esse comando.", console, session)
                continue

            if answer:
                console.print(f"[bold green]Jarvis:[/bold green] {answer}")
                speak(answer, console, session)
            if once:
                return
        except KeyboardInterrupt:
            console.print("\n[dim]Jarvis por voz encerrado.[/dim]")
            return


__all__ = ["voice_assistant", "_extract_command"]
