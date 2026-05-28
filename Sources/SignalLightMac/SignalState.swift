import Foundation

enum SignalState: String {
    case idle
    case thinking
    case working
    case toolDone = "tool_done"
    case attention
    case permission
    case blocked
    case done
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case off

    var displayMode: SignalDisplayMode {
        switch self {
        case .idle, .done, .sessionStart, .sessionEnd:
            return .steady(.green)
        case .thinking, .working, .toolDone:
            return .workPulse
        case .attention:
            return .flash(.yellow)
        case .permission, .blocked:
            return .flash(.red)
        case .off:
            return .off
        }
    }
}

enum SignalColor {
    case green
    case yellow
    case red
}

enum SignalDisplayMode {
    case off
    case steady(SignalColor)
    case flash(SignalColor)
    case workPulse
}

struct SignalFrame {
    var green: CGFloat
    var yellow: CGFloat
    var red: CGFloat
}

struct SignalStatus: Decodable {
    let aggregate: String
    let updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case aggregate
        case updatedAt = "updated_at"
    }
}

final class SignalStateStore {
    private let fileURL: URL
    let stateDirectoryURL: URL
    private(set) var state: SignalState = .idle

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let root = environment["SIGNAL_LIGHT_STATE_DIR"] ?? "/private/tmp/signal-light"
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

func frame(for state: SignalState, tick: Int) -> SignalFrame {
    switch state.displayMode {
    case .off:
        return SignalFrame(green: 0, yellow: 0, red: 0)
    case .steady(let color):
        return frame(color: color, brightness: 1)
    case .flash(let color):
        return frame(color: color, brightness: tick.isMultiple(of: 2) ? 1 : 0)
    case .workPulse:
        return frame(color: .green, brightness: tick % 8 < 5 ? 1 : 0)
    }
}

private func frame(color: SignalColor, brightness: CGFloat) -> SignalFrame {
    switch color {
    case .green:
        return SignalFrame(green: brightness, yellow: 0, red: 0)
    case .yellow:
        return SignalFrame(green: 0, yellow: brightness, red: 0)
    case .red:
        return SignalFrame(green: 0, yellow: 0, red: brightness)
    }
}
