import Foundation

public struct NotificationEvaluation: Sendable {
    public let creditProjection: CreditBurnProjection?
}

@MainActor
public final class NotificationCoordinator {
    private let notificationService: NotificationService
    private var points: [UsageDataPoint] = []

    /// Upper bound on retained samples. At 5-minute polling this covers ~5 hours,
    /// which is more than the burn-rate projection window needs.
    private static let maxPoints = 64

    public init(notificationService: NotificationService) {
        self.notificationService = notificationService
    }

    public func evaluate(usage: UsageResponse) -> NotificationEvaluation {
        recordSample(from: usage)

        if let fiveHourPct = usage.fiveHour?.utilization {
            let projection = BurnRateCalculator.project(
                points: points,
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

        var creditProjection: CreditBurnProjection?
        if let extra = usage.extraUsage, extra.isEnabled,
           let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
            creditProjection = BurnRateCalculator.projectCredits(
                usedDollars: used,
                limitDollars: limit
            )
        }

        if let pct = usage.fiveHour?.utilization {
            notificationService.checkAndNotify(fiveHourPct: pct)
        }

        return NotificationEvaluation(creditProjection: creditProjection)
    }

    public func reset() {
        notificationService.resetBurnRateNotification(bucketLabel: "5-Hour")
        points.removeAll()
    }

    private func recordSample(from usage: UsageResponse) {
        let point = UsageDataPoint(
            timestamp: Date(),
            fiveHourUtilization: usage.fiveHour?.utilization ?? 0,
            sevenDayUtilization: usage.sevenDay?.utilization ?? 0,
            sonnetUtilization: usage.sevenDaySonnet?.utilization,
            opusUtilization: usage.sevenDayOpus?.utilization,
            extraUsageUtilization: usage.extraUsage?.utilization,
            extraUsedCents: usage.extraUsage?.usedCredits,
            extraLimitCents: usage.extraUsage?.monthlyLimit
        )
        points.append(point)
        if points.count > Self.maxPoints {
            points.removeFirst(points.count - Self.maxPoints)
        }
    }
}
