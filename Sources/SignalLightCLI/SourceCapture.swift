import AppKit
import Foundation
import SignalLightShared

private let signalLightBundleIdentifier = "com.vibecoding.signal-light"
private let codexBundleIdentifiers = ["com.openai.codex"]
private let terminalBundleIdentifiers = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "dev.warp.Warp-Stable",
    "dev.warp.Warp",
    "com.mitchellh.ghostty",
    "io.alacritty",
    "net.kovidgoyal.kitty",
    "org.tabby",
]

func currentCodexSessionSource() -> SessionSource? {
    if let explicit = sourceFromEnvironmentOverride() {
        return explicit
    }

    return sourceFromTerminalEnvironment()
        ?? sourceFromFrontmostApp(bundleIdentifiers: Set(codexBundleIdentifiers + terminalBundleIdentifiers))
        ?? sourceFromRunningApp(bundleIdentifiers: codexBundleIdentifiers)
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
