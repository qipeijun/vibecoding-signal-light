import Foundation

public final class SignalLightConfigStore {
    private let configDir: URL
    private let configFile: URL
    public private(set) var lastRepairResult: String?

    public init(configDirectory: URL? = nil) {
        if let configDirectory {
            configDir = configDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            configDir = appSupport.appendingPathComponent("Signal Light")
        }
        configFile = configDir.appendingPathComponent("config.json")
    }

    public func configDirectoryURL() -> URL { configDir }
    public func configFileURL() -> URL { configFile }

    // MARK: - 加载与修复

    public func loadOrRepairConfig() -> SignalLightConfig {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return createDefaultConfig()
        }

        guard let data = try? Data(contentsOf: configFile) else {
            lastRepairResult = "无法读取配置文件，已重建默认配置"
            return createDefaultConfig()
        }

        guard let raw = try? JSONDecoder().decode(RawConfig.self, from: data) else {
            backupCorruptedConfig(data)
            lastRepairResult = "配置 JSON 损坏，已备份并重建默认配置"
            return createDefaultConfig()
        }

        var config = decodeConfig(from: raw)
        var needsSave = false

        if let rawVersion = raw.schemaVersion, rawVersion > configSchemaVersion {
            lastRepairResult = "配置 schema 版本(\(rawVersion))高于当前版本(\(configSchemaVersion))，保留原样"
            return config
        }

        if config.schemaVersion != configSchemaVersion {
            config.schemaVersion = configSchemaVersion
            lastRepairResult = "配置已从 schema \(raw.schemaVersion ?? 0) 升级到 \(configSchemaVersion)"
            needsSave = true
        }

        let cleaned = validateAndCleanRules(config)
        config = cleaned.config
        needsSave = needsSave || cleaned.didChange

        if needsSave {
            saveRepairedConfig(config)
        }

        return config
    }

    public func repairConfig() throws -> SignalLightConfig {
        let config = SignalLightConfig.default
        try saveConfig(config)
        lastRepairResult = "已重建默认配置 (schema \(configSchemaVersion))"
        return config
    }

    // MARK: - 保存

    public func saveConfig(_ config: SignalLightConfig) throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFile, options: .atomic)
    }

    // MARK: - 环境变量覆盖

    /// 应用环境变量覆盖，返回生效的 AgentConfig。
    public func effectiveAgentConfig(
        from config: SignalLightConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AgentConfig {
        var agent = config.agent
        if let envDir = environment["SIGNAL_LIGHT_STATE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envDir.isEmpty {
            agent.stateDirectory = envDir
        }
        if let value = validatedNumber(environment["SIGNAL_LIGHT_SESSION_TTL_SECONDS"], range: 1...604800) {
            agent.sessionTTLSeconds = value
        }
        if let value = validatedNumber(environment["SIGNAL_LIGHT_WORKING_LEASE_SECONDS"], range: 60...604800) {
            agent.workingLeaseSeconds = value
        }
        if let value = validatedNumber(environment["SIGNAL_LIGHT_ATTENTION_LEASE_SECONDS"], range: 60...604800) {
            agent.attentionLeaseSeconds = value
        }
        if let value = validatedNumber(environment["SIGNAL_LIGHT_CRITICAL_LEASE_SECONDS"], range: 60...604800) {
            agent.criticalLeaseSeconds = value
        }
        if let value = validatedNumber(environment["SIGNAL_LIGHT_DONE_DISPLAY_SECONDS"], range: 1...30) {
            agent.doneDisplaySeconds = value
        }
        return agent
    }

    // MARK: - 内部方法

    private func createDefaultConfig() -> SignalLightConfig {
        let config = SignalLightConfig.default
        do {
            try saveConfig(config)
        } catch {
            lastRepairResult = appendRepairResult(lastRepairResult, "默认配置写入失败: \(error.localizedDescription)")
        }
        return config
    }

    private func saveRepairedConfig(_ config: SignalLightConfig) {
        do {
            try saveConfig(config)
        } catch {
            lastRepairResult = appendRepairResult(lastRepairResult, "修复后的配置写入失败: \(error.localizedDescription)")
        }
    }

    private func backupCorruptedConfig(_ data: Data) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = formatter.string(from: Date())
        let backupURL = configFile.deletingPathExtension().appendingPathExtension("broken-\(timestamp).json")
        try? data.write(to: backupURL, options: .atomic)
    }

    private func decodeConfig(from raw: RawConfig) -> SignalLightConfig {
        SignalLightConfig(
            schemaVersion: raw.schemaVersion ?? 0,
            display: raw.display?.mergedWithDefaults() ?? .default,
            agent: raw.agent?.mergedWithDefaults() ?? .default,
            statusRules: raw.statusRules?.mergedWithDefaults() ?? .default
        )
    }

    private func validateAndCleanRules(_ config: SignalLightConfig) -> (config: SignalLightConfig, didChange: Bool) {
        var config = config
        var changed = false
        var removedSignals: [String] = []
        var cleanedRules: [String] = []

        for (signal, rule) in config.statusRules.rules {
            guard validSignals.contains(signal) else {
                config.statusRules.rules.removeValue(forKey: signal)
                removedSignals.append(signal)
                changed = true
                continue
            }

            var cleanRule = rule
            // 颜色代表固定状态语义；旧配置可解码，但保存时必须移除自定义颜色。
            if cleanRule.color != nil {
                cleanRule.color = nil
                changed = true
            }
            if let mode = cleanRule.mode, !SignalRuleConfig.validModes.contains(mode) {
                cleanRule.mode = nil
                changed = true
            }
            if cleanRule.mode == "off", signal != "done", signal != "off" {
                cleanRule.mode = nil
                changed = true
            }

            if cleanRule.color == nil && cleanRule.mode == nil {
                if rule.color != nil || rule.mode != nil {
                    cleanedRules.append(signal)
                    changed = true
                }
                config.statusRules.rules.removeValue(forKey: signal)
            } else {
                if cleanRule.color != rule.color || cleanRule.mode != rule.mode {
                    cleanedRules.append(signal)
                }
                config.statusRules.rules[signal] = cleanRule
            }
        }

        if !removedSignals.isEmpty {
            lastRepairResult = appendRepairResult(
                lastRepairResult,
                "已移除未知信号规则: \(removedSignals.sorted().joined(separator: ", "))"
            )
        }
        if !cleanedRules.isEmpty {
            lastRepairResult = appendRepairResult(
                lastRepairResult,
                "已清理非法颜色/模式规则: \(cleanedRules.sorted().joined(separator: ", "))"
            )
        }

        return (config, changed)
    }

    private func appendRepairResult(_ current: String?, _ message: String) -> String {
        guard let current, !current.isEmpty else {
            return message
        }
        return "\(current)；\(message)"
    }
}

/// 用于字段级合并旧配置，所有字段可选以兼容旧版本。
private struct RawConfig: Decodable {
    let schemaVersion: Int?
    let display: RawDisplayConfig?
    let agent: RawAgentConfig?
    let statusRules: RawStatusRulesConfig?
}

private struct RawDisplayConfig: Decodable {
    let showFloatingWindowAtStartup: Bool?
    let alwaysOnTop: Bool?
    let windowScale: Double?
    let opacity: Double?
    let animationSpeed: Double?
    let showDockIcon: Bool?
    let showTouchBar: Bool?

    func mergedWithDefaults() -> DisplayConfig {
        let defaults = DisplayConfig.default
        return DisplayConfig(
            showFloatingWindowAtStartup: showFloatingWindowAtStartup ?? defaults.showFloatingWindowAtStartup,
            alwaysOnTop: alwaysOnTop ?? defaults.alwaysOnTop,
            windowScale: windowScale ?? defaults.windowScale,
            opacity: opacity ?? defaults.opacity,
            animationSpeed: validatedNumber(animationSpeed, fallback: defaults.animationSpeed, range: 0.25...1.0),
            showDockIcon: showDockIcon ?? defaults.showDockIcon,
            showTouchBar: showTouchBar ?? defaults.showTouchBar
        )
    }
}

private struct RawAgentConfig: Decodable {
    let stateDirectory: String?
    let sessionTTLSeconds: Double?
    let workingLeaseSeconds: Double?
    let attentionLeaseSeconds: Double?
    let criticalLeaseSeconds: Double?
    let doneDisplaySeconds: Double?
    let launchAtLogin: Bool?

    func mergedWithDefaults() -> AgentConfig {
        let defaults = AgentConfig.default
        return AgentConfig(
            stateDirectory: stateDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? defaults.stateDirectory,
            sessionTTLSeconds: validatedNumber(sessionTTLSeconds, fallback: defaults.sessionTTLSeconds, range: 1...604800),
            workingLeaseSeconds: validatedNumber(workingLeaseSeconds, fallback: defaults.workingLeaseSeconds, range: 60...604800),
            attentionLeaseSeconds: validatedNumber(attentionLeaseSeconds, fallback: defaults.attentionLeaseSeconds, range: 60...604800),
            criticalLeaseSeconds: validatedNumber(criticalLeaseSeconds, fallback: defaults.criticalLeaseSeconds, range: 60...604800),
            doneDisplaySeconds: validatedNumber(doneDisplaySeconds, fallback: defaults.doneDisplaySeconds, range: 1...30),
            launchAtLogin: launchAtLogin ?? defaults.launchAtLogin
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private func validatedNumber(_ raw: String?, range: ClosedRange<Double>) -> Double? {
    guard let raw, let value = Double(raw), value.isFinite, range.contains(value) else {
        return nil
    }
    return value
}

private func validatedNumber(_ value: Double?, fallback: Double, range: ClosedRange<Double>) -> Double {
    guard let value, value.isFinite, range.contains(value) else {
        return fallback
    }
    return value
}

private struct RawStatusRulesConfig: Decodable {
    let rules: [String: SignalRuleConfig]?

    func mergedWithDefaults() -> StatusRulesConfig {
        StatusRulesConfig(rules: rules ?? StatusRulesConfig.default.rules)
    }
}
