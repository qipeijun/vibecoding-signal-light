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

    private static func writeJSON<T: Encodable>(_ payload: T, to url: URL, stateDirectory: URL) throws {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }
}
