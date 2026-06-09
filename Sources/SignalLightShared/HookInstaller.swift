import Foundation

private let codexHookEvents: [(name: String, matcher: String?)] = [
    ("SessionStart", nil),
    ("UserPromptSubmit", nil),
    ("PreToolUse", "*"),
    ("PermissionRequest", "*"),
    ("PostToolUse", "*"),
    ("Stop", nil),
]

private let claudeHookEvents: [(name: String, matcher: String?)] = [
    ("SessionStart", nil),
    ("UserPromptSubmit", nil),
    ("PreToolUse", "*"),
    ("PostToolUse", "*"),
    ("PostToolUseFailure", nil),
    ("PostToolBatch", nil),
    ("PermissionDenied", nil),
    ("Notification", nil),
    ("PermissionRequest", "*"),
    ("PreCompact", nil),
    ("PostCompact", nil),
    ("SubagentStart", nil),
    ("SubagentStop", nil),
    ("TaskCreated", nil),
    ("TaskCompleted", nil),
    ("Stop", nil),
    ("StopFailure", nil),
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
        try installClaudeHooks(homeDirectory: homeDirectory),
    ]
}

public func checkSignalLightHooks(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) -> [HookInstallReport] {
    [
        checkCodexHooks(homeDirectory: homeDirectory),
        checkClaudeHooks(homeDirectory: homeDirectory),
    ]
}

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

private func installClaudeHooks(homeDirectory: URL) throws -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".claude/settings.json")
    var root = try readJSONObject(at: path) ?? [:]
    let before = root
    root = upsertHooks(in: root, command: SignalLightPaths.claudeHookCommand, events: claudeHookEvents)
    try writeJSONObject(root, to: path)

    let changed = !jsonObjectsEqual(before, root)
    return HookInstallReport(
        title: "Claude Code hooks",
        path: path.path,
        changed: changed,
        ok: true,
        message: changed ? "已写入 Claude Code hooks" : "已存在，无需修改"
    )
}

private func checkCodexHooks(homeDirectory: URL) -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".codex/hooks.json")
    return checkHooks(path: path, title: "Codex hooks", command: SignalLightPaths.codexHookCommand, events: codexHookEvents)
}

private func checkClaudeHooks(homeDirectory: URL) -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".claude/settings.json")
    return checkHooks(path: path, title: "Claude Code hooks", command: SignalLightPaths.claudeHookCommand, events: claudeHookEvents)
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
    if expectedCommand.hasSuffix("/claude-code-signal-hook") {
        return existing == expectedCommand || existing.contains("/claude-code-signal-hook")
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
