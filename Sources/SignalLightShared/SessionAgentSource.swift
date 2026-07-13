import Foundation

public enum PreferredAgentSource: String, Codable, CaseIterable, Equatable {
    case auto
    case cursor
    case codex
    case claude
    case opencode
    case terminal

    public var displayName: String {
        switch self {
        case .auto:
            return "自动（最近活跃）"
        case .cursor:
            return "Cursor"
        case .codex:
            return "Codex"
        case .claude:
            return "Claude Code"
        case .opencode:
            return "OpenCode"
        case .terminal:
            return "终端"
        }
    }
}

public let openCodeDisplayName = "OpenCode"
public let openCodeBundleIdentifier = "ai.opencode.cli"
public let openCodeSessionKeyPrefix = "ses_"

public let codexBundleIdentifiers: Set<String> = ["com.openai.codex"]
public let claudeBundleIdentifiers: Set<String> = ["com.anthropic.claudefordesktop"]
public let cursorBundleIdentifiers: Set<String> = [
    "com.todesktop.230313mzl4w4u92",
    "com.cursor.osx",
]
public let terminalBundleIdentifiers: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "dev.warp.Warp-Stable",
    "dev.warp.Warp",
    "com.mitchellh.ghostty",
    "io.alacritty",
    "net.kovidgoyal.kitty",
    "org.tabby",
]

public let openCodeSessionPayloadKeys = [
    "session_id",
    "conversation_id",
    "thread_id",
    "chat_id",
    "codex_session_id",
]

public func isOpenCodeSessionKey(_ sessionKey: String) -> Bool {
    sessionKey.hasPrefix(openCodeSessionKeyPrefix)
}

public func openCodeSessionID(from payload: [String: Any]) -> String? {
    for key in openCodeSessionPayloadKeys {
        if let value = payload[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }
    return nil
}

public func isOpenCodePayload(_ payload: [String: Any]) -> Bool {
    guard let sessionID = openCodeSessionID(from: payload) else {
        return false
    }
    return isOpenCodeSessionKey(sessionID)
}

public func makeOpenCodeSessionSource(capturedAt: Double = Date().timeIntervalSince1970) -> SessionSource {
    SessionSource(
        bundleIdentifier: openCodeBundleIdentifier,
        processIdentifier: nil,
        localizedName: openCodeDisplayName,
        capturedAt: capturedAt
    )
}

public func sessionAgentKind(sessionKey: String, source: SessionSource?) -> PreferredAgentSource {
    if isOpenCodeSessionKey(sessionKey) {
        return .opencode
    }
    return sessionAgentKind(for: source)
}

public func sessionAgentKind(for source: SessionSource?) -> PreferredAgentSource {
    guard let source else {
        return .terminal
    }

    if let localizedName = source.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) {
        if localizedName == openCodeDisplayName {
            return .opencode
        }
        if localizedName == "Claude Code" {
            return .claude
        }
    }

    guard let bundleIdentifier = source.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
          !bundleIdentifier.isEmpty
    else {
        return .terminal
    }

    if bundleIdentifier == openCodeBundleIdentifier {
        return .opencode
    }
    if cursorBundleIdentifiers.contains(bundleIdentifier) {
        return .cursor
    }
    if codexBundleIdentifiers.contains(bundleIdentifier) {
        return .codex
    }
    if claudeBundleIdentifiers.contains(bundleIdentifier) {
        return .claude
    }
    if terminalBundleIdentifiers.contains(bundleIdentifier) {
        return .terminal
    }
    return .terminal
}

public func activeSessions(
    _ sessions: [String: SessionRecord],
    now: Double,
    sessionTTL: Double,
    excludingEndSignals: Bool = false
) -> [String: SessionRecord] {
    sessions.filter { _, record in
        if excludingEndSignals, sessionEndSignals.contains(record.signal) {
            return false
        }
        let ttl = signalTTLs[record.signal] ?? sessionTTL
        return now - record.updatedAt <= ttl
    }
}

public func filteredSessions(
    _ sessions: [String: SessionRecord],
    preferred: PreferredAgentSource,
    now: Double,
    sessionTTL: Double,
    excludingEndSignals: Bool = false
) -> [String: SessionRecord] {
    let active = activeSessions(
        sessions,
        now: now,
        sessionTTL: sessionTTL,
        excludingEndSignals: excludingEndSignals
    )
    guard preferred != .auto else {
        return active
    }
    return active.filter { key, record in
        sessionAgentKind(sessionKey: key, source: record.source) == preferred
    }
}

public func preferredSessionRecord(
    in sessions: [String: SessionRecord],
    preferred: PreferredAgentSource,
    now: Double,
    sessionTTL: Double,
    excludingEndSignals: Bool = true
) -> SessionRecord? {
    filteredSessions(
        sessions,
        preferred: preferred,
        now: now,
        sessionTTL: sessionTTL,
        excludingEndSignals: excludingEndSignals
    ).values.max(by: { $0.updatedAt < $1.updatedAt })
}

public func aggregateSessions(
    _ sessions: [String: SessionRecord],
    preferred: PreferredAgentSource = .auto,
    now: Double = Date().timeIntervalSince1970,
    sessionTTL: Double = AgentConfig.default.sessionTTLSeconds
) -> String {
    let scoped = filteredSessions(
        sessions,
        preferred: preferred,
        now: now,
        sessionTTL: sessionTTL,
        excludingEndSignals: false
    )
    return aggregateSessions(scoped)
}
