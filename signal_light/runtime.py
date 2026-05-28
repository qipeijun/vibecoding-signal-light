"""Runtime state management for the macOS signal-light app."""

from __future__ import annotations

import json
import os
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from signal_light.agent_signals import AgentSignal, SIGNALS


STATE_DIR = Path(os.environ.get("SIGNAL_LIGHT_STATE_DIR", "/private/tmp/signal-light"))
SESSION_FILE = STATE_DIR / "sessions.json"
CURRENT_STATUS_FILE = STATE_DIR / "current_status.json"
LOCK_FILE = STATE_DIR / "state.lock"
SESSION_TTL_SECONDS = int(os.environ.get("SIGNAL_LIGHT_SESSION_TTL_SECONDS", "86400"))
STATUS_CHANGED_NOTIFICATION = b"com.vibecoding.signal-light.status-changed"

RED_SIGNALS = {"permission", "blocked"}
YELLOW_SIGNALS = {"attention"}
WORKING_SIGNALS = {"thinking", "working", "tool_done"}
SESSION_END_SIGNALS = {"session_end", "off"}
TURN_END_SIGNALS = {"turn_end"}


class SignalLightError(RuntimeError):
    """Raised when the signal-light state cannot be updated."""


def apply_signal(signal: AgentSignal, *, speed: float = 1.0) -> None:
    """Write a signal as the current persistent macOS UI status."""
    del speed
    write_current_status(signal.name)


def apply_session_signal(session_key: str, signal_name: str, *, speed: float = 1.0) -> str:
    """Update one Codex session state, then apply the aggregated global state."""
    with _state_lock():
        state = _read_session_state()
        sessions = state.setdefault("sessions", {})
        now = time.time()
        _prune_sessions(sessions, now)

        if signal_name in SESSION_END_SIGNALS:
            sessions.pop(session_key, None)
        elif signal_name in TURN_END_SIGNALS:
            current = sessions.get(session_key)
            current_signal = current.get("signal") if isinstance(current, dict) else None
            if current_signal not in RED_SIGNALS:
                sessions.pop(session_key, None)
        else:
            sessions[session_key] = {
                "signal": signal_name,
                "updated_at": now,
            }

        aggregate = aggregate_sessions(sessions)
        _write_session_state(state)
        apply_signal(SIGNALS[aggregate], speed=speed)
        return aggregate


def clear_session_state() -> None:
    """Clear all tracked Codex session states."""
    with _state_lock():
        _write_session_state({"sessions": {}})


def write_current_status(signal_name: str, *, updated_at: float | None = None) -> None:
    """Persist the current aggregate state for the Swift status-light app."""
    if signal_name not in SIGNALS:
        raise SignalLightError(f"Unknown signal: {signal_name}")

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "aggregate": signal_name,
        "updated_at": time.time() if updated_at is None else updated_at,
    }
    _atomic_write_json(CURRENT_STATUS_FILE, payload)
    _post_status_changed_notification()


def aggregate_sessions(sessions: dict[str, object]) -> str:
    signals = []
    for value in sessions.values():
        if isinstance(value, dict):
            signal_name = value.get("signal")
            if isinstance(signal_name, str):
                signals.append(signal_name)

    if any(signal_name in RED_SIGNALS for signal_name in signals):
        return "permission"
    if any(signal_name in YELLOW_SIGNALS for signal_name in signals):
        return "attention"
    if any(signal_name in WORKING_SIGNALS for signal_name in signals):
        return "working"
    return "idle"


def read_session_snapshot() -> dict[str, object]:
    state = _read_session_state()
    sessions = state.get("sessions", {})
    if not isinstance(sessions, dict):
        sessions = {}
    now = time.time()
    _prune_sessions(sessions, now)
    aggregate = aggregate_sessions(sessions)
    return {
        "aggregate": aggregate,
        "sessions": sessions,
    }


@contextmanager
def _state_lock() -> Iterator[None]:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("a+") as lock_file:
        try:
            import fcntl

            fcntl.flock(lock_file, fcntl.LOCK_EX)
            yield
        finally:
            try:
                fcntl.flock(lock_file, fcntl.LOCK_UN)
            except Exception:
                pass


def _read_session_state() -> dict[str, object]:
    try:
        state = json.loads(SESSION_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {"sessions": {}}

    if not isinstance(state, dict):
        return {"sessions": {}}
    if not isinstance(state.get("sessions"), dict):
        state["sessions"] = {}
    return state


def _write_session_state(state: dict[str, object]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    _atomic_write_json(SESSION_FILE, state)


def _atomic_write_json(path: Path, payload: dict[str, object]) -> None:
    tmp_path = path.with_suffix(f"{path.suffix}.tmp")
    try:
        tmp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
        tmp_path.replace(path)
    except OSError as exc:
        raise SignalLightError(f"Failed to write signal-light state {path}: {exc}") from exc


def _post_status_changed_notification() -> None:
    if sys.platform != "darwin":
        return

    try:
        import ctypes

        core_foundation = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        core_foundation.CFNotificationCenterGetDarwinNotifyCenter.restype = ctypes.c_void_p
        core_foundation.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
        core_foundation.CFStringCreateWithCString.restype = ctypes.c_void_p
        core_foundation.CFNotificationCenterPostNotification.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_bool,
        ]
        core_foundation.CFRelease.argtypes = [ctypes.c_void_p]

        notification_name = core_foundation.CFStringCreateWithCString(None, STATUS_CHANGED_NOTIFICATION, 0x08000100)
        if not notification_name:
            return
        try:
            center = core_foundation.CFNotificationCenterGetDarwinNotifyCenter()
            core_foundation.CFNotificationCenterPostNotification(center, notification_name, None, None, True)
        finally:
            core_foundation.CFRelease(notification_name)
    except Exception:
        return


def _prune_sessions(sessions: dict[str, object], now: float) -> None:
    expired = []
    for session_key, value in sessions.items():
        if not isinstance(value, dict):
            expired.append(session_key)
            continue
        updated_at = value.get("updated_at")
        if not isinstance(updated_at, (int, float)) or now - updated_at > SESSION_TTL_SECONDS:
            expired.append(session_key)

    for session_key in expired:
        sessions.pop(session_key, None)
