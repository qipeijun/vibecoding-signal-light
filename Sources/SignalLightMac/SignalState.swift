import Foundation
import SignalLightShared

final class SignalStateStore {
    private let fileURL: URL
    let stateDirectoryURL: URL
    private(set) var state: SignalState = .idle

    init(environment: [String: String] = ProcessInfo.processInfo.environment, stateDirectory: String? = nil) {
        let root = stateDirectory ?? environment["SIGNAL_LIGHT_STATE_DIR"] ?? "/private/tmp/signal-light"
        stateDirectoryURL = URL(fileURLWithPath: root)
        fileURL = stateDirectoryURL.appendingPathComponent("current_status.json")
    }

    func refresh() -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let status = try? JSONDecoder().decode(SignalStatus.self, from: data),
              let nextState = SignalState(rawValue: status.aggregate)
        else {
            return false
        }

        let didChange = state != nextState
        state = nextState
        return didChange
    }
}
