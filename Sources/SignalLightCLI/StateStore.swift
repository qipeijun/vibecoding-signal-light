import CoreFoundation
import Foundation

private let statusChangedNotificationName = "com.vibecoding.signal-light.status-changed"
private let statusChangedCFNotificationName = statusChangedNotificationName as CFString
private let statusChangedNotification = Notification.Name(statusChangedNotificationName)

struct SessionRecord: Codable {
    var signal: String
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case signal
        case updatedAt = "updated_at"
    }
}

struct SessionState: Codable {
    var sessions: [String: SessionRecord]
}

struct CurrentStatus: Codable {
    var aggregate: String
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case aggregate
        case updatedAt = "updated_at"
    }
}

final class StateStore {
    let stateDir: URL
    private let sessionFile: URL
    private let currentStatusFile: URL
    private let lockFile: URL
    private let sessionTTL: Double

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        stateDir = URL(fileURLWithPath: environment["SIGNAL_LIGHT_STATE_DIR"] ?? "/private/tmp/signal-light")
        sessionFile = stateDir.appendingPathComponent("sessions.json")
        currentStatusFile = stateDir.appendingPathComponent("current_status.json")
        lockFile = stateDir.appendingPathComponent("state.lock")
        sessionTTL = Double(environment["SIGNAL_LIGHT_SESSION_TTL_SECONDS"] ?? "86400") ?? 86400
    }

    func applySignal(_ signal: String) throws {
        guard validSignals.contains(signal) else {
            throw SignalCLIError.message("Unknown signal: \(signal)")
        }
        try writeCurrentStatus(signal)
    }

    func applySessionSignal(sessionKey: String, signalName: String) throws -> String {
        try withLock {
            var state = readSessionState()
            let now = Date().timeIntervalSince1970
            pruneSessions(&state.sessions, now: now)

            if sessionEndSignals.contains(signalName) {
                state.sessions.removeValue(forKey: sessionKey)
            } else if turnEndSignals.contains(signalName) {
                let current = state.sessions[sessionKey]?.signal
                if current == nil || !redSignals.contains(current!) {
                    state.sessions.removeValue(forKey: sessionKey)
                }
            } else {
                guard validSignals.contains(signalName) else {
                    throw SignalCLIError.message("Unknown signal: \(signalName)")
                }
                state.sessions[sessionKey] = SessionRecord(signal: signalName, updatedAt: now)
            }

            let aggregate = aggregateSessions(state.sessions)
            try writeJSON(state, to: sessionFile)
            try writeCurrentStatus(aggregate)
            return aggregate
        }
    }

    func clearSessions() throws {
        try withLock {
            try writeJSON(SessionState(sessions: [:]), to: sessionFile)
        }
    }

    func snapshotData() throws -> Data {
        if let currentStatus = try readCurrentStatus() {
            return try JSONEncoder.prettySignalEncoder.encode(currentStatus)
        }

        var state = readSessionState()
        pruneSessions(&state.sessions, now: Date().timeIntervalSince1970)
        let aggregate = aggregateSessions(state.sessions)
        let payload: [String: Any] = [
            "aggregate": aggregate,
            "sessions": state.sessions.mapValues { [
                "signal": $0.signal,
                "updated_at": $0.updatedAt,
            ] },
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private func writeCurrentStatus(_ signal: String) throws {
        let payload = CurrentStatus(aggregate: signal, updatedAt: Date().timeIntervalSince1970)
        try writeJSON(payload, to: currentStatusFile)
        notifyStatusChanged()
    }

    private func notifyStatusChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(statusChangedCFNotificationName),
            nil,
            nil,
            true
        )

        DistributedNotificationCenter.default().postNotificationName(
            statusChangedNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func readCurrentStatus() throws -> CurrentStatus? {
        guard FileManager.default.fileExists(atPath: currentStatusFile.path) else {
            return nil
        }
        let data = try Data(contentsOf: currentStatusFile)
        let status = try JSONDecoder().decode(CurrentStatus.self, from: data)
        guard validSignals.contains(status.aggregate) else {
            throw SignalCLIError.message("Unknown signal in current status: \(status.aggregate)")
        }
        return status
    }

    private func readSessionState() -> SessionState {
        guard let data = try? Data(contentsOf: sessionFile),
              let state = try? JSONDecoder().decode(SessionState.self, from: data)
        else {
            return SessionState(sessions: [:])
        }
        return state
    }

    private func pruneSessions(_ sessions: inout [String: SessionRecord], now: Double) {
        sessions = sessions.filter { _, record in
            now - record.updatedAt <= sessionTTL
        }
    }

    private func writeJSON<T: Encodable>(_ payload: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettySignalEncoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    private func withLock<T>(_ work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let fd = open(lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard fd >= 0 else {
            throw SignalCLIError.message("Failed to open state lock: \(lockFile.path)")
        }
        defer {
            close(fd)
        }
        guard flock(fd, LOCK_EX) == 0 else {
            throw SignalCLIError.message("Failed to lock state file.")
        }
        defer {
            flock(fd, LOCK_UN)
        }
        return try work()
    }
}

extension JSONEncoder {
    static var prettySignalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

enum SignalCLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}
