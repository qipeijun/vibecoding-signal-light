import Foundation
import SignalLightShared

let args = Array(CommandLine.arguments.dropFirst())

// 提前加载配置，供 StateStore 使用
let configStore = SignalLightConfigStore()
let rawConfig = configStore.loadOrRepairConfig()
let store = StateStore(config: rawConfig)

do {
    let code = try run(args: args, store: store, configStore: configStore)
    exit(Int32(code))
} catch {
    print(String(describing: error), to: &standardError)
    exit(1)
}

func run(args: [String], store: StateStore, configStore: SignalLightConfigStore) throws -> Int {
    guard let command = args.first else {
        printHelp()
        return 2
    }

    let rest = Array(args.dropFirst())
    switch command {
    case "list":
        print("Signal language:")
        for signal in signalOrder {
            if let text = signalSummaries[signal] {
                print("- \(signal): \(text.summary) \(text.attention)")
            }
        }
        return 0
    case "play":
        return try playSignal(args: rest, store: store)
    case "status":
        let data = try store.snapshotData()
        FileHandle.standardOutput.write(data)
        print("")
        return 0
    case "version", "--version", "-v":
        print("Signal Light \(SignalLightVersion.displayString)")
        return 0
    case "codex-hook":
        return try runCodexHook(args: rest, store: store)
    case "claude-code-hook":
        return try runClaudeHook(args: rest, store: store)
    case "test":
        return try runPreview(store: store)
    case "app":
        return try runApp()
    case "quit":
        quitSignalLightApp()
        return 0
    case "uninstall":
        try uninstallSignalLight(stateDir: store.stateDir)
        return 0
    case "doctor":
        return try runDoctor(args: rest, store: store, configStore: configStore)
    case "install-hooks":
        return try runInstallHooks(args: rest)
    case "config":
        return try configCommand(args: rest, configStore: configStore)
    default:
        printHelp()
        return 2
    }
}

private func runDoctor(args: [String], store: StateStore, configStore: SignalLightConfigStore) throws -> Int {
    let homeDirectory = try homeDirectoryArgument(from: args) ?? FileManager.default.homeDirectoryForCurrentUser
    let configFile = configStore.configFileURL()
    let config = configStore.loadOrRepairConfig()
    let agent = configStore.effectiveAgentConfig(from: config)
    let stateDir = URL(fileURLWithPath: agent.stateDirectory)
    let appPath = "/Applications/Signal Light.app"
    let checks: [(String, Bool, String)] = [
        ("App 已安装", FileManager.default.fileExists(atPath: appPath), appPath),
        ("signal-light 命令可执行", FileManager.default.isExecutableFile(atPath: "/usr/local/bin/signal-light"), "/usr/local/bin/signal-light"),
        ("Codex hook 命令可执行", FileManager.default.isExecutableFile(atPath: "/usr/local/bin/codex-signal-hook"), "/usr/local/bin/codex-signal-hook"),
        ("Claude hook 命令可执行", FileManager.default.isExecutableFile(atPath: "/usr/local/bin/claude-code-signal-hook"), "/usr/local/bin/claude-code-signal-hook"),
        ("配置文件存在", FileManager.default.fileExists(atPath: configFile.path), configFile.path),
        ("状态目录可写", directoryIsWritable(stateDir), stateDir.path),
    ]

    var failed = false
    for (title, ok, detail) in checks {
        if !ok { failed = true }
        print("\(ok ? "OK" : "FAIL") \(title): \(detail)")
    }

    for report in checkSignalLightHooks(homeDirectory: homeDirectory) {
        if !report.ok { failed = true }
        print("\(report.ok ? "OK" : "FAIL") \(report.title): \(report.message) (\(report.path))")
    }

    print("config path: \(configFile.path)")
    print("state directory: \(store.stateDir.path)")
    print("version: \(SignalLightVersion.current)")
    return failed ? 1 : 0
}

private func runInstallHooks(args: [String]) throws -> Int {
    let quiet = args.contains("--quiet")
    let homeDirectory = try homeDirectoryArgument(from: args) ?? FileManager.default.homeDirectoryForCurrentUser
    let reports = try installSignalLightHooks(homeDirectory: homeDirectory)
    if !quiet {
        for report in reports {
            print("\(report.changed ? "UPDATED" : "OK") \(report.title): \(report.message) (\(report.path))")
        }
        print("Codex 首次发现新 hook 时仍会要求在 /hooks 里确认信任；这是 Codex 的安全机制。")
    }
    return 0
}

private func homeDirectoryArgument(from args: [String]) throws -> URL? {
    guard let index = args.firstIndex(of: "--home") else {
        return nil
    }
    let valueIndex = args.index(after: index)
    guard valueIndex < args.endIndex else {
        throw SignalCLIError.message("--home requires a path")
    }
    return URL(fileURLWithPath: args[valueIndex], isDirectory: true)
}

private func playSignal(args: [String], store: StateStore) throws -> Int {
    guard let signal = args.first, validSignals.contains(signal) else {
        throw SignalCLIError.message("Unknown or missing signal.")
    }

    if args.contains("--dry-run") {
        print("signal=\(signal)")
        return 0
    }

    if ["idle", "off"].contains(signal) {
        try store.clearSessions()
    }
    try store.applySignal(signal)

    if !args.contains("--quiet") {
        let text = signalSummaries[signal]
        print("Playing \(signal): \(text?.summary ?? "")")
    }
    return 0
}

private func runCodexHook(args: [String], store: StateStore) throws -> Int {
    let stdinText = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let payload = readPayload(stdinText: stdinText)
    let event = eventFromArgs(
        args,
        payload: payload,
        keys: ["hook_event_name", "event_name", "event", "hook", "type"],
        fallback: ProcessInfo.processInfo.environment["CODEX_HOOK_EVENT"]
            ?? ProcessInfo.processInfo.environment["HOOK_EVENT"]
            ?? "Stop"
    )
    let signal = chooseCodexSignal(eventName: event, payload: payload)
    let key = codexSessionKey(payload: payload, environment: ProcessInfo.processInfo.environment)

    if args.contains("--dry-run") {
        print("Session \(key): \(signal)")
        return 0
    }

    _ = try store.applySessionSignal(
        sessionKey: key,
        signalName: signal,
        source: currentSessionSource(preference: .codex)
    )
    return 0
}

private func runClaudeHook(args: [String], store: StateStore) throws -> Int {
    let stdinText = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let payload = readPayload(stdinText: stdinText)
    let event = eventFromArgs(args, payload: payload, keys: ["event", "hook_event_name"], fallback: "Stop")
    let signal = chooseClaudeSignal(eventName: event, payload: payload)
    let key = claudeSessionKey(payload: payload, environment: ProcessInfo.processInfo.environment)

    if args.contains("--dry-run") {
        print("Session \(key): \(signal)")
        return 0
    }

    _ = try store.applySessionSignal(
        sessionKey: key,
        signalName: signal,
        source: currentSessionSource(preference: .claudeCode)
    )
    return 0
}

private func runPreview(store: StateStore) throws -> Int {
    for signal in ["permission", "attention", "working", "idle"] {
        try store.applySignal(signal)
        Thread.sleep(forTimeInterval: 0.8)
    }
    return 0
}

private func runApp() throws -> Int {
    let override = ProcessInfo.processInfo.environment["SIGNAL_LIGHT_APP_BIN"]
    let candidates = [
        override,
        "/Applications/Signal Light.app/Contents/MacOS/signal-light-mac",
    ].compactMap { $0 }

    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        do {
            try process.run()
            process.waitUntilExit()
            return Int(process.terminationStatus)
        } catch {
            continue
        }
    }

    throw SignalCLIError.message("Signal Light.app is not installed. Open /Applications/Signal Light.app first.")
}

private func configCommand(args: [String], configStore: SignalLightConfigStore) throws -> Int {
    guard let subcommand = args.first else {
        print("Usage: signal-light config <status|repair>")
        return 2
    }

    switch subcommand {
    case "status":
        let configFile = configStore.configFileURL()
        print("config path: \(configFile.path)")
        print("exists: \(FileManager.default.fileExists(atPath: configFile.path))")

        let config = configStore.loadOrRepairConfig()
        let agent = configStore.effectiveAgentConfig(from: config)
        print("schema version: \(config.schemaVersion)")
        print("state directory: \(agent.stateDirectory)")
        print("session TTL: \(agent.sessionTTLSeconds)")

        if let repairResult = configStore.lastRepairResult {
            print("last repair: \(repairResult)")
        }
        return 0

    case "repair":
        let config = try configStore.repairConfig()
        print("config repaired (schema version \(config.schemaVersion))")
        return 0

    default:
        print("Usage: signal-light config <status|repair>")
        return 2
    }
}

private func printHelp() {
    print("Usage: signal-light <list|play|status|version|codex-hook|claude-code-hook|test|app|doctor|install-hooks|config|quit|uninstall>")
    print("       signal-light doctor [--home <path>]")
    print("       signal-light install-hooks [--home <path>] [--quiet]")
}

private func directoryIsWritable(_ url: URL) -> Bool {
    if FileManager.default.fileExists(atPath: url.path) {
        return FileManager.default.isWritableFile(atPath: url.path)
    }
    return FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
}

private var standardError = FileHandle.standardError

extension String {
    func write(to file: inout FileHandle) {
        if let data = (self + "\n").data(using: .utf8) {
            file.write(data)
        }
    }
}

private func print(_ text: String, to file: inout FileHandle) {
    text.write(to: &file)
}
