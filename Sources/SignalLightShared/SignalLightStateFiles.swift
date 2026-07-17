import Foundation

public enum SignalLightStateFileError: Error, CustomStringConvertible {
    case unknownSignal(String)

    public var description: String {
        switch self {
        case .unknownSignal(let signal):
            return "Unknown signal: \(signal)"
        }
    }
}

public enum SignalLightStateFiles {
    public static func clearSessionsAndWriteIdle(in stateDirectory: URL) throws {
        try writeSessionState(SessionState(sessions: [:]), in: stateDirectory)
        try writeCurrentStatus("idle", in: stateDirectory)
    }

    public static func writeSessionState(_ state: SessionState, in stateDirectory: URL) throws {
        try writeJSON(state, to: stateDirectory.appendingPathComponent("sessions.json"), stateDirectory: stateDirectory)
    }

    public static func writeCurrentStatus(
        _ signal: String,
        in stateDirectory: URL,
        updatedAt: Double = Date().timeIntervalSince1970
    ) throws {
        guard validSignals.contains(signal) else {
            throw SignalLightStateFileError.unknownSignal(signal)
        }
        let payload = CurrentStatus(aggregate: signal, updatedAt: updatedAt)
        try writeJSON(payload, to: stateDirectory.appendingPathComponent("current_status.json"), stateDirectory: stateDirectory)
    }

    /// 追加一条只含状态元数据的历史，并按 24 小时和 200 条双重上限滚动清理。
    /// 连续同会话、同状态记录会更新最后时间，避免全局与项目 Hook 重复执行时伪造状态流。
    public static func appendHistoryEntry(
        _ entry: SignalHistoryEntry,
        in stateDirectory: URL,
        now: Double = Date().timeIntervalSince1970
    ) throws {
        let url = stateDirectory.appendingPathComponent("history.json")
        var history = readHistory(from: url)
        history.entries = history.entries.filter { now - $0.recordedAt <= historyRetentionSeconds }
        history.entries = coalescingConsecutiveDuplicates(history.entries)
        if let last = history.entries.last,
           last.sessionKey == entry.sessionKey,
           last.signal == entry.signal,
           last.aggregate == entry.aggregate {
            history.entries[history.entries.count - 1] = entry
        } else {
            history.entries.append(entry)
        }
        if history.entries.count > historyEntryLimit {
            history.entries = Array(history.entries.suffix(historyEntryLimit))
        }
        try writeJSON(history, to: url, stateDirectory: stateDirectory)
    }

    private static func coalescingConsecutiveDuplicates(
        _ entries: [SignalHistoryEntry]
    ) -> [SignalHistoryEntry] {
        entries.reduce(into: []) { result, entry in
            if let last = result.last,
               last.sessionKey == entry.sessionKey,
               last.signal == entry.signal,
               last.aggregate == entry.aggregate {
                result[result.count - 1] = entry
            } else {
                result.append(entry)
            }
        }
    }

    public static func readHistory(in stateDirectory: URL) -> SignalHistory {
        readHistory(from: stateDirectory.appendingPathComponent("history.json"))
    }

    public static func clearHistory(in stateDirectory: URL) throws {
        try writeJSON(
            SignalHistory(entries: []),
            to: stateDirectory.appendingPathComponent("history.json"),
            stateDirectory: stateDirectory
        )
    }

    /// 记录 Codex Hook 已实际运行。该文件只含时间戳，用于区分“已配置”和“已产生事件”。
    public static func writeCodexHookActivity(
        in stateDirectory: URL,
        lastEventAt: Double = Date().timeIntervalSince1970
    ) throws {
        try writeJSON(
            CodexHookActivity(lastEventAt: lastEventAt),
            to: stateDirectory.appendingPathComponent("codex_hook_activity.json"),
            stateDirectory: stateDirectory
        )
    }

    public static func readCodexHookActivity(in stateDirectory: URL) -> CodexHookActivity? {
        let url = stateDirectory.appendingPathComponent("codex_hook_activity.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(CodexHookActivity.self, from: data)
    }

    private static func readHistory(from url: URL) -> SignalHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(SignalHistory.self, from: data)
        else {
            return SignalHistory(entries: [])
        }
        return history
    }

    private static func writeJSON<T: Encodable>(_ payload: T, to url: URL, stateDirectory: URL) throws {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }
}
