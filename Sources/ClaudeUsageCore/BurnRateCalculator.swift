import Foundation

public struct BurnRateProjection: Sendable {
    public let velocityPerHour: Double
    public let projectedExhaustionDate: Date?
    public let minutesUntilExhaustion: Double?
}

public struct CreditBurnProjection: Sendable {
    public let burnRatePerDay: Double
    public let projectedExhaustionDate: Date?
}

public enum BurnRateCalculator {

    /// Project when usage will hit 100% based on recent history.
    /// Uses simple linear slope from oldest to newest point within windowHours.
    public static func project(
        points: [UsageDataPoint],
        currentUtilization: Double,
        windowHours: Double = 4,
        keyPath: KeyPath<UsageDataPoint, Double> = \.fiveHourUtilization,
        now: Date = Date()
    ) -> BurnRateProjection {
        guard points.count >= 2 else {
            return BurnRateProjection(velocityPerHour: 0, projectedExhaustionDate: nil, minutesUntilExhaustion: nil)
        }

        let windowStart = now.addingTimeInterval(-windowHours * 3600)
        let windowPoints = points
            .filter { $0.timestamp >= windowStart }
            .sorted { $0.timestamp < $1.timestamp }

        guard let oldest = windowPoints.first, let newest = windowPoints.last,
              oldest.timestamp != newest.timestamp else {
            return BurnRateProjection(velocityPerHour: 0, projectedExhaustionDate: nil, minutesUntilExhaustion: nil)
        }

        let timeDeltaHours = newest.timestamp.timeIntervalSince(oldest.timestamp) / 3600
        guard timeDeltaHours > 0 else {
            return BurnRateProjection(velocityPerHour: 0, projectedExhaustionDate: nil, minutesUntilExhaustion: nil)
        }

        let valueDelta = newest[keyPath: keyPath] - oldest[keyPath: keyPath]
        let velocityPerHour = valueDelta / timeDeltaHours

        guard velocityPerHour > 0 else {
            return BurnRateProjection(velocityPerHour: velocityPerHour, projectedExhaustionDate: nil, minutesUntilExhaustion: nil)
        }

        let remaining = 100.0 - currentUtilization
        let hoursUntilExhaustion = remaining / velocityPerHour
        let exhaustionDate = now.addingTimeInterval(hoursUntilExhaustion * 3600)

        return BurnRateProjection(
            velocityPerHour: velocityPerHour,
            projectedExhaustionDate: exhaustionDate,
            minutesUntilExhaustion: hoursUntilExhaustion * 60
        )
    }

    /// Project when enterprise credits will be exhausted.
    /// Assumes calendar month billing cycle (resets on 1st).
    public static func projectCredits(
        usedDollars: Double,
        limitDollars: Double,
        now: Date = Date()
    ) -> CreditBurnProjection {
        let cal = Calendar.current
        let dayOfMonth = cal.component(.day, from: now)

        // Need at least 1 full day of data
        guard dayOfMonth > 1, usedDollars > 0, limitDollars > 0 else {
            return CreditBurnProjection(burnRatePerDay: 0, projectedExhaustionDate: nil)
        }

        let burnRatePerDay = usedDollars / Double(dayOfMonth)
        let remaining = limitDollars - usedDollars

        guard remaining > 0 else {
            return CreditBurnProjection(burnRatePerDay: burnRatePerDay, projectedExhaustionDate: now)
        }

        let daysUntilExhaustion = remaining / burnRatePerDay

        // Cap to end of month — credits reset
        let daysInMonth = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)
        let daysLeftInMonth = daysInMonth - Double(dayOfMonth)
        let effectiveDays = min(daysUntilExhaustion, daysLeftInMonth)

        let exhaustionDate = now.addingTimeInterval(effectiveDays * 86400)

        return CreditBurnProjection(burnRatePerDay: burnRatePerDay, projectedExhaustionDate: exhaustionDate)
    }
}
