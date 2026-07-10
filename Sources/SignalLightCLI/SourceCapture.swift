import AppKit
import Foundation
import SignalLightShared

enum SessionSourcePreference {
    case codex
    case claudeCode
    case cursor
}

func currentSessionSource(preference: SessionSourcePreference, payload: [String: Any] = [:]) -> SessionSource? {
    if let explicit = sourceFromEnvironmentOverride() {
        return explicit
    }

    if let inferred = sourceFromPayload(payload, preference: preference) {
        return inferred
    }

    switch preference {
    case .codex:
        return sourceFromRunningApp(bundleIdentifiers: Array(codexBundleIdentifiers))
            ?? sourceFromFrontmostApp(bundleIdentifiers: codexBundleIdentifiers)
            ?? sourceFromTerminalEnvironment()
    case .claudeCode:
        return sourceFromClaudeSession(payload: payload)
            ?? sourceFromRunningApp(bundleIdentifiers: Array(claudeBundleIdentifiers))
            ?? sourceFromFrontmostApp(bundleIdentifiers: claudeBundleIdentifiers)
            ?? sourceFromTerminalEnvironment()
    case .cursor:
        return sourceFromRunningApp(bundleIdentifiers: Array(cursorBundleIdentifiers))
            ?? sourceFromFrontmostApp(bundleIdentifiers: cursorBundleIdentifiers)
    }
}

private let signalLightBundleIdentifier = "com.vibecoding.signal-light"

private func sourceFromPayload(_ payload: [String: Any], preference: SessionSourcePreference) -> SessionSource? {
    if isOpenCodePayload(payload) {
        return makeOpenCodeSessionSource()
    }

    if isCursorPayload(payload) {
        return sourceFromRunningApp(bundleIdentifiers: Array(cursorBundleIdentifiers))
            ?? sourceFromKnownBundleIdentifier("com.todesktop.230313mzl4w4u92", localizedName: "Cursor")
    }

    if let claudeSource = sourceFromClaudeSession(payload: payload) {
        return claudeSource
    }

    if payload["codex_session_id"] != nil {
        return sourceFromRunningApp(bundleIdentifiers: Array(codexBundleIdentifiers))
            ?? sourceFromKnownBundleIdentifier("com.openai.codex", localizedName: "Codex")
    }

    switch preference {
    case .cursor:
        return nil
    case .claudeCode, .codex:
        return nil
    }
}

private func isCursorPayload(_ payload: [String: Any]) -> Bool {
    if isOpenCodePayload(payload) {
        return false
    }

    guard let conversationID = payload["conversation_id"] as? String,
          !conversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return false
    }

    if isOpenCodeSessionKey(conversationID) {
        return false
    }

    if payload["cursor_version"] != nil || payload["workspace_roots"] != nil {
        return true
    }

    if let eventName = payload["hook_event_name"] as? String {
        let trimmed = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first.isLowercase, resolvedCodexEventSignal(eventName: trimmed) != nil {
            return true
        }
    }

    return false
}

private func sourceFromEnvironmentOverride() -> SessionSource? {
    let environment = ProcessInfo.processInfo.environment
    guard let bundleIdentifier = environment["SIGNAL_LIGHT_SOURCE_BUNDLE_IDENTIFIER"],
          !bundleIdentifier.isEmpty,
          bundleIdentifier != signalLightBundleIdentifier
    else {
        return nil
    }

    let processIdentifier = environment["SIGNAL_LIGHT_SOURCE_PROCESS_IDENTIFIER"].flatMap(Int.init)
    return SessionSource(
        bundleIdentifier: bundleIdentifier,
        processIdentifier: processIdentifier,
        localizedName: environment["SIGNAL_LIGHT_SOURCE_LOCALIZED_NAME"],
        capturedAt: Date().timeIntervalSince1970
    )
}

private func sourceFromFrontmostApp(bundleIdentifiers: Set<String>) -> SessionSource? {
    guard let app = NSWorkspace.shared.frontmostApplication,
          let bundleIdentifier = app.bundleIdentifier,
          bundleIdentifiers.contains(bundleIdentifier)
    else {
        return nil
    }
    return source(from: app)
}

private func sourceFromRunningApp(bundleIdentifiers: [String]) -> SessionSource? {
    for bundleIdentifier in bundleIdentifiers {
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) {
            return source(from: app)
        }
    }
    return nil
}

private func sourceFromTerminalEnvironment() -> SessionSource? {
    let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? ""
    switch termProgram {
    case "Apple_Terminal":
        return sourceFromRunningApp(bundleIdentifiers: ["com.apple.Terminal"])
            ?? sourceFromKnownBundleIdentifier("com.apple.Terminal", localizedName: "终端")
    case "iTerm.app":
        return sourceFromRunningApp(bundleIdentifiers: ["com.googlecode.iterm2"])
            ?? sourceFromKnownBundleIdentifier("com.googlecode.iterm2", localizedName: "iTerm")
    case "WarpTerminal":
        return sourceFromRunningApp(bundleIdentifiers: ["dev.warp.Warp-Stable", "dev.warp.Warp"])
            ?? sourceFromKnownBundleIdentifier("dev.warp.Warp-Stable", localizedName: "Warp")
    default:
        return nil
    }
}

private func sourceFromClaudeSession(payload: [String: Any]) -> SessionSource? {
    guard let sessionID = claudeSessionID(payload: payload) else {
        return nil
    }

    let sessionDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions", isDirectory: true)
    guard let urls = try? FileManager.default.contentsOfDirectory(
        at: sessionDirectory,
        includingPropertiesForKeys: nil
    ) else {
        return nil
    }

    for url in urls where url.pathExtension == "json" {
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(ClaudeSessionMetadata.self, from: data),
              metadata.sessionId == sessionID
        else {
            continue
        }

        return SessionSource(
            bundleIdentifier: nil,
            processIdentifier: metadata.pid,
            localizedName: "Claude Code",
            capturedAt: Date().timeIntervalSince1970
        )
    }

    return nil
}

private func claudeSessionID(payload: [String: Any]) -> String? {
    if let sessionID = payload["session_id"] as? String {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }

    let environment = ProcessInfo.processInfo.environment
    for key in ["CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID"] {
        if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
    }

    return nil
}

private struct ClaudeSessionMetadata: Decodable {
    let pid: Int?
    let sessionId: String?
}

private func sourceFromKnownBundleIdentifier(_ bundleIdentifier: String, localizedName: String) -> SessionSource {
    SessionSource(
        bundleIdentifier: bundleIdentifier,
        processIdentifier: nil,
        localizedName: localizedName,
        capturedAt: Date().timeIntervalSince1970
    )
}

private func source(from app: NSRunningApplication) -> SessionSource? {
    guard app.bundleIdentifier != signalLightBundleIdentifier else {
        return nil
    }
    return SessionSource(
        bundleIdentifier: app.bundleIdentifier,
        processIdentifier: Int(app.processIdentifier),
        localizedName: app.localizedName,
        capturedAt: Date().timeIntervalSince1970
    )
}
