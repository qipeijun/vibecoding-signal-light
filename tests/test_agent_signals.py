import io
import json

import pytest

from signal_light.agent_signals import SIGNALS
from signal_light import cli
from signal_light.claude_code_hook import ClaudeCodeHookInput, choose_signal as choose_claude_signal
from signal_light.claude_code_hook import model_name as claude_model_name
from signal_light.codex_hook import CodexHookInput, choose_signal, model_name as codex_model_name, session_key
from signal_light import runtime
from signal_light.runtime import aggregate_sessions, apply_session_signal, write_current_status


class RecordingLight:
    def __init__(self) -> None:
        self.states: list[tuple[bool, bool, bool]] = []
        self.brightness_states: list[tuple[float, float, float]] = []

    def write(self, *, green: bool = False, yellow: bool = False, red: bool = False) -> None:
        self.states.append((green, yellow, red))

    def write_brightness(self, *, green: float = 0.0, yellow: float = 0.0, red: float = 0.0) -> None:
        self.brightness_states.append((green, yellow, red))

    def off(self) -> None:
        self.write()


def test_idle_signal_leaves_green_on() -> None:
    light = RecordingLight()

    SIGNALS["idle"].play(light, speed=0.05)

    assert SIGNALS["idle"].repeat is False
    assert light.states[-1] == (True, False, False)


def test_working_signal_uses_slow_green_flash() -> None:
    light = RecordingLight()

    SIGNALS["working"].play(light, speed=0.05, cycles=1)

    assert SIGNALS["working"].repeat is True
    assert light.states[:2] == [(True, False, False), (False, False, False)]
    assert light.brightness_states == []


def test_attention_signal_flashes_yellow() -> None:
    light = RecordingLight()

    SIGNALS["attention"].play(light, speed=0.05, cycles=1)

    assert SIGNALS["attention"].repeat is True
    assert light.states[:2] == [(False, True, False), (False, False, False)]


def test_thinking_signal_uses_slow_green_flash() -> None:
    light = RecordingLight()

    SIGNALS["thinking"].play(light, speed=0.05, cycles=1)

    assert SIGNALS["thinking"].frames == SIGNALS["working"].frames
    assert light.states[:2] == [(True, False, False), (False, False, False)]
    assert light.brightness_states == []


def test_permission_signal_flashes_red() -> None:
    light = RecordingLight()

    SIGNALS["permission"].play(light, speed=0.05, cycles=1)

    assert SIGNALS["permission"].repeat is True
    assert light.states[:2] == [(False, False, True), (False, False, False)]


def test_session_end_returns_to_idle_green() -> None:
    light = RecordingLight()

    SIGNALS["session_end"].play(light, speed=0.05)

    assert light.states[-1] == (True, False, False)


def test_done_signal_returns_to_idle_green() -> None:
    light = RecordingLight()

    SIGNALS["done"].play(light, speed=0.05)

    assert SIGNALS["done"].repeat is False
    assert light.states[-1] == (True, False, False)


def test_codex_stop_maps_to_done_idle() -> None:
    signal = choose_signal(CodexHookInput(event_name="Stop", payload={}))

    assert signal == "done"


def test_codex_stop_with_failed_payload_maps_to_blocked() -> None:
    signal = choose_signal(CodexHookInput(event_name="Stop", payload={"status": "failed"}))

    assert signal == "blocked"


def test_claude_stop_maps_to_done_idle() -> None:
    signal = choose_claude_signal(ClaudeCodeHookInput(event_name="Stop", payload={}))

    assert signal == "done"


def test_claude_stop_with_error_reason_maps_to_blocked() -> None:
    signal = choose_claude_signal(ClaudeCodeHookInput(event_name="Stop", payload={"stop_reason": "error"}))

    assert signal == "blocked"


@pytest.mark.parametrize(
    ("event_name", "expected_signal"),
    [
        ("PostToolBatch", "working"),
        ("TaskCreated", "working"),
        ("TaskCompleted", "tool_done"),
        ("PermissionDenied", "blocked"),
        ("StopFailure", "blocked"),
        ("PostCompact", "tool_done"),
    ],
)
def test_claude_modern_events_map_to_explicit_signals(event_name: str, expected_signal: str) -> None:
    signal = choose_claude_signal(ClaudeCodeHookInput(event_name=event_name, payload={}))

    assert signal == expected_signal


def test_failed_payload_maps_to_blocked() -> None:
    signal = choose_signal(
        CodexHookInput(
            event_name="PostToolUse",
            payload={"status": "failed"},
        )
    )

    assert signal == "blocked"


def test_structured_error_payload_maps_to_blocked() -> None:
    signal = choose_signal(
        CodexHookInput(
            event_name="PostToolUse",
            payload={"error": {"message": "command failed"}},
        )
    )

    assert signal == "blocked"


def test_prompt_text_containing_error_does_not_map_to_blocked() -> None:
    signal = choose_signal(
        CodexHookInput(
            event_name="UserPromptSubmit",
            payload={"prompt": "please fix this error"},
        )
    )

    assert signal == "thinking"


def test_success_status_does_not_become_unknown_signal() -> None:
    signal = choose_signal(
        CodexHookInput(
            event_name="PostToolUse",
            payload={"status": "success"},
        )
    )

    assert signal == "tool_done"


def test_aggregate_uses_latest_working_over_old_attention() -> None:
    aggregate = aggregate_sessions(
        {
            "a": {"signal": "attention", "updated_at": 1},
            "b": {"signal": "working", "updated_at": 2},
        }
    )

    assert aggregate == "working"


def test_aggregate_uses_latest_attention_over_old_permission() -> None:
    aggregate = aggregate_sessions(
        {
            "a": {"signal": "attention", "updated_at": 1},
            "b": {"signal": "working", "updated_at": 2},
            "c": {"signal": "permission", "updated_at": 0},
        }
    )

    assert aggregate == "working"


def test_aggregate_maps_latest_tool_done_to_working() -> None:
    aggregate = aggregate_sessions(
        {
            "a": {"signal": "idle", "updated_at": 1},
            "b": {"signal": "tool_done", "updated_at": 2},
        }
    )

    assert aggregate == "working"


def test_aggregate_returns_idle_for_empty_sessions() -> None:
    assert aggregate_sessions({}) == "idle"


def test_aggregate_returns_idle_when_only_done_sessions_remain() -> None:
    aggregate = aggregate_sessions(
        {
            "a": {"signal": "done", "updated_at": 1},
        }
    )

    assert aggregate == "idle"


def test_session_key_prefers_payload_session_id() -> None:
    key = session_key(
        CodexHookInput(event_name="Stop", payload={"session_id": "session-a", "cwd": "/tmp/x"}),
        {},
    )

    assert key == "session-a"


def test_session_key_falls_back_to_cwd() -> None:
    key = session_key(
        CodexHookInput(event_name="Stop", payload={"cwd": "/tmp/project"}),
        {},
    )

    assert key == "cwd:/tmp/project"


def test_session_key_ignores_turn_id_and_uses_cwd() -> None:
    key = session_key(
        CodexHookInput(event_name="Stop", payload={"turn_id": "turn-a", "cwd": "/tmp/project"}),
        {"CODEX_TURN_ID": "turn-env"},
    )

    assert key == "cwd:/tmp/project"


def test_cli_codex_hook_uses_session_aware_path(monkeypatch) -> None:
    calls: list[tuple[str, str, bool, bool, str | None]] = []
    monkeypatch.setattr("sys.stdin", io.StringIO('{"session_id":"session-a","event":"Stop"}'))
    monkeypatch.setattr(
        cli,
        "play_hook_signal",
        lambda signal_name, *, session_key, dry_run=False, quiet=False, model_name=None: calls.append(
            (signal_name, session_key, dry_run, quiet, model_name)
        )
        or 0,
    )

    assert cli.main(["codex-hook", "--dry-run"]) == 0
    assert calls == [("done", "session-a", True, True, None)]


def test_cli_codex_hook_without_event_uses_stdin_event(monkeypatch) -> None:
    calls: list[tuple[str, str, bool, bool, str | None]] = []
    monkeypatch.setattr("sys.stdin", io.StringIO('{"session_id":"session-a","event":"PermissionRequest"}'))
    monkeypatch.setattr(
        cli,
        "play_hook_signal",
        lambda signal_name, *, session_key, dry_run=False, quiet=False, model_name=None: calls.append(
            (signal_name, session_key, dry_run, quiet, model_name)
        )
        or 0,
    )

    assert cli.main(["codex-hook", "--dry-run"]) == 0
    assert calls == [("permission", "session-a", True, True, None)]


def test_apply_session_signal_uses_newer_work_over_old_attention(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))
    monkeypatch.setattr(cli, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))

    assert apply_session_signal("session-a", "attention") == "attention"
    assert apply_session_signal("session-b", "working") == "working"

    assert applied == ["attention", "working"]


def test_apply_session_signal_uses_newer_permission_over_attention(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))
    monkeypatch.setattr(cli, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))

    assert apply_session_signal("session-a", "attention") == "attention"
    assert apply_session_signal("session-b", "permission") == "permission"


def test_write_current_status_uses_fixed_json_contract(tmp_path, monkeypatch) -> None:
    current_file = tmp_path / "current_status.json"
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "CURRENT_STATUS_FILE", current_file)

    write_current_status("working", updated_at=123.0)

    assert json.loads(current_file.read_text()) == {
        "aggregate": "working",
        "updated_at": 123.0,
    }


def test_write_current_status_rejects_unknown_signal(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "CURRENT_STATUS_FILE", tmp_path / "current_status.json")

    with pytest.raises(runtime.SignalLightError):
        write_current_status("maybe-working")


def test_cli_play_signal_writes_status(monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(cli, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))
    monkeypatch.setattr(cli, "clear_session_state", lambda: None)

    assert cli.play_signal("working", quiet=True) == 0

    assert applied == ["working"]


def test_apply_session_signal_removes_session_on_end(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))

    assert apply_session_signal("session-a", "working") == "working"
    assert apply_session_signal("session-a", "session_end") == "idle"

    assert applied == ["working", "idle"]


def test_apply_session_signal_clears_non_urgent_session_on_turn_end(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))

    assert apply_session_signal("session-a", "working") == "working"
    assert apply_session_signal("session-a", "turn_end") == "idle"

    assert runtime.read_session_snapshot() == {"aggregate": "idle", "sessions": {}}
    assert applied == ["working", "idle"]


def test_apply_session_signal_returns_to_idle_on_done(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))

    assert apply_session_signal("session-a", "working") == "working"
    assert apply_session_signal("session-a", "done") == "idle"

    assert applied == ["working", "idle"]


def test_old_session_json_without_source_remains_readable(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    (tmp_path / "sessions.json").write_text(
        json.dumps({"sessions": {"session-a": {"signal": "working", "updated_at": 1}}})
    )

    snapshot = runtime.read_session_snapshot()

    assert snapshot["aggregate"] == "idle"
    assert snapshot["sessions"] == {}


def test_session_source_is_preserved_by_python_runtime(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))
    source = {
        "bundle_identifier": "com.apple.Terminal",
        "process_identifier": 123,
        "localized_name": "Terminal",
        "captured_at": 456.0,
    }
    (tmp_path / "sessions.json").write_text(
        json.dumps({"sessions": {"session-a": {"signal": "working", "updated_at": 9999999999, "source": source}}})
    )

    assert apply_session_signal("session-a", "tool_done") == "working"

    updated = json.loads((tmp_path / "sessions.json").read_text())
    assert updated["sessions"]["session-a"]["source"] == source
    assert applied == ["working"]


def test_session_model_is_written_and_preserved_by_python_runtime(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))

    assert apply_session_signal("session-a", "working", model_name="gpt-5") == "working"
    assert apply_session_signal("session-a", "tool_done") == "working"

    updated = json.loads((tmp_path / "sessions.json").read_text())
    assert updated["sessions"]["session-a"]["model"] == "gpt-5"
    assert applied == ["working", "working"]


def test_codex_model_name_prefers_payload_over_environment() -> None:
    hook_input = CodexHookInput(
        event_name="PreToolUse",
        payload={"request": {"model_name": "gpt-5-codex"}},
    )

    assert codex_model_name(hook_input, {"SIGNAL_LIGHT_MODEL": "fallback-model"}) == "gpt-5-codex"


def test_claude_model_name_uses_environment_fallback() -> None:
    hook_input = ClaudeCodeHookInput(event_name="PreToolUse", payload={})

    assert claude_model_name(hook_input, {"ANTHROPIC_MODEL": "claude-opus-4.1"}) == "claude-opus-4.1"


def test_apply_session_signal_keeps_permission_on_turn_end(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))

    assert apply_session_signal("session-a", "permission") == "permission"
    assert apply_session_signal("session-a", "turn_end") == "permission"

    assert runtime.read_session_snapshot()["aggregate"] == "permission"
    assert applied == ["permission", "permission"]


def test_manual_idle_clears_all_session_state(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))
    monkeypatch.setattr(cli, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))

    assert apply_session_signal("session-a", "attention") == "attention"
    assert cli.play_signal("idle") == 0
    assert runtime.read_session_snapshot() == {"aggregate": "idle", "sessions": {}}
    assert applied == ["attention", "idle"]


def test_manual_off_clears_all_session_state(tmp_path, monkeypatch) -> None:
    applied: list[str] = []
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "SESSION_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr(runtime, "LOCK_FILE", tmp_path / "state.lock")
    monkeypatch.setattr(runtime, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))
    monkeypatch.setattr(cli, "apply_signal", lambda signal, speed=1.0: applied.append(signal.name))

    assert apply_session_signal("session-a", "permission") == "permission"
    assert cli.play_signal("off") == 0
    assert runtime.read_session_snapshot() == {"aggregate": "idle", "sessions": {}}
    assert applied == ["permission", "off"]


def test_apply_signal_writes_current_status(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(runtime, "STATE_DIR", tmp_path)
    monkeypatch.setattr(runtime, "CURRENT_STATUS_FILE", tmp_path / "current_status.json")

    runtime.apply_signal(SIGNALS["permission"])

    payload = json.loads((tmp_path / "current_status.json").read_text())
    assert payload["aggregate"] == "permission"
    assert isinstance(payload["updated_at"], float)
