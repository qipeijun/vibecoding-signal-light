import Foundation

let args = Array(CommandLine.arguments.dropFirst())
let store = StateStore()

do {
    let code = try run(args: args, store: store)
    exit(Int32(code))
} catch {
    print(String(describing: error), to: &standardError)
    exit(1)
}

func run(args: [String], store: StateStore) throws -> Int {
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
    default:
        printHelp()
        return 2
    }
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

    _ = try store.applySessionSignal(sessionKey: key, signalName: signal)
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

    _ = try store.applySessionSignal(sessionKey: key, signalName: signal)
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

private func printHelp() {
    print("Usage: signal-light <list|play|status|codex-hook|claude-code-hook|test|app|quit|uninstall>")
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
