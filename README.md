# Vibecoding Signal Light

> A native macOS status light for local AI coding agents.
> 给 AI Agent 一个看得见的 macOS 状态灯。

Vibecoding Signal Light turns Codex, Claude Code, and other local AI coding agents into a small traffic-light utility on macOS. Its goal is not to show off automation, but to keep agent state visible without forcing you to keep checking a terminal or chat window.

Vibecoding Signal Light 把 Codex、Claude Code 等本地 AI 编程助手的状态变成 macOS 上的小型交通灯工具。它的目标不是炫技，而是让 Agent 状态保持可见，避免你反复切回终端或聊天窗口确认进度。v1 使用 macOS 原生悬浮交通灯，不接入外部硬件。

## Demo / 示例

![Vibecoding Signal Light hardware reference: green idle state mounted beside a laptop](docs/images/demo.jpg)

The macOS floating window keeps the vertical traffic-light shape from the original hardware reference.

macOS 悬浮窗会参考这张效果图，保留竖向三色信号灯形态。

## What It Shows / 灯语

| Light / 灯效 | Agent state / Agent 状态 | Human action / 你该做什么 |
| --- | --- | --- |
| Steady green / 绿灯常亮 | Idle / 空闲 | Nothing / 不用管 |
| Slow green flash / 绿灯慢闪 | Working / 正在思考、跑工具、改文件、测试或输出内容 | Wait / 等它跑 |
| Flashing yellow / 黄灯闪烁 | Attention / 明确需要你读结果或继续 | Look when convenient / 有空看一眼 |
| Flashing red / 红灯闪烁 | Permission, blocked, or failed / 需要权限、阻塞或失败 | Look now / 马上处理 |
| Off / 全灭 | Manual clear / 手动清除 | Nothing / 不用管 |

## macOS App / macOS 状态灯

The long-running display is a native Swift/AppKit app:

- Menu bar status icon with no text.
- Floating vertical traffic-light window.
- Public `NSTouchBar` integration when the app is active on Touch Bar Macs.
- Python hooks only write state files; Python does not stay alive to render UI.

长驻显示端是 Swift/AppKit 原生应用：

- 状态栏常驻三色灯图标，不显示文字。
- 可拖动的竖向信号灯悬浮窗。
- 带 Touch Bar 的 Mac 在本应用激活时会显示紧凑三灯状态。
- Python hook 只负责写状态文件，不作为长驻 UI 进程。

Touch Bar note: macOS public APIs show Touch Bar content for the active app. This project does not use private APIs to occupy the Touch Bar globally.

Touch Bar 说明：macOS 公开 API 只允许前台 App 提供 Touch Bar 内容。本项目不使用私有 API 全局占用 Touch Bar。

## Install / 安装

Build the installer package:

```bash
./scripts/build-installer
```

Then open:

```bash
open "dist/Signal Light Installer.pkg"
```

The installer puts the app in `/Applications` and installs these commands to `/usr/local/bin`:

- `signal-light`
- `codex-signal-hook`
- `claude-code-signal-hook`
- `signal-light-uninstall`

No Python environment is required for the installed app or installed hook commands.

The installer opens Signal Light automatically after installation. The app appears in the Dock and also shows a menu bar signal icon.

安装包会把应用安装到 `/Applications`，并把命令安装到 `/usr/local/bin`。安装完成后会自动启动 Signal Light；App 会出现在 Dock，同时也会显示状态栏信号灯图标。安装后的 App 和 hook 命令不依赖 Python 环境。

## Quick Start / 快速开始

Start the native macOS status light:

```bash
open "/Applications/Signal Light.app"
```

In another shell, preview signals:

```bash
signal-light list
signal-light play working
signal-light play attention
signal-light play permission
signal-light play idle
```

Quit the running app:

```bash
signal-light quit
```

Uninstall everything installed by the package:

```bash
signal-light uninstall
```

or:

```bash
signal-light-uninstall
```

The uninstaller quits the app first, then removes `/Applications/Signal Light.app`, the `/usr/local/bin` commands, and the local state directory.

During local development, you can run from the repo without installing:

```bash
./scripts/signal-light-app
./scripts/signal-light app
```

The app reads:

```text
/private/tmp/signal-light/current_status.json
```

Override the state directory when needed:

```bash
export SIGNAL_LIGHT_STATE_DIR=/private/tmp/my-signal-light
```

## Codex Integration / Codex 集成

Codex hooks can call the wrapper with the event name:

```bash
./scripts/codex-signal-hook UserPromptSubmit
./scripts/codex-signal-hook PreToolUse
./scripts/codex-signal-hook PermissionRequest
./scripts/codex-signal-hook Stop
```

Recommended mapping:

| Codex event | Signal behavior |
| --- | --- |
| `SessionStart` | Green idle |
| `UserPromptSubmit` | Green slow flash |
| `PreToolUse` | Green slow flash |
| `PostToolUse` | Green slow flash |
| `PermissionRequest` | Red flashing |
| `Stop` | Green idle |
| `SessionEnd` | Green idle |

See [docs/LAMP_LANGUAGE.md](docs/LAMP_LANGUAGE.md) for complete hook examples.

## Claude Code Integration / Claude Code 集成

Claude Code sends hook data as JSON on stdin, so the wrapper usually needs no event argument:

```bash
echo '{"event":"PreToolUse","session_id":"demo"}' | ./scripts/claude-code-signal-hook
echo '{"event":"PermissionRequest","session_id":"demo"}' | ./scripts/claude-code-signal-hook
echo '{"event":"Notification","session_id":"demo"}' | ./scripts/claude-code-signal-hook
```

Supported Claude Code events include:

| Claude Code event | Signal behavior |
| --- | --- |
| `SessionStart` | Green idle |
| `UserPromptSubmit` | Green slow flash |
| `PreToolUse` | Green slow flash |
| `PostToolUse` | Green slow flash |
| `PostToolUseFailure` | Red flashing |
| `Notification` | Yellow flashing |
| `PermissionRequest` | Red flashing |
| `Stop` | Green idle |
| `SessionEnd` | Green idle |

## Multi-Session Behavior / 多会话行为

The runtime stores the latest state for each agent session and writes the highest-priority aggregate to the macOS app state file:

```text
red flashing > yellow flashing > green slow flash > steady green
```

That means one session waiting for permission stays red even if another session starts working.

运行时会记录每个 Agent 会话的最新状态，并把最高优先级状态写给 macOS 状态灯：

```text
红灯闪烁 > 黄灯闪烁 > 工作绿灯慢闪 > 绿灯常亮
```

因此，一个会话正在等待权限时，即使另一个会话开始工作，状态灯也会继续保持红灯闪烁。

## State File Contract / 状态文件约定

The Swift app only reads explicit signal names:

```json
{
  "aggregate": "working",
  "updated_at": 1770000000.0
}
```

Unknown values are ignored instead of guessed.

Swift 应用只识别明确状态枚举；未知值会被忽略，不做宽泛兜底。

## Project Status / 项目状态

This is a native macOS status-light utility for local AI coding agents. The old MCP2221A/GPIO hardware control path remains out of scope for v1.

这是一个 macOS 原生 AI 编程状态灯小工具，用悬浮三色交通灯展示本地 Agent 状态。v1 不恢复旧的 MCP2221A/GPIO 硬件控制路径。
