import Foundation

private let codexHookEvents: [(name: String, matcher: String?)] = [
    ("SessionStart", nil),
    ("UserPromptSubmit", nil),
    ("PreToolUse", "*"),
    ("PermissionRequest", "*"),
    ("PostToolUse", "*"),
    ("Stop", nil),
    // 会话正常结束时清理对应状态，租约仅负责异常退出兜底。
    ("SessionEnd", nil),
]

public struct HookInstallReport: Equatable {
    public var title: String
    public var path: String
    public var changed: Bool
    public var ok: Bool
    public var message: String

    public init(title: String, path: String, changed: Bool, ok: Bool, message: String) {
        self.title = title
        self.path = path
        self.changed = changed
        self.ok = ok
        self.message = message
    }
}

/// Codex Hook 的可验证连接阶段。
public enum CodexHookConnectionState: Equatable {
    /// Hook 配置不存在或不完整。
    case missingConfiguration(String)
    /// 配置已经写入，但尚未收到真实事件；用户可能仍需在 `/hooks` 确认信任。
    case awaitingFirstEvent
    /// 已收到至少一次真实 Hook 事件。
    case active(lastEventAt: Double)
}

public func inspectCodexHookConnection(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    stateDirectory: URL
) -> CodexHookConnectionState {
    if let failed = checkSignalLightHooks(homeDirectory: homeDirectory).first(where: { !$0.ok }) {
        return .missingConfiguration(failed.message)
    }
    guard let activity = SignalLightStateFiles.readCodexHookActivity(in: stateDirectory) else {
        return .awaitingFirstEvent
    }
    return .active(lastEventAt: activity.lastEventAt)
}

public enum HookInstallError: Error, LocalizedError, CustomStringConvertible {
    case message(String)

    public var errorDescription: String? {
        description
    }

    public var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

public func installSignalLightHooks(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) throws -> [HookInstallReport] {
    [
        try installCodexHooks(homeDirectory: homeDirectory),
    ]
}

public func checkSignalLightHooks(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) -> [HookInstallReport] {
    [
        checkCodexHooks(homeDirectory: homeDirectory),
    ]
}

/// Codex-only 版本的一次性升级迁移：仅移除旧 Signal Light Claude Hook，保留其他 Claude 配置。
@discardableResult
public func removeLegacyClaudeHookConfiguration(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) throws -> Bool {
    let path = homeDirectory.appendingPathComponent(".claude/settings.json")
    guard var root = try readJSONObject(at: path), var hooks = root["hooks"] as? [String: Any] else {
        return false
    }

    var changed = false
    for (event, value) in hooks {
        guard let groups = value as? [[String: Any]] else {
            continue
        }
        let retainedGroups = groups.compactMap { group -> [String: Any]? in
            guard let handlers = group["hooks"] as? [[String: Any]] else {
                return group
            }
            let retainedHandlers = handlers.filter { handler in
                guard let command = handler["command"] as? String else {
                    return true
                }
                return !legacySignalLightClaudeHookCommands.contains(
                    command.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            guard retainedHandlers.count != handlers.count else {
                return group
            }
            changed = true
            guard !retainedHandlers.isEmpty else {
                return nil
            }
            var updated = group
            updated["hooks"] = retainedHandlers
            return updated
        }
        if retainedGroups.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = retainedGroups
        }
    }

    guard changed else {
        return false
    }
    if hooks.isEmpty {
        root.removeValue(forKey: "hooks")
    } else {
        root["hooks"] = hooks
    }
    try writeJSONObject(root, to: path)
    return true
}

/// 历史版本实际写入过的 Signal Light Claude Hook 命令。
/// 使用精确集合，避免删除用户或其他工具的同名脚本。
private let legacySignalLightClaudeHookCommands: Set<String> = [
    "/usr/local/bin/claude-code-signal-hook",
    "/opt/signal-light/claude-code-signal-hook",
    "/Applications/Signal Light.app/Contents/Resources/bin/claude-code-signal-hook",
]

private func installCodexHooks(homeDirectory: URL) throws -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".codex/hooks.json")
    var root = try readJSONObject(at: path) ?? [:]
    let before = root
    root = upsertHooks(in: root, command: SignalLightPaths.codexHookCommand, events: codexHookEvents)
    try writeJSONObject(root, to: path)

    let changed = !jsonObjectsEqual(before, root)
    return HookInstallReport(
        title: "Codex hooks",
        path: path.path,
        changed: changed,
        ok: true,
        message: changed ? "已写入用户级 Codex hooks" : "已存在，无需修改"
    )
}

private func checkCodexHooks(homeDirectory: URL) -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".codex/hooks.json")
    return checkHooks(path: path, title: "Codex hooks", command: SignalLightPaths.codexHookCommand, events: codexHookEvents)
}

private func checkHooks(
    path: URL,
    title: String,
    command: String,
    events: [(name: String, matcher: String?)]
) -> HookInstallReport {
    do {
        guard let root = try readJSONObject(at: path) else {
            return HookInstallReport(title: title, path: path.path, changed: false, ok: false, message: "未找到配置文件")
        }
        let missing = events.filter { !hasHook(root: root, event: $0.name, command: command) }.map(\.name)
        if missing.isEmpty {
            return HookInstallReport(title: title, path: path.path, changed: false, ok: true, message: "已安装")
        }
        return HookInstallReport(
            title: title,
            path: path.path,
            changed: false,
            ok: false,
            message: "缺少事件: \(missing.joined(separator: ", "))"
        )
    } catch {
        return HookInstallReport(title: title, path: path.path, changed: false, ok: false, message: error.localizedDescription)
    }
}

private func readJSONObject(at url: URL) throws -> [String: Any]? {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return nil
    }
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let root = object as? [String: Any] else {
        throw HookInstallError.message("配置不是 JSON object: \(url.path)")
    }
    return root
}

private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    let tmpURL = url.appendingPathExtension("tmp")
    try data.write(to: tmpURL, options: .atomic)
    defer {
        try? FileManager.default.removeItem(at: tmpURL)
    }
    if FileManager.default.fileExists(atPath: url.path) {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
    } else {
        try FileManager.default.moveItem(at: tmpURL, to: url)
    }
}

private func upsertHooks(
    in root: [String: Any],
    command: String,
    events: [(name: String, matcher: String?)]
) -> [String: Any] {
    var root = root
    var hooks = root["hooks"] as? [String: Any] ?? [:]
    for event in events {
        hooks[event.name] = upsertEventHook(
            value: hooks[event.name],
            matcher: event.matcher,
            command: command
        )
    }
    root["hooks"] = hooks
    return root
}

private func upsertEventHook(value: Any?, matcher: String?, command: String) -> [[String: Any]] {
    var groups = value as? [[String: Any]] ?? []
    let newGroup = makeHookGroup(matcher: matcher, command: command)

    groups = groups.compactMap { group in
        guard let handlers = group["hooks"] as? [[String: Any]] else {
            return group
        }
        let filteredHandlers = handlers.filter { handler in
            guard let existingCommand = handler["command"] as? String else {
                return true
            }
            return !isSignalLightHookCommand(existingCommand, expectedCommand: command)
        }
        if filteredHandlers.isEmpty {
            return nil
        }
        var updated = group
        updated["hooks"] = filteredHandlers
        return updated
    }

    groups.append(newGroup)
    return groups
}

private func makeHookGroup(matcher: String?, command: String) -> [String: Any] {
    var group: [String: Any] = [
        "hooks": [[
            "type": "command",
            "command": command,
            "timeout": 5,
        ]],
    ]
    if let matcher {
        group["matcher"] = matcher
    }
    return group
}

private func hasHook(root: [String: Any], event: String, command: String) -> Bool {
    guard let hooks = root["hooks"] as? [String: Any],
          let groups = hooks[event] as? [[String: Any]] else {
        return false
    }
    return groups.contains { group in
        guard let handlers = group["hooks"] as? [[String: Any]] else {
            return false
        }
        return handlers.contains { handler in
            guard let existingCommand = handler["command"] as? String else {
                return false
            }
            return isSignalLightHookCommand(existingCommand, expectedCommand: command)
        }
    }
}

private func isSignalLightHookCommand(_ existing: String, expectedCommand: String) -> Bool {
    if expectedCommand.hasSuffix("/codex-signal-hook") {
        return existing == expectedCommand || existing.contains("/codex-signal-hook")
    }
    return existing == expectedCommand
}

private func jsonObjectsEqual(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
    guard JSONSerialization.isValidJSONObject(lhs),
          JSONSerialization.isValidJSONObject(rhs),
          let lhsData = try? JSONSerialization.data(withJSONObject: lhs, options: [.sortedKeys]),
          let rhsData = try? JSONSerialization.data(withJSONObject: rhs, options: [.sortedKeys])
    else {
        return false
    }
    return lhsData == rhsData
}
