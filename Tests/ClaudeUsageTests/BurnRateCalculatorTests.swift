import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("BurnRateCalculator")
struct BurnRateCalculatorTests {

    private func makePoints(hourlyValues: [(hoursAgo: Double, pct: Double)]) -> [UsageDataPoint] {
        hourlyValues.map {
            UsageDataPoint(
                timestamp: Date().addingTimeInterval(-$0.hoursAgo * 3600),
                fiveHourUtilization: $0.pct,
                sevenDayUtilization: 0
            )
        }.reversed() // oldest first
    }

    @Test("Steady increase projects exhaustion time")
    func steadyIncrease() throws {
        // 10% per hour over 3 hours: 20%, 30%, 40% — currently at 40%
        let points = makePoints(hourlyValues: [(2, 20), (1, 30), (0, 40)])

        let projection = BurnRateCalculator.project(
            points: points,
            currentUtilization: 40
        )

        #expect(projection.velocityPerHour > 9 && projection.velocityPerHour < 11) // ~10%/hr
        // 60% remaining at 10%/hr = ~6 hours
        let mins = try #require(projection.minutesUntilExhaustion)
        #expect(mins > 300 && mins < 420) // ~360 minutes
        #expect(projection.projectedExhaustionDate != nil)
    }

    @Test("Zero velocity returns nil exhaustion")
    func zeroVelocity() {
        let points = makePoints(hourlyValues: [(2, 50), (1, 50), (0, 50)])

        let projection = BurnRateCalculator.project(
            points: points,
            currentUtilization: 50
        )

        #expect(projection.velocityPerHour == 0)
        #expect(projection.projectedExhaustionDate == nil)
        #expect(projection.minutesUntilExhaustion == nil)
    }

    @Test("Decreasing usage returns nil exhaustion")
    func decreasing() {
        let points = makePoints(hourlyValues: [(2, 80), (1, 60), (0, 40)])

        let projection = BurnRateCalculator.project(
            points: points,
            currentUtilization: 40
        )

        #expect(projection.velocityPerHour < 0)
        #expect(projection.projectedExhaustionDate == nil)
    }

    @Test("Single point returns nil projection")
    func singlePoint() {
        let points = makePoints(hourlyValues: [(0, 50)])

        let projection = BurnRateCalculator.project(
            points: points,
            currentUtilization: 50
        )

        #expect(projection.projectedExhaustionDate == nil)
    }

    @Test("Credit burn rate on day 22 of month")
    func creditBurn() {
        // Day 22, $66 used of $150 → ~$3/day
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day22 = cal.date(from: DateComponents(year: 2026, month: 3, day: 22, hour: 12))!

        let projection = BurnRateCalculator.projectCredits(
            usedDollars: 66,
            limitDollars: 150,
            now: day22
        )

        #expect(projection.burnRatePerDay > 2.5 && projection.burnRatePerDay < 3.5)
        #expect(projection.projectedExhaustionDate != nil)
    }

    @Test("Zero credits used returns nil")
    func zeroCreditBurn() {
        let projection = BurnRateCalculator.projectCredits(
            usedDollars: 0,
            limitDollars: 100
        )

        #expect(projection.projectedExhaustionDate == nil)
    }

    @Test("Day 1 of month returns nil — not enough data")
    func day1ReturnsNil() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day1 = cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 6))!

        let projection = BurnRateCalculator.projectCredits(
            usedDollars: 10,
            limitDollars: 100,
            now: day1
        )

        #expect(projection.projectedExhaustionDate == nil)
    }

    @Test("Projection capped to end of month")
    func cappedToMonthEnd() {
        // Day 28, $10 used of $1000 → very slow burn, but capped to month end
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day28 = cal.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12))!

        let projection = BurnRateCalculator.projectCredits(
            usedDollars: 10,
            limitDollars: 1000,
            now: day28
        )

        // Should not project past March 31
        if let exhaustion = projection.projectedExhaustionDate {
            let endOfMonth = cal.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 23, minute: 59, second: 59))!
            #expect(exhaustion <= endOfMonth.addingTimeInterval(86400))
        }
        // With $10/28days ≈ $0.36/day, $990 remaining → ~2750 days → capped
        #expect(projection.burnRatePerDay > 0.3 && projection.burnRatePerDay < 0.4)
    }
}
