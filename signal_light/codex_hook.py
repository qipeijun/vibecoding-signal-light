"""Codex hook adapter for the signal light lamp language."""

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
    "PermissionRequest": "permission",
    "Stop": "done",
    "SessionEnd": "session_end",
}

FAILURE_SIGNALS = {
    "error": "blocked",
    "failed": "blocked",
    "failure": "blocked",
    "exception": "blocked",
}


@dataclass(frozen=True)
class CodexHookInput:
    event_name: str
    payload: Mapping[str, Any]


def read_codex_hook_input(argv: list[str], stdin_text: str, environ: Mapping[str, str]) -> CodexHookInput:
    event_name = _event_from_args(argv)
    payload: Mapping[str, Any] = {}

    if stdin_text.strip():
        try:
            parsed = json.loads(stdin_text)
            if isinstance(parsed, Mapping):
                payload = parsed
                event_name = event_name or _event_from_payload(parsed)
        except json.JSONDecodeError:
            payload = {"raw": stdin_text}

    event_name = event_name or environ.get("CODEX_HOOK_EVENT") or environ.get("HOOK_EVENT") or "Stop"
    return CodexHookInput(event_name=event_name, payload=payload)


def choose_signal(hook_input: CodexHookInput) -> str:
    explicit = _first_string(
        hook_input.payload,
        ("signal", "signal_name", "lamp_signal"),
    )
    if explicit:
        normalized = explicit.strip().lower()
        if normalized in SIGNALS:
            return normalized

    status = _first_string(hook_input.payload, ("status", "state"))
    if status:
        normalized_status = status.strip().lower()
        if normalized_status in SIGNALS:
            return normalized_status
        if normalized_status in FAILURE_SIGNALS:
            return FAILURE_SIGNALS[normalized_status]

    failure_marker = _structured_failure_marker(hook_input.payload)
    if failure_marker:
        return FAILURE_SIGNALS[failure_marker]

    return EVENT_TO_SIGNAL.get(hook_input.event_name, EVENT_TO_SIGNAL.get(hook_input.event_name.strip(), "attention"))


def session_key(hook_input: CodexHookInput, environ: Mapping[str, str]) -> str:
    explicit = _first_string(
        hook_input.payload,
        (
            "session_id",
            "conversation_id",
            "thread_id",
            "chat_id",
            "codex_session_id",
        ),
    )
    if explicit:
        return explicit.strip()

    nested = _find_nested_string(
        hook_input.payload,
        (
            "session_id",
            "conversation_id",
            "thread_id",
            "codex_session_id",
        ),
    )
    if nested:
        return nested

    for key in (
        "CODEX_SESSION_ID",
        "CODEX_CONVERSATION_ID",
        "CODEX_THREAD_ID",
    ):
        value = environ.get(key)
        if value:
            return value.strip()

    cwd = _first_string(hook_input.payload, ("cwd", "workspace", "workspace_dir", "project_dir"))
    if cwd:
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


def _event_from_payload(payload: Mapping[str, Any]) -> str | None:
    return _first_string(
        payload,
        ("hook_event_name", "event_name", "event", "hook", "type"),
    )


def _first_string(payload: Mapping[str, Any], keys: tuple[str, ...]) -> str | None:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return value
    return None


def _find_nested_string(value: Any, keys: tuple[str, ...]) -> str | None:
    if isinstance(value, Mapping):
        direct = _first_string(value, keys)
        if direct:
            return direct.strip()
        for child in value.values():
            found = _find_nested_string(child, keys)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _find_nested_string(child, keys)
            if found:
                return found
    return None


def _structured_failure_marker(payload: Mapping[str, Any]) -> str | None:
    return _find_failure_marker(
        payload,
        (
            "error",
            "failure",
            "exception",
            "error_type",
            "error_message",
            "failure_reason",
            "exit_status",
            "tool_error",
        ),
    )


def _find_failure_marker(value: Any, keys: tuple[str, ...]) -> str | None:
    if isinstance(value, Mapping):
        for key, child in value.items():
            normalized_key = str(key).strip().lower()
            if normalized_key in FAILURE_SIGNALS or normalized_key in keys:
                marker = _failure_marker_from_value(child)
                if marker:
                    return marker
            found = _find_failure_marker(child, keys)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _find_failure_marker(child, keys)
            if found:
                return found
    return None


def _failure_marker_from_value(value: Any) -> str | None:
    if isinstance(value, bool):
        return "error" if value else None
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return "failed" if value != 0 else None
    if isinstance(value, str):
        normalized = value.strip().lower()
        if not normalized or normalized in {"0", "false", "no", "none", "null", "success", "ok"}:
            return None
        for marker in FAILURE_SIGNALS:
            if marker in normalized:
                return marker
        return "error"
    return "error"


def main() -> int:
    hook_input = read_codex_hook_input(sys.argv, sys.stdin.read(), os.environ)
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
