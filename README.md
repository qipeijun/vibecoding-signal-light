# Vibecoding Signal Light

[![GitHub Pages](https://img.shields.io/badge/website-online-22c949?style=flat-square)](https://qipeijun.github.io/vibecoding-signal-light/)
[![macOS](https://img.shields.io/badge/macOS-11%2B-111111?style=flat-square&logo=apple)](#安装)
[![Codex](https://img.shields.io/badge/Codex-supported-22c949?style=flat-square)](#codex-集成)

Codex 的 macOS 三盏状态灯。

Vibecoding Signal Light 用绿、黄、红三盏灯显示 Codex 的工作、关注、授权和阻塞。多个会话并行时按风险优先级聚合，不用反复切回 Codex，也能判断现在是否需要处理。

[下载最新 macOS 安装包](https://github.com/qipeijun/vibecoding-signal-light/releases/latest/download/Signal-Light-Installer.pkg) · [在线预览](https://qipeijun.github.io/vibecoding-signal-light/) · [查看所有版本](https://github.com/qipeijun/vibecoding-signal-light/releases)

## 适合谁

- 经常同时运行多个 Codex 会话的开发者。
- 想在 macOS 菜单栏、状态中心或桌面悬浮窗里看到 Codex 状态的人。
- 需要区分“正在工作”“等待授权”“需要关注”“已经完成”的长任务工作流。

## 核心体验

- **三盏灯状态中心**：展示当前主灯、状态说明、来源应用、模型、更新时间和跨会话风险。
- **活跃会话与最近对话**：读取本机 Codex 会话索引，显示真实会话名称；点击整行可通过 Codex URL Scheme 返回对应会话。
- **Codex 额度**：在状态中心查看 5 小时和 7 天窗口的剩余额度，并支持手动刷新。
- **菜单栏与悬浮灯**：菜单栏随时查看聚合状态，桌面悬浮灯支持置顶、透明度、尺寸和动画速度设置。
- **本地优先**：状态历史只保留灯语、时间、来源与模型等必要元数据，不记录提示词、工具参数、命令或输出。

## 功能特性

- macOS 原生 AppKit 应用，不依赖网页窗口渲染主界面。
- 菜单栏常驻三色灯图标，左键打开状态中心，右键打开快捷菜单。
- 可拖动的桌面悬浮状态灯，支持置顶、透明度、尺寸和动画速度配置。
- 单击悬浮状态灯可跳回当前主灯对应的 Codex 会话或来源应用，拖动浮层不触发跳转。
- 状态中心列出活跃会话和最近对话，支持整行点击返回指定 Codex 会话。
- 状态中心显示 Codex 5 小时与 7 天额度窗口的剩余比例。
- 支持 Codex hook，把本地事件映射为灯语。
- 安装包会自动写入用户级 Codex hooks，也可用 `signal-light doctor` 检查接线状态。
- 支持多会话风险优先聚合：阻塞、授权和关注状态不会被新的绿色工作事件覆盖。
- 状态颜色语义固定，只允许调整动画模式，避免把高风险状态误配成绿灯。
- 本地保留最近 24 小时或 200 条最小状态历史，不记录提示词、命令与输出。
- 提供配置诊断和修复入口，能检查配置文件、状态目录、写入权限和 Codex Hook 接线。
- 安装包会安装 App 和命令行工具，安装后的 hook 不依赖 Python 环境。

## 灯语说明

| 灯效 | 状态含义 | 你需要做什么 |
| --- | --- | --- |
| 绿灯常亮 | 空闲、会话开始或结束 | 不用处理 |
| 绿灯脉冲 | Codex 正在思考、执行工具、写文件、跑测试或输出内容 | 等它继续跑 |
| 绿灯双闪 | 任务刚刚完成 | 不用处理 |
| 黄灯闪烁 | Codex 等你查看结果或继续回复 | 有空看一眼 |
| 黄灯慢呼吸 | 状态来源失联，当前真实状态无法确认 | 检查 Codex 或 Hook |
| 红灯慢呼吸 | 等待授权 | 立即确认 |
| 红灯双闪 | 阻塞或失败 | 立即处理 |
| 全灭 | 状态关闭 | 不用处理 |

多个会话同时存在时按 `阻塞 > 授权 > 关注/失联 > 工作 > 完成 > 空闲` 聚合，同级状态选择最近更新的会话。

## 安装

系统要求：macOS 11 或更高版本。登录启动的自动注册需要 macOS 13 或更高版本。

从 [GitHub Release](https://github.com/qipeijun/vibecoding-signal-light/releases/latest/download/Signal-Light-Installer.pkg) 下载最新 `Signal-Light-Installer.pkg` 并安装。当前 Release 默认使用 ad-hoc 签名，macOS 可能提示无法验证；确认下载地址来自本仓库后，可在“系统设置 → 隐私与安全性”中选择“仍要打开”。

安装完成后，在 Codex 的 `/hooks` 面板确认首次发现的非托管 Hook。Signal Light 的诊断页会区分“未配置”“等待首次事件”和“已连接”。

从源码构建开发安装包：

```bash
./scripts/build-installer
```

打开安装包：

```bash
open "dist/Signal-Light-Installer.pkg"
```

本地构建的开发包默认使用 ad-hoc 签名，macOS 可能提示无法验证。确认安装包来自本地源码后，可在“系统设置 → 隐私与安全性”中选择“仍要打开”。

Release workflow 在配置以下可选 secrets 后，会自动执行 Developer ID 签名、公证、staple 和验证：

- `MACOS_CERTIFICATE_P12_BASE64`：包含 Developer ID Application / Installer 证书和私钥的 p12 文件 base64。
- `MACOS_CERTIFICATE_PASSWORD`：p12 密码。
- `DEVELOPER_ID_APPLICATION`：例如 `Developer ID Application: Your Name (TEAMID)`。
- `DEVELOPER_ID_INSTALLER`：例如 `Developer ID Installer: Your Name (TEAMID)`。
- `APPLE_ID`：Apple Developer 账号邮箱。
- `APPLE_TEAM_ID`：Apple Developer Team ID。
- `APPLE_APP_SPECIFIC_PASSWORD`：Apple ID app-specific password。

未配置上述凭据时，手动运行 workflow 或推送 `v*` Tag 仍会创建 GitHub Release，并明确标注安装包采用 ad-hoc 签名；未签名构建也会额外保留一份 Actions artifact。

安装后会写入：

- `/Applications/Signal Light.app`
- `/usr/local/bin/signal-light`
- `/usr/local/bin/codex-signal-hook`
- `/usr/local/bin/signal-light-uninstall`

安装器会在当前登录用户下尝试写入：

- `~/.codex/hooks.json`

从旧版升级时，安装器会移除旧 Signal Light 写入的 Claude Hook 和命令文件，但保留用户自己的其他 Claude 配置。

Codex 的非托管 hook 首次运行前仍需要在 Codex 的 `/hooks` 面板里确认信任，这是 Codex 自身的安全机制。

启动应用：

```bash
open "/Applications/Signal Light.app"
```

卸载：

```bash
signal-light uninstall
```

或：

```bash
signal-light-uninstall
```

## 快速试用

启动 App 后，可以用命令行预览不同状态：

```bash
signal-light list
signal-light version
signal-light play working
signal-light play attention
signal-light play permission
signal-light play idle
```

退出运行中的 App：

```bash
signal-light quit
```

检查安装和 hook 接线：

```bash
signal-light doctor
```

手动重新写入 Codex hooks：

```bash
signal-light install-hooks
```

## Codex 集成

Codex hook 可以直接调用适配脚本：

```bash
codex-signal-hook UserPromptSubmit
codex-signal-hook PreToolUse
codex-signal-hook PermissionRequest
codex-signal-hook Stop
```

推荐映射：

| Codex 事件 | 状态灯表现 |
| --- | --- |
| `SessionStart` | 绿灯常亮 |
| `UserPromptSubmit` | 绿灯脉冲 |
| `PreToolUse` | 绿灯脉冲 |
| `PostToolUse` | 绿灯脉冲 |
| `PermissionRequest` | 红灯慢呼吸 |
| `Stop` | 绿灯双闪后回到空闲 |
| `SessionEnd` | 绿灯常亮 |

Hook payload 如果通过 `status`、`state`、`error`、`failure`、`exception` 或非零 `exit_status` 明确报告失败，会映射为红灯双闪的 `blocked` 状态。

## 配置文件

配置文件路径：

```text
~/Library/Application Support/Signal Light/config.json
```

Mac App、Swift CLI 和 Python 开发脚本共享同一份配置。环境变量优先级高于配置文件：

| 环境变量 | 覆盖配置 |
| --- | --- |
| `SIGNAL_LIGHT_STATE_DIR` | `agent.stateDirectory` |
| `SIGNAL_LIGHT_SESSION_TTL_SECONDS` | `agent.sessionTTLSeconds` |
| `SIGNAL_LIGHT_WORKING_LEASE_SECONDS` | `agent.workingLeaseSeconds` |
| `SIGNAL_LIGHT_ATTENTION_LEASE_SECONDS` | `agent.attentionLeaseSeconds` |
| `SIGNAL_LIGHT_CRITICAL_LEASE_SECONDS` | `agent.criticalLeaseSeconds` |
| `SIGNAL_LIGHT_DONE_DISPLAY_SECONDS` | `agent.doneDisplaySeconds` |

配置生命周期：

- 首次启动缺少配置文件时，会自动创建默认配置。
- 旧配置会按字段合并升级，保留已有用户设置并补齐缺失字段。
- JSON 损坏时会备份为 `.broken-<timestamp>.json` 后重建默认配置。
- 旧版自定义颜色和非法动画模式会被清理，并保存清理后的配置。
- 保存或修复失败会在 UI 中显示错误，CLI 会返回非 0。

检查配置：

```bash
signal-light config status
```

修复配置：

```bash
signal-light config repair
```

## 设置面板

左键点击菜单栏图标先打开三盏灯状态中心，查看主状态、来源、模型、活跃会话、最近对话和 Codex 额度；点击齿轮进入设置：

- **显示**：悬浮窗启动显示、置顶、窗口大小、透明度、动画速度、Dock 图标、Touch Bar。
- **Codex**：状态目录、分级租约、登录启动、清理会话和状态历史。
- **规则**：为 12 个已知状态调整动画模式；颜色由风险语义锁定。
- **诊断**：区分 Hook 未配置、等待首次事件和已连接；重建配置、恢复默认与 Hook 修复都需要明确确认。

右键点击菜单栏图标打开快捷菜单，可以显示/隐藏悬浮窗或退出应用。

登录启动使用 Apple 官方 `SMAppService` API。macOS 13 及以上支持自动注册；macOS 11/12 会在 UI 中标明不支持自动设置，不保存假成功状态。

## 本地开发

运行 Swift 构建：

```bash
swift build --package-path .
```

运行 Python 测试：

```bash
PYTHONPATH=. uv run pytest
```

从源码启动 macOS App：

```bash
./scripts/signal-light-app
```

生成 README 软件界面截图：

```bash
.build/debug/signal-light-mac --capture-readme-screenshots docs/images
```

## 项目边界

- 当前版本是 macOS 原生状态灯，不恢复 MCP2221A/GPIO 硬件控制路径。
- Touch Bar 使用 macOS 公开 API，只在本 App 激活时展示，不使用私有 API 全局占用 Touch Bar。
- 未知状态、未知颜色、未知动画模式会按错误配置处理并在修复时清理，不做猜测式兜底。

## 致谢

本项目基于 [starlight36/vibecoding-signal-light](https://github.com/starlight36/vibecoding-signal-light) 二次开发。感谢原作者和原项目让“给 AI Agent 一个可见状态灯”这个想法有了可延展的开源基础。
