# Vibecoding Signal Light

给本地 AI 编程助手一个看得见的 macOS 状态灯。

Vibecoding Signal Light 是一个 macOS 原生状态灯工具，用悬浮三色灯、菜单栏图标和配置面板展示 Codex、Claude Code 等本地 Agent 的实时状态。它适合长时间让 Agent 跑工具、改文件、等权限或等待你继续回复的场景：不用反复切回终端，也能一眼知道现在该不该处理。

项目预览地址：[在线预览](https://qipeijun.github.io/vibecoding-signal-light/)


## 界面预览

### 悬浮状态灯

![悬浮状态灯](docs/images/screenshot-floating-light.png)

### 显示设置

![显示设置面板](docs/images/screenshot-settings-display.png)

### 状态规则

![状态规则面板](docs/images/screenshot-rules-panel.png)

### 配置诊断

![配置诊断面板](docs/images/screenshot-diagnostics.png)

### 演示视频

<video src="https://github.com/user-attachments/assets/509e2720-5d0c-4852-89b9-305272a998b1" controls muted playsinline width="720">
  <a href="https://github.com/user-attachments/assets/509e2720-5d0c-4852-89b9-305272a998b1">查看演示视频 1</a>
</video>

<video src="https://github.com/user-attachments/assets/b676d1f0-470c-4ce9-970e-c6f3e2542ea4" controls muted playsinline width="720">
  <a href="https://github.com/user-attachments/assets/b676d1f0-470c-4ce9-970e-c6f3e2542ea4">查看演示视频 2</a>
</video>

## 功能特性

- macOS 原生 AppKit 应用，不依赖网页窗口渲染主界面。
- 菜单栏常驻三色灯图标，左键打开设置面板，右键打开快捷菜单。
- 可拖动的桌面悬浮状态灯，支持置顶、透明度、尺寸和动画速度配置。
- 支持 Codex、Claude Code hook，把本地 Agent 事件映射为灯语。
- 支持多会话聚合：有任意会话请求权限或阻塞时，整体状态优先显示红灯。
- 支持状态规则自定义，可以为每个已知状态配置颜色和动画模式。
- 提供配置诊断和修复入口，能检查配置文件、状态目录和写入权限。
- 安装包会安装 App 和命令行工具，安装后的 hook 不依赖 Python 环境。

## 灯语说明

| 灯效 | 状态含义 | 你需要做什么 |
| --- | --- | --- |
| 绿灯常亮 | 空闲、完成、会话开始或结束 | 不用处理 |
| 绿灯脉冲 | Agent 正在思考、执行工具、写文件、跑测试或输出内容 | 等它继续跑 |
| 黄灯闪烁 | Agent 停下来等你查看结果或继续回复 | 有空看一眼 |
| 红灯闪烁 | 请求授权、阻塞、失败或需要你明确处理 | 立即处理 |
| 全灭 | 状态关闭 | 不用处理 |

状态规则只影响 macOS 显示端，不改变 hook 写入的状态枚举，也不改变多会话聚合优先级。

## 安装

构建安装包：

```bash
./scripts/build-installer
```

打开安装包：

```bash
open "dist/Signal-Light-Installer.pkg"
```

安装后会写入：

- `/Applications/Signal Light.app`
- `/usr/local/bin/signal-light`
- `/usr/local/bin/codex-signal-hook`
- `/usr/local/bin/claude-code-signal-hook`
- `/usr/local/bin/signal-light-uninstall`

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
signal-light play working
signal-light play attention
signal-light play permission
signal-light play idle
```

退出运行中的 App：

```bash
signal-light quit
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
| `PermissionRequest` | 红灯闪烁 |
| `Stop` | 绿灯常亮 |
| `SessionEnd` | 绿灯常亮 |

完整灯语和 hook 示例见 [docs/LAMP_LANGUAGE.md](docs/LAMP_LANGUAGE.md)。

## Claude Code 集成

Claude Code hook 通常从 stdin 传入 JSON：

```bash
echo '{"event":"PreToolUse","session_id":"demo"}' | claude-code-signal-hook
echo '{"event":"PermissionRequest","session_id":"demo"}' | claude-code-signal-hook
echo '{"event":"Notification","session_id":"demo"}' | claude-code-signal-hook
```

常见映射：

| Claude Code 事件 | 状态灯表现 |
| --- | --- |
| `SessionStart` | 绿灯常亮 |
| `UserPromptSubmit` | 绿灯脉冲 |
| `PreToolUse` | 绿灯脉冲 |
| `PostToolUse` | 绿灯脉冲 |
| `PostToolUseFailure` | 红灯闪烁 |
| `PermissionDenied` | 红灯闪烁 |
| `Notification` | 黄灯闪烁 |
| `PermissionRequest` | 红灯闪烁 |
| `Stop` | 绿灯常亮 |
| `StopFailure` | 红灯闪烁 |
| `SessionEnd` | 绿灯常亮 |

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

配置生命周期：

- 首次启动缺少配置文件时，会自动创建默认配置。
- 旧配置会按字段合并升级，保留已有用户设置并补齐缺失字段。
- JSON 损坏时会备份为 `.broken-<timestamp>.json` 后重建默认配置。
- 非法状态规则、颜色或动画模式会被清理，并保存清理后的配置。
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

左键点击菜单栏图标打开设置面板：

- **显示**：悬浮窗启动显示、置顶、窗口大小、透明度、动画速度、Dock 图标、Touch Bar。
- **Agent**：状态目录、会话超时、登录启动、清理会话。
- **规则**：为 11 个已知状态配置颜色和动画模式。
- **诊断**：检查配置文件、状态目录和修复写入问题。

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
