import Foundation
@testable import SignalLightShared
#if canImport(Testing)
import Testing
#elseif canImport(XCTest)
import XCTest
#endif

#if canImport(Testing)
struct SignalLightSharedTests {
    @Test
    func aggregateSessionsMatchesSharedContract() throws {
        try SignalLightSharedTestSupport.aggregateSessionsMatchesSharedContract()
    }

    @Test
    func defaultFrames() throws {
        try SignalLightSharedTestSupport.defaultFrames()
    }

    @Test
    func statusRulesOverrideDefaultFrame() throws {
        try SignalLightSharedTestSupport.statusRulesOverrideDefaultFrame()
    }

    @Test
    func configRepairCleansInvalidRulesAndUpgradesSchema() throws {
        try SignalLightSharedTestSupport.configRepairCleansInvalidRulesAndUpgradesSchema()
    }

    @Test
    func environmentOverridesAgentConfig() throws {
        try SignalLightSharedTestSupport.environmentOverridesAgentConfig()
    }
}
#elseif canImport(XCTest)
final class SignalLightSharedTests: XCTestCase {
    func testAggregateSessionsMatchesSharedContract() throws {
        try SignalLightSharedTestSupport.aggregateSessionsMatchesSharedContract()
    }

    func testDefaultFrames() throws {
        try SignalLightSharedTestSupport.defaultFrames()
    }

    func testStatusRulesOverrideDefaultFrame() throws {
        try SignalLightSharedTestSupport.statusRulesOverrideDefaultFrame()
    }

    func testConfigRepairCleansInvalidRulesAndUpgradesSchema() throws {
        try SignalLightSharedTestSupport.configRepairCleansInvalidRulesAndUpgradesSchema()
    }

    func testEnvironmentOverridesAgentConfig() throws {
        try SignalLightSharedTestSupport.environmentOverridesAgentConfig()
    }
}
#endif

private enum SignalLightSharedTestSupport {
    static func aggregateSessionsMatchesSharedContract() throws {
        for testCase in try loadAggregationContract() {
            var sessions = testCase.sessions
            if let now = testCase.now, let sessionTTL = testCase.sessionTTLSeconds {
                pruneExpiredSessions(&sessions, now: now, sessionTTL: sessionTTL)
            }
            try expectEqual(
                aggregateSessions(sessions),
                testCase.expectedAggregate,
                testCase.name
            )
        }
    }

    static func defaultFrames() throws {
        try expectEqual(frame(for: .idle, tick: 0), SignalFrame(green: 1, yellow: 0, red: 0))
        try expectEqual(frame(for: .working, tick: 0), SignalFrame(green: 1, yellow: 0, red: 0))
        try expectEqual(frame(for: .working, tick: 5), SignalFrame(green: 0, yellow: 0, red: 0))
        try expectEqual(frame(for: .attention, tick: 0), SignalFrame(green: 0, yellow: 1, red: 0))
        try expectEqual(frame(for: .attention, tick: 1), SignalFrame(green: 0, yellow: 0, red: 0))
        try expectEqual(frame(for: .permission, tick: 0), SignalFrame(green: 0, yellow: 0, red: 1))
        try expectEqual(frame(for: .blocked, tick: 0), SignalFrame(green: 0, yellow: 0, red: 1))
        try expectEqual(frame(for: .off, tick: 0), SignalFrame(green: 0, yellow: 0, red: 0))
    }

    static func statusRulesOverrideDefaultFrame() throws {
        let rules = StatusRulesConfig(rules: [
            "working": SignalRuleConfig(color: "yellow", mode: "steady"),
            "permission": SignalRuleConfig(color: "green", mode: "flash"),
            "attention": SignalRuleConfig(color: nil, mode: "off"),
        ])

        try expectEqual(frame(for: .working, tick: 0, rules: rules), SignalFrame(green: 0, yellow: 1, red: 0))
        try expectEqual(frame(for: .permission, tick: 0, rules: rules), SignalFrame(green: 1, yellow: 0, red: 0))
        try expectEqual(frame(for: .permission, tick: 1, rules: rules), SignalFrame(green: 0, yellow: 0, red: 0))
        try expectEqual(frame(for: .attention, tick: 0, rules: rules), SignalFrame(green: 0, yellow: 0, red: 0))
    }

    static func configRepairCleansInvalidRulesAndUpgradesSchema() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let configFile = tempDir.appendingPathComponent("config.json")
        try """
        {
          "schemaVersion": 0,
          "statusRules": {
            "rules": {
              "working": { "color": "blue", "mode": "flash" },
              "permission": { "color": "red", "mode": "dance" },
              "unknown": { "color": "green", "mode": "steady" }
            }
          }
        }
        """.data(using: .utf8)!.write(to: configFile)

        let store = SignalLightConfigStore(configDirectory: tempDir)
        let config = store.loadOrRepairConfig()

        try expectEqual(config.schemaVersion, configSchemaVersion)
        try expectEqual(config.statusRules.rules["working"], SignalRuleConfig(color: nil, mode: "flash"))
        try expectEqual(config.statusRules.rules["permission"], SignalRuleConfig(color: "red", mode: nil))
        try expect(config.statusRules.rules["unknown"] == nil, "unknown rule should be removed")
        try expect(store.lastRepairResult != nil, "repair result should be recorded")
    }

    static func environmentOverridesAgentConfig() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = SignalLightConfigStore(configDirectory: tempDir)
        let config = SignalLightConfig.default
        let agent = store.effectiveAgentConfig(
            from: config,
            environment: [
                "SIGNAL_LIGHT_STATE_DIR": "/tmp/custom-signal-light",
                "SIGNAL_LIGHT_SESSION_TTL_SECONDS": "42.5",
            ]
        )

        try expectEqual(agent.stateDirectory, "/tmp/custom-signal-light")
        try expectEqual(agent.sessionTTLSeconds, 42.5)
    }

    private static func loadAggregationContract() throws -> [AggregationContractCase] {
        let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixtureURL = packageRoot.appendingPathComponent("tests/fixtures/session_aggregation.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode([AggregationContractCase].self, from: data)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-light-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure(message)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") throws {
        guard actual == expected else {
            let suffix = message.isEmpty ? "" : " (\(message))"
            throw TestFailure("Expected \(expected), got \(actual)\(suffix)")
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct AggregationContractCase: Decodable {
    let name: String
    let sessions: [String: SessionRecord]
    let now: Double?
    let sessionTTLSeconds: Double?
    let expectedAggregate: String

    enum CodingKeys: String, CodingKey {
        case name
        case sessions
        case now
        case sessionTTLSeconds = "session_ttl_seconds"
        case expectedAggregate = "expected_aggregate"
    }
}

extension SignalFrame: Equatable {
    public static func == (lhs: SignalFrame, rhs: SignalFrame) -> Bool {
        lhs.green == rhs.green && lhs.yellow == rhs.yellow && lhs.red == rhs.red
    }
}
