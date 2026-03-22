import Foundation

public struct UsageResponse: Codable, Sendable {
    public let fiveHour: UsageBucket?
    public let sevenDay: UsageBucket?
    public let sevenDaySonnet: UsageBucket?
    public let sevenDayOpus: UsageBucket?
    public let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
    }
}

public struct UsageBucket: Codable, Sendable {
    public let utilization: Double
    public let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public var resetsAtDate: Date? {
        guard let resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: resetsAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: resetsAt)
    }
}

public struct ExtraUsage: Codable, Sendable {
    public let isEnabled: Bool
    public let utilization: Double?
    public let usedCredits: Double?
    public let monthlyLimit: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
    }

    /// Credits in cents → dollars
    public var usedCreditsAmount: Double? {
        usedCredits.map { $0 / 100.0 }
    }

    /// Limit in cents → dollars
    public var monthlyLimitAmount: Double? {
        monthlyLimit.map { $0 / 100.0 }
    }
}
