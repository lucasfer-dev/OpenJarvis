"""Tests for the personal Windows helper tools."""

from __future__ import annotations

from unittest.mock import patch

import openjarvis.tools.windows_control as wc


def test_open_url_rejects_non_http_schemes():
    result = wc.WindowsOpenUrlTool().execute(url="file:///C:/Windows/System32/cmd.exe")
    assert result.success is False
    assert "Only http/https" in result.content


def test_open_url_accepts_https():
    with patch.object(wc.webbrowser, "open", return_value=True) as mocked:
        result = wc.WindowsOpenUrlTool().execute(url="https://example.com")
    assert result.success is True
    mocked.assert_called_once_with("https://example.com", new=2)


def test_open_app_has_strict_allowlist():
    assert set(wc._ALLOWED_APPS) == {
        "vscode",
        "chrome",
        "terminal",
        "powershell",
        "explorer",
    }


def test_open_app_rejects_unknown_app_on_windows():
    with patch.object(wc.sys, "platform", "win32"):
        result = wc.WindowsOpenAppTool().execute(app="cmd /c calc.exe")
    assert result.success is False
    assert result.content == "App not allowed."


def test_open_project_rejects_missing_directory_on_windows(tmp_path):
    missing = tmp_path / "does-not-exist"
    with patch.object(wc.sys, "platform", "win32"):
        result = wc.WindowsOpenProjectTool().execute(path=str(missing))
    assert result.success is False
    assert "Project folder not found" in result.content
