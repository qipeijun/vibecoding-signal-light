import Foundation

let signalOrder = [
    "idle",
    "thinking",
    "working",
    "tool_done",
    "attention",
    "permission",
    "blocked",
    "done",
    "session_start",
    "session_end",
    "off",
]

let signalSummaries: [String: (summary: String, attention: String)] = [
    "idle": ("Agent 空闲。", "不需要关注。"),
    "thinking": ("Agent 已收到任务，正在思考、工作或输出内容。", "不用处理。"),
    "working": ("Agent 正在执行工具、读写文件、跑命令、测试或输出内容。", "不用处理。"),
    "tool_done": ("一次工具调用完成，Agent 仍处于工作流中。", "不用处理。"),
    "attention": ("Agent 停下来等你读结果或继续回复。", "需要你看一眼 Codex。"),
    "permission": ("Codex 请求授权或需要你明确批准。", "需要立即关注。"),
    "blocked": ("Agent 遇到阻塞、失败或无法继续。", "需要你处理。"),
    "done": ("任务已完成。", "不需要关注。"),
    "session_start": ("Codex 会话开始。", "不用处理。"),
    "session_end": ("Codex 会话结束，回到空闲状态。", "不需要关注。"),
    "off": ("关闭所有灯。", "不需要关注。"),
]

let validSignals = Set(signalOrder)
let redSignals: Set<String> = ["permission", "blocked"]
let yellowSignals: Set<String> = ["attention"]
let workingSignals: Set<String> = ["thinking", "working", "tool_done"]
let sessionEndSignals: Set<String> = ["session_end", "off"]
let turnEndSignals: Set<String> = ["turn_end"]

func aggregateSessions(_ sessions: [String: SessionRecord]) -> String {
    let signals = sessions.values.map(\.signal)
    if signals.contains(where: { redSignals.contains($0) }) {
        return "permission"
    }
    if signals.contains(where: { yellowSignals.contains($0) }) {
        return "attention"
    }
    if signals.contains(where: { workingSignals.contains($0) }) {
        return "working"
    }
    return "idle"
}
