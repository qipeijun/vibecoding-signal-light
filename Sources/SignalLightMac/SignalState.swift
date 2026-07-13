import Foundation
import SignalLightShared

final class SignalStateStore {
    private let fileURL: URL
    private let sessionFileURL: URL
    let stateDirectoryURL: URL
    private(set) var state: SignalState = .idle
    private(set) var updatedAt: Double?
    private(set) var sessionState = SessionState(sessions: [:])
    private var preferredAgentSource: PreferredAgentSource = .auto
    private var sessionTTL: Double = AgentConfig.default.sessionTTLSeconds

    init(environment: [String: String] = ProcessInfo.processInfo.environment, stateDirectory: String? = nil) {
        let root = stateDirectory ?? environment["SIGNAL_LIGHT_STATE_DIR"] ?? "/private/tmp/signal-light"
        stateDirectoryURL = URL(fileURLWithPath: root)
        fileURL = stateDirectoryURL.appendingPathComponent("current_status.json")
        sessionFileURL = stateDirectoryURL.appendingPathComponent("sessions.json")
    }

    func setPresentationPreferences(preferredAgentSource: PreferredAgentSource, sessionTTL: Double) {
        self.preferredAgentSource = preferredAgentSource
        self.sessionTTL = sessionTTL
    }

    func refresh() -> Bool {
        refreshSessions()
        let nextState = resolvedState()
        let fileUpdatedAt = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode(SignalStatus.self, from: $0) }?
            .updatedAt

        let didChange = state != nextState
        state = nextState
        updatedAt = fileUpdatedAt
        return didChange
    }

    func resolvedState(now: Double = Date().timeIntervalSince1970) -> SignalState {
        let aggregate = aggregateSessions(
            sessionState.sessions,
            preferred: preferredAgentSource,
            now: now,
            sessionTTL: sessionTTL
        )
        return SignalState(rawValue: aggregate) ?? .idle
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
