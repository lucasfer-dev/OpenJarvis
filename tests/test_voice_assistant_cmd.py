from openjarvis.cli.voice_assistant_cmd import _extract_command


def test_extract_command_requires_wake_word():
    assert _extract_command("abra o vscode", "jarvis") is None


def test_extract_command_portuguese():
    assert _extract_command("Jarvis, abra o VS Code", "jarvis") == "abra o VS Code"


def test_extract_command_hey_prefix():
    assert _extract_command("Hey Jarvis procura Python", "jarvis") == "procura Python"


def test_extract_command_empty_activation():
    assert _extract_command("Jarvis", "jarvis") == ""
