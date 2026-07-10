import Foundation

public func isCursorSessionSource(_ source: SessionSource?) -> Bool {
    guard let bundleIdentifier = source?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
          !bundleIdentifier.isEmpty
    else {
        return false
    }
    return cursorBundleIdentifiers.contains(bundleIdentifier)
}

public enum CursorQuotaState: Equatable {
    case loading
    case loaded(CursorUsageSnapshot)
    case unavailable(String)
}

public struct CursorUsageSnapshot: Equatable {
    public var planType: String?
    public var email: String?
    public var totalUsedPercent: Int
    public var autoUsedPercent: Int
    public var apiUsedPercent: Int
    public var includedLimitCents: Int?
    public var totalSpendCents: Int?
    public var billingCycleEnd: Date?
    public var displayMessage: String?

    public init(
        planType: String?,
        email: String?,
        totalUsedPercent: Int,
        autoUsedPercent: Int,
        apiUsedPercent: Int,
        includedLimitCents: Int?,
        totalSpendCents: Int?,
        billingCycleEnd: Date?,
        displayMessage: String?
    ) {
        self.planType = planType
        self.email = email
        self.totalUsedPercent = totalUsedPercent
        self.autoUsedPercent = autoUsedPercent
        self.apiUsedPercent = apiUsedPercent
        self.includedLimitCents = includedLimitCents
        self.totalSpendCents = totalSpendCents
        self.billingCycleEnd = billingCycleEnd
        self.displayMessage = displayMessage
    }

    public var totalRemainingPercent: Int {
        max(0, 100 - totalUsedPercent)
    }

    public var formattedPlanType: String? {
        guard let planType = cleanText(planType) else {
            return nil
        }
        return planType
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { part in
                let text = String(part)
                guard let first = text.first else {
                    return text
                }
                return String(first).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }

    public func usageWindow(usedPercent: Int, resetsAt: Date?) -> CodexRateLimitWindow {
        CodexRateLimitWindow(
            usedPercent: min(100, max(0, usedPercent)),
            windowDurationMins: nil,
            resetsAt: resetsAt.map { Int64($0.timeIntervalSince1970) }
        )
    }
}

public enum CursorUsageDecodingError: Error, LocalizedError, Equatable {
    case invalidPayload
    case missingPlanUsage

    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Cursor 额度返回结构无法解析"
        case .missingPlanUsage:
            return "Cursor 额度返回缺少 planUsage"
        }
    }
}

public enum CursorUsagePayload {
    public static func decodeSnapshot(
        from data: Data,
        planType: String? = nil,
        email: String? = nil
    ) throws -> CursorUsageSnapshot {
        let response: RawCurrentPeriodUsageResponse
        do {
            response = try JSONDecoder().decode(RawCurrentPeriodUsageResponse.self, from: data)
        } catch {
            throw CursorUsageDecodingError.invalidPayload
        }
        guard let planUsage = response.planUsage else {
            throw CursorUsageDecodingError.missingPlanUsage
        }

        let billingCycleEnd = parseEpochMilliseconds(response.billingCycleEnd)
        return CursorUsageSnapshot(
            planType: planType,
            email: email,
            totalUsedPercent: percentValue(planUsage.totalPercentUsed),
            autoUsedPercent: percentValue(planUsage.autoPercentUsed),
            apiUsedPercent: percentValue(planUsage.apiPercentUsed),
            includedLimitCents: planUsage.limit,
            totalSpendCents: planUsage.totalSpend,
            billingCycleEnd: billingCycleEnd,
            displayMessage: cleanText(response.displayMessage)
        )
    }

    private static func percentValue(_ value: Double?) -> Int {
        guard let value else {
            return 0
        }
        return min(100, max(0, Int(value.rounded())))
    }

    private static func parseEpochMilliseconds(_ value: String?) -> Date? {
        guard let value, let milliseconds = Double(value) else {
            return nil
        }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

private struct RawCurrentPeriodUsageResponse: Decodable {
    var billingCycleEnd: String?
    var planUsage: RawPlanUsage?
    var displayMessage: String?
}

private struct RawPlanUsage: Decodable {
    var totalSpend: Int?
    var includedSpend: Int?
    var limit: Int?
    var autoPercentUsed: Double?
    var apiPercentUsed: Double?
    var totalPercentUsed: Double?
}

private func cleanText(_ value: String?) -> String? {
    guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return nil
    }
    return text
}
