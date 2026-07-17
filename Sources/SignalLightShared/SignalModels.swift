import Foundation

// MARK: - 信号状态枚举

public enum SignalState: String, Codable, CaseIterable {
    /// 当前没有需要处理的 Agent 活动。
    case idle
    /// Agent 已收到请求，尚未进入工具执行阶段。
    case thinking
    /// Agent 正在执行工具、命令或生成结果。
    case working
    /// 单次工具调用完成，但当前任务仍在继续。
    case toolDone = "tool_done"
    /// Agent 等待用户查看结果或继续回复。
    case attention
    /// Agent 等待用户明确授权后才能继续。
    case permission
    /// Agent 因错误或外部条件无法继续，区别于等待授权。
    case blocked
    /// 任务刚刚完成；该状态只短暂展示，随后回到空闲。
    case done
    /// Agent 会话刚刚建立。
    case sessionStart = "session_start"
    /// Agent 会话已经结束。
    case sessionEnd = "session_end"
    /// 最近状态已超过租约，当前真实运行状态无法确认。
    case stale
    /// 用户主动关闭全部灯光显示。
    case off

    public var displayMode: SignalDisplayMode {
        switch self {
        case .idle, .sessionStart, .sessionEnd:
            return .steady(.green)
        case .thinking, .working, .toolDone:
            return .workPulse(.green)
        case .attention:
            return .flash(.yellow)
        case .permission:
            return .slowPulse(.red)
        case .blocked:
            return .doubleFlash(.red)
        case .done:
            return .doubleFlash(.green)
        case .stale:
            return .slowPulse(.yellow)
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
        case .stale:
            return "状态失联"
        case .off:
            return "已关闭"
        }
    }

    /// 仅长期驻留的环境状态允许用户调整动画速度，行动提示保持固定节奏，避免失去紧迫度语义。
    public var allowsAnimationSpeedAdjustment: Bool {
        switch self {
        case .thinking, .working, .toolDone, .stale:
            return true
        case .idle, .attention, .permission, .blocked, .done, .sessionStart, .sessionEnd, .off:
            return false
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
    case slowPulse(SignalColor)
    case doubleFlash(SignalColor)

    public init?(rule: SignalRuleConfig, defaultMode: SignalDisplayMode) {
        // 状态颜色承担固定语义，不允许配置覆盖；color 仅为旧配置解码兼容保留。
        let color = defaultMode.defaultColor
        switch rule.mode {
        case nil:
            self = defaultMode
        case "off":
            self = .off
        case "steady":
            guard let color else { return nil }
            self = .steady(color)
        case "flash":
            guard let color else { return nil }
            self = .flash(color)
        case "workPulse":
            self = .workPulse(color ?? .green)
        case "slowPulse":
            guard let color else { return nil }
            self = .slowPulse(color)
        case "doubleFlash":
            guard let color else { return nil }
            self = .doubleFlash(color)
        default:
            return nil
        }
    }

    private var defaultColor: SignalColor? {
        switch self {
        case .steady(let color), .flash(let color):
            return color
        case .workPulse(let color), .slowPulse(let color), .doubleFlash(let color):
            return color
        case .off:
            return nil
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

/// 本地状态历史条目。只记录状态元数据，不保存 prompt、工具参数或输出内容。
public struct SignalHistoryEntry: Codable, Equatable {
    public var recordedAt: Double
    public var sessionKey: String?
    public var signal: String
    public var aggregate: String
    public var source: SessionSource?
    public var model: String?

    enum CodingKeys: String, CodingKey {
        case recordedAt = "recorded_at"
        case sessionKey = "session_key"
        case signal
        case aggregate
        case source
        case model
    }

    public init(
        recordedAt: Double,
        sessionKey: String?,
        signal: String,
        aggregate: String,
        source: SessionSource? = nil,
        model: String? = nil
    ) {
        self.recordedAt = recordedAt
        self.sessionKey = sessionKey
        self.signal = signal
        self.aggregate = aggregate
        self.source = source
        self.model = model
    }
}

public struct SignalHistory: Codable, Equatable {
    public var entries: [SignalHistoryEntry]

    public init(entries: [SignalHistoryEntry]) {
        self.entries = entries
    }
}

/// Codex Hook 最近一次真实事件，只记录时间戳，不保存事件内容。
public struct CodexHookActivity: Codable, Equatable {
    public var lastEventAt: Double

    enum CodingKeys: String, CodingKey {
        case lastEventAt = "last_event_at"
    }

    public init(lastEventAt: Double) {
        self.lastEventAt = lastEventAt
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
    "stale",
    "off",
]

public let signalSummaries: [String: (summary: String, attention: String)] = [
    "idle": ("Codex 空闲。", "不需要关注。"),
    "thinking": ("Codex 已收到任务，正在思考、工作或输出内容。", "不用处理。"),
    "working": ("Codex 正在执行工具、读写文件、跑命令、测试或输出内容。", "不用处理。"),
    "tool_done": ("一次工具调用完成，Codex 仍处于工作流中。", "不用处理。"),
    "attention": ("Codex 停下来等你读结果或继续回复。", "需要你看一眼 Codex。"),
    "permission": ("Codex 请求授权或需要你明确批准。", "需要立即关注。"),
    "blocked": ("Codex 遇到阻塞、失败或无法继续。", "需要你处理。"),
    "done": ("任务已完成。", "不需要关注。"),
    "session_start": ("Codex 会话开始。", "不用处理。"),
    "session_end": ("Codex 会话结束，回到空闲状态。", "不需要关注。"),
    "stale": ("最近状态已超过租约，当前真实状态无法确认。", "建议检查 Codex 或 Hook 是否仍在运行。"),
    "off": ("关闭所有灯。", "不需要关注。"),
]

public let validSignals = Set(signalOrder)
public let redSignals: Set<String> = ["permission", "blocked"]
public let yellowSignals: Set<String> = ["attention", "stale"]
public let workingSignals: Set<String> = ["thinking", "working", "tool_done"]
public let sessionEndSignals: Set<String> = ["session_end", "off"]
public let turnEndSignals: Set<String> = ["turn_end"]

public let historyRetentionSeconds: Double = 24 * 60 * 60
public let historyEntryLimit = 200

/// 可配置的分级状态租约，Swift CLI、macOS App 与 Python runtime 必须使用同一组值。
public struct SignalLeasePolicy: Codable, Equatable {
    public var workingSeconds: Double
    public var attentionSeconds: Double
    public var criticalSeconds: Double
    public var doneSeconds: Double

    public static let `default` = SignalLeasePolicy(
        workingSeconds: 1800,
        attentionSeconds: 7200,
        criticalSeconds: 86400,
        doneSeconds: 6
    )

    public init(workingSeconds: Double, attentionSeconds: Double, criticalSeconds: Double, doneSeconds: Double) {
        self.workingSeconds = workingSeconds
        self.attentionSeconds = attentionSeconds
        self.criticalSeconds = criticalSeconds
        self.doneSeconds = doneSeconds
    }
}

/// 返回状态的有效租约；nil 表示该状态不依赖时间自动过期。
public func leaseDuration(for signal: String, policy: SignalLeasePolicy = .default) -> Double? {
    switch signal {
    case "thinking", "working", "tool_done":
        return policy.workingSeconds
    case "attention":
        return policy.attentionSeconds
    case "permission", "blocked":
        return policy.criticalSeconds
    case "done":
        return policy.doneSeconds
    default:
        return nil
    }
}

/// 将单个持久化状态解析为当前有效状态，供文件读取端和聚合端共用。
public func effectiveSignal(
    _ signal: String,
    updatedAt: Double,
    now: Double,
    policy: SignalLeasePolicy = .default
) -> String {
    guard let lease = leaseDuration(for: signal, policy: policy), now - updatedAt > lease else {
        return signal
    }
    return signal == "done" ? "idle" : "stale"
}

// MARK: - 动画帧计算

public func frame(for state: SignalState, tick: Int) -> SignalFrame {
    frame(for: state.displayMode, tick: tick)
}

public func frame(
    for state: SignalState,
    tick: Int,
    rules: StatusRulesConfig,
    reduceMotion: Bool = false
) -> SignalFrame {
    let mode = resolvedDisplayMode(for: state, rules: rules)
    return reduceMotion ? reducedMotionFrame(for: mode) : frame(for: mode, tick: tick)
}

/// 按时间采样 UI 动画帧。该入口供高刷新率界面使用，避免 UI 自行换算离散 tick。
public func frame(
    for state: SignalState,
    elapsedTime: TimeInterval,
    rules: StatusRulesConfig,
    reduceMotion: Bool = false
) -> SignalFrame {
    let mode = resolvedDisplayMode(for: state, rules: rules)
    return reduceMotion
        ? reducedMotionFrame(for: mode)
        : frame(for: mode, state: state, elapsedTime: max(0, elapsedTime))
}

private func resolvedDisplayMode(for state: SignalState, rules: StatusRulesConfig) -> SignalDisplayMode {
    let defaultMode = state.displayMode
    return rules.rules[state.rawValue].flatMap { rule -> SignalDisplayMode? in
        var visibleRule = rule
        if visibleRule.mode == "off", state != .done, state != .off {
            visibleRule.mode = nil
        }
        return SignalDisplayMode(rule: visibleRule, defaultMode: defaultMode)
    } ?? defaultMode
}

/// 减少动态效果开启时保留颜色语义，用常亮替代闪烁、脉冲和双闪。
private func reducedMotionFrame(for mode: SignalDisplayMode) -> SignalFrame {
    switch mode {
    case .off:
        return SignalFrame(green: 0, yellow: 0, red: 0)
    case .steady(let color),
         .flash(let color),
         .workPulse(let color),
         .slowPulse(let color),
         .doubleFlash(let color):
        return frame(color: color, brightness: 1)
    }
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
        let levels = SignalAnimationTiming.pulseLevels
        return frame(color: color, brightness: levels[positiveModulo(tick, levels.count)])
    case .slowPulse(let color):
        let levels = SignalAnimationTiming.pulseLevels
        return frame(color: color, brightness: levels[positiveModulo(tick, levels.count)])
    case .doubleFlash(let color):
        let phase = positiveModulo(tick, 8)
        return frame(color: color, brightness: phase == 0 || phase == 2 ? 1 : 0)
    }
}

/// 状态灯默认节奏。颜色表示状态性质，动画形态表示是否需要介入，周期只表达紧迫程度。
private enum SignalAnimationTiming {
    static let ambientPulsePeriod: TimeInterval = 2.0
    static let attentionPeriod: TimeInterval = 1.0
    static let attentionOnDuration: TimeInterval = 0.30
    static let permissionPulsePeriod: TimeInterval = 2.0
    static let stalePulsePeriod: TimeInterval = 2.8
    static let doubleFlashPeriod: TimeInterval = 2.0
    static let flashDuration: TimeInterval = 0.18
    static let flashGap: TimeInterval = 0.18
    static let fadeDuration: TimeInterval = 0.06
    static let pulseMinimumBrightness = 0.25
    static let pulseLevels: [CGFloat] = [1, 0.93, 0.74, 0.48, 0.32, 0.25, 0.32, 0.48, 0.74, 0.93]
}

/// 连续时间动画用于 AppKit UI。脉冲使用正弦缓动，警示闪烁使用短过渡，
/// 避免低速设置通过降低刷新率造成肉眼可见的阶梯跳变。
private func frame(
    for displayMode: SignalDisplayMode,
    state: SignalState,
    elapsedTime: TimeInterval
) -> SignalFrame {
    switch displayMode {
    case .off:
        return SignalFrame(green: 0, yellow: 0, red: 0)
    case .steady(let color):
        return frame(color: color, brightness: 1)
    case .flash(let color):
        return frame(
            color: color,
            brightness: repeatingFlashBrightness(
                elapsedTime: elapsedTime,
                period: SignalAnimationTiming.attentionPeriod,
                onDuration: SignalAnimationTiming.attentionOnDuration,
                fadeDuration: SignalAnimationTiming.fadeDuration
            )
        )
    case .workPulse(let color):
        return frame(
            color: color,
            brightness: smoothPulseBrightness(
                elapsedTime: elapsedTime,
                period: SignalAnimationTiming.ambientPulsePeriod,
                minimumBrightness: SignalAnimationTiming.pulseMinimumBrightness
            )
        )
    case .slowPulse(let color):
        let period = state == .stale
            ? SignalAnimationTiming.stalePulsePeriod
            : SignalAnimationTiming.permissionPulsePeriod
        return frame(
            color: color,
            brightness: smoothPulseBrightness(
                elapsedTime: elapsedTime,
                period: period,
                minimumBrightness: SignalAnimationTiming.pulseMinimumBrightness
            )
        )
    case .doubleFlash(let color):
        return frame(
            color: color,
            brightness: doubleFlashBrightness(
                elapsedTime: elapsedTime,
                repeats: state != .done
            )
        )
    }
}

private func smoothPulseBrightness(
    elapsedTime: TimeInterval,
    period: TimeInterval,
    minimumBrightness: Double
) -> CGFloat {
    let phase = positiveRemainder(elapsedTime, period) / period
    let wave = 0.5 + 0.5 * cos(phase * 2 * .pi)
    return CGFloat(minimumBrightness + (1 - minimumBrightness) * wave)
}

private func repeatingFlashBrightness(
    elapsedTime: TimeInterval,
    period: TimeInterval,
    onDuration: TimeInterval,
    fadeDuration: TimeInterval
) -> CGFloat {
    let phase = positiveRemainder(elapsedTime, period)
    if phase < onDuration - fadeDuration {
        return 1
    }
    if phase < onDuration {
        return CGFloat(smoothStep((onDuration - phase) / fadeDuration))
    }
    if phase >= period - fadeDuration {
        return CGFloat(smoothStep((phase - (period - fadeDuration)) / fadeDuration))
    }
    return 0
}

private func doubleFlashBrightness(elapsedTime: TimeInterval, repeats: Bool) -> CGFloat {
    let period = SignalAnimationTiming.doubleFlashPeriod
    if !repeats, elapsedTime >= period {
        return 1
    }

    let fadeDuration = SignalAnimationTiming.fadeDuration
    let phase = repeats ? positiveRemainder(elapsedTime, period) : elapsedTime
    let firstFlashEnd = SignalAnimationTiming.flashDuration
    let secondFlashStart = SignalAnimationTiming.flashDuration + SignalAnimationTiming.flashGap
    let secondFlashEnd = secondFlashStart + SignalAnimationTiming.flashDuration

    let firstFlash: Double
    if phase < firstFlashEnd - fadeDuration {
        firstFlash = 1
    } else if phase < firstFlashEnd {
        firstFlash = smoothStep((firstFlashEnd - phase) / fadeDuration)
    } else if repeats, phase >= period - fadeDuration {
        firstFlash = smoothStep((phase - (period - fadeDuration)) / fadeDuration)
    } else {
        firstFlash = 0
    }

    let secondFlash = pulseWindowBrightness(
        phase: phase,
        start: secondFlashStart,
        end: secondFlashEnd,
        fadeDuration: fadeDuration
    )
    return CGFloat(max(firstFlash, secondFlash))
}

private func pulseWindowBrightness(
    phase: TimeInterval,
    start: TimeInterval,
    end: TimeInterval,
    fadeDuration: TimeInterval
) -> Double {
    guard phase >= start, phase < end else {
        return 0
    }
    if phase < start + fadeDuration {
        return smoothStep((phase - start) / fadeDuration)
    }
    if phase >= end - fadeDuration {
        return smoothStep((end - phase) / fadeDuration)
    }
    return 1
}

private func smoothStep(_ value: Double) -> Double {
    let clamped = max(0, min(1, value))
    return clamped * clamped * (3 - 2 * clamped)
}

private func positiveRemainder(_ value: TimeInterval, _ divisor: TimeInterval) -> TimeInterval {
    let remainder = value.truncatingRemainder(dividingBy: divisor)
    return remainder >= 0 ? remainder : remainder + divisor
}

private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
    let remainder = value % divisor
    return remainder >= 0 ? remainder : remainder + divisor
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

public func aggregateSessions(
    _ sessions: [String: SessionRecord],
    now: Double = Date().timeIntervalSince1970,
    leasePolicy: SignalLeasePolicy = .default
) -> String {
    var candidates: [(signal: String, priority: Int, updatedAt: Double)] = []

    for record in sessions.values {
        let normalized = normalizedAggregateSignal(record.signal)
        let effective = effectiveSignal(normalized, updatedAt: record.updatedAt, now: now, policy: leasePolicy)
        guard let priority = aggregatePriority[effective] else {
            continue
        }
        candidates.append((effective, priority, record.updatedAt))
    }

    if let selected = candidates.max(by: {
        $0.priority == $1.priority ? $0.updatedAt < $1.updatedAt : $0.priority < $1.priority
    }), selected.priority > 0 {
        return selected.signal
    }
    return candidates.max(by: { $0.updatedAt < $1.updatedAt })?.signal ?? "idle"
}

private let aggregatePriority: [String: Int] = [
    "idle": 0,
    "done": 1,
    "working": 2,
    "attention": 3,
    "stale": 3,
    "permission": 4,
    "blocked": 5,
]

/// 状态风险优先级。数值越大越需要优先展示和跳转。
public func signalRiskPriority(_ signal: String) -> Int? {
    aggregatePriority[normalizedAggregateSignal(signal)]
}

/// 选择与当前聚合状态一致的会话来源，确保主灯、状态中心和点击跳转指向同一风险会话。
public func preferredSessionSource(
    in sessions: [String: SessionRecord],
    aggregate: SignalState,
    sessionTTL: Double,
    leasePolicy: SignalLeasePolicy = .default,
    now: Double = Date().timeIntervalSince1970
) -> SessionSource? {
    let expectedSignal = normalizedAggregateSignal(aggregate.rawValue)
    let candidates = sessions.values.compactMap { record -> SessionRecord? in
        guard record.source != nil, !sessionEndSignals.contains(record.signal) else {
            return nil
        }
        let normalized = normalizedAggregateSignal(record.signal)
        let lease = leaseDuration(for: normalized, policy: leasePolicy) ?? 0
        guard now - record.updatedAt <= lease + sessionTTL else {
            return nil
        }
        let effective = effectiveSignal(normalized, updatedAt: record.updatedAt, now: now, policy: leasePolicy)
        return effective == expectedSignal ? record : nil
    }
    return candidates.max { $0.updatedAt < $1.updatedAt }?.source
}

/// 将 Hook 的瞬时事件归一为可持续展示和风险聚合的会话状态。
public func normalizedAggregateSignal(_ signal: String) -> String {
    if workingSignals.contains(signal) {
        return "working"
    }
    if ["session_start", "session_end", "off"].contains(signal) {
        return "idle"
    }
    return signal
}

/// 计算一条记录是否仍属于“活跃会话”，并返回适合列表展示的状态。
///
/// rollout 的终止事件优先于 Hook 租约；未知生命周期才退回租约判断。
/// `tool_done` 只表示单次工具结束，任务仍在运行，因此列表展示为 working。
public func activeSessionSignal(
    for record: SessionRecord,
    activity: CodexThreadActivitySnapshot?,
    now: Double = Date().timeIntervalSince1970,
    policy: SignalLeasePolicy = .default
) -> String? {
    if let activity, activity.updatedAt + 0.5 >= record.updatedAt {
        switch activity.state {
        case .completed, .interrupted:
            return nil
        case .running, .unknown:
            break
        }
    }

    let normalized = normalizedAggregateSignal(record.signal)
    let effective = effectiveSignal(normalized, updatedAt: record.updatedAt, now: now, policy: policy)
    guard !["idle", "done", "stale"].contains(effective) else {
        return nil
    }
    if effective == "working" {
        return record.signal == "thinking" ? "thinking" : "working"
    }
    return effective
}

/// 用 Codex rollout 的终止事件校准 Hook 会话。
///
/// 正常完成保留短暂 done 灯语；手动中断立即移除，避免继续显示“思考中”。
public func reconcileSessionsWithThreadActivities(
    _ sessions: [String: SessionRecord],
    activities: [String: CodexThreadActivitySnapshot],
    now: Double = Date().timeIntervalSince1970,
    policy: SignalLeasePolicy = .default
) -> [String: SessionRecord] {
    sessions.reduce(into: [:]) { result, item in
        let key = item.key
        let record = item.value
        guard let activity = activities[key], activity.updatedAt + 0.5 >= record.updatedAt else {
            result[key] = record
            return
        }

        switch activity.state {
        case .interrupted:
            return
        case .completed:
            guard now - activity.updatedAt <= policy.doneSeconds else {
                return
            }
            var completedRecord = record
            completedRecord.signal = "done"
            completedRecord.updatedAt = activity.updatedAt
            result[key] = completedRecord
        case .running, .unknown:
            result[key] = record
        }
    }
}

public func pruneExpiredSessions(
    _ sessions: inout [String: SessionRecord],
    now: Double,
    sessionTTL: Double,
    leasePolicy: SignalLeasePolicy = .default
) {
    sessions = sessions.filter { _, record in
        let lease = leaseDuration(for: normalizedAggregateSignal(record.signal), policy: leasePolicy) ?? 0
        // 租约结束后继续保留 sessionTTL，供 stale 展示和故障追踪使用。
        return now - record.updatedAt <= lease + sessionTTL
    }
}
