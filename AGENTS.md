# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## 项目概述

Vibecoding Signal Light 是一个面向 Codex 的 macOS 原生交通灯工具，以悬浮窗、菜单栏图标和 Touch Bar 可视化状态。

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
| `agent_signals.py` | 灯语定义 — 12 个 `AgentSignal`，包含 `stale` 失联态及各状态动画 |
| `runtime.py` | 多会话风险优先聚合、分级租约和最小化状态历史。写入 `current_status.json` / `sessions.json` / `history.json` / `codex_hook_activity.json` |
| `cli.py` | CLI 入口（`signal-light` 命令），包含 `play`/`list`/`status`/`codex-hook`/`test`/`app` 等子命令 |
| `codex_hook.py` | Codex hook 适配器，解析 Codex hook 输入的 JSON/环境变量，映射到信号名，支持从 payload 的 status/error 字段检测失败 |

### Swift 层

| 目标 | 文件 | 职责 |
| --- | --- | --- |
| SignalLightMac | `AppDelegate.swift` | 应用生命周期：状态栏图标、悬浮窗、Timer 驱动动画刷新、Darwin 通知监听、文件系统变化监听 |
| SignalLightMac | `SignalLightView.swift` | 竖向三色灯悬浮窗视图（56x122） |
| SignalLightMac | `StatusIcon.swift` | 菜单栏图标（36x18 横向三灯） |
| SignalLightMac | `TouchBarSignalView.swift` | Touch Bar 视图（132x30） |
| SignalLightShared | `SignalModels.swift` | 状态枚举、风险优先级、租约和基于 tick 的动画帧计算 |
| SignalLightShared | `SignalStateStore.swift` | 读取状态文件，以会话为状态真值并输出 UI 快照 |
| SignalLightCLI | `StateStore.swift` | Swift 版 CLI 的状态管理实现（功能与 Python runtime 对等） |
| SignalLightCLI | `HookParsing.swift` | Swift 版 Codex hook 解析（功能与 Python codex hook 对等） |
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

`sessions.json` 是多会话状态真值；`current_status.json` 是兼容旧版本的聚合快照。`codex_hook_activity.json` 只记录最近一次 Codex Hook 事件时间，用于区分“未配置”“等待首次事件”“已收到事件”三种连接状态。

### 多会话聚合

多个会话同时存在时，整体灯语按 `blocked > permission > attention/stale > working > done > idle` 聚合，同级取最近状态。

Hook 控制信号 `turn_end` 只清除非紧急会话；`idle`/`off` 播放会清除所有会话。

### 构建产物

- `swift build` 产出 `.build/release/signal-light-mac` 和 `.build/release/signal-light-cli`
- `scripts/build-installer` 将 Swift 产物打包进 `.app` bundle，再打包成 `.pkg` 安装器
- 安装后路径：`/Applications/Signal Light.app`，CLI 工具在 `/usr/local/bin/`
