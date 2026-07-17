import Foundation

/// Codex rollout 中可确认的当前任务生命周期。
public enum CodexThreadActivity: String, Equatable {
    /// 已收到 task_started，且之后尚未出现终止事件。
    case running
    /// 已收到 task_complete，任务正常结束。
    case completed
    /// 已收到 turn_aborted，任务被用户或系统中断。
    case interrupted
    /// rollout 不存在或尾部没有足够信息，继续使用 Hook 租约判断。
    case unknown
}

/// 一条带真实事件时间的 Codex 任务生命周期快照。
public struct CodexThreadActivitySnapshot: Equatable {
    public let state: CodexThreadActivity
    public let updatedAt: Double

    public init(state: CodexThreadActivity, updatedAt: Double) {
        self.state = state
        self.updatedAt = updatedAt
    }
}

/// Codex 本地会话索引中的用户可见名称与最新任务生命周期。
public struct CodexThreadSummary: Equatable {
    public let id: String
    public let name: String
    public let updatedAt: Double?
    public let activity: CodexThreadActivitySnapshot?

    public init(
        id: String,
        name: String,
        updatedAt: Double? = nil,
        activity: CodexThreadActivitySnapshot? = nil
    ) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.activity = activity
    }
}

/// 读取 Codex 自己维护的 `session_index.jsonl`，为状态面板补充真实会话名称。
///
/// 索引按文件修改时间和大小缓存；损坏或尚未写完的单行会被忽略，不影响其他会话。
public final class CodexThreadCatalog {
    private struct IndexEntry: Decodable {
        let id: String
        let threadName: String
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
            case updatedAt = "updated_at"
        }
    }

    private struct FileStamp: Equatable {
        let modifiedAt: TimeInterval
        let size: UInt64
    }

    private struct ActivityCacheEntry {
        let stamp: FileStamp
        let snapshot: CodexThreadActivitySnapshot
    }

    private struct RolloutEnvelope: Decodable {
        struct Payload: Decodable {
            let type: String?
        }

        let timestamp: String?
        let type: String
        let payload: Payload?
    }

    public let indexURL: URL
    public let sessionsRootURL: URL
    private let lock = NSLock()
    private var cachedStamp: FileStamp?
    private var cachedSummaries: [String: CodexThreadSummary] = [:]
    private var rolloutURLs: [String: URL] = [:]
    private var missingRolloutCheckedAt: [String: TimeInterval] = [:]
    private var activityCache: [String: ActivityCacheEntry] = [:]

    private static let rolloutTailByteLimit: UInt64 = 512 * 1024
    private static let missingRolloutRetryInterval: TimeInterval = 5
    private static let lifecycleStates: [String: CodexThreadActivity] = [
        "task_started": .running,
        "task_complete": .completed,
        "turn_aborted": .interrupted,
    ]
    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let dateFormatter = ISO8601DateFormatter()

    public convenience init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let home = environment["CODEX_HOME"].flatMap(Self.cleanText)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .path
        let codexHome = URL(fileURLWithPath: home, isDirectory: true)
        self.init(
            indexURL: codexHome.appendingPathComponent("session_index.jsonl"),
            sessionsRootURL: codexHome.appendingPathComponent("sessions", isDirectory: true)
        )
    }

    public init(indexURL: URL, sessionsRootURL: URL? = nil) {
        self.indexURL = indexURL
        self.sessionsRootURL = sessionsRootURL
            ?? indexURL.deletingLastPathComponent().appendingPathComponent("sessions", isDirectory: true)
    }

    /// 返回指定会话的名称；同一会话重复出现在索引时，以最后一条记录为准。
    public func summaries(for threadIDs: Set<String>) -> [String: CodexThreadSummary] {
        guard !threadIDs.isEmpty else {
            return [:]
        }

        lock.lock()
        defer { lock.unlock() }
        refreshCacheIfNeeded()
        return cachedSummaries.reduce(into: [:]) { result, item in
            guard threadIDs.contains(item.key) else {
                return
            }
            let summary = item.value
            result[item.key] = CodexThreadSummary(
                id: summary.id,
                name: summary.name,
                updatedAt: summary.updatedAt,
                activity: activitySnapshot(for: item.key)
            )
        }
    }

    /// 返回 Codex 索引中最近更新的会话，供状态面板在活跃会话结束后继续提供返回入口。
    ///
    /// 没有合法 `updated_at` 的旧索引记录仍可用于名称查询，但不会混入最近会话排序。
    public func recentSummaries(limit: Int, excluding threadIDs: Set<String> = []) -> [CodexThreadSummary] {
        guard limit > 0 else {
            return []
        }

        lock.lock()
        defer { lock.unlock() }
        refreshCacheIfNeeded()
        return Array(
            cachedSummaries.values
                .filter { summary in
                    summary.updatedAt != nil && !threadIDs.contains(summary.id)
                }
                .sorted { left, right in
                    guard let leftUpdatedAt = left.updatedAt, let rightUpdatedAt = right.updatedAt else {
                        return left.updatedAt != nil
                    }
                    return leftUpdatedAt == rightUpdatedAt
                        ? left.id > right.id
                        : leftUpdatedAt > rightUpdatedAt
                }
                .prefix(limit)
        )
    }

    /// 返回指定会话的最新任务生命周期；找不到 rollout 时不写入 unknown，调用方继续走 Hook 租约。
    public func activities(for threadIDs: Set<String>) -> [String: CodexThreadActivitySnapshot] {
        guard !threadIDs.isEmpty else {
            return [:]
        }

        lock.lock()
        defer { lock.unlock() }
        return threadIDs.reduce(into: [:]) { result, threadID in
            if let snapshot = activitySnapshot(for: threadID), snapshot.state != .unknown {
                result[threadID] = snapshot
            }
        }
    }

    private func refreshCacheIfNeeded() {
        guard let stamp = fileStamp(for: indexURL) else {
            cachedStamp = nil
            cachedSummaries = [:]
            return
        }
        guard stamp != cachedStamp else {
            return
        }
        guard let data = try? Data(contentsOf: indexURL),
              let text = String(data: data, encoding: .utf8)
        else {
            cachedStamp = stamp
            cachedSummaries = [:]
            return
        }

        let decoder = JSONDecoder()
        var summaries: [String: CodexThreadSummary] = [:]
        for line in text.split(whereSeparator: { $0.isNewline }) {
            guard let lineData = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(IndexEntry.self, from: lineData),
                  let id = Self.cleanText(entry.id),
                  let name = Self.cleanText(entry.threadName)
            else {
                continue
            }
            summaries[id] = CodexThreadSummary(
                id: id,
                name: name,
                updatedAt: entry.updatedAt.flatMap(Self.parseTimestamp)
            )
        }
        cachedStamp = stamp
        cachedSummaries = summaries
    }

    private func activitySnapshot(for threadID: String) -> CodexThreadActivitySnapshot? {
        guard let rolloutURL = rolloutURL(for: threadID),
              let stamp = fileStamp(for: rolloutURL)
        else {
            return nil
        }
        if let cached = activityCache[threadID], cached.stamp == stamp {
            return cached.snapshot
        }

        guard let parsed = readLatestActivity(from: rolloutURL) else {
            // 长任务的 task_started 可能已离开尾部窗口；保留上次已确认的生命周期。
            return activityCache[threadID]?.snapshot
        }
        activityCache[threadID] = ActivityCacheEntry(stamp: stamp, snapshot: parsed)
        return parsed
    }

    private func rolloutURL(for threadID: String) -> URL? {
        let normalized = threadID.lowercased()
        guard UUID(uuidString: normalized) != nil else {
            return nil
        }
        if let cached = rolloutURLs[normalized], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let lastCheck = missingRolloutCheckedAt[normalized],
           now - lastCheck < Self.missingRolloutRetryInterval {
            return nil
        }
        missingRolloutCheckedAt[normalized] = now

        let suffix = "-\(normalized).jsonl"
        if let datedURL = datedRolloutDirectories(for: normalized).lazy.compactMap({ directory in
            try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).first { $0.lastPathComponent.hasSuffix(suffix) }
        }).first {
            rolloutURLs[normalized] = datedURL
            missingRolloutCheckedAt.removeValue(forKey: normalized)
            return datedURL
        }

        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(suffix) {
            rolloutURLs[normalized] = url
            missingRolloutCheckedAt.removeValue(forKey: normalized)
            return url
        }
        return nil
    }

    /// UUIDv7 前 48 位是毫秒时间戳，优先定位当天目录；前后各一天覆盖时区边界。
    private func datedRolloutDirectories(for threadID: String) -> [URL] {
        let compact = threadID.replacingOccurrences(of: "-", with: "")
        guard compact.count >= 12,
              let milliseconds = UInt64(compact.prefix(12), radix: 16)
        else {
            return []
        }
        let createdAt = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return (-1...1).compactMap { offset -> URL? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: createdAt) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else {
                return nil
            }
            return sessionsRootURL
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
        }
    }

    private func readLatestActivity(from url: URL) -> CodexThreadActivitySnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let endOffset = handle.seekToEndOfFile()
        let startOffset = endOffset > Self.rolloutTailByteLimit ? endOffset - Self.rolloutTailByteLimit : 0
        handle.seek(toFileOffset: startOffset)
        let data = handle.readDataToEndOfFile()
        guard var text = String(data: data, encoding: .utf8) else {
            return nil
        }
        if startOffset > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }

        let decoder = JSONDecoder()
        for line in text.split(whereSeparator: { $0.isNewline }).reversed() {
            guard let lineData = String(line).data(using: .utf8),
                  let envelope = try? decoder.decode(RolloutEnvelope.self, from: lineData),
                  envelope.type == "event_msg",
                  let payloadType = envelope.payload?.type,
                  let state = Self.lifecycleStates[payloadType],
                  let timestamp = envelope.timestamp,
                  let date = Self.fractionalDateFormatter.date(from: timestamp)
                    ?? Self.dateFormatter.date(from: timestamp)
            else {
                continue
            }
            return CodexThreadActivitySnapshot(state: state, updatedAt: date.timeIntervalSince1970)
        }
        return nil
    }

    private func fileStamp(for url: URL) -> FileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return FileStamp(modifiedAt: modifiedAt.timeIntervalSince1970, size: size.uint64Value)
    }

    private static func cleanText(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func parseTimestamp(_ value: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let date = fractionalDateFormatter.date(from: text) ?? dateFormatter.date(from: text)
        else {
            return nil
        }
        return date.timeIntervalSince1970
    }
}

/// 只为 Codex UUID 会话生成深链，避免把 cwd/global 等 fallback key 当作可导航会话。
public func codexThreadURL(threadID: String) -> URL? {
    let normalized = threadID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard UUID(uuidString: normalized) != nil else {
        return nil
    }
    return URL(string: "codex://threads/\(normalized)")
}
