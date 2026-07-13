import Foundation

/// 当前配置 schema 版本，用于升级迁移
public let configSchemaVersion = 1

public struct SignalLightConfig: Codable, Equatable {
    public var schemaVersion: Int
    public var display: DisplayConfig
    public var agent: AgentConfig
    public var statusRules: StatusRulesConfig

    public static let `default` = SignalLightConfig(
        schemaVersion: configSchemaVersion,
        display: .default,
        agent: .default,
        statusRules: .default
    )

    public init(schemaVersion: Int, display: DisplayConfig, agent: AgentConfig, statusRules: StatusRulesConfig) {
        self.schemaVersion = schemaVersion
        self.display = display
        self.agent = agent
        self.statusRules = statusRules
    }
}

public struct DisplayConfig: Codable, Equatable {
    /// 启动时显示悬浮窗
    public var showFloatingWindowAtStartup: Bool
    /// 始终置顶
    public var alwaysOnTop: Bool
    /// 窗口缩放比例（1.0 = 56x122）
    public var windowScale: Double
    /// 不透明度（0.0-1.0）
    public var opacity: Double
    /// 动画速度（1.0 = 默认 tick 频率）
    public var animationSpeed: Double
    /// 显示 Dock 图标（需重启生效）
    public var showDockIcon: Bool
    /// 显示 Touch Bar
    public var showTouchBar: Bool

    public static let `default` = DisplayConfig(
        showFloatingWindowAtStartup: true,
        alwaysOnTop: true,
        windowScale: 1.0,
        opacity: 1.0,
        animationSpeed: 1.0,
        showDockIcon: true,
        showTouchBar: true
    )

    public init(
        showFloatingWindowAtStartup: Bool,
        alwaysOnTop: Bool,
        windowScale: Double,
        opacity: Double,
        animationSpeed: Double,
        showDockIcon: Bool,
        showTouchBar: Bool
    ) {
        self.showFloatingWindowAtStartup = showFloatingWindowAtStartup
        self.alwaysOnTop = alwaysOnTop
        self.windowScale = windowScale
        self.opacity = opacity
        self.animationSpeed = animationSpeed
        self.showDockIcon = showDockIcon
        self.showTouchBar = showTouchBar
    }
}

public struct AgentConfig: Codable, Equatable {
    /// 状态文件目录
    public var stateDirectory: String
    /// 会话超时（秒）
    public var sessionTTLSeconds: Double
    /// 登录时启动
    public var launchAtLogin: Bool
    /// 多 Agent 同时运行时优先展示的来源
    public var preferredAgentSource: PreferredAgentSource

    public static let `default` = AgentConfig(
        stateDirectory: "/private/tmp/signal-light",
        sessionTTLSeconds: 86400,
        launchAtLogin: true,
        preferredAgentSource: .auto
    )

    public init(
        stateDirectory: String,
        sessionTTLSeconds: Double,
        launchAtLogin: Bool,
        preferredAgentSource: PreferredAgentSource = .auto
    ) {
        self.stateDirectory = stateDirectory
        self.sessionTTLSeconds = sessionTTLSeconds
        self.launchAtLogin = launchAtLogin
        self.preferredAgentSource = preferredAgentSource
    }
}

public struct StatusRulesConfig: Codable, Equatable {
    /// key = 信号名，value = 自定义规则
    public var rules: [String: SignalRuleConfig]

    public static let `default` = StatusRulesConfig(rules: [:])

    public init(rules: [String: SignalRuleConfig]) {
        self.rules = rules
    }
}

public struct SignalRuleConfig: Codable, Equatable {
    /// nil = 使用默认颜色
    public var color: String?
    /// nil = 使用默认模式
    public var mode: String?

    public static let validColors: Set<String> = ["green", "yellow", "red"]
    public static let validModes: Set<String> = ["off", "steady", "flash", "workPulse"]

    public init(color: String? = nil, mode: String? = nil) {
        self.color = color
        self.mode = mode
    }

    public var isValid: Bool {
        let colorIsValid = color.map { Self.validColors.contains($0) } ?? true
        let modeIsValid = mode.map { Self.validModes.contains($0) } ?? true
        return colorIsValid && modeIsValid
    }
}
