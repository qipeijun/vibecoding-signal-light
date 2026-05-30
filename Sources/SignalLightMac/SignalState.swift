import Foundation
import SignalLightShared

final class SignalStateStore {
    private let fileURL: URL
    private let sessionFileURL: URL
    let stateDirectoryURL: URL
    private(set) var state: SignalState = .idle
    private(set) var updatedAt: Double?
    private(set) var sessionState = SessionState(sessions: [:])

    init(environment: [String: String] = ProcessInfo.processInfo.environment, stateDirectory: String? = nil) {
        let root = stateDirectory ?? environment["SIGNAL_LIGHT_STATE_DIR"] ?? "/private/tmp/signal-light"
        stateDirectoryURL = URL(fileURLWithPath: root)
        fileURL = stateDirectoryURL.appendingPathComponent("current_status.json")
        sessionFileURL = stateDirectoryURL.appendingPathComponent("sessions.json")
    }

    func refresh() -> Bool {
        refreshSessions()
        guard let data = try? Data(contentsOf: fileURL),
              let status = try? JSONDecoder().decode(SignalStatus.self, from: data),
              let nextState = SignalState(rawValue: status.aggregate)
        else {
            return false
        }

        let didChange = state != nextState
        state = nextState
        updatedAt = status.updatedAt
        return didChange
    }

    private func refreshSessions() {
        guard let data = try? Data(contentsOf: sessionFileURL),
              let state = try? JSONDecoder().decode(SessionState.self, from: data)
        else {
            sessionState = SessionState(sessions: [:])
            return
        }
        sessionState = state
    }
}
