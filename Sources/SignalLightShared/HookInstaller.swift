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

private let cursorHookEvents: [(name: String, matcher: String?)] = [
    ("sessionStart", nil),
    ("beforeSubmitPrompt", nil),
    ("preToolUse", "*"),
    ("postToolUse", "*"),
    ("postToolUseFailure", nil),
    ("subagentStart", nil),
    ("subagentStop", nil),
    ("beforeShellExecution", "*"),
    ("afterShellExecution", "*"),
    ("beforeMCPExecution", "*"),
    ("afterMCPExecution", "*"),
    ("beforeReadFile", nil),
    ("afterFileEdit", nil),
    ("preCompact", nil),
    ("afterAgentResponse", nil),
    ("afterAgentThought", nil),
    ("stop", nil),
    ("sessionEnd", nil),
    ("beforeTabFileRead", nil),
    ("afterTabFileEdit", nil),
    ("workspaceOpen", nil),
]

private let cursorFlatFormatMinimumVersion = "3.10"

enum CursorHookEnvelopeFormat: Equatable {
    case nested
    case flat
}

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
        try installCursorHooks(homeDirectory: homeDirectory),
        try installOpenCodeHooks(homeDirectory: homeDirectory),
    ]
}

public func checkSignalLightHooks(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) -> [HookInstallReport] {
    [
        checkCodexHooks(homeDirectory: homeDirectory),
        checkClaudeHooks(homeDirectory: homeDirectory),
        checkCursorHooks(homeDirectory: homeDirectory),
        checkOpenCodeHooks(homeDirectory: homeDirectory),
    ]
}

func resolveCursorHookEnvelopeFormat(
    existingRoot: [String: Any]?,
    cursorAppSearchPaths: [URL] = defaultCursorAppSearchPaths()
) -> CursorHookEnvelopeFormat {
    if let existingRoot, let sniffed = sniffCursorHookEnvelopeFormat(from: existingRoot) {
        return sniffed
    }
    if let version = readCursorAppVersion(searchPaths: cursorAppSearchPaths),
       !isVersion(version, greaterThanOrEqualTo: cursorFlatFormatMinimumVersion) {
        return .nested
    }
    return .flat
}

private func installCodexHooks(homeDirectory: URL) throws -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".codex/hooks.json")
    var root = try readJSONObject(at: path) ?? [:]
    let before = root
    root = upsertNestedHooks(in: root, command: SignalLightPaths.codexHookCommand, events: codexHookEvents)
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
    root = upsertNestedHooks(in: root, command: SignalLightPaths.claudeHookCommand, events: claudeHookEvents)
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
    return checkNestedHooks(path: path, title: "Codex hooks", command: SignalLightPaths.codexHookCommand, events: codexHookEvents)
}

private func checkClaudeHooks(homeDirectory: URL) -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".claude/settings.json")
    return checkNestedHooks(path: path, title: "Claude Code hooks", command: SignalLightPaths.claudeHookCommand, events: claudeHookEvents)
}

private func installCursorHooks(homeDirectory: URL) throws -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".cursor/hooks.json")
    let existing = try readJSONObject(at: path)
    var root = existing ?? ["version": 1]
    let before = root
    let format = resolveCursorHookEnvelopeFormat(existingRoot: existing)
    root = upsertCursorHooks(
        in: root,
        command: SignalLightPaths.cursorHookCommand,
        events: cursorHookEvents,
        format: format
    )
    try writeJSONObject(root, to: path)

    let changed = !jsonObjectsEqual(before, root)
    return HookInstallReport(
        title: "Cursor hooks",
        path: path.path,
        changed: changed,
        ok: true,
        message: changed ? "已写入 Cursor hooks" : "已存在，无需修改"
    )
}

private func checkCursorHooks(homeDirectory: URL) -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".cursor/hooks.json")
    return checkCursorHooks(
        path: path,
        title: "Cursor hooks",
        command: SignalLightPaths.cursorHookCommand,
        events: cursorHookEvents
    )
}

private func installOpenCodeHooks(homeDirectory: URL) throws -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".config/opencode/hooks.json")
    var root = try readJSONObject(at: path) ?? [:]
    let before = root
    root = upsertNestedHooks(in: root, command: SignalLightPaths.codexHookCommand, events: codexHookEvents)
    try writeJSONObject(root, to: path)

    let changed = !jsonObjectsEqual(before, root)
    return HookInstallReport(
        title: "OpenCode hooks",
        path: path.path,
        changed: changed,
        ok: true,
        message: changed ? "已写入 OpenCode hooks" : "已存在，无需修改"
    )
}

private func checkOpenCodeHooks(homeDirectory: URL) -> HookInstallReport {
    let path = homeDirectory.appendingPathComponent(".config/opencode/hooks.json")
    return checkNestedHooks(path: path, title: "OpenCode hooks", command: SignalLightPaths.codexHookCommand, events: codexHookEvents)
}

private func checkNestedHooks(
    path: URL,
    title: String,
    command: String,
    events: [(name: String, matcher: String?)]
) -> HookInstallReport {
    do {
        guard let root = try readJSONObject(at: path) else {
            return HookInstallReport(title: title, path: path.path, changed: false, ok: false, message: "未找到配置文件")
        }
        let missing = events.filter { !hasNestedHook(root: root, event: $0.name, command: command) }.map(\.name)
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

private func checkCursorHooks(
    path: URL,
    title: String,
    command: String,
    events: [(name: String, matcher: String?)]
) -> HookInstallReport {
    do {
        guard let root = try readJSONObject(at: path) else {
            return HookInstallReport(title: title, path: path.path, changed: false, ok: false, message: "未找到配置文件")
        }
        let missing = events.filter { !hasCursorHook(root: root, event: $0.name, command: command) }.map(\.name)
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

private func upsertNestedHooks(
    in root: [String: Any],
    command: String,
    events: [(name: String, matcher: String?)]
) -> [String: Any] {
    var root = root
    var hooks = root["hooks"] as? [String: Any] ?? [:]
    for event in events {
        hooks[event.name] = upsertNestedEventHook(
            value: hooks[event.name],
            matcher: event.matcher,
            command: command
        )
    }
    root["hooks"] = hooks
    return root
}

private func upsertCursorHooks(
    in root: [String: Any],
    command: String,
    events: [(name: String, matcher: String?)],
    format: CursorHookEnvelopeFormat
) -> [String: Any] {
    var root = root
    var hooks = root["hooks"] as? [String: Any] ?? [:]
    for event in events {
        switch format {
        case .nested:
            hooks[event.name] = upsertNestedEventHook(
                value: hooks[event.name],
                matcher: event.matcher,
                command: command
            )
        case .flat:
            hooks[event.name] = upsertFlatEventHook(
                value: hooks[event.name],
                matcher: event.matcher,
                command: command
            )
        }
    }
    root["hooks"] = hooks
    return root
}

private func upsertNestedEventHook(value: Any?, matcher: String?, command: String) -> [[String: Any]] {
    var groups = value as? [[String: Any]] ?? []
    groups = groups.compactMap { group in
        guard let handlers = group["hooks"] as? [[String: Any]] else {
            return group
        }
        let kept = handlers.filter { handler in
            guard let cmd = handler["command"] as? String else { return true }
            return !isSignalLightHookCommand(cmd, expectedCommand: command)
        }
        return kept.isEmpty ? nil : updatedHookGroup(group, handlers: kept)
    }
    groups.append(makeNestedHookGroup(matcher: matcher, command: command))
    return groups
}

private func upsertFlatEventHook(value: Any?, matcher: String?, command: String) -> [[String: Any]] {
    var scripts = value as? [[String: Any]] ?? []
    scripts = scripts.compactMap { entry in
        if let handlers = entry["hooks"] as? [[String: Any]] {
            let kept = handlers.filter { handler in
                guard let cmd = handler["command"] as? String else { return true }
                return !isSignalLightHookCommand(cmd, expectedCommand: command)
            }
            return kept.isEmpty ? nil : updatedHookGroup(entry, handlers: kept)
        }
        if let cmd = entry["command"] as? String, isSignalLightHookCommand(cmd, expectedCommand: command) {
            return nil
        }
        return entry
    }
    scripts.append(makeFlatHookScript(matcher: matcher, command: command))
    return scripts
}

private func updatedHookGroup(_ group: [String: Any], handlers: [[String: Any]]) -> [String: Any] {
    var updated = group
    updated["hooks"] = handlers
    return updated
}

private func makeNestedHookGroup(matcher: String?, command: String) -> [String: Any] {
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

private func makeFlatHookScript(matcher: String?, command: String) -> [String: Any] {
    var script: [String: Any] = [
        "type": "command",
        "command": command,
        "timeout": 5,
    ]
    if let matcher {
        script["matcher"] = matcher
    }
    return script
}

private func hasNestedHook(root: [String: Any], event: String, command: String) -> Bool {
    guard let hooks = root["hooks"] as? [String: Any],
          let groups = hooks[event] as? [[String: Any]] else {
        return false
    }
    return groups.contains { group in
        guard let handlers = group["hooks"] as? [[String: Any]] else {
            return false
        }
        return handlers.contains { handler in
            guard let cmd = handler["command"] as? String else { return false }
            return isSignalLightHookCommand(cmd, expectedCommand: command)
        }
    }
}

private func hasCursorHook(root: [String: Any], event: String, command: String) -> Bool {
    guard let hooks = root["hooks"] as? [String: Any],
          let entries = hooks[event] as? [[String: Any]] else {
        return false
    }
    return entries.contains { entry in
        if let cmd = entry["command"] as? String {
            return isSignalLightHookCommand(cmd, expectedCommand: command)
        }
        if let handlers = entry["hooks"] as? [[String: Any]] {
            return handlers.contains { handler in
                guard let cmd = handler["command"] as? String else { return false }
                return isSignalLightHookCommand(cmd, expectedCommand: command)
            }
        }
        return false
    }
}

private func sniffCursorHookEnvelopeFormat(from root: [String: Any]) -> CursorHookEnvelopeFormat? {
    guard let hooks = root["hooks"] as? [String: Any] else {
        return nil
    }
    var sawNested = false
    var sawFlat = false
    for value in hooks.values {
        guard let entries = value as? [[String: Any]] else {
            continue
        }
        for entry in entries {
            if entry["hooks"] != nil {
                sawNested = true
            } else if entry["command"] != nil {
                sawFlat = true
            }
        }
    }
    if sawFlat {
        return .flat
    }
    if sawNested {
        return .nested
    }
    return nil
}

private func defaultCursorAppSearchPaths() -> [URL] {
    var paths = [
        URL(fileURLWithPath: "/Applications/Cursor.app", isDirectory: true),
    ]
    let homeApplications = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Cursor.app", isDirectory: true)
    paths.append(homeApplications)
    return paths
}

private func readCursorAppVersion(searchPaths: [URL]) -> String? {
    for appURL in searchPaths {
        guard let bundle = Bundle(url: appURL),
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            continue
        }
        return version
    }
    return nil
}

private func isVersion(_ lhs: String, greaterThanOrEqualTo rhs: String) -> Bool {
    let left = parseVersionParts(lhs)
    let right = parseVersionParts(rhs)
    let count = max(left.count, right.count)
    for index in 0..<count {
        let leftPart = index < left.count ? left[index] : 0
        let rightPart = index < right.count ? right[index] : 0
        if leftPart != rightPart {
            return leftPart > rightPart
        }
    }
    return true
}

private func parseVersionParts(_ version: String) -> [Int] {
    version
        .split { !$0.isNumber }
        .compactMap { Int($0) }
}

private func isSignalLightHookCommand(_ existing: String, expectedCommand: String) -> Bool {
    if expectedCommand.hasSuffix("/codex-signal-hook") {
        return existing == expectedCommand || existing.contains("/codex-signal-hook")
    }
    if expectedCommand.hasSuffix("/claude-code-signal-hook") {
        return existing == expectedCommand || existing.contains("/claude-code-signal-hook")
    }
    if expectedCommand.hasSuffix("/cursor-signal-hook") {
        return existing == expectedCommand || existing.contains("/cursor-signal-hook")
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
