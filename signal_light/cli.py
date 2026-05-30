"""Command line interface for AI agent status lights."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Sequence

from signal_light.agent_signals import SIGNALS, AgentSignal, Frame
from signal_light.runtime import SignalLightError, apply_session_signal, apply_signal, clear_session_state, read_session_snapshot


HOOK_CONTROL_SIGNALS = {"turn_end"}


class DryRunLight:
    def write(self, *, green: bool = False, yellow: bool = False, red: bool = False) -> None:
        print(f"green={int(green)} yellow={int(yellow)} red={int(red)}")

    def write_brightness(self, *, green: float = 0.0, yellow: float = 0.0, red: float = 0.0) -> None:
        print(f"green={green:.2f} yellow={yellow:.2f} red={red:.2f}")

    def off(self) -> None:
        self.write()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="signal-light",
        description="Play AI agent status patterns on the macOS signal-light app.",
    )
    subparsers = parser.add_subparsers(dest="command")

    play = subparsers.add_parser("play", help="play one lamp-language signal")
    play.add_argument("signal", choices=sorted(SIGNALS), help="signal name")
    play.add_argument("--dry-run", action="store_true", help="print light frames instead of writing macOS app state")
    play.add_argument("--speed", type=float, default=1.0, help="delay multiplier; lower is faster")
    play.add_argument("--quiet", action="store_true", help="suppress non-error output")

    subparsers.add_parser("list", help="list available lamp-language signals")
    subparsers.add_parser("status", help="show aggregated Codex session signal state")
    subparsers.add_parser("app", help="start the native macOS signal-light app")

    hook = subparsers.add_parser("codex-hook", help="read a Codex hook event and play the matching signal")
    hook.add_argument("event", nargs="?", help="Codex hook event name, for example Stop or PermissionRequest")
    hook.add_argument("--event", dest="event_option", help="Codex hook event name")
    hook.add_argument("--dry-run", action="store_true", help="print light frames instead of writing macOS app state")

    cc_hook = subparsers.add_parser("claude-code-hook", help="read a Claude Code hook event and play the matching signal")
    cc_hook.add_argument("event", nargs="?", help="Claude Code hook event name, for example Stop or PreToolUse")
    cc_hook.add_argument("--event", dest="event_option", help="Claude Code hook event name")
    cc_hook.add_argument("--dry-run", action="store_true", help="print light frames instead of writing macOS app state")

    test = subparsers.add_parser("test", help="run a quick macOS UI status preview")
    test.add_argument("--dry-run", action="store_true", help="print light frames instead of writing macOS app state")

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "list":
        return list_signals()
    if args.command == "play":
        return play_signal(args.signal, dry_run=args.dry_run, speed=args.speed, quiet=args.quiet)
    if args.command == "codex-hook":
        event = args.event_option or args.event
        from signal_light.codex_hook import choose_signal, model_name, read_codex_hook_input, session_key

        hook_argv = ["signal-light", "--event", event] if event else ["signal-light"]
        hook_input = read_codex_hook_input(hook_argv, sys.stdin.read(), os.environ)
        signal = choose_signal(hook_input)
        key = session_key(hook_input, os.environ)
        model = model_name(hook_input, os.environ)
        return play_hook_signal(signal, session_key=key, dry_run=args.dry_run, quiet=True, model_name=model)
    if args.command == "claude-code-hook":
        event = args.event_option or args.event
        from signal_light.claude_code_hook import choose_signal as cc_choose_signal
        from signal_light.claude_code_hook import model_name as cc_model_name
        from signal_light.claude_code_hook import read_hook_input, session_key as cc_session_key

        hook_argv = ["signal-light", "--event", event] if event else ["signal-light"]
        hook_input = read_hook_input(hook_argv, sys.stdin.read())
        signal = cc_choose_signal(hook_input)
        key = cc_session_key(hook_input, os.environ)
        model = cc_model_name(hook_input, os.environ)
        return play_hook_signal(signal, session_key=key, dry_run=args.dry_run, quiet=True, model_name=model)
    if args.command == "status":
        print(json.dumps(read_session_snapshot(), ensure_ascii=False, indent=2))
        return 0
    if args.command == "app":
        return run_app()
    if args.command == "test":
        return run_test(dry_run=args.dry_run)

    parser.print_help()
    return 2


def list_signals() -> int:
    print("Signal language:")
    for signal in SIGNALS.values():
        print(f"- {signal.name}: {signal.summary} {signal.attention}")
    return 0


def play_signal(signal_name: str, *, dry_run: bool = False, speed: float = 1.0, quiet: bool = False) -> int:
    signal = SIGNALS.get(signal_name)
    if signal is None:
        if not quiet:
            print(f"Unknown signal: {signal_name}", file=sys.stderr)
        return 2

    if not quiet:
        print(f"Playing {signal.name}: {signal.summary}")

    try:
        if dry_run:
            if signal.repeat:
                _preview_repeating_signal(signal, speed=speed)
            else:
                signal.play(DryRunLight(), speed=speed)
        else:
            if signal.name in {"idle", "off"}:
                clear_session_state()
            apply_signal(signal, speed=speed)
    except SignalLightError as exc:
        if not quiet:
            print(str(exc), file=sys.stderr)
        return 1

    return 0


def play_hook_signal(
    signal_name: str,
    *,
    session_key: str,
    dry_run: bool = False,
    speed: float = 1.0,
    quiet: bool = False,
    model_name: str | None = None,
) -> int:
    signal = SIGNALS.get(signal_name)
    if signal is None and signal_name not in HOOK_CONTROL_SIGNALS:
        if not quiet:
            print(f"Unknown signal: {signal_name}", file=sys.stderr)
        return 2

    if dry_run:
        if not quiet:
            print(f"Session {session_key}: {signal_name}")
        if signal is None:
            return 0
        if signal.repeat:
            _preview_repeating_signal(signal, speed=speed)
        else:
            signal.play(DryRunLight(), speed=speed)
        return 0

    try:
        aggregate = apply_session_signal(session_key, signal_name, speed=speed, model_name=model_name)
    except SignalLightError as exc:
        if not quiet:
            print(str(exc), file=sys.stderr)
        return 1

    if not quiet:
        print(f"Session {session_key}: {signal_name}; aggregate={aggregate}")
    return 0


def _preview_repeating_signal(signal: AgentSignal, *, speed: float) -> None:
    signal.play(DryRunLight(), speed=speed, cycles=2)


def run_test(*, dry_run: bool = False) -> int:
    test_signal = AgentSignal(
        name="test",
        summary="red/yellow/green wiring test",
        attention="",
        frames=(
            Frame(red=True, seconds=0.35),
            Frame(yellow=True, seconds=0.35),
            Frame(green=True, seconds=0.35),
            Frame(red=True, yellow=True, green=True, seconds=0.35),
        ),
        loops=2,
    )

    try:
        if dry_run:
            test_signal.play(DryRunLight())
        else:
            for signal_name in ("permission", "attention", "working", "idle"):
                apply_signal(SIGNALS[signal_name])
                time.sleep(0.8)
    except SignalLightError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    return 0


def run_app() -> int:
    root_dir = Path(__file__).resolve().parents[1]
    bundled_app_bin = root_dir.parent.parent / "MacOS" / "signal-light-mac"
    release_bin = root_dir / ".build" / "release" / "signal-light-mac"
    command = _app_command(root_dir, bundled_app_bin, release_bin)
    try:
        return subprocess.call(command)
    except FileNotFoundError:
        print("Swift is not installed or not available on PATH.", file=sys.stderr)
        return 1


def _app_command(root_dir: Path, bundled_app_bin: Path, release_bin: Path) -> list[str]:
    override = os.environ.get("SIGNAL_LIGHT_APP_BIN")
    if override:
        return [override]
    if bundled_app_bin.exists():
        return [str(bundled_app_bin)]
    if release_bin.exists():
        return [str(release_bin)]
    return ["swift", "run", "--package-path", str(root_dir), "signal-light-mac"]


if __name__ == "__main__":
    raise SystemExit(main())
