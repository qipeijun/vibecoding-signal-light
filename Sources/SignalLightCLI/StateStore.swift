import CoreFoundation
import Foundation
import SignalLightShared

private let statusChangedNotificationName = "com.vibecoding.signal-light.status-changed"
private let statusChangedCFNotificationName = statusChangedNotificationName as CFString
private let statusChangedNotification = Notification.Name(statusChangedNotificationName)

final class StateStore {
    let stateDir: URL
    private let sessionFile: URL
    private let currentStatusFile: URL
    private let lockFile: URL
    private let sessionTTL: Double

    init(environment: [String: String] = ProcessInfo.processInfo.environment, config: SignalLightConfig? = nil) {
        let configStore = SignalLightConfigStore()
        let agentConfig: AgentConfig
        if let config {
            agentConfig = configStore.effectiveAgentConfig(from: config, environment: environment)
        } else {
            // 无 config 时也尝试加载，让环境变量覆盖机制正常工作
            let loaded = configStore.loadOrRepairConfig()
            agentConfig = configStore.effectiveAgentConfig(from: loaded, environment: environment)
        }

        stateDir = URL(fileURLWithPath: agentConfig.stateDirectory)
        sessionFile = stateDir.appendingPathComponent("sessions.json")
        currentStatusFile = stateDir.appendingPathComponent("current_status.json")
        lockFile = stateDir.appendingPathComponent("state.lock")
        sessionTTL = agentConfig.sessionTTLSeconds
    }

    func applySignal(_ signal: String) throws {
        guard validSignals.contains(signal) else {
            throw SignalCLIError.message("Unknown signal: \(signal)")
        }
        try writeCurrentStatus(signal)
    }

    func applySessionSignal(
        sessionKey: String,
        signalName: String,
        source: SessionSource? = nil,
        model: String? = nil
    ) throws -> String {
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
                let existingSource = state.sessions[sessionKey]?.source
                let existingModel = state.sessions[sessionKey]?.model
                state.sessions[sessionKey] = SessionRecord(
                    signal: signalName,
                    updatedAt: now,
                    source: source ?? existingSource,
                    model: model ?? existingModel
                )
            }

            let aggregate = aggregateSessions(state.sessions)
            try writeJSON(state, to: sessionFile)
            try writeCurrentStatus(aggregate)
            return aggregate
        }
    }

    func clearSessions() throws {
        try withLock {
            try SignalLightStateFiles.writeSessionState(SessionState(sessions: [:]), in: stateDir)
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
            "sessions": state.sessions.mapValues { record in
                var payload: [String: Any] = [
                    "signal": record.signal,
                    "updated_at": record.updatedAt,
                ]
                if let source = record.source {
                    var sourcePayload: [String: Any] = [
                        "captured_at": source.capturedAt,
                    ]
                    if let bundleIdentifier = source.bundleIdentifier {
                        sourcePayload["bundle_identifier"] = bundleIdentifier
                    }
                    if let processIdentifier = source.processIdentifier {
                        sourcePayload["process_identifier"] = processIdentifier
                    }
                    if let localizedName = source.localizedName {
                        sourcePayload["localized_name"] = localizedName
                    }
                    payload["source"] = sourcePayload
                }
                if let model = record.model {
                    payload["model"] = model
                }
                return payload
            },
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private func writeCurrentStatus(_ signal: String) throws {
        try SignalLightStateFiles.writeCurrentStatus(signal, in: stateDir)
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
        pruneExpiredSessions(&sessions, now: now, sessionTTL: sessionTTL)
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
