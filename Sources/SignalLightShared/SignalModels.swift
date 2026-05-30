import Foundation

// MARK: - 信号状态枚举

public enum SignalState: String, Codable, CaseIterable {
    case idle
    case thinking
    case working
    case toolDone = "tool_done"
    case attention
    case permission
    case blocked
    case done
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case off

    public var displayMode: SignalDisplayMode {
        switch self {
        case .idle, .done, .sessionStart, .sessionEnd:
            return .steady(.green)
        case .thinking, .working, .toolDone:
            return .workPulse(.green)
        case .attention:
            return .flash(.yellow)
        case .permission, .blocked:
            return .flash(.red)
        case .off:
            return .off
        }
    }

    public var displayName: String {
        switch self {
        case .idle:
            return "空闲"
        case .thinking:
            return "思考中"
        case .working, .toolDone:
            return "工作中"
        case .attention:
            return "等待关注"
        case .permission:
            return "等待授权"
        case .blocked:
            return "已阻塞"
        case .done:
            return "已完成"
        case .sessionStart:
            return "会话开始"
        case .sessionEnd:
            return "会话结束"
        case .off:
            return "已关闭"
        }
    }
}

public enum SignalColor {
    case green
    case yellow
    case red

    public init?(rawConfig: String) {
        switch rawConfig {
        case "green":
            self = .green
        case "yellow":
            self = .yellow
        case "red":
            self = .red
        default:
            return nil
        }
    }
}

public enum SignalDisplayMode {
    case off
    case steady(SignalColor)
    case flash(SignalColor)
    case workPulse(SignalColor)

    public init?(rule: SignalRuleConfig, defaultMode: SignalDisplayMode) {
        let color: SignalColor?
        if let rawColor = rule.color {
            guard let parsedColor = SignalColor(rawConfig: rawColor) else {
                return nil
            }
            color = parsedColor
        } else {
            color = nil
        }
        switch rule.mode {
        case nil:
            self = defaultMode.replacingColor(with: color)
        case "off":
            self = .off
        case "steady":
            guard let color = color ?? defaultMode.defaultColor else { return nil }
            self = .steady(color)
        case "flash":
            guard let color = color ?? defaultMode.defaultColor else { return nil }
            self = .flash(color)
        case "workPulse":
            self = .workPulse(color ?? defaultMode.defaultColor ?? .green)
        default:
            return nil
        }
    }

    private var defaultColor: SignalColor? {
        switch self {
        case .steady(let color), .flash(let color):
            return color
        case .workPulse(let color):
            return color
        case .off:
            return nil
        }
    }

    private func replacingColor(with color: SignalColor?) -> SignalDisplayMode {
        guard let color else {
            return self
        }
        switch self {
        case .steady:
            return .steady(color)
        case .flash:
            return .flash(color)
        case .workPulse:
            return .workPulse(color)
        case .off:
            return .steady(color)
        }
    }
}

public struct SignalFrame {
    public var green: CGFloat
    public var yellow: CGFloat
    public var red: CGFloat

    public init(green: CGFloat, yellow: CGFloat, red: CGFloat) {
        self.green = green
        self.yellow = yellow
        self.red = red
    }
}

// MARK: - 状态文件数据模型

public struct SignalStatus: Decodable {
    public let aggregate: String
    public let updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case aggregate
        case updatedAt = "updated_at"
    }
}

public struct SessionSource: Codable, Equatable {
    public var bundleIdentifier: String?
    public var processIdentifier: Int?
    public var localizedName: String?
    public var capturedAt: Double

    enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundle_identifier"
        case processIdentifier = "process_identifier"
        case localizedName = "localized_name"
        case capturedAt = "captured_at"
    }

    public init(
        bundleIdentifier: String?,
        processIdentifier: Int?,
        localizedName: String?,
        capturedAt: Double
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.localizedName = localizedName
        self.capturedAt = capturedAt
    }
}

public struct SessionRecord: Codable {
    public var signal: String
    public var updatedAt: Double
    public var source: SessionSource?
    public var model: String?

    enum CodingKeys: String, CodingKey {
        case signal
        case updatedAt = "updated_at"
        case source
        case model
    }

    public init(signal: String, updatedAt: Double, source: SessionSource? = nil, model: String? = nil) {
        self.signal = signal
        self.updatedAt = updatedAt
        self.source = source
        self.model = model
    }
}

public struct SessionState: Codable {
    public var sessions: [String: SessionRecord]

    public init(sessions: [String: SessionRecord]) {
        self.sessions = sessions
    }
}

public struct CurrentStatus: Codable {
    public var aggregate: String
    public var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case aggregate
        case updatedAt = "updated_at"
    }

    public init(aggregate: String, updatedAt: Double) {
        self.aggregate = aggregate
        self.updatedAt = updatedAt
    }
}

// MARK: - 信号分类常量

public let signalOrder = [
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

public let signalSummaries: [String: (summary: String, attention: String)] = [
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

public let validSignals = Set(signalOrder)
public let redSignals: Set<String> = ["permission", "blocked"]
public let yellowSignals: Set<String> = ["attention"]
public let workingSignals: Set<String> = ["thinking", "working", "tool_done"]
public let sessionEndSignals: Set<String> = ["session_end", "off"]
public let turnEndSignals: Set<String> = ["turn_end"]

// MARK: - 动画帧计算

public func frame(for state: SignalState, tick: Int) -> SignalFrame {
    frame(for: state.displayMode, tick: tick)
}

public func frame(for state: SignalState, tick: Int, rules: StatusRulesConfig) -> SignalFrame {
    let defaultMode = state.displayMode
    let mode = rules.rules[state.rawValue].flatMap {
        SignalDisplayMode(rule: $0, defaultMode: defaultMode)
    } ?? defaultMode
    return frame(for: mode, tick: tick)
}

private func frame(for displayMode: SignalDisplayMode, tick: Int) -> SignalFrame {
    switch displayMode {
    case .off:
        return SignalFrame(green: 0, yellow: 0, red: 0)
    case .steady(let color):
        return frame(color: color, brightness: 1)
    case .flash(let color):
        return frame(color: color, brightness: tick.isMultiple(of: 2) ? 1 : 0)
    case .workPulse(let color):
        return frame(color: color, brightness: tick % 8 < 5 ? 1 : 0)
    }
}

private func frame(color: SignalColor, brightness: CGFloat) -> SignalFrame {
    switch color {
    case .green:
        return SignalFrame(green: brightness, yellow: 0, red: 0)
    case .yellow:
        return SignalFrame(green: 0, yellow: brightness, red: 0)
    case .red:
        return SignalFrame(green: 0, yellow: 0, red: brightness)
    }
}

// MARK: - 会话聚合

public func aggregateSessions(_ sessions: [String: SessionRecord]) -> String {
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
