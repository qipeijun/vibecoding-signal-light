import Foundation
@testable import SignalLightShared
import Testing

struct SignalLightSharedTests {
    @Test
    func testAggregateSessionsMatchesSharedContract() throws {
        for testCase in try loadAggregationContract() {
            var sessions = testCase.sessions
            if let now = testCase.now, let sessionTTL = testCase.sessionTTLSeconds {
                pruneExpiredSessions(&sessions, now: now, sessionTTL: sessionTTL)
            }
            #expect(
                aggregateSessions(sessions) == testCase.expectedAggregate,
                Comment(rawValue: testCase.name)
            )
        }
    }

    @Test
    func testDefaultFrames() {
        #expect(frame(for: .idle, tick: 0) == SignalFrame(green: 1, yellow: 0, red: 0))
        #expect(frame(for: .working, tick: 0) == SignalFrame(green: 1, yellow: 0, red: 0))
        #expect(frame(for: .working, tick: 5) == SignalFrame(green: 0, yellow: 0, red: 0))
        #expect(frame(for: .attention, tick: 0) == SignalFrame(green: 0, yellow: 1, red: 0))
        #expect(frame(for: .attention, tick: 1) == SignalFrame(green: 0, yellow: 0, red: 0))
        #expect(frame(for: .permission, tick: 0) == SignalFrame(green: 0, yellow: 0, red: 1))
        #expect(frame(for: .blocked, tick: 0) == SignalFrame(green: 0, yellow: 0, red: 1))
        #expect(frame(for: .off, tick: 0) == SignalFrame(green: 0, yellow: 0, red: 0))
    }

    @Test
    func testStatusRulesOverrideDefaultFrame() {
        let rules = StatusRulesConfig(rules: [
            "working": SignalRuleConfig(color: "yellow", mode: "steady"),
            "permission": SignalRuleConfig(color: "green", mode: "flash"),
            "attention": SignalRuleConfig(color: nil, mode: "off"),
        ])

        #expect(frame(for: .working, tick: 0, rules: rules) == SignalFrame(green: 0, yellow: 1, red: 0))
        #expect(frame(for: .permission, tick: 0, rules: rules) == SignalFrame(green: 1, yellow: 0, red: 0))
        #expect(frame(for: .permission, tick: 1, rules: rules) == SignalFrame(green: 0, yellow: 0, red: 0))
        #expect(frame(for: .attention, tick: 0, rules: rules) == SignalFrame(green: 0, yellow: 0, red: 0))
    }

    @Test
    func testConfigRepairCleansInvalidRulesAndUpgradesSchema() throws {
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

        #expect(config.schemaVersion == configSchemaVersion)
        #expect(config.statusRules.rules["working"] == SignalRuleConfig(color: nil, mode: "flash"))
        #expect(config.statusRules.rules["permission"] == SignalRuleConfig(color: "red", mode: nil))
        #expect(config.statusRules.rules["unknown"] == nil)
        #expect(store.lastRepairResult != nil)
    }

    @Test
    func testEnvironmentOverridesAgentConfig() throws {
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

        #expect(agent.stateDirectory == "/tmp/custom-signal-light")
        #expect(agent.sessionTTLSeconds == 42.5)
    }

    private func loadAggregationContract() throws -> [AggregationContractCase] {
        let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixtureURL = packageRoot.appendingPathComponent("tests/fixtures/session_aggregation.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode([AggregationContractCase].self, from: data)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-light-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
