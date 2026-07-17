import Foundation

/// macOS UI 的状态真值读取器。
///
/// 会话文件是风险聚合的主要来源，当前状态文件用于没有会话时的单状态回退。
/// 连接异常只会把低风险状态降为 stale，不得覆盖 permission 或 blocked。
public final class SignalStateStore {
    private let fileURL: URL
    private let sessionFileURL: URL
    public let stateDirectoryURL: URL
    private var leasePolicy: SignalLeasePolicy
    private var sessionTTL: Double
    private let threadCatalog: CodexThreadCatalog?

    public private(set) var state: SignalState = .idle
    public private(set) var updatedAt: Double?
    public private(set) var sessionState = SessionState(sessions: [:])
    public private(set) var threadActivities: [String: CodexThreadActivitySnapshot] = [:]
    public private(set) var history = SignalHistory(entries: [])
    public private(set) var stateFileIssue: String?
    public private(set) var hookIssue: String?

    /// UI 的最终状态。红色风险优先于连接异常；其他状态在连接异常时显示 stale。
    public var effectiveState: SignalState {
        guard connectionIssue != nil else {
            return state
        }
        return redSignals.contains(state.rawValue) ? state : .stale
    }

    public var connectionIssue: String? {
        stateFileIssue ?? hookIssue
    }

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stateDirectory: String? = nil,
        leasePolicy: SignalLeasePolicy = .default,
        sessionTTL: Double = AgentConfig.default.sessionTTLSeconds,
        threadCatalog: CodexThreadCatalog? = nil
    ) {
        let root = stateDirectory ?? environment["SIGNAL_LIGHT_STATE_DIR"] ?? "/private/tmp/signal-light"
        stateDirectoryURL = URL(fileURLWithPath: root)
        fileURL = stateDirectoryURL.appendingPathComponent("current_status.json")
        sessionFileURL = stateDirectoryURL.appendingPathComponent("sessions.json")
        self.leasePolicy = leasePolicy
        self.sessionTTL = sessionTTL
        self.threadCatalog = threadCatalog
    }

    @discardableResult
    public func refresh(now: Double = Date().timeIntervalSince1970) -> Bool {
        let previousState = effectiveState
        stateFileIssue = refreshSessions()
        history = SignalLightStateFiles.readHistory(in: stateDirectoryURL)

        var retainedSessions = sessionState.sessions
        pruneExpiredSessions(
            &retainedSessions,
            now: now,
            sessionTTL: sessionTTL,
            leasePolicy: leasePolicy
        )
        let sessionsBeforeLifecycleReconciliation = retainedSessions
        let activityThreadIDs = Set(retainedSessions.compactMap { key, record in
            // done/session_end 已由 Hook 明确收口，不再读取 rollout，避免启动时扫描历史会话。
            ["done", "session_end", "off"].contains(record.signal) ? nil : key
        })
        threadActivities = threadCatalog?.activities(for: activityThreadIDs) ?? [:]
        retainedSessions = reconcileSessionsWithThreadActivities(
            retainedSessions,
            activities: threadActivities,
            now: now,
            policy: leasePolicy
        )
        let lifecycleEndedAllSessions = !sessionsBeforeLifecycleReconciliation.isEmpty && retainedSessions.isEmpty
        sessionState = SessionState(sessions: retainedSessions)

        let sessionAggregate = retainedSessions.isEmpty
            ? nil
            : aggregateSessions(retainedSessions, now: now, leasePolicy: leasePolicy)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // sessions.json 已包含完整风险状态时，不依赖 current_status.json 才能正确亮灯。
            if let sessionAggregate {
                state = SignalState(rawValue: sessionAggregate) ?? .stale
                updatedAt = retainedSessions.values.map(\.updatedAt).max()
            } else {
                state = .idle
                updatedAt = nil
            }
            return previousState != effectiveState
        }

        // current_status.json 是会话聚合快照；真实 rollout 已终止全部会话时不能继续用旧快照亮灯。
        if lifecycleEndedAllSessions {
            state = .idle
            updatedAt = threadActivities.values.map(\.updatedAt).max()
            return previousState != effectiveState
        }

        guard let data = try? Data(contentsOf: fileURL),
              let status = try? JSONDecoder().decode(SignalStatus.self, from: data),
              let persistedState = SignalState(rawValue: status.aggregate)
        else {
            stateFileIssue = "当前状态文件无法读取"
            if let sessionAggregate {
                state = SignalState(rawValue: sessionAggregate) ?? .stale
                updatedAt = retainedSessions.values.map(\.updatedAt).max()
            } else {
                // 文件损坏后不能沿用上一次内存状态，尤其不能让已经失去会话证据的红灯永久残留。
                state = .stale
                updatedAt = nil
            }
            return previousState != effectiveState
        }

        let aggregate = sessionAggregate
            ?? effectiveSignal(persistedState.rawValue, updatedAt: status.updatedAt, now: now, policy: leasePolicy)
        state = SignalState(rawValue: aggregate) ?? .stale
        updatedAt = retainedSessions.values.map(\.updatedAt).max() ?? status.updatedAt
        return previousState != effectiveState
    }

    public func updateLeasePolicy(_ policy: SignalLeasePolicy, sessionTTL: Double) {
        leasePolicy = policy
        self.sessionTTL = sessionTTL
    }

    /// 更新只读连接检查结果，不在这里执行任何配置修复。
    @discardableResult
    public func updateHookIssue(_ issue: String?) -> Bool {
        let previousState = effectiveState
        hookIssue = issue
        return previousState != effectiveState
    }

    private func refreshSessions() -> String? {
        guard FileManager.default.fileExists(atPath: sessionFileURL.path) else {
            sessionState = SessionState(sessions: [:])
            return nil
        }
        guard let data = try? Data(contentsOf: sessionFileURL),
              let state = try? JSONDecoder().decode(SessionState.self, from: data)
        else {
            sessionState = SessionState(sessions: [:])
            return "会话状态文件无法读取"
        }
        sessionState = state
        return nil
    }
}
