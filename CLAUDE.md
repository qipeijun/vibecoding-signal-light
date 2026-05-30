# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Vibecoding Signal Light 是一个 macOS 原生交通灯工具，将 Codex、Claude Code 等本地 AI Agent 的状态以悬浮窗、菜单栏图标和 Touch Bar 的形式可视化展示。

## 常用命令

```bash
# Python 测试
uv run pytest                          # 运行所有测试
uv run pytest tests/test_agent_signals.py -v  # 运行单个测试文件

# 开发时运行 Python CLI（不安装）
./scripts/signal-light list            # 列出所有信号
./scripts/signal-light play working    # 播放信号
./scripts/signal-light status          # 查看聚合状态

# 构建和运行 Swift 应用
swift build --package-path .           # 构建 Swift 目标
./scripts/signal-light-app             # 启动 macOS 应用

# Hook 测试
./scripts/codex-signal-hook Stop       # Codex hook
echo '{"event":"PreToolUse"}' | ./scripts/claude-code-signal-hook  # Claude Code hook

# 构建安装包
./scripts/build-installer              # 输出到 dist/Signal Light Installer.pkg
```

## 核心架构

### 双语言设计

- **Python** (`signal_light/`)：状态管理、CLI、hook 适配器。Python 只负责写状态文件，不做长驻 UI。
- **Swift** (`Sources/`)：macOS AppKit 原生 UI，长驻进程，读取 Python 写的状态文件并渲染。

### Python 层

| 文件 | 职责 |
| --- | --- |
| `agent_signals.py` | 灯语定义 — 11 个 `AgentSignal`（`idle`, `thinking`, `working`, `tool_done`, `attention`, `permission`, `blocked`, `done`, `session_start`, `session_end`, `off`），每个信号包含帧序列和循环行为 |
| `runtime.py` | 多会话状态管理。每个 Agent 会话独立追踪状态，以最近一次有效 hook 写入聚合状态。写入 `current_status.json` |
| `cli.py` | CLI 入口（`signal-light` 命令），子命令：`play`/`list`/`status`/`codex-hook`/`claude-code-hook`/`test`/`app` |
| `codex_hook.py` | Codex hook 适配器，解析 Codex hook 输入的 JSON/环境变量，映射到信号名，支持从 payload 的 status/error 字段检测失败 |
| `claude_code_hook.py` | Claude Code hook 适配器，支持 `stop_reason` 检测（`max_tokens`/`error` → blocked） |

### Swift 层

| 目标 | 文件 | 职责 |
| --- | --- | --- |
| SignalLightMac | `AppDelegate.swift` | 应用生命周期：状态栏图标、悬浮窗、Timer 驱动动画刷新、Darwin 通知监听、文件系统变化监听 |
| SignalLightMac | `SignalState.swift` | 状态枚举 + 状态文件读取 + 帧计算（基于 tick 的动画逻辑） |
| SignalLightMac | `SignalLightView.swift` | 竖向三色灯悬浮窗视图（56x122） |
| SignalLightMac | `StatusIcon.swift` | 菜单栏图标（36x18 横向三灯） |
| SignalLightMac | `TouchBarSignalView.swift` | Touch Bar 视图（132x30） |
| SignalLightCLI | `StateStore.swift` | Swift 版 CLI 的状态管理实现（功能与 Python runtime 对等） |
| SignalLightCLI | `HookParsing.swift` | Swift 版 hook 解析（功能与 Python codex/claude hook 对等） |
| SignalLightCLI | `AppLifecycle.swift` | 应用卸载和生命周期管理 |

关键点：CLI 有两套实现（Python 和 Swift），安装后的 `/usr/local/bin/signal-light` 指向 app bundle 内的 Swift 编译产物，不依赖 Python。

### 通信机制

Python 写入状态文件 → 通过三重通道通知 Swift 应用：
1. **Darwin CFNotification** (`com.vibecoding.signal-light.status-changed`) — 跨进程广播
2. **DistributedNotificationCenter** — 同用户会话内通知
3. **文件系统监控** (`DispatchSourceFileSystemObject`) — 兜底机制

Swift 应用每 0.18s 刷新一帧动画（tick 驱动），每 3s 做一次文件回退检查。

### 状态文件约定

```json
// /private/tmp/signal-light/current_status.json （可通过 SIGNAL_LIGHT_STATE_DIR 覆盖）
{"aggregate": "working", "updated_at": 1770000000.0}
```

aggregate 必须是已知信号名，未知值会被 Swift 应用忽略。

### 多会话聚合

多个会话同时存在时，整体灯语以最近一次有效 hook 写入为准，避免旧会话长期压住新会话。

Hook 控制信号 `turn_end` 只清除非紧急会话；`idle`/`off` 播放会清除所有会话。

### 构建产物

- `swift build` 产出 `.build/release/signal-light-mac` 和 `.build/release/signal-light-cli`
- `scripts/build-installer` 将 Swift 产物打包进 `.app` bundle，再打包成 `.pkg` 安装器
- 安装后路径：`/Applications/Signal Light.app`，CLI 工具在 `/usr/local/bin/`
