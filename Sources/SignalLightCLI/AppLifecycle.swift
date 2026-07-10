import AppKit
import Foundation

private let appBundleIdentifier = "com.vibecoding.signal-light"
private let installedAppPath = "/Applications/Signal Light.app"
private let installedCommandPaths = [
    "/usr/local/bin/signal-light",
    "/usr/local/bin/codex-signal-hook",
    "/usr/local/bin/claude-code-signal-hook",
    "/usr/local/bin/cursor-signal-hook",
    "/usr/local/bin/signal-light-uninstall",
]

func quitSignalLightApp() {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: appBundleIdentifier)
    for app in apps {
        app.terminate()
    }
    runAppleScriptQuit()
    runKillallFallback()

    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if NSRunningApplication.runningApplications(withBundleIdentifier: appBundleIdentifier).isEmpty {
            return
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    for app in NSRunningApplication.runningApplications(withBundleIdentifier: appBundleIdentifier) {
        app.forceTerminate()
    }
    runKillallFallback()
}

func uninstallSignalLight(stateDir: URL) throws {
    quitSignalLightApp()

    let paths = [installedAppPath] + installedCommandPaths + [stateDir.path]
    let protectedPaths = paths.filter { FileManager.default.fileExists(atPath: $0) && !canRemove(path: $0) }

    if protectedPaths.isEmpty {
        for path in paths {
            try removeIfExists(path)
        }
        print("Signal Light 已卸载。")
        return
    }

    let script = shellRemovalScript(paths: paths)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = [
        "-e",
        "do shell script \(appleScriptQuoted(script)) with administrator privileges",
    ]
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        throw SignalCLIError.message("卸载已取消或失败。")
    }

    print("Signal Light 已卸载。")
}

private func canRemove(path: String) -> Bool {
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
    return FileManager.default.isWritableFile(atPath: parent)
}

private func removeIfExists(_ path: String) throws {
    if FileManager.default.fileExists(atPath: path) {
        try FileManager.default.removeItem(atPath: path)
    }
}

private func shellRemovalScript(paths: [String]) -> String {
    paths
        .map { "rm -rf \(shellQuoted($0))" }
        .joined(separator: "\n")
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func appleScriptQuoted(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    + "\""
}

private func runAppleScriptQuit() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", "tell application \"Signal Light\" to quit"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

private func runKillallFallback() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["signal-light-mac"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}
