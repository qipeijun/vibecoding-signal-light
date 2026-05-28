# AI Agent Signal-Light Status Language

This project uses a native macOS traffic-light utility as an ambient display for Codex, Claude Code, and other local AI agents.

The language is deliberately small: the current light must describe the current state without asking you to keep checking a terminal or chat window. Animated states keep running in the Swift/AppKit app until another hook or CLI command writes a new state.

## Status Semantics

| Light | Meaning | Human action |
| --- | --- | --- |
| steady green | Agent is idle | Nothing |
| slow green flash | Agent is thinking, using tools, writing files, testing, or outputting content | Wait |
| flashing yellow | Agent explicitly needs you to read or continue | Look when convenient |
| flashing red | Agent needs permission, is blocked, or hit a failure | Look now |
| off | Manual clear | Nothing |

## Signal Names

The CLI exposes stable signal names for hooks and other agents:

| Signal | Light | Meaning |
| --- | --- | --- |
| `idle` | steady green | Agent is idle |
| `thinking` | slow green flash | Agent has received the prompt and is thinking or outputting content |
| `working` | slow green flash | Agent is using tools, editing, running commands, testing, or outputting content |
| `tool_done` | slow green flash | A tool call finished, but the agent is still active |
| `attention` | flashing yellow | Agent expects you to read or continue |
| `done` | steady green | Task completed and returned to idle |
| `permission` | flashing red | Agent requests permission |
| `blocked` | flashing red | Agent cannot continue without intervention |
| `session_start` | steady green | Agent session started and is idle |
| `session_end` | steady green | Agent session ended and returned to idle |
| `off` | off | Clear the light |

## macOS Display Surfaces

The Swift/AppKit app renders the same state in three places:

- Menu bar icon: always visible while the app is running.
- Floating window: a draggable vertical traffic-light panel.
- Touch Bar: compact three-light view when this app is active on Touch Bar Macs.

Touch Bar is not globally persistent because public macOS APIs display Touch Bar content for the active app.

## State File Contract

Python hooks and CLI commands write the current state to:

```text
/private/tmp/signal-light/current_status.json
```

Override the directory with `SIGNAL_LIGHT_STATE_DIR`.

The file shape is fixed:

```json
{
  "aggregate": "working",
  "updated_at": 1770000000.0
}
```

The Swift app only accepts known signal names and ignores unknown values.

## Codex Hook Mapping

| Codex event | Signal | Light |
| --- | --- | --- |
| `SessionStart` | `session_start` | steady green |
| `UserPromptSubmit` | `thinking` | slow green flash |
| `PreToolUse` | `working` | slow green flash |
| `PostToolUse` | `tool_done` | slow green flash |
| `PermissionRequest` | `permission` | flashing red |
| `Stop` | `done` | steady green |
| `SessionEnd` | `session_end` | steady green |

`turn_end` remains available as a hook-only control state for custom integrations. It removes that session's non-urgent working state, while leaving an existing `permission` or `blocked` red alert intact.

If the hook payload reports failure through structured fields such as `status`, `state`, `error`, `failure`, `exception`, or a non-zero `exit_status`, the adapter uses `blocked`.

## Claude Code Hook Mapping

| Claude Code event | Signal | Light |
| --- | --- | --- |
| `SessionStart` | `session_start` | steady green |
| `UserPromptSubmit` | `thinking` | slow green flash |
| `PreToolUse` | `working` | slow green flash |
| `PostToolUse` | `tool_done` | slow green flash |
| `PostToolUseFailure` | `blocked` | flashing red |
| `PreCompact` | `working` | slow green flash |
| `SubagentStart` | `working` | slow green flash |
| `SubagentStop` | `tool_done` | slow green flash |
| `PermissionRequest` | `permission` | flashing red |
| `Notification` | `attention` | flashing yellow |
| `Stop` | `done` | steady green |
| `SessionEnd` | `session_end` | steady green |

If `Stop` carries a `stop_reason` of `max_tokens` or `error`, the adapter uses `blocked` instead of clearing state.

## Hook Examples

Codex hooks can call:

```bash
/path/to/vibecoding-signal-light/scripts/codex-signal-hook UserPromptSubmit
/path/to/vibecoding-signal-light/scripts/codex-signal-hook PreToolUse
/path/to/vibecoding-signal-light/scripts/codex-signal-hook PermissionRequest
/path/to/vibecoding-signal-light/scripts/codex-signal-hook Stop
```

Claude Code hooks can call:

```bash
/path/to/vibecoding-signal-light/scripts/claude-code-signal-hook
```

Build the installer package:

```bash
/path/to/vibecoding-signal-light/scripts/build-installer
```

After installing, start the native macOS display app:

```bash
open "/Applications/Signal Light.app"
```

The installer also opens the app automatically when installation finishes. Signal Light is a normal Dock-visible app and also keeps a status icon in the menu bar.

Installed hook commands are available from `/usr/local/bin`:

```bash
signal-light
codex-signal-hook
claude-code-signal-hook
signal-light-uninstall
```

Quit the running app:

```bash
signal-light quit
```

Uninstall the app, commands, and local state:

```bash
signal-light uninstall
```
