import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("MenuBarMetrics")
struct MenuBarMetricsTests {

    private func makeUsage(fiveHour: Double?, sevenDay: Double?) -> UsageResponse {
        let fiveBucket = fiveHour.map { UsageBucket(utilization: $0, resetsAt: nil) }
        let sevenBucket = sevenDay.map { UsageBucket(utilization: $0, resetsAt: nil) }
        return UsageResponse(
            fiveHour: fiveBucket,
            sevenDay: sevenBucket,
            sevenDaySonnet: nil,
            sevenDayOpus: nil,
            extraUsage: nil
        )
    }

    // MARK: - Percent extraction

    @Test("Happy path: primary and secondary percentages extracted from buckets")
    func extractsBothPercentages() {
        let usage = makeUsage(fiveHour: 35, sevenDay: 71)
        #expect(MenuBarMetrics.consumerPrimaryPercent(from: usage) == 35)
        #expect(MenuBarMetrics.consumerSecondaryPercent(from: usage) == 71)
    }

    @Test("Edge: nil fiveHour yields nil primary")
    func nilFiveHourYieldsNilPrimary() {
        let usage = makeUsage(fiveHour: nil, sevenDay: 42)
        #expect(MenuBarMetrics.consumerPrimaryPercent(from: usage) == nil)
        #expect(MenuBarMetrics.consumerSecondaryPercent(from: usage) == 42)
    }

    @Test("Edge: both buckets nil yields both helpers nil")
    func bothNilYieldsBothNil() {
        let usage = makeUsage(fiveHour: nil, sevenDay: nil)
        #expect(MenuBarMetrics.consumerPrimaryPercent(from: usage) == nil)
        #expect(MenuBarMetrics.consumerSecondaryPercent(from: usage) == nil)
    }

    @Test("Edge: nil UsageResponse yields both helpers nil")
    func nilUsageYieldsBothNil() {
        #expect(MenuBarMetrics.consumerPrimaryPercent(from: nil) == nil)
        #expect(MenuBarMetrics.consumerSecondaryPercent(from: nil) == nil)
    }

    @Test("Fractional utilization truncates via Int conversion")
    func fractionalUtilizationTruncates() {
        let usage = makeUsage(fiveHour: 49.9, sevenDay: 0.5)
        #expect(MenuBarMetrics.consumerPrimaryPercent(from: usage) == 49)
        #expect(MenuBarMetrics.consumerSecondaryPercent(from: usage) == 0)
    }

    // MARK: - Traffic-light color mode

    @Test("Traffic light: below warning returns ok")
    func trafficLightBelowWarning() {
        let color = MenuBarMetrics.thresholdColor(for: 10, warning: 50, critical: 80, colorMode: "traffic_light")
        #expect(color == .ok)
    }

    @Test("Traffic light: at warning returns warning")
    func trafficLightAtWarning() {
        let color = MenuBarMetrics.thresholdColor(for: 50, warning: 50, critical: 80, colorMode: "traffic_light")
        #expect(color == .warning)
    }

    @Test("Traffic light: between warning and critical returns warning")
    func trafficLightBetween() {
        let color = MenuBarMetrics.thresholdColor(for: 65, warning: 50, critical: 80, colorMode: "traffic_light")
        #expect(color == .warning)
    }

    @Test("Traffic light: at critical returns critical")
    func trafficLightAtCritical() {
        let color = MenuBarMetrics.thresholdColor(for: 80, warning: 50, critical: 80, colorMode: "traffic_light")
        #expect(color == .critical)
    }

    @Test("Traffic light: above critical returns critical")
    func trafficLightAboveCritical() {
        let color = MenuBarMetrics.thresholdColor(for: 95, warning: 50, critical: 80, colorMode: "traffic_light")
        #expect(color == .critical)
    }

    // MARK: - Single-color tealScale mode

    @Test("Single color: opacity scales from 0.4 at 0% to 1.0 at 100%")
    func singleColorScalesWithPercent() {
        let zero = MenuBarMetrics.thresholdColor(for: 0, warning: 50, critical: 80, colorMode: "single_color")
        #expect(zero == .tealScale(opacity: 0.4))

        let hundred = MenuBarMetrics.thresholdColor(for: 100, warning: 50, critical: 80, colorMode: "single_color")
        #expect(hundred == .tealScale(opacity: 1.0))

        let fifty = MenuBarMetrics.thresholdColor(for: 50, warning: 50, critical: 80, colorMode: "single_color")
        #expect(fifty == .tealScale(opacity: 0.7))
    }

    @Test("Single color: opacity clamped to [0.4, 1.0]")
    func singleColorClamped() {
        let negative = MenuBarMetrics.thresholdColor(for: -20, warning: 50, critical: 80, colorMode: "single_color")
        #expect(negative == .tealScale(opacity: 0.4))

        let overLimit = MenuBarMetrics.thresholdColor(for: 150, warning: 50, critical: 80, colorMode: "single_color")
        #expect(overLimit == .tealScale(opacity: 1.0))
    }

    @Test("Single color: ignores warning/critical thresholds")
    func singleColorIgnoresThresholds() {
        let a = MenuBarMetrics.thresholdColor(for: 90, warning: 50, critical: 80, colorMode: "single_color")
        let b = MenuBarMetrics.thresholdColor(for: 90, warning: 10, critical: 20, colorMode: "single_color")
        #expect(a == b)
    }
}
