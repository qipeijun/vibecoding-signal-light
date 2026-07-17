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

    @Test
    func historyRollsByAgeAndCountWithoutContent() throws {
        try SignalLightSharedTestSupport.historyRollsByAgeAndCountWithoutContent()
    }

    @Test
    func codexQuotaDecodesCodexBucket() throws {
        try SignalLightSharedTestSupport.codexQuotaDecodesCodexBucket()
    }

    @Test
    func codexQuotaDecodesBackwardCompatibleBucket() throws {
        try SignalLightSharedTestSupport.codexQuotaDecodesBackwardCompatibleBucket()
    }

    @Test
    func codexQuotaRequiresBothWindows() throws {
        try SignalLightSharedTestSupport.codexQuotaRequiresBothWindows()
    }

    @Test
    func codexQuotaRejectsInvalidPayload() throws {
        try SignalLightSharedTestSupport.codexQuotaRejectsInvalidPayload()
    }

    @Test
    func codexQuotaWindowDisplayHelpers() throws {
        try SignalLightSharedTestSupport.codexQuotaWindowDisplayHelpers()
    }

    @Test
    func hookDiagnosticsReportsMissingHooks() throws {
        try SignalLightSharedTestSupport.hookDiagnosticsReportsMissingHooks()
    }

    @Test
    func hookInstallerRepairsCodexHooks() throws {
        try SignalLightSharedTestSupport.hookInstallerRepairsCodexHooks()
    }

    @Test
    func codexOnlyMigrationRemovesOnlyLegacySignalLightHook() throws {
        try SignalLightSharedTestSupport.codexOnlyMigrationRemovesOnlyLegacySignalLightHook()
    }

    @Test
    func hookDiagnosticsAcceptsExistingSignalLightCommandsInCustomPaths() throws {
        try SignalLightSharedTestSupport.hookDiagnosticsAcceptsExistingSignalLightCommandsInCustomPaths()
    }

    @Test
    func pathMergePreservesUserPathOrderAndDeduplicatesDefaults() throws {
        try SignalLightSharedTestSupport.pathMergePreservesUserPathOrderAndDeduplicatesDefaults()
    }

    @Test
    func uninstallKeepsCustomDirectoryAndUnknownFiles() throws {
        try SignalLightSharedTestSupport.uninstallKeepsCustomDirectoryAndUnknownFiles()
    }

    @Test
    func legacyCommandCleanupRequiresSignalLightOwnership() throws {
        try SignalLightSharedTestSupport.legacyCommandCleanupRequiresSignalLightOwnership()
    }

    @Test
    func stateStoreUsesSessionsWhenCurrentStatusIsMissing() throws {
        try SignalLightSharedTestSupport.stateStoreUsesSessionsWhenCurrentStatusIsMissing()
    }

    @Test
    func connectionIssueDoesNotMaskRedRisk() throws {
        try SignalLightSharedTestSupport.connectionIssueDoesNotMaskRedRisk()
    }

    @Test
    func invalidCurrentStatusDoesNotPreservePreviousRedRisk() throws {
        try SignalLightSharedTestSupport.invalidCurrentStatusDoesNotPreservePreviousRedRisk()
    }

    @Test
    func preferredSourceMatchesAggregateRisk() throws {
        try SignalLightSharedTestSupport.preferredSourceMatchesAggregateRisk()
    }

    @Test
    func hookConnectionDistinguishesConfiguredAndActive() throws {
        try SignalLightSharedTestSupport.hookConnectionDistinguishesConfiguredAndActive()
    }

    @Test
    func reducedMotionUsesSteadySemanticColor() throws {
        try SignalLightSharedTestSupport.reducedMotionUsesSteadySemanticColor()
    }

    @Test
    func continuousAnimationAvoidsVisibleFrameJumps() throws {
        try SignalLightSharedTestSupport.continuousAnimationAvoidsVisibleFrameJumps()
    }

    @Test
    func semanticAnimationTimingsRemainDistinct() throws {
        try SignalLightSharedTestSupport.semanticAnimationTimingsRemainDistinct()
    }

    @Test
    func codexThreadCatalogReadsLatestValidName() throws {
        try SignalLightSharedTestSupport.codexThreadCatalogReadsLatestValidName()
    }

    @Test
    func codexThreadCatalogReturnsRecentThreads() throws {
        try SignalLightSharedTestSupport.codexThreadCatalogReturnsRecentThreads()
    }

    @Test
    func codexThreadCatalogReadsInterruptedLifecycle() throws {
        try SignalLightSharedTestSupport.codexThreadCatalogReadsInterruptedLifecycle()
    }

    @Test
    func activeSessionSignalUsesLifecycleAndLease() throws {
        try SignalLightSharedTestSupport.activeSessionSignalUsesLifecycleAndLease()
    }

    @Test
    func stateStoreDropsInterruptedSessionImmediately() throws {
        try SignalLightSharedTestSupport.stateStoreDropsInterruptedSessionImmediately()
    }

    @Test
    func historyCoalescesDuplicateTransitions() throws {
        try SignalLightSharedTestSupport.historyCoalescesDuplicateTransitions()
    }

    @Test
    func codexThreadURLAcceptsOnlyUUIDThreads() throws {
        try SignalLightSharedTestSupport.codexThreadURLAcceptsOnlyUUIDThreads()
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

    func testHistoryRollsByAgeAndCountWithoutContent() throws {
        try SignalLightSharedTestSupport.historyRollsByAgeAndCountWithoutContent()
    }

    func testCodexQuotaDecodesCodexBucket() throws {
        try SignalLightSharedTestSupport.codexQuotaDecodesCodexBucket()
    }

    func testCodexQuotaDecodesBackwardCompatibleBucket() throws {
        try SignalLightSharedTestSupport.codexQuotaDecodesBackwardCompatibleBucket()
    }

    func testCodexQuotaRequiresBothWindows() throws {
        try SignalLightSharedTestSupport.codexQuotaRequiresBothWindows()
    }

    func testCodexQuotaRejectsInvalidPayload() throws {
        try SignalLightSharedTestSupport.codexQuotaRejectsInvalidPayload()
    }

    func testCodexQuotaWindowDisplayHelpers() throws {
        try SignalLightSharedTestSupport.codexQuotaWindowDisplayHelpers()
    }

    func testHookDiagnosticsReportsMissingHooks() throws {
        try SignalLightSharedTestSupport.hookDiagnosticsReportsMissingHooks()
    }

    func testHookInstallerRepairsCodexHooks() throws {
        try SignalLightSharedTestSupport.hookInstallerRepairsCodexHooks()
    }

    func testCodexOnlyMigrationRemovesOnlyLegacySignalLightHook() throws {
        try SignalLightSharedTestSupport.codexOnlyMigrationRemovesOnlyLegacySignalLightHook()
    }

    func testHookDiagnosticsAcceptsExistingSignalLightCommandsInCustomPaths() throws {
        try SignalLightSharedTestSupport.hookDiagnosticsAcceptsExistingSignalLightCommandsInCustomPaths()
    }

    func testPathMergePreservesUserPathOrderAndDeduplicatesDefaults() throws {
        try SignalLightSharedTestSupport.pathMergePreservesUserPathOrderAndDeduplicatesDefaults()
    }

    func testUninstallKeepsCustomDirectoryAndUnknownFiles() throws {
        try SignalLightSharedTestSupport.uninstallKeepsCustomDirectoryAndUnknownFiles()
    }

    func testLegacyCommandCleanupRequiresSignalLightOwnership() throws {
        try SignalLightSharedTestSupport.legacyCommandCleanupRequiresSignalLightOwnership()
    }

    func testStateStoreUsesSessionsWhenCurrentStatusIsMissing() throws {
        try SignalLightSharedTestSupport.stateStoreUsesSessionsWhenCurrentStatusIsMissing()
    }

    func testConnectionIssueDoesNotMaskRedRisk() throws {
        try SignalLightSharedTestSupport.connectionIssueDoesNotMaskRedRisk()
    }

    func testInvalidCurrentStatusDoesNotPreservePreviousRedRisk() throws {
        try SignalLightSharedTestSupport.invalidCurrentStatusDoesNotPreservePreviousRedRisk()
    }

    func testPreferredSourceMatchesAggregateRisk() throws {
        try SignalLightSharedTestSupport.preferredSourceMatchesAggregateRisk()
    }

    func testHookConnectionDistinguishesConfiguredAndActive() throws {
        try SignalLightSharedTestSupport.hookConnectionDistinguishesConfiguredAndActive()
    }

    func testReducedMotionUsesSteadySemanticColor() throws {
        try SignalLightSharedTestSupport.reducedMotionUsesSteadySemanticColor()
    }

    func testContinuousAnimationAvoidsVisibleFrameJumps() throws {
        try SignalLightSharedTestSupport.continuousAnimationAvoidsVisibleFrameJumps()
    }

    func testSemanticAnimationTimingsRemainDistinct() throws {
        try SignalLightSharedTestSupport.semanticAnimationTimingsRemainDistinct()
    }

    func testCodexThreadCatalogReadsLatestValidName() throws {
        try SignalLightSharedTestSupport.codexThreadCatalogReadsLatestValidName()
    }

    func testCodexThreadCatalogReturnsRecentThreads() throws {
        try SignalLightSharedTestSupport.codexThreadCatalogReturnsRecentThreads()
    }

    func testCodexThreadCatalogReadsInterruptedLifecycle() throws {
        try SignalLightSharedTestSupport.codexThreadCatalogReadsInterruptedLifecycle()
    }

    func testActiveSessionSignalUsesLifecycleAndLease() throws {
        try SignalLightSharedTestSupport.activeSessionSignalUsesLifecycleAndLease()
    }

    func testStateStoreDropsInterruptedSessionImmediately() throws {
        try SignalLightSharedTestSupport.stateStoreDropsInterruptedSessionImmediately()
    }

    func testHistoryCoalescesDuplicateTransitions() throws {
        try SignalLightSharedTestSupport.historyCoalescesDuplicateTransitions()
    }

    func testCodexThreadURLAcceptsOnlyUUIDThreads() throws {
        try SignalLightSharedTestSupport.codexThreadURLAcceptsOnlyUUIDThreads()
    }
}
#endif

private enum SignalLightSharedTestSupport {
    private static let lifecycleThreadID = "019f68ca-5c16-7422-98db-82a64ada9d1a"
    private static let lifecycleTimestamp = 1_784_202_856.143

    static func codexThreadCatalogReadsLatestValidName() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let indexURL = tempDir.appendingPathComponent("session_index.jsonl")
        let text = [
            #"{"id":"019f6a74-fae6-7733-b441-b2d0fc5c28cd","thread_name":"旧名称"}"#,
            "not-json",
            #"{"id":"019f6a74-fae6-7733-b441-b2d0fc5c28cd","thread_name":"优化状态面板"}"#,
            #"{"id":"other","thread_name":"其他会话"}"#,
        ].joined(separator: "\n")
        try text.write(to: indexURL, atomically: true, encoding: .utf8)

        let catalog = CodexThreadCatalog(indexURL: indexURL)
        let threadID = "019f6a74-fae6-7733-b441-b2d0fc5c28cd"
        let summaries = catalog.summaries(for: [threadID])
        try expectEqual(summaries[threadID]?.name, "优化状态面板")
        try expectEqual(summaries["other"], nil)
    }

    static func codexThreadCatalogReturnsRecentThreads() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let indexURL = tempDir.appendingPathComponent("session_index.jsonl")
        let newestThreadID = "019f6d97-0002-7243-836b-abe13bf9886a"
        let excludedThreadID = "019f6ac5-5d79-7840-b3b5-a763e44ed308"
        let text = [
            #"{"id":"019f6a74-fae6-7733-b441-b2d0fc5c28cd","thread_name":"较早对话","updated_at":"2026-07-16T10:25:00.385502Z"}"#,
            #"{"id":"019f6a74-fae6-7733-b441-b2d0fc5c28cd","thread_name":"较早对话已重命名","updated_at":"2026-07-16T10:26:00Z"}"#,
            #"{"id":"019f6ac5-5d79-7840-b3b5-a763e44ed308","thread_name":"活跃对话","updated_at":"2026-07-16T11:53:23.448354Z"}"#,
            #"{"id":"019f6d97-0002-7243-836b-abe13bf9886a","thread_name":"最新对话","updated_at":"2026-07-17T01:00:43.808646Z"}"#,
            #"{"id":"legacy","thread_name":"缺少时间"}"#,
            #"{"id":"invalid-time","thread_name":"时间损坏","updated_at":"not-a-date"}"#,
        ].joined(separator: "\n")
        try text.write(to: indexURL, atomically: true, encoding: .utf8)

        let catalog = CodexThreadCatalog(indexURL: indexURL)
        let recent = catalog.recentSummaries(limit: 3, excluding: [excludedThreadID])

        try expectEqual(recent.map(\.id), [newestThreadID, "019f6a74-fae6-7733-b441-b2d0fc5c28cd"])
        try expectEqual(recent.last?.name, "较早对话已重命名")
        try expectEqual(catalog.recentSummaries(limit: 0).count, 0)
    }

    static func codexThreadCatalogReadsInterruptedLifecycle() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let indexURL = tempDir.appendingPathComponent("session_index.jsonl")
        try #"{"id":"019f68ca-5c16-7422-98db-82a64ada9d1a","thread_name":"评估 superpowers"}"#
            .write(to: indexURL, atomically: true, encoding: .utf8)
        let sessionsRoot = tempDir.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        let rolloutURL = sessionsRoot.appendingPathComponent(
            "rollout-2026-07-16T10-38-40-\(lifecycleThreadID).jsonl"
        )
        let rollout = [
            #"{"timestamp":"2026-07-16T11:54:06.340Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T11:54:16.143Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#,
        ].joined(separator: "\n")
        try rollout.write(to: rolloutURL, atomically: true, encoding: .utf8)

        let catalog = CodexThreadCatalog(indexURL: indexURL, sessionsRootURL: sessionsRoot)
        let summary = catalog.summaries(for: [lifecycleThreadID])[lifecycleThreadID]

        try expectEqual(summary?.activity?.state, .interrupted)
        try expectEqual(summary?.activity?.updatedAt, lifecycleTimestamp)
    }

    static func activeSessionSignalUsesLifecycleAndLease() throws {
        let policy = SignalLeasePolicy(workingSeconds: 30, attentionSeconds: 60, criticalSeconds: 90, doneSeconds: 6)
        let thinking = SessionRecord(signal: "thinking", updatedAt: 100)
        let toolDone = SessionRecord(signal: "tool_done", updatedAt: 100)

        try expectEqual(
            activeSessionSignal(
                for: thinking,
                activity: CodexThreadActivitySnapshot(state: .interrupted, updatedAt: 101),
                now: 102,
                policy: policy
            ),
            nil
        )
        try expectEqual(
            activeSessionSignal(
                for: toolDone,
                activity: CodexThreadActivitySnapshot(state: .running, updatedAt: 101),
                now: 102,
                policy: policy
            ),
            "working"
        )
        try expectEqual(
            activeSessionSignal(for: thinking, activity: nil, now: 131, policy: policy),
            nil,
            "租约过期的 stale 记录不能继续出现在活跃会话中"
        )
    }

    static func stateStoreDropsInterruptedSessionImmediately() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let indexURL = tempDir.appendingPathComponent("session_index.jsonl")
        try #"{"id":"019f68ca-5c16-7422-98db-82a64ada9d1a","thread_name":"评估 superpowers"}"#
            .write(to: indexURL, atomically: true, encoding: .utf8)
        let sessionsRoot = tempDir.appendingPathComponent("codex-sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        let rolloutURL = sessionsRoot.appendingPathComponent("rollout-\(lifecycleThreadID).jsonl")
        try [
            #"{"timestamp":"2026-07-16T11:54:06.340Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T11:54:16.143Z","type":"event_msg","payload":{"type":"turn_aborted"}}"#,
        ].joined(separator: "\n").write(to: rolloutURL, atomically: true, encoding: .utf8)
        try SignalLightStateFiles.writeSessionState(
            SessionState(sessions: [
                lifecycleThreadID: SessionRecord(signal: "thinking", updatedAt: lifecycleTimestamp - 10),
            ]),
            in: tempDir
        )
        try SignalLightStateFiles.writeCurrentStatus("working", in: tempDir, updatedAt: lifecycleTimestamp - 10)

        let catalog = CodexThreadCatalog(indexURL: indexURL, sessionsRootURL: sessionsRoot)
        let store = SignalStateStore(stateDirectory: tempDir.path, threadCatalog: catalog)
        _ = store.refresh(now: lifecycleTimestamp + 1)

        try expectEqual(store.state, .idle)
        try expectEqual(store.sessionState.sessions.count, 0)
    }

    static func historyCoalescesDuplicateTransitions() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let first = SignalHistoryEntry(
            recordedAt: 100,
            sessionKey: "session",
            signal: "working",
            aggregate: "working"
        )
        var duplicate = first
        duplicate.recordedAt = 100.1
        try SignalLightStateFiles.appendHistoryEntry(first, in: tempDir, now: 100)
        try SignalLightStateFiles.appendHistoryEntry(duplicate, in: tempDir, now: 100.1)
        try SignalLightStateFiles.appendHistoryEntry(
            SignalHistoryEntry(
                recordedAt: 101,
                sessionKey: "session",
                signal: "tool_done",
                aggregate: "working"
            ),
            in: tempDir,
            now: 101
        )

        let history = SignalLightStateFiles.readHistory(in: tempDir)
        try expectEqual(history.entries.count, 2)
        try expectEqual(history.entries.first?.recordedAt, 100.1)
        try expectEqual(history.entries.last?.signal, "tool_done")
    }

    static func codexThreadURLAcceptsOnlyUUIDThreads() throws {
        let threadID = "019F6A74-FAE6-7733-B441-B2D0FC5C28CD"
        try expectEqual(
            codexThreadURL(threadID: threadID)?.absoluteString,
            "codex://threads/019f6a74-fae6-7733-b441-b2d0fc5c28cd"
        )
        try expectEqual(codexThreadURL(threadID: "cwd:/tmp/project"), nil)
        try expectEqual(codexThreadURL(threadID: "global"), nil)
    }

    static func aggregateSessionsMatchesSharedContract() throws {
        for testCase in try loadAggregationContract() {
            var sessions = testCase.sessions
            if let now = testCase.now, let sessionTTL = testCase.sessionTTLSeconds {
                pruneExpiredSessions(&sessions, now: now, sessionTTL: sessionTTL)
            }
            try expectEqual(
                aggregateSessions(sessions, now: testCase.now ?? Date().timeIntervalSince1970),
                testCase.expectedAggregate,
                testCase.name
            )
        }
    }

    static func defaultFrames() throws {
        try expectEqual(frame(for: .idle, tick: 0), SignalFrame(green: 1, yellow: 0, red: 0))
        try expectEqual(frame(for: .working, tick: 0), SignalFrame(green: 1, yellow: 0, red: 0))
        try expectEqual(frame(for: .working, tick: 5), SignalFrame(green: 0.25, yellow: 0, red: 0))
        try expectEqual(frame(for: .attention, tick: 0), SignalFrame(green: 0, yellow: 1, red: 0))
        try expectEqual(frame(for: .attention, tick: 1), SignalFrame(green: 0, yellow: 0, red: 0))
        try expectEqual(frame(for: .permission, tick: 0), SignalFrame(green: 0, yellow: 0, red: 1))
        try expectEqual(frame(for: .blocked, tick: 0), SignalFrame(green: 0, yellow: 0, red: 1))
        try expectEqual(frame(for: .blocked, tick: 1), SignalFrame(green: 0, yellow: 0, red: 0))
        try expectEqual(frame(for: .blocked, tick: 2), SignalFrame(green: 0, yellow: 0, red: 1))
        try expectEqual(frame(for: .done, tick: 0), SignalFrame(green: 1, yellow: 0, red: 0))
        try expectEqual(frame(for: .stale, tick: 0), SignalFrame(green: 0, yellow: 1, red: 0))
        try expectEqual(frame(for: .off, tick: 0), SignalFrame(green: 0, yellow: 0, red: 0))
    }

    static func continuousAnimationAvoidsVisibleFrameJumps() throws {
        let slowPulseSamples = (0...54).map { index in
            frame(
                for: .stale,
                elapsedTime: Double(index) / 30,
                rules: .default
            ).yellow
        }
        let slowPulseLargestJump = zip(slowPulseSamples, slowPulseSamples.dropFirst())
            .map { abs($0 - $1) }
            .max() ?? 0
        let workPulseSamples = (0...36).map { index in
            frame(
                for: .working,
                elapsedTime: Double(index) / 30,
                rules: .default
            ).green
        }
        let workPulseLargestJump = zip(workPulseSamples, workPulseSamples.dropFirst())
            .map { abs($0 - $1) }
            .max() ?? 0

        try expect(slowPulseLargestJump <= 0.12, "慢呼吸相邻帧亮度跳变过大: \(slowPulseLargestJump)")
        try expect(workPulseLargestJump <= 0.12, "工作脉冲相邻帧亮度跳变过大: \(workPulseLargestJump)")
        try expect(
            (slowPulseSamples.max() ?? 0) - (slowPulseSamples.min() ?? 0) >= 0.74,
            "慢呼吸亮度范围不足"
        )
        try expect(
            (workPulseSamples.max() ?? 0) - (workPulseSamples.min() ?? 0) >= 0.74,
            "工作脉冲亮度范围不足"
        )
    }

    static func semanticAnimationTimingsRemainDistinct() throws {
        try expect(SignalState.working.allowsAnimationSpeedAdjustment, "工作状态应允许调整环境动画速度")
        try expect(SignalState.stale.allowsAnimationSpeedAdjustment, "失联状态应允许调整环境动画速度")
        try expect(!SignalState.attention.allowsAnimationSpeedAdjustment, "等待关注应保持固定提示节奏")
        try expect(!SignalState.permission.allowsAnimationSpeedAdjustment, "等待授权应保持固定提示节奏")
        try expect(!SignalState.blocked.allowsAnimationSpeedAdjustment, "阻塞状态应保持固定提示节奏")
        try expect(!SignalState.done.allowsAnimationSpeedAdjustment, "完成状态应保持固定提示节奏")

        let workingMinimum = frame(for: .working, elapsedTime: 1.0, rules: .default).green
        let workingFullCycle = frame(for: .working, elapsedTime: 2.0, rules: .default).green
        let permissionMinimum = frame(for: .permission, elapsedTime: 1.0, rules: .default).red
        let staleMinimum = frame(for: .stale, elapsedTime: 1.4, rules: .default).yellow

        try expectEqual(workingMinimum, 0.25)
        try expectEqual(workingFullCycle, 1)
        try expectEqual(permissionMinimum, 0.25)
        try expectEqual(staleMinimum, 0.25)

        try expectEqual(frame(for: .attention, elapsedTime: 0.15, rules: .default).yellow, 1)
        try expectEqual(frame(for: .attention, elapsedTime: 0.50, rules: .default).yellow, 0)

        try expectEqual(frame(for: .blocked, elapsedTime: 0.24, rules: .default).red, 0)
        try expectEqual(frame(for: .blocked, elapsedTime: 0.42, rules: .default).red, 1)
        try expectEqual(frame(for: .blocked, elapsedTime: 0.80, rules: .default).red, 0)
        try expectEqual(frame(for: .blocked, elapsedTime: 2.0, rules: .default).red, 1)

        try expectEqual(frame(for: .done, elapsedTime: 0.24, rules: .default).green, 0)
        try expectEqual(frame(for: .done, elapsedTime: 0.42, rules: .default).green, 1)
        try expectEqual(frame(for: .done, elapsedTime: 0.80, rules: .default).green, 0)
        try expectEqual(frame(for: .done, elapsedTime: 2.0, rules: .default).green, 1)
        try expectEqual(frame(for: .done, elapsedTime: 3.0, rules: .default).green, 1)
    }

    static func statusRulesOverrideDefaultFrame() throws {
        let rules = StatusRulesConfig(rules: [
            "working": SignalRuleConfig(color: "yellow", mode: "steady"),
            "permission": SignalRuleConfig(color: "green", mode: "flash"),
            "attention": SignalRuleConfig(color: nil, mode: "off"),
        ])

        try expectEqual(frame(for: .working, tick: 0, rules: rules), SignalFrame(green: 1, yellow: 0, red: 0))
        try expectEqual(frame(for: .permission, tick: 0, rules: rules), SignalFrame(green: 0, yellow: 0, red: 1))
        try expectEqual(frame(for: .permission, tick: 1, rules: rules), SignalFrame(green: 0, yellow: 0, red: 0))
        try expectEqual(frame(for: .attention, tick: 0, rules: rules), SignalFrame(green: 0, yellow: 1, red: 0))
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
              "attention": { "mode": "off" },
              "unknown": { "color": "green", "mode": "steady" }
            }
          }
        }
        """.data(using: .utf8)!.write(to: configFile)

        let store = SignalLightConfigStore(configDirectory: tempDir)
        let config = store.loadOrRepairConfig()

        try expectEqual(config.schemaVersion, configSchemaVersion)
        try expectEqual(config.statusRules.rules["working"], SignalRuleConfig(color: nil, mode: "flash"))
        try expectEqual(config.statusRules.rules["permission"], nil)
        try expectEqual(config.statusRules.rules["attention"], nil)
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
                "SIGNAL_LIGHT_WORKING_LEASE_SECONDS": "120",
                "SIGNAL_LIGHT_ATTENTION_LEASE_SECONDS": "240",
                "SIGNAL_LIGHT_CRITICAL_LEASE_SECONDS": "360",
                "SIGNAL_LIGHT_DONE_DISPLAY_SECONDS": "8",
            ]
        )

        try expectEqual(agent.stateDirectory, "/tmp/custom-signal-light")
        try expectEqual(agent.sessionTTLSeconds, 42.5)
        try expectEqual(agent.workingLeaseSeconds, 120)
        try expectEqual(agent.attentionLeaseSeconds, 240)
        try expectEqual(agent.criticalLeaseSeconds, 360)
        try expectEqual(agent.doneDisplaySeconds, 8)

        let invalid = store.effectiveAgentConfig(
            from: config,
            environment: [
                "SIGNAL_LIGHT_SESSION_TTL_SECONDS": "invalid",
                "SIGNAL_LIGHT_WORKING_LEASE_SECONDS": "-1",
                "SIGNAL_LIGHT_DONE_DISPLAY_SECONDS": "999",
            ]
        )
        try expectEqual(invalid.sessionTTLSeconds, AgentConfig.default.sessionTTLSeconds)
        try expectEqual(invalid.workingLeaseSeconds, AgentConfig.default.workingLeaseSeconds)
        try expectEqual(invalid.doneDisplaySeconds, AgentConfig.default.doneDisplaySeconds)
    }

    static func historyRollsByAgeAndCountWithoutContent() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let source = SessionSource(
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 42,
            localizedName: "Codex",
            capturedAt: 100
        )

        try SignalLightStateFiles.appendHistoryEntry(
            SignalHistoryEntry(
                recordedAt: 0,
                sessionKey: "old",
                signal: "working",
                aggregate: "working",
                source: source,
                model: "gpt-test"
            ),
            in: tempDir,
            now: historyRetentionSeconds + 1
        )
        for index in 0...historyEntryLimit {
            let now = historyRetentionSeconds + 2 + Double(index)
            try SignalLightStateFiles.appendHistoryEntry(
                SignalHistoryEntry(
                    recordedAt: now,
                    sessionKey: "session-\(index)",
                    signal: "working",
                    aggregate: "working",
                    source: source,
                    model: "gpt-test"
                ),
                in: tempDir,
                now: now
            )
        }

        let history = SignalLightStateFiles.readHistory(in: tempDir)
        try expectEqual(history.entries.count, historyEntryLimit)
        try expect(history.entries.allSatisfy { $0.sessionKey != "old" }, "expired history should be removed")
        let data = try Data(contentsOf: tempDir.appendingPathComponent("history.json"))
        let text = String(decoding: data, as: UTF8.self)
        try expect(!text.contains("prompt"), "history must not contain prompt content")
        try expectEqual(history.entries.last?.source, source)
        try expectEqual(history.entries.last?.model, "gpt-test")
    }

    static func codexQuotaDecodesCodexBucket() throws {
        let data = """
        {
          "rateLimits": {
            "limitId": "legacy",
            "limitName": "Legacy",
            "primary": { "usedPercent": 99, "windowDurationMins": 60, "resetsAt": 1780000000 },
            "secondary": { "usedPercent": 98, "windowDurationMins": 120, "resetsAt": 1780000300 }
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": "Codex",
              "planType": "plus",
              "rateLimitReachedType": "rate_limit_reached",
              "credits": { "balance": "12.50", "hasCredits": true, "unlimited": false },
              "primary": { "usedPercent": 42, "windowDurationMins": 300, "resetsAt": 1780000600 },
              "secondary": { "usedPercent": 17, "windowDurationMins": 10080, "resetsAt": 1780000900 }
            }
          }
        }
        """.data(using: .utf8)!

        let snapshot = try CodexRateLimitPayload.decodeSnapshot(from: data)

        try expectEqual(snapshot.limitId, "codex")
        try expectEqual(snapshot.limitName, "Codex")
        try expectEqual(snapshot.planType, "plus")
        try expectEqual(snapshot.rateLimitReachedType, "rate_limit_reached")
        try expectEqual(snapshot.credits?.balance, "12.50")
        try expectEqual(snapshot.primary.usedPercent, 42)
        try expectEqual(snapshot.primary.windowDurationMins, 300)
        try expectEqual(snapshot.primary.resetsAt, 1780000600)
        try expectEqual(snapshot.secondary.usedPercent, 17)
        try expectEqual(snapshot.secondary.windowDurationMins, 10080)
    }

    static func codexQuotaDecodesBackwardCompatibleBucket() throws {
        let data = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": "Codex",
            "planType": "pro",
            "primary": { "usedPercent": 5, "windowDurationMins": 300, "resetsAt": null },
            "secondary": { "usedPercent": 9, "windowDurationMins": 10080, "resetsAt": null }
          },
          "rateLimitsByLimitId": null
        }
        """.data(using: .utf8)!

        let snapshot = try CodexRateLimitPayload.decodeSnapshot(from: data)

        try expectEqual(snapshot.limitId, "codex")
        try expectEqual(snapshot.planType, "pro")
        try expectEqual(snapshot.primary.usedPercent, 5)
        try expectEqual(snapshot.secondary.usedPercent, 9)
    }

    static func codexQuotaRequiresBothWindows() throws {
        let data = """
        {
          "rateLimits": {
            "limitId": "codex",
            "primary": { "usedPercent": 5, "windowDurationMins": 300, "resetsAt": null }
          }
        }
        """.data(using: .utf8)!

        do {
            _ = try CodexRateLimitPayload.decodeSnapshot(from: data)
        } catch let error as CodexRateLimitDecodingError {
            try expectEqual(error, .missingWindows)
            return
        }
        throw TestFailure("Expected missing window decoding error")
    }

    static func codexQuotaRejectsInvalidPayload() throws {
        let data = """
        { "rateLimits": "not-a-rate-limit-object" }
        """.data(using: .utf8)!

        do {
            _ = try CodexRateLimitPayload.decodeSnapshot(from: data)
        } catch let error as CodexRateLimitDecodingError {
            try expectEqual(error, .invalidPayload)
            return
        }
        throw TestFailure("Expected invalid payload decoding error")
    }

    static func codexQuotaWindowDisplayHelpers() throws {
        let fiveHour = CodexRateLimitWindow(usedPercent: 73, windowDurationMins: 300, resetsAt: nil)
        let actualWindow = CodexRateLimitWindow(usedPercent: 120, windowDurationMins: 90, resetsAt: nil)

        try expectEqual(fiveHour.remainingPercent, 27)
        try expectEqual(fiveHour.displayTitle(defaultTitle: "5 小时"), "5 小时")
        try expectEqual(actualWindow.remainingPercent, 0)
        try expectEqual(actualWindow.displayTitle(defaultTitle: "5 小时"), "90 分钟窗口")
        try expectEqual(CodexRateLimitWindow.formatDuration(minutes: 10080), "7 天")
    }

    static func hookDiagnosticsReportsMissingHooks() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let reports = checkSignalLightHooks(homeDirectory: tempDir)

        try expectEqual(reports.count, 1)
        try expect(reports.allSatisfy { !$0.ok }, "fresh home should report missing hooks")
        try expect(
            reports.contains { $0.title == "Codex hooks" && $0.message == "未找到配置文件" },
            "Codex hooks should be reported as missing"
        )
    }

    static func hookInstallerRepairsCodexHooks() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let installReports = try installSignalLightHooks(homeDirectory: tempDir)
        let checkReports = checkSignalLightHooks(homeDirectory: tempDir)

        try expectEqual(installReports.count, 1)
        try expect(installReports.allSatisfy(\.ok), "install reports should pass")
        try expect(checkReports.allSatisfy(\.ok), "installed hooks should check cleanly")

        let data = try Data(contentsOf: tempDir.appendingPathComponent(".codex/hooks.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = object?["hooks"] as? [String: Any]
        let sessionEndGroups = hooks?["SessionEnd"] as? [[String: Any]]
        let sessionEndHandlers = sessionEndGroups?.first?["hooks"] as? [[String: Any]]
        try expect(
            sessionEndHandlers?.contains { ($0["command"] as? String) == "/usr/local/bin/codex-signal-hook" } == true,
            "Codex SessionEnd hook should be installed"
        )
    }

    static func codexOnlyMigrationRemovesOnlyLegacySignalLightHook() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let settingsURL = tempDir.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" },
          "hooks": {
            "PreToolUse": [{
              "hooks": [
                { "type": "command", "command": "/usr/local/bin/claude-code-signal-hook" },
                { "type": "command", "command": "/usr/local/bin/my-own-hook" }
              ]
            }],
            "Stop": [{
              "hooks": [
                { "type": "command", "command": "/opt/signal-light/claude-code-signal-hook" }
              ]
            }]
          }
        }
        """.data(using: .utf8)!.write(to: settingsURL)

        let changed = try removeLegacyClaudeHookConfiguration(homeDirectory: tempDir)
        try expect(changed, "legacy Signal Light hook should be removed")

        let data = try Data(contentsOf: settingsURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let statusLine = object?["statusLine"] as? [String: Any]
        let hooks = object?["hooks"] as? [String: Any]
        let preToolGroups = hooks?["PreToolUse"] as? [[String: Any]]
        let handlers = preToolGroups?.first?["hooks"] as? [[String: Any]]

        try expectEqual(statusLine?["command"] as? String, "~/.claude/statusline.sh")
        try expectEqual(handlers?.count, 1)
        try expectEqual(handlers?.first?["command"] as? String, "/usr/local/bin/my-own-hook")
        try expect(hooks?["Stop"] == nil, "empty legacy event should be removed")
        let changedAgain = try removeLegacyClaudeHookConfiguration(homeDirectory: tempDir)
        try expect(!changedAgain, "second migration should be a no-op")
    }

    static func hookDiagnosticsAcceptsExistingSignalLightCommandsInCustomPaths() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let codexDir = tempDir.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        try hookFixtureJSON(command: "/opt/homebrew/bin/codex-signal-hook", events: [
            "SessionStart",
            "UserPromptSubmit",
            "PreToolUse",
            "PermissionRequest",
            "PostToolUse",
            "Stop",
            "SessionEnd",
        ]).data(using: .utf8)!.write(to: codexDir.appendingPathComponent("hooks.json"))

        let reports = checkSignalLightHooks(homeDirectory: tempDir)

        try expect(reports.allSatisfy(\.ok), "custom Signal Light command paths should be accepted")
    }

    static func pathMergePreservesUserPathOrderAndDeduplicatesDefaults() throws {
        let merged = SignalLightPaths.mergePath("/custom/bin:/usr/local/bin:/bin")
        let entries = SignalLightPaths.pathEntries(from: merged)

        try expect(entries.count >= 3, "merged PATH should include user entries")
        try expectEqual(Array(entries[0..<3]), ["/custom/bin", "/usr/local/bin", "/bin"])
        try expectEqual(entries.filter { $0 == "/usr/local/bin" }.count, 1)
        try expectEqual(entries.filter { $0 == "/bin" }.count, 1)
        try expect(entries.contains("/opt/homebrew/bin"), "default executable directories should be appended")
    }

    static func uninstallKeepsCustomDirectoryAndUnknownFiles() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for name in SignalLightInstallLifecycle.stateFileNames {
            try Data(name.utf8).write(to: tempDir.appendingPathComponent(name))
        }
        let userFile = tempDir.appendingPathComponent("project-notes.txt")
        try Data("keep".utf8).write(to: userFile)

        let removed = try SignalLightInstallLifecycle.removeOwnedStateFiles(in: tempDir)

        try expectEqual(removed.count, SignalLightInstallLifecycle.stateFileNames.count)
        try expect(FileManager.default.fileExists(atPath: tempDir.path), "custom state directory must be preserved")
        try expect(FileManager.default.fileExists(atPath: userFile.path), "unknown user files must be preserved")
    }

    static func legacyCommandCleanupRequiresSignalLightOwnership() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let owned = tempDir.appendingPathComponent("claude-code-signal-hook")
        try Data("#!/bin/sh\nexec \"/Applications/Signal Light.app/Contents/Resources/bin/claude-code-signal-hook\" \"$@\"\n".utf8)
            .write(to: owned)
        let userOwned = tempDir.appendingPathComponent("user-claude-code-signal-hook")
        try Data("#!/bin/sh\necho user-owned\n".utf8).write(to: userOwned)

        let removedOwned = try SignalLightInstallLifecycle.removeOwnedLegacyClaudeCommand(at: owned)
        try expect(removedOwned, "owned wrapper should be removed")
        try expect(!FileManager.default.fileExists(atPath: owned.path), "owned wrapper should no longer exist")
        let removedUserOwned = try SignalLightInstallLifecycle.removeOwnedLegacyClaudeCommand(at: userOwned)
        try expect(!removedUserOwned, "unowned command must not be removed")
        try expect(FileManager.default.fileExists(atPath: userOwned.path), "user command must be preserved")
    }

    static func stateStoreUsesSessionsWhenCurrentStatusIsMissing() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try SignalLightStateFiles.writeSessionState(
            SessionState(sessions: ["blocked": SessionRecord(signal: "blocked", updatedAt: 100)]),
            in: tempDir
        )

        let store = SignalStateStore(stateDirectory: tempDir.path)
        _ = store.refresh(now: 101)

        try expectEqual(store.state, .blocked)
        try expectEqual(store.effectiveState, .blocked)
        try expectEqual(store.updatedAt, 100)
    }

    static func connectionIssueDoesNotMaskRedRisk() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try SignalLightStateFiles.writeSessionState(
            SessionState(sessions: ["permission": SessionRecord(signal: "permission", updatedAt: 100)]),
            in: tempDir
        )
        let store = SignalStateStore(stateDirectory: tempDir.path)
        _ = store.refresh(now: 101)
        _ = store.updateHookIssue("Hook 未连接")
        try expectEqual(store.effectiveState, .permission)

        try SignalLightStateFiles.writeSessionState(
            SessionState(sessions: ["working": SessionRecord(signal: "working", updatedAt: 102)]),
            in: tempDir
        )
        _ = store.refresh(now: 103)
        try expectEqual(store.state, .working)
        try expectEqual(store.effectiveState, .stale)
    }

    static func invalidCurrentStatusDoesNotPreservePreviousRedRisk() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try SignalLightStateFiles.writeCurrentStatus("blocked", in: tempDir, updatedAt: 100)

        let store = SignalStateStore(stateDirectory: tempDir.path)
        _ = store.refresh(now: 101)
        try expectEqual(store.effectiveState, .blocked)

        try Data("not-json".utf8).write(to: tempDir.appendingPathComponent("current_status.json"))
        _ = store.refresh(now: 102)

        try expectEqual(store.state, .stale)
        try expectEqual(store.effectiveState, .stale)
        try expectEqual(store.updatedAt, nil)
        try expectEqual(store.stateFileIssue, "当前状态文件无法读取")
    }

    static func preferredSourceMatchesAggregateRisk() throws {
        let blockedSource = SessionSource(
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 10,
            localizedName: "Blocked Codex",
            capturedAt: 90
        )
        let workingSource = SessionSource(
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 20,
            localizedName: "Working Codex",
            capturedAt: 100
        )
        let sessions = [
            "blocked": SessionRecord(signal: "blocked", updatedAt: 90, source: blockedSource),
            "working": SessionRecord(signal: "working", updatedAt: 100, source: workingSource),
        ]

        let source = preferredSessionSource(
            in: sessions,
            aggregate: .blocked,
            sessionTTL: 86_400,
            now: 101
        )
        try expectEqual(source, blockedSource)
    }

    static func hookConnectionDistinguishesConfiguredAndActive() throws {
        let tempHome = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let stateDirectory = tempHome.appendingPathComponent("state", isDirectory: true)

        let missing = inspectCodexHookConnection(homeDirectory: tempHome, stateDirectory: stateDirectory)
        guard case .missingConfiguration = missing else {
            throw TestFailure("missing hook config should be reported")
        }

        _ = try installSignalLightHooks(homeDirectory: tempHome)
        try expectEqual(
            inspectCodexHookConnection(homeDirectory: tempHome, stateDirectory: stateDirectory),
            .awaitingFirstEvent
        )

        try SignalLightStateFiles.writeCodexHookActivity(in: stateDirectory, lastEventAt: 123)
        try expectEqual(
            inspectCodexHookConnection(homeDirectory: tempHome, stateDirectory: stateDirectory),
            .active(lastEventAt: 123)
        )
    }

    static func reducedMotionUsesSteadySemanticColor() throws {
        try expectEqual(
            frame(for: .permission, tick: 0, rules: .default, reduceMotion: true),
            SignalFrame(green: 0, yellow: 0, red: 1)
        )
        try expectEqual(
            frame(for: .stale, tick: 0, rules: .default, reduceMotion: true),
            SignalFrame(green: 0, yellow: 1, red: 0)
        )
        try expectEqual(
            frame(for: .working, tick: 7, rules: .default, reduceMotion: true),
            SignalFrame(green: 1, yellow: 0, red: 0)
        )
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

    private static func hookFixtureJSON(command: String, events: [String]) -> String {
        let body = events.map { event in
            """
              "\(event)": [
                {
                  "hooks": [
                    {
                      "type": "command",
                      "command": "\(command)",
                      "timeout": 5
                    }
                  ]
                }
              ]
            """
        }.joined(separator: ",\n")

        return """
        {
          "hooks": {
        \(body)
          }
        }
        """
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
