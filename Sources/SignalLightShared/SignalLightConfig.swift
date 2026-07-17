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
    /// 环境状态动画速度倍率（1.0 = 默认周期，不影响授权、阻塞等行动提示）
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
    /// 工作状态租约（秒），超时后显示 stale。
    public var workingLeaseSeconds: Double
    /// 等待关注状态租约（秒），超时后显示 stale。
    public var attentionLeaseSeconds: Double
    /// 授权与阻塞状态租约（秒），超时后显示 stale。
    public var criticalLeaseSeconds: Double
    /// 完成状态展示时长（秒），超时后回到 idle。
    public var doneDisplaySeconds: Double
    /// 登录时启动
    public var launchAtLogin: Bool

    public static let `default` = AgentConfig(
        stateDirectory: "/private/tmp/signal-light",
        sessionTTLSeconds: 86400,
        workingLeaseSeconds: 1800,
        attentionLeaseSeconds: 7200,
        criticalLeaseSeconds: 86400,
        doneDisplaySeconds: 6,
        launchAtLogin: true
    )

    public init(
        stateDirectory: String,
        sessionTTLSeconds: Double,
        workingLeaseSeconds: Double = 1800,
        attentionLeaseSeconds: Double = 7200,
        criticalLeaseSeconds: Double = 86400,
        doneDisplaySeconds: Double = 6,
        launchAtLogin: Bool
    ) {
        self.stateDirectory = stateDirectory
        self.sessionTTLSeconds = sessionTTLSeconds
        self.workingLeaseSeconds = workingLeaseSeconds
        self.attentionLeaseSeconds = attentionLeaseSeconds
        self.criticalLeaseSeconds = criticalLeaseSeconds
        self.doneDisplaySeconds = doneDisplaySeconds
        self.launchAtLogin = launchAtLogin
    }

    public var leasePolicy: SignalLeasePolicy {
        SignalLeasePolicy(
            workingSeconds: workingLeaseSeconds,
            attentionSeconds: attentionLeaseSeconds,
            criticalSeconds: criticalLeaseSeconds,
            doneSeconds: doneDisplaySeconds
        )
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
    /// 旧配置兼容字段。颜色语义已锁定，加载后会被清理为 nil。
    public var color: String?
    /// nil = 使用默认模式
    public var mode: String?

    public static let validColors: Set<String> = ["green", "yellow", "red"]
    public static let validModes: Set<String> = ["off", "steady", "flash", "workPulse", "slowPulse", "doubleFlash"]

    public init(color: String? = nil, mode: String? = nil) {
        self.color = color
        self.mode = mode
    }

    public var isValid: Bool {
        let modeIsValid = mode.map { Self.validModes.contains($0) } ?? true
        return color == nil && modeIsValid
    }
}
