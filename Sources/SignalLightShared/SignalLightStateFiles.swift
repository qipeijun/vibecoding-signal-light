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

    // MARK: - Event Log

    private static let eventLogMaxBytes = 5 * 1024 * 1024

    public static func appendEventLog(entry: [String: Any], in stateDirectory: URL) {
        do {
            try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            let logURL = stateDirectory.appendingPathComponent("events.log")

            let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else { return }
            let output = line + "\n"

            let fd = open(logURL.path, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
            guard fd >= 0 else { return }
            defer { close(fd) }
            guard flock(fd, LOCK_EX) == 0 else { return }
            defer { flock(fd, LOCK_UN) }

            var stat = stat()
            if fstat(fd, &stat) == 0 && stat.st_size > off_t(eventLogMaxBytes) {
                // Rotate: keep last half of lines when file exceeds 5MB.
                if let contents = try? String(contentsOfFile: logURL.path, encoding: .utf8) {
                    var lines = contents.components(separatedBy: "\n")
                    lines.removeAll { $0.isEmpty }
                    if lines.count > 1 {
                        let keep = lines[lines.count / 2 ..< lines.count]
                        let rotated = keep.joined(separator: "\n") + "\n"
                        _ = try? rotated.write(to: logURL, atomically: true, encoding: .utf8)
                    }
                }
                close(fd)
                let newFd = open(logURL.path, O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
                guard newFd >= 0 else { return }
                defer { close(newFd) }
                let lineData = output.data(using: .utf8)!
                _ = lineData.withUnsafeBytes { write(newFd, $0.baseAddress!, lineData.count) }
            } else {
                let lineData = output.data(using: .utf8)!
                _ = lineData.withUnsafeBytes { write(fd, $0.baseAddress!, lineData.count) }
            }
        } catch {
            // Logging must never break state writes — silently ignore.
        }
    }
}
