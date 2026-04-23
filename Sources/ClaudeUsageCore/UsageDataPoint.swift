import Foundation

/// In-memory sample of a usage response, used by the burn-rate ring buffer
/// inside NotificationCoordinator.
public struct UsageDataPoint: Sendable {
    public let timestamp: Date
    public let fiveHourUtilization: Double
    public let sevenDayUtilization: Double
    public let sonnetUtilization: Double?
    public let opusUtilization: Double?
    public let extraUsageUtilization: Double?
    public let extraUsedCents: Double?
    public let extraLimitCents: Double?

    public init(
        timestamp: Date,
        fiveHourUtilization: Double,
        sevenDayUtilization: Double,
        sonnetUtilization: Double? = nil,
        opusUtilization: Double? = nil,
        extraUsageUtilization: Double? = nil,
        extraUsedCents: Double? = nil,
        extraLimitCents: Double? = nil
    ) {
        self.timestamp = timestamp
        self.fiveHourUtilization = fiveHourUtilization
        self.sevenDayUtilization = sevenDayUtilization
        self.sonnetUtilization = sonnetUtilization
        self.opusUtilization = opusUtilization
        self.extraUsageUtilization = extraUsageUtilization
        self.extraUsedCents = extraUsedCents
        self.extraLimitCents = extraLimitCents
    }
}
