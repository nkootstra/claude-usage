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

    @Test("Credit burn rate projects exhaustion")
    func creditBurn() {
        // $15 used of $100 over 5 days = $3/day → exhausts in ~28.3 more days
        let projection = BurnRateCalculator.projectCredits(
            usedDollars: 15,
            limitDollars: 100,
            historyStartDate: Date().addingTimeInterval(-5 * 86400)
        )

        #expect(projection.burnRatePerDay > 2.5 && projection.burnRatePerDay < 3.5)
        #expect(projection.projectedExhaustionDate != nil)
    }

    @Test("Zero credits used returns nil exhaustion")
    func zeroCreditBurn() {
        let projection = BurnRateCalculator.projectCredits(
            usedDollars: 0,
            limitDollars: 100,
            historyStartDate: Date().addingTimeInterval(-86400)
        )

        #expect(projection.burnRatePerDay == 0)
        #expect(projection.projectedExhaustionDate == nil)
    }

    @Test("No history start date returns nil exhaustion")
    func noHistoryStart() {
        let projection = BurnRateCalculator.projectCredits(
            usedDollars: 50,
            limitDollars: 100,
            historyStartDate: nil
        )

        #expect(projection.projectedExhaustionDate == nil)
    }
}
