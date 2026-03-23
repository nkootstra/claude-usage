import Foundation

public struct NotificationEvaluation: Sendable {
    public let creditProjection: CreditBurnProjection?
}

public protocol NotificationCoordinatorProtocol: Sendable {
    func evaluate(usage: UsageResponse, historyPoints: [UsageDataPoint]) -> NotificationEvaluation
    func reset()
}

public final class NotificationCoordinator: NotificationCoordinatorProtocol, Sendable {
    private let notificationService: NotificationService

    public init(notificationService: NotificationService) {
        self.notificationService = notificationService
    }

    public func evaluate(usage: UsageResponse, historyPoints: [UsageDataPoint]) -> NotificationEvaluation {
        // Burn rate projection + notification
        if let fiveHourPct = usage.fiveHour?.utilization {
            let projection = BurnRateCalculator.project(
                points: historyPoints,
                currentUtilization: fiveHourPct
            )
            if notificationService.shouldNotifyBurnRate(projection: projection, bucketLabel: "5-Hour") {
                notificationService.sendBurnRateNotification(
                    bucketLabel: "5-Hour",
                    minutesRemaining: projection.minutesUntilExhaustion ?? 0
                )
                notificationService.markBurnRateNotified(bucketLabel: "5-Hour")
            }
        }

        // Enterprise credit projection
        var creditProjection: CreditBurnProjection?
        if let extra = usage.extraUsage, extra.isEnabled,
           let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
            creditProjection = BurnRateCalculator.projectCredits(
                usedDollars: used,
                limitDollars: limit
            )
        }

        // Threshold notifications
        if let pct = usage.fiveHour?.utilization {
            notificationService.checkAndNotify(fiveHourPct: pct)
        }

        return NotificationEvaluation(creditProjection: creditProjection)
    }

    public func reset() {
        notificationService.resetBurnRateNotification(bucketLabel: "5-Hour")
    }
}
