"""``jarvis channel`` -- channel management commands."""

from __future__ import annotations

from typing import Any, Dict, Optional
import time

import click
from rich.console import Console
from rich.table import Table

_CHANNEL_TYPE_HELP = (
    "Channel type (sendblue, telegram, discord, slack, webhook, email, "
    "whatsapp, whatsapp_baileys, signal, google_chat, irc, webchat, teams, "
    "matrix, mattermost, feishu, bluebubbles)."
)


def _get_channel(
    channel_type: str | None,
    config: Any,
) -> Any:
    """Resolve a channel backend by type.

    Resolution order: ``--channel-type`` flag >
    ``config.channel.default_channel`` > error.
    """
    import openjarvis.channels  # noqa: F401 -- trigger registration
    from openjarvis.core.registry import ChannelRegistry

    key = channel_type or config.channel.default_channel
    if not key:
        raise click.ClickException(
            "No channel type specified. Use --channel-type or set "
            "default_channel in [channel] config."
        )

    kwargs: Dict[str, Any] = {}
    if key == "telegram":
        tc = config.channel.telegram
        if tc.bot_token:
            kwargs["bot_token"] = tc.bot_token
    elif key == "discord":
        dc = config.channel.discord
        if dc.bot_token:
            kwargs["bot_token"] = dc.bot_token
    elif key == "slack":
        sc = config.channel.slack
        if sc.bot_token:
            kwargs["bot_token"] = sc.bot_token
        if sc.app_token:
            kwargs["app_token"] = sc.app_token
    elif key == "webhook":
        wc = config.channel.webhook
        if wc.url:
            kwargs["url"] = wc.url
        if wc.secret:
            kwargs["secret"] = wc.secret
        if wc.method:
            kwargs["method"] = wc.method
    elif key == "email":
        ec = config.channel.email
        if ec.smtp_host:
            kwargs["smtp_host"] = ec.smtp_host
        kwargs["smtp_port"] = ec.smtp_port
        if ec.username:
            kwargs["username"] = ec.username
        if ec.password:
            kwargs["password"] = ec.password
        kwargs["use_tls"] = ec.use_tls
    elif key == "whatsapp":
        wac = config.channel.whatsapp
        if wac.access_token:
            kwargs["access_token"] = wac.access_token
        if wac.phone_number_id:
            kwargs["phone_number_id"] = wac.phone_number_id
    elif key == "signal":
        sgc = config.channel.signal
        if sgc.api_url:
            kwargs["api_url"] = sgc.api_url
        if sgc.phone_number:
            kwargs["phone_number"] = sgc.phone_number
    elif key == "google_chat":
        gcc = config.channel.google_chat
        if gcc.webhook_url:
            kwargs["webhook_url"] = gcc.webhook_url
    elif key == "irc":
        ic = config.channel.irc
        if ic.server:
            kwargs["server"] = ic.server
        kwargs["port"] = ic.port
        if ic.nick:
            kwargs["nick"] = ic.nick
        if ic.password:
            kwargs["password"] = ic.password
        kwargs["use_tls"] = ic.use_tls
    elif key == "webchat":
        pass  # no config needed
    elif key == "teams":
        tmc = config.channel.teams
        if tmc.app_id:
            kwargs["app_id"] = tmc.app_id
        if tmc.app_password:
            kwargs["app_password"] = tmc.app_password
        if tmc.service_url:
            kwargs["service_url"] = tmc.service_url
    elif key == "matrix":
        mc = config.channel.matrix
        if mc.homeserver:
            kwargs["homeserver"] = mc.homeserver
        if mc.access_token:
            kwargs["access_token"] = mc.access_token
    elif key == "mattermost":
        mmc = config.channel.mattermost
        if mmc.url:
            kwargs["url"] = mmc.url
        if mmc.token:
            kwargs["token"] = mmc.token
    elif key == "feishu":
        fc = config.channel.feishu
        if fc.app_id:
            kwargs["app_id"] = fc.app_id
        if fc.app_secret:
            kwargs["app_secret"] = fc.app_secret
    elif key == "bluebubbles":
        bbc = config.channel.bluebubbles
        if bbc.url:
            kwargs["url"] = bbc.url
        if bbc.password:
            kwargs["password"] = bbc.password
    elif key == "whatsapp_baileys":
        wbc = config.channel.whatsapp_baileys
        if wbc.auth_dir:
            kwargs["auth_dir"] = wbc.auth_dir
        if wbc.assistant_name:
            kwargs["assistant_name"] = wbc.assistant_name
        kwargs["assistant_has_own_number"] = wbc.assistant_has_own_number
    elif key == "sendblue":
        import os

        kwargs["api_key_id"] = os.environ.get("SENDBLUE_API_KEY_ID", "")
        kwargs["api_secret_key"] = os.environ.get("SENDBLUE_API_SECRET_KEY", "")
        kwargs["from_number"] = os.environ.get("SENDBLUE_FROM_NUMBER", "")
        sbc = getattr(config.channel, "sendblue", None)
        if sbc:
            if getattr(sbc, "api_key_id", ""):
                kwargs["api_key_id"] = sbc.api_key_id
            if getattr(sbc, "api_secret_key", ""):
                kwargs["api_secret_key"] = sbc.api_secret_key
            if getattr(sbc, "from_number", ""):
                kwargs["from_number"] = sbc.from_number

    if not ChannelRegistry.contains(key):
        raise click.ClickException(f"Unknown channel type: {key}")

    return ChannelRegistry.create(key, **kwargs)


@click.group()
def channel() -> None:
    """Manage messaging channels."""


@channel.command("list")
@click.option(
    "--channel-type",
    default=None,
    help=_CHANNEL_TYPE_HELP,
)
def channel_list(
    channel_type: Optional[str],
) -> None:
    """List available channels."""
    console = Console()
    from openjarvis.core.config import load_config

    config = load_config()

    try:
        ch = _get_channel(channel_type, config)
    except click.ClickException as exc:
        console.print(f"[red]{exc.message}[/red]")
        return

    try:
        channels = ch.list_channels()
    except Exception as exc:
        console.print(f"[red]Failed to list channels: {exc}[/red]")
        return

    if not channels:
        console.print("[yellow]No channels available[/yellow]")
        return

    table = Table(title="Available Channels")
    table.add_column("Channel", style="cyan")
    for name in channels:
        table.add_row(name)
    console.print(table)


@channel.command("send")
@click.argument("target")
@click.argument("message")
@click.option(
    "--channel-type",
    default=None,
    help=_CHANNEL_TYPE_HELP,
)
def _connect_for_cli(ch: Any, console: Console, timeout: float = 60.0) -> bool:
    """Connect a stateful channel before a one-shot CLI operation."""
    try:
        ch.connect()
        waiter = getattr(ch, "wait_until_ready", None)
        if callable(waiter):
            if waiter(timeout):
                return True
            qr_getter = getattr(ch, "wait_for_qr", None)
            qr = qr_getter(0) if callable(qr_getter) else ""
            if qr:
                console.print("[yellow]WhatsApp precisa ser autenticado primeiro. Rode: jarvis channel login --channel-type whatsapp_baileys[/yellow]")
            return False
        return getattr(ch.status(), "value", "") == "connected"
    except Exception as exc:
        console.print(f"[red]Falha ao conectar canal: {exc}[/red]")
        return False


def channel_send(
    target: str,
    message: str,
    channel_type: Optional[str],
) -> None:
    """Send a message to a channel."""
    console = Console()
    from openjarvis.core.config import load_config

    config = load_config()

    try:
        ch = _get_channel(channel_type, config)
    except click.ClickException as exc:
        console.print(f"[red]{exc.message}[/red]")
        return

    connected_here = False
    if getattr(ch.status(), "value", "") != "connected":
        connected_here = _connect_for_cli(ch, console)
        if not connected_here:
            return
    ok = ch.send(target, message)
    if connected_here:
        time.sleep(0.5)
        try:
            ch.disconnect()
        except Exception:
            pass
    if ok:
        console.print(f"[green]Message sent to {target}[/green]")
    else:
        console.print(
            f"[red]Failed to send message to {target}[/red]",
        )


@channel.command("status")
@click.option(
    "--channel-type",
    default=None,
    help=_CHANNEL_TYPE_HELP,
)
def channel_status(
    channel_type: Optional[str],
) -> None:
    """Show channel connection status."""
    console = Console()
    from openjarvis.core.config import load_config

    config = load_config()

    try:
        ch = _get_channel(channel_type, config)
    except click.ClickException as exc:
        console.print(f"[red]{exc.message}[/red]")
        return

    st = ch.status()
    color = {
        "connected": "green",
        "disconnected": "yellow",
        "connecting": "blue",
        "error": "red",
    }.get(st.value, "white")

    key = channel_type or config.channel.default_channel or "unknown"
    console.print(f"Channel: [cyan]{key}[/cyan]")
    console.print(f"Status: [{color}]{st.value}[/{color}]")


@channel.command("login")
@click.option("--channel-type", default="whatsapp_baileys", help=_CHANNEL_TYPE_HELP)
@click.option("--timeout", default=120, type=int, show_default=True)
def channel_login(channel_type: str, timeout: int) -> None:
    """Authenticate a stateful messaging channel and persist its session."""
    console = Console()
    from openjarvis.core.config import load_config

    ch = _get_channel(channel_type, load_config())
    if channel_type != "whatsapp_baileys":
        raise click.ClickException("login interativo esta disponivel para whatsapp_baileys.")

    ch.connect()
    try:
        # Existing sessions may connect immediately.
        if ch.wait_until_ready(3):
            console.print("[green]WhatsApp ja esta autenticado e conectado.[/green]")
            return

        qr = ch.wait_for_qr(20)
        if qr:
            try:
                import qrcode
                qr_obj = qrcode.QRCode(border=1)
                qr_obj.add_data(qr)
                qr_obj.make(fit=True)
                qr_obj.print_ascii(invert=True)
            except ImportError:
                console.print("[yellow]Instale qrcode para renderizar o QR no terminal.[/yellow]")
                console.print(qr)
            console.print("[cyan]No celular: WhatsApp > Aparelhos conectados > Conectar aparelho. Escaneie o QR acima.[/cyan]")
        else:
            console.print("[yellow]Ainda aguardando o WhatsApp gerar o QR...[/yellow]")

        if ch.wait_until_ready(max(1, timeout)):
            console.print("[bold green]WhatsApp conectado. A sessao ficou salva; nao precisa escanear novamente normalmente.[/bold green]")
        else:
            raise click.ClickException("Tempo esgotado esperando a autenticacao do WhatsApp.")
    finally:
        try:
            ch.disconnect()
        except Exception:
            pass
