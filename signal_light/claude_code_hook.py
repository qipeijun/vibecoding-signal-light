"""Claude Code hook adapter for the signal light lamp language."""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from typing import Any, Mapping

from signal_light.agent_signals import SIGNALS


EVENT_TO_SIGNAL = {
    "SessionStart": "session_start",
    "UserPromptSubmit": "thinking",
    "PreToolUse": "working",
    "PostToolUse": "tool_done",
    "PostToolUseFailure": "blocked",
    "PostToolBatch": "working",
    "PermissionDenied": "blocked",
    "PreCompact": "working",
    "PostCompact": "tool_done",
    "SubagentStart": "working",
    "SubagentStop": "tool_done",
    "TaskCreated": "working",
    "TaskCompleted": "tool_done",
    "Stop": "done",
    "StopFailure": "blocked",
    "Notification": "attention",
    "PermissionRequest": "permission",
    "SessionEnd": "session_end",
}

STOP_REASON_SIGNAL = {
    "max_tokens": "blocked",
    "error": "blocked",
}


@dataclass(frozen=True)
class ClaudeCodeHookInput:
    event_name: str
    payload: Mapping[str, Any]


def read_hook_input(argv: list[str], stdin_text: str) -> ClaudeCodeHookInput:
    event_name = _event_from_args(argv)
    payload: Mapping[str, Any] = {}

    if stdin_text.strip():
        try:
            parsed = json.loads(stdin_text)
            if isinstance(parsed, Mapping):
                payload = parsed
                event_name = event_name or parsed.get("event") or parsed.get("hook_event_name")
        except json.JSONDecodeError:
            payload = {"raw": stdin_text}

    event_name = event_name or "Stop"
    return ClaudeCodeHookInput(event_name=event_name, payload=payload)


def choose_signal(hook_input: ClaudeCodeHookInput) -> str:
    explicit = hook_input.payload.get("signal") or hook_input.payload.get("signal_name")
    if isinstance(explicit, str) and explicit.strip().lower() in SIGNALS:
        return explicit.strip().lower()

    if hook_input.event_name == "Stop":
        stop_reason = hook_input.payload.get("stop_reason")
        if isinstance(stop_reason, str) and stop_reason in STOP_REASON_SIGNAL:
            return STOP_REASON_SIGNAL[stop_reason]

    return EVENT_TO_SIGNAL.get(hook_input.event_name, "attention")


def session_key(hook_input: ClaudeCodeHookInput, environ: Mapping[str, str]) -> str:
    sid = hook_input.payload.get("session_id")
    if isinstance(sid, str) and sid.strip():
        return sid.strip()

    for key in ("CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID"):
        value = environ.get(key)
        if value:
            return value.strip()

    cwd = hook_input.payload.get("cwd")
    if isinstance(cwd, str) and cwd.strip():
        return f"cwd:{cwd.strip()}"

    return "global"


def _event_from_args(argv: list[str]) -> str | None:
    for index, value in enumerate(argv):
        if value in {"--event", "-e"} and index + 1 < len(argv):
            return argv[index + 1]
        if value.startswith("--event="):
            return value.split("=", 1)[1]
    if len(argv) >= 2 and not argv[1].startswith("-"):
        return argv[1]
    return None


def main() -> int:
    hook_input = read_hook_input(sys.argv, sys.stdin.read())
    signal = choose_signal(hook_input)
    key = session_key(hook_input, os.environ)

    from signal_light.cli import play_hook_signal

    return play_hook_signal(
        signal_name=signal,
        session_key=key,
        dry_run=os.environ.get("SIGNAL_LIGHT_DRY_RUN", "").strip().lower() in {"1", "true", "yes", "on"},
        quiet=True,
    )


if __name__ == "__main__":
    raise SystemExit(main())
