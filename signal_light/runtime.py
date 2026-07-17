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


def _config_file_path() -> Path:
    """共享配置文件路径，与 Swift 层一致。"""
    return Path.home() / "Library" / "Application Support" / "Signal Light" / "config.json"


def _validated_number(value: object, default: float, minimum: float, maximum: float) -> float:
    """解析配置数字；非法值回到默认值，保持与 Swift 配置层一致。"""
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return default
    if not minimum <= parsed <= maximum:
        return default
    return parsed


def _read_agent_config() -> dict:
    """读取 agent 配置，环境变量优先级高于配置文件。"""
    result = {
        "state_dir": "/private/tmp/signal-light",
        "session_ttl": 86400,
        "working_lease": 1800,
        "attention_lease": 7200,
        "critical_lease": 86400,
        "done_display": 6,
    }

    config_path = _config_file_path()
    try:
        if config_path.exists():
            config = json.loads(config_path.read_text())
            agent = config.get("agent", {})
            if isinstance(agent, dict):
                if "stateDirectory" in agent:
                    state_dir = agent["stateDirectory"]
                    if isinstance(state_dir, str) and state_dir.strip():
                        result["state_dir"] = state_dir.strip()
                if "sessionTTLSeconds" in agent:
                    result["session_ttl"] = _validated_number(agent["sessionTTLSeconds"], 86400, 1, 604800)
                if "workingLeaseSeconds" in agent:
                    result["working_lease"] = _validated_number(agent["workingLeaseSeconds"], 1800, 60, 604800)
                if "attentionLeaseSeconds" in agent:
                    result["attention_lease"] = _validated_number(agent["attentionLeaseSeconds"], 7200, 60, 604800)
                if "criticalLeaseSeconds" in agent:
                    result["critical_lease"] = _validated_number(agent["criticalLeaseSeconds"], 86400, 60, 604800)
                if "doneDisplaySeconds" in agent:
                    result["done_display"] = _validated_number(agent["doneDisplaySeconds"], 6, 1, 30)
    except (json.JSONDecodeError, OSError, ValueError):
        pass

    # 环境变量覆盖
    if "SIGNAL_LIGHT_STATE_DIR" in os.environ:
        state_dir = os.environ["SIGNAL_LIGHT_STATE_DIR"].strip()
        if state_dir:
            result["state_dir"] = state_dir
    if "SIGNAL_LIGHT_SESSION_TTL_SECONDS" in os.environ:
        result["session_ttl"] = _validated_number(os.environ["SIGNAL_LIGHT_SESSION_TTL_SECONDS"], result["session_ttl"], 1, 604800)
    if "SIGNAL_LIGHT_WORKING_LEASE_SECONDS" in os.environ:
        result["working_lease"] = _validated_number(os.environ["SIGNAL_LIGHT_WORKING_LEASE_SECONDS"], result["working_lease"], 60, 604800)
    if "SIGNAL_LIGHT_ATTENTION_LEASE_SECONDS" in os.environ:
        result["attention_lease"] = _validated_number(os.environ["SIGNAL_LIGHT_ATTENTION_LEASE_SECONDS"], result["attention_lease"], 60, 604800)
    if "SIGNAL_LIGHT_CRITICAL_LEASE_SECONDS" in os.environ:
        result["critical_lease"] = _validated_number(os.environ["SIGNAL_LIGHT_CRITICAL_LEASE_SECONDS"], result["critical_lease"], 60, 604800)
    if "SIGNAL_LIGHT_DONE_DISPLAY_SECONDS" in os.environ:
        result["done_display"] = _validated_number(os.environ["SIGNAL_LIGHT_DONE_DISPLAY_SECONDS"], result["done_display"], 1, 30)

    return result


_agent_config = _read_agent_config()
STATE_DIR = Path(_agent_config["state_dir"])
SESSION_FILE = STATE_DIR / "sessions.json"
CURRENT_STATUS_FILE = STATE_DIR / "current_status.json"
HISTORY_FILE = STATE_DIR / "history.json"
HOOK_ACTIVITY_FILE = STATE_DIR / "codex_hook_activity.json"
LOCK_FILE = STATE_DIR / "state.lock"
SESSION_TTL_SECONDS = _agent_config["session_ttl"]
WORKING_LEASE_SECONDS = _agent_config["working_lease"]
ATTENTION_LEASE_SECONDS = _agent_config["attention_lease"]
CRITICAL_LEASE_SECONDS = _agent_config["critical_lease"]
DONE_DISPLAY_SECONDS = _agent_config["done_display"]
HISTORY_RETENTION_SECONDS = 86400
HISTORY_ENTRY_LIMIT = 200
STATUS_CHANGED_NOTIFICATION = b"com.vibecoding.signal-light.status-changed"

RED_SIGNALS = {"permission", "blocked"}
YELLOW_SIGNALS = {"attention", "stale"}
WORKING_SIGNALS = {"thinking", "working", "tool_done"}
SESSION_END_SIGNALS = {"session_end", "off"}
TURN_END_SIGNALS = {"turn_end"}


class SignalLightError(RuntimeError):
    """Raised when the signal-light state cannot be updated."""


def apply_signal(signal: AgentSignal, *, speed: float = 1.0) -> None:
    """Write a signal as the current persistent macOS UI status."""
    del speed
    write_current_status(signal.name)


def apply_session_signal(
    session_key: str,
    signal_name: str,
    *,
    speed: float = 1.0,
    model_name: str | None = None,
) -> str:
    """Update one Codex session state, then apply the aggregated global state."""
    with _state_lock():
        state = _read_session_state()
        sessions = state.setdefault("sessions", {})
        now = time.time()
        _prune_sessions(sessions, now)
        previous = sessions.get(session_key)

        if signal_name in SESSION_END_SIGNALS:
            sessions.pop(session_key, None)
        elif signal_name in TURN_END_SIGNALS:
            current = sessions.get(session_key)
            current_signal = current.get("signal") if isinstance(current, dict) else None
            if current_signal not in RED_SIGNALS:
                sessions.pop(session_key, None)
        else:
            source = previous.get("source") if isinstance(previous, dict) else None
            previous_model = previous.get("model") if isinstance(previous, dict) else None
            sessions[session_key] = {
                "signal": signal_name,
                "updated_at": now,
            }
            if isinstance(source, dict):
                sessions[session_key]["source"] = source
            if model_name:
                sessions[session_key]["model"] = model_name
            elif isinstance(previous_model, str) and previous_model.strip():
                sessions[session_key]["model"] = previous_model

        aggregate = aggregate_sessions(sessions, now=now)
        history_record = sessions.get(session_key)
        if not isinstance(history_record, dict):
            history_record = previous if isinstance(previous, dict) else {}
        _write_session_state(state)
        _append_history(
            recorded_at=now,
            session_key=session_key,
            signal=signal_name,
            aggregate=aggregate,
            source=history_record.get("source"),
            model=history_record.get("model"),
        )
        _atomic_write_json(HOOK_ACTIVITY_FILE, {"last_event_at": now})
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


def aggregate_sessions(sessions: dict[str, object], *, now: float | None = None) -> str:
    """按风险优先级聚合；同级选择最新记录，stale 与 attention 同属黄色风险。"""
    current_time = time.time() if now is None else now
    candidates: list[tuple[int, float, str]] = []
    for value in sessions.values():
        if isinstance(value, dict):
            signal_name = value.get("signal")
            updated_at = value.get("updated_at")
            if not isinstance(signal_name, str) or not isinstance(updated_at, (int, float)):
                continue
            normalized = _normalized_aggregate_signal(signal_name)
            effective = _effective_signal(normalized, updated_at=float(updated_at), now=current_time)
            priority = _aggregate_priority(effective)
            if priority is not None:
                candidates.append((priority, float(updated_at), effective))

    active = [candidate for candidate in candidates if candidate[0] > 0]
    if active:
        return max(active, key=lambda candidate: (candidate[0], candidate[1]))[2]
    return max(candidates, key=lambda candidate: candidate[1])[2] if candidates else "idle"


def read_session_snapshot() -> dict[str, object]:
    state = _read_session_state()
    sessions = state.get("sessions", {})
    if not isinstance(sessions, dict):
        sessions = {}
    now = time.time()
    _prune_sessions(sessions, now)
    aggregate = aggregate_sessions(sessions, now=now)
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


def _append_history(
    *,
    recorded_at: float,
    session_key: str,
    signal: str,
    aggregate: str,
    source: object,
    model: object,
) -> None:
    """追加状态元数据历史；连续同态只更新时间，不记录重复 Hook 噪声。"""
    history_file = STATE_DIR / "history.json"
    try:
        payload = json.loads(history_file.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        payload = {"entries": []}

    entries = payload.get("entries") if isinstance(payload, dict) else None
    if not isinstance(entries, list):
        entries = []
    entries = [
        entry
        for entry in entries
        if isinstance(entry, dict)
        and isinstance(entry.get("recorded_at"), (int, float))
        and recorded_at - float(entry["recorded_at"]) <= HISTORY_RETENTION_SECONDS
    ]
    coalesced_entries: list[dict[str, object]] = []
    for existing in entries:
        if (
            coalesced_entries
            and coalesced_entries[-1].get("session_key") == existing.get("session_key")
            and coalesced_entries[-1].get("signal") == existing.get("signal")
            and coalesced_entries[-1].get("aggregate") == existing.get("aggregate")
        ):
            coalesced_entries[-1] = existing
        else:
            coalesced_entries.append(existing)
    entries = coalesced_entries
    entry: dict[str, object] = {
        "recorded_at": recorded_at,
        "signal": signal,
        "aggregate": aggregate,
    }
    safe_session_key = _history_session_key(session_key)
    if safe_session_key:
        entry["session_key"] = safe_session_key
    safe_source = _history_source(source)
    if safe_source:
        entry["source"] = safe_source
    if isinstance(model, str) and model.strip():
        entry["model"] = model.strip()
    if (
        entries
        and entries[-1].get("session_key") == entry.get("session_key")
        and entries[-1].get("signal") == entry.get("signal")
        and entries[-1].get("aggregate") == entry.get("aggregate")
    ):
        entries[-1] = entry
    else:
        entries.append(entry)
    _atomic_write_json(history_file, {"entries": entries[-HISTORY_ENTRY_LIMIT:]})


def _history_source(source: object) -> dict[str, object] | None:
    if not isinstance(source, dict):
        return None
    allowed = {"bundle_identifier", "process_identifier", "localized_name", "captured_at"}
    filtered = {key: value for key, value in source.items() if key in allowed}
    return filtered or None


def _history_session_key(value: str) -> str | None:
    """过滤可能由 cwd fallback 生成的本地路径。"""
    if value.startswith("cwd:") or "/" in value or "\\" in value:
        return None
    return value


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
        signal_name = value.get("signal")
        lease = _lease_duration(_normalized_aggregate_signal(signal_name)) if isinstance(signal_name, str) else 0
        if not isinstance(updated_at, (int, float)) or now - updated_at > lease + SESSION_TTL_SECONDS:
            expired.append(session_key)

    for session_key in expired:
        sessions.pop(session_key, None)


def _lease_duration(signal_name: str) -> float:
    if signal_name == "working":
        return WORKING_LEASE_SECONDS
    if signal_name == "attention":
        return ATTENTION_LEASE_SECONDS
    if signal_name in RED_SIGNALS:
        return CRITICAL_LEASE_SECONDS
    if signal_name == "done":
        return DONE_DISPLAY_SECONDS
    return 0


def _effective_signal(signal_name: str, *, updated_at: float, now: float) -> str:
    lease = _lease_duration(signal_name)
    if lease <= 0 or now - updated_at <= lease:
        return signal_name
    return "idle" if signal_name == "done" else "stale"


def _normalized_aggregate_signal(signal_name: str) -> str:
    if signal_name in WORKING_SIGNALS:
        return "working"
    if signal_name in {"session_start", "session_end", "off"}:
        return "idle"
    return signal_name


def _aggregate_priority(signal_name: str) -> int | None:
    return {
        "idle": 0,
        "done": 1,
        "working": 2,
        "attention": 3,
        "stale": 3,
        "permission": 4,
        "blocked": 5,
    }.get(signal_name)
