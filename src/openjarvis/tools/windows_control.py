"""Safe Windows desktop helper tools for opening trusted apps and projects."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import webbrowser
from pathlib import Path
from typing import Any

from openjarvis.core.registry import ToolRegistry
from openjarvis.core.types import ToolResult
from openjarvis.tools._stubs import BaseTool, ToolSpec


_ALLOWED_APPS = {
    "vscode": ["code"],
    "chrome": ["chrome"],
    "terminal": ["wt"],
    "powershell": ["powershell"],
    "explorer": ["explorer"],
}


def _windows_only(tool_name: str) -> ToolResult | None:
    if sys.platform != "win32":
        return ToolResult(
            tool_name=tool_name,
            content="This tool is available only on Windows.",
            success=False,
        )
    return None


@ToolRegistry.register("windows_open_app")
class WindowsOpenAppTool(BaseTool):
    """Open a small allow-list of desktop applications."""

    tool_id = "windows_open_app"

    @property
    def spec(self) -> ToolSpec:
        return ToolSpec(
            name="windows_open_app",
            description="Open a trusted Windows application: VS Code, Chrome, Terminal, PowerShell, or Explorer.",
            parameters={
                "type": "object",
                "properties": {
                    "app": {
                        "type": "string",
                        "enum": sorted(_ALLOWED_APPS),
                        "description": "Application to open.",
                    }
                },
                "required": ["app"],
            },
            category="system",
            required_capabilities=["shell:execute"],
        )

    def execute(self, **params: Any) -> ToolResult:
        err = _windows_only(self.tool_id)
        if err:
            return err
        app = str(params.get("app", "")).lower()
        cmd = _ALLOWED_APPS.get(app)
        if not cmd:
            return ToolResult(tool_name=self.tool_id, content="App not allowed.", success=False)
        executable = shutil.which(cmd[0]) or cmd[0]
        try:
            subprocess.Popen([executable], shell=False)
            return ToolResult(tool_name=self.tool_id, content=f"Opened {app}.", success=True)
        except OSError as exc:
            return ToolResult(tool_name=self.tool_id, content=f"Could not open {app}: {exc}", success=False)


@ToolRegistry.register("windows_open_project")
class WindowsOpenProjectTool(BaseTool):
    """Open a local folder in VS Code after path validation."""

    tool_id = "windows_open_project"

    @property
    def spec(self) -> ToolSpec:
        return ToolSpec(
            name="windows_open_project",
            description="Open an existing local project folder in VS Code.",
            parameters={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute or user-relative project folder path."}
                },
                "required": ["path"],
            },
            category="system",
            required_capabilities=["filesystem:read", "shell:execute"],
        )

    def execute(self, **params: Any) -> ToolResult:
        err = _windows_only(self.tool_id)
        if err:
            return err
        raw = str(params.get("path", "")).strip()
        if not raw:
            return ToolResult(tool_name=self.tool_id, content="No path provided.", success=False)
        path = Path(os.path.expandvars(os.path.expanduser(raw))).resolve()
        if not path.exists() or not path.is_dir():
            return ToolResult(tool_name=self.tool_id, content=f"Project folder not found: {path}", success=False)
        code = shutil.which("code")
        if not code:
            return ToolResult(tool_name=self.tool_id, content="VS Code CLI ('code') was not found on PATH.", success=False)
        try:
            subprocess.Popen([code, str(path)], shell=False)
            return ToolResult(tool_name=self.tool_id, content=f"Opened project in VS Code: {path}", success=True)
        except OSError as exc:
            return ToolResult(tool_name=self.tool_id, content=f"Could not open project: {exc}", success=False)


@ToolRegistry.register("windows_open_url")
class WindowsOpenUrlTool(BaseTool):
    """Open an HTTP(S) URL in the default browser."""

    tool_id = "windows_open_url"

    @property
    def spec(self) -> ToolSpec:
        return ToolSpec(
            name="windows_open_url",
            description="Open a safe http/https URL in the default browser.",
            parameters={
                "type": "object",
                "properties": {"url": {"type": "string", "description": "HTTP or HTTPS URL."}},
                "required": ["url"],
            },
            category="system",
            required_capabilities=["shell:execute"],
        )

    def execute(self, **params: Any) -> ToolResult:
        url = str(params.get("url", "")).strip()
        if not (url.startswith("https://") or url.startswith("http://")):
            return ToolResult(tool_name=self.tool_id, content="Only http/https URLs are allowed.", success=False)
        opened = webbrowser.open(url, new=2)
        return ToolResult(tool_name=self.tool_id, content=f"Opened {url}." if opened else f"Could not open {url}.", success=bool(opened))


__all__ = ["WindowsOpenAppTool", "WindowsOpenProjectTool", "WindowsOpenUrlTool"]
