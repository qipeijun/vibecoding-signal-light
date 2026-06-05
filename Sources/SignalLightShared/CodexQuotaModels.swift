import Foundation

public enum CodexQuotaState: Equatable {
    case loading
    case loaded(CodexRateLimitSnapshot)
    case unavailable(String)
}

public struct CodexRateLimitSnapshot: Equatable {
    public var limitId: String?
    public var limitName: String?
    public var planType: String?
    public var rateLimitReachedType: String?
    public var credits: CodexCreditsSnapshot?
    public var primary: CodexRateLimitWindow
    public var secondary: CodexRateLimitWindow

    public init(
        limitId: String?,
        limitName: String?,
        planType: String?,
        rateLimitReachedType: String?,
        credits: CodexCreditsSnapshot?,
        primary: CodexRateLimitWindow,
        secondary: CodexRateLimitWindow
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
        self.credits = credits
        self.primary = primary
        self.secondary = secondary
    }
}

public struct CodexCreditsSnapshot: Equatable, Decodable {
    public var balance: String?
    public var hasCredits: Bool
    public var unlimited: Bool
}

public struct CodexRateLimitWindow: Equatable {
    public var usedPercent: Int
    public var windowDurationMins: Int?
    public var resetsAt: Int64?

    public init(usedPercent: Int, windowDurationMins: Int?, resetsAt: Int64?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int {
        max(0, 100 - usedPercent)
    }

    public func displayTitle(defaultTitle: String) -> String {
        guard let windowDurationMins else {
            return defaultTitle
        }
        let duration = CodexRateLimitWindow.formatDuration(minutes: windowDurationMins)
        if defaultTitle.contains(duration) {
            return defaultTitle
        }
        return "\(duration)窗口"
    }

    public static func formatDuration(minutes: Int) -> String {
        if minutes % (24 * 60) == 0 {
            return "\(minutes / (24 * 60)) 天"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60) 小时"
        }
        return "\(minutes) 分钟"
    }
}

public enum CodexRateLimitDecodingError: Error, LocalizedError, Equatable {
    case invalidPayload
    case missingWindows

    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Codex 额度返回结构无法解析"
        case .missingWindows:
            return "Codex 额度返回缺少 5 小时或 7 天窗口"
        }
    }
}

public enum CodexRateLimitPayload {
    public static func decodeSnapshot(from data: Data) throws -> CodexRateLimitSnapshot {
        let response: RawGetAccountRateLimitsResponse
        do {
            response = try JSONDecoder().decode(RawGetAccountRateLimitsResponse.self, from: data)
        } catch {
            throw CodexRateLimitDecodingError.invalidPayload
        }
        let rawSnapshot = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        guard let primary = rawSnapshot.primary, let secondary = rawSnapshot.secondary else {
            throw CodexRateLimitDecodingError.missingWindows
        }

        return CodexRateLimitSnapshot(
            limitId: rawSnapshot.limitId,
            limitName: rawSnapshot.limitName,
            planType: rawSnapshot.planType,
            rateLimitReachedType: rawSnapshot.rateLimitReachedType,
            credits: rawSnapshot.credits,
            primary: CodexRateLimitWindow(
                usedPercent: primary.usedPercent,
                windowDurationMins: primary.windowDurationMins,
                resetsAt: primary.resetsAt
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: secondary.usedPercent,
                windowDurationMins: secondary.windowDurationMins,
                resetsAt: secondary.resetsAt
            )
        )
    }
}

private struct RawGetAccountRateLimitsResponse: Decodable {
    var rateLimits: RawRateLimitSnapshot
    var rateLimitsByLimitId: [String: RawRateLimitSnapshot]?
}

private struct RawRateLimitSnapshot: Decodable {
    var limitId: String?
    var limitName: String?
    var planType: String?
    var rateLimitReachedType: String?
    var credits: CodexCreditsSnapshot?
    var primary: RawRateLimitWindow?
    var secondary: RawRateLimitWindow?
}

private struct RawRateLimitWindow: Decodable {
    var usedPercent: Int
    var windowDurationMins: Int?
    var resetsAt: Int64?
}
