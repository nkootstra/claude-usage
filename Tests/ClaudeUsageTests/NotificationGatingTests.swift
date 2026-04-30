import Testing
import Foundation
@testable import ClaudeUsageCore

/// Validates that the new "Notifications" settings toggles actually gate
/// `NotificationService.checkAndNotify` and `shouldNotifyBurnRate`.
/// Each test uses an isolated UserDefaults suite so the gate keys never leak
/// into the global standard defaults that other parallel tests read from.
@Suite("Notification gating")
struct NotificationGatingTests {
    private let notifiedKey = "claude-usage.notified.thresholds"

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "claude-usage.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func validProjection() -> BurnRateProjection {
        BurnRateProjection(
            velocityPerHour: 80,
            projectedExhaustionDate: Date().addingTimeInterval(30 * 60),
            minutesUntilExhaustion: 30
        )
    }

    @Test("Threshold alerts disabled blocks side effects")
    func thresholdAlertsDisabledBlocksSideEffects() {
        let defaults = makeIsolatedDefaults()
        defaults.set(false, forKey: "notificationThresholdAlerts")
        let service = NotificationService(defaults: defaults)

        service.checkAndNotify(fiveHourPct: 95.0)

        // The early-return in checkAndNotify must short-circuit before recording
        // the threshold cross — otherwise the gate isn't actually gating.
        #expect(defaults.array(forKey: notifiedKey) == nil)
    }

    @Test("Threshold alerts default (key unset) records crossings")
    func thresholdAlertsDefaultRecordsCrossings() {
        let defaults = makeIsolatedDefaults()
        // Don't set the gate key — must default to enabled (`?? true`).
        let service = NotificationService(defaults: defaults)

        service.checkAndNotify(fiveHourPct: 95.0)

        let notified = defaults.array(forKey: notifiedKey) as? [Double] ?? []
        #expect(notified.contains(50.0))
        #expect(notified.contains(80.0))
    }

    @Test("Burn rate alerts disabled returns false even when criteria met")
    func burnRateAlertsDisabledReturnsFalse() {
        let defaults = makeIsolatedDefaults()
        defaults.set(false, forKey: "notificationBurnRateAlerts")
        let service = NotificationService(defaults: defaults)

        #expect(service.shouldNotifyBurnRate(
            projection: validProjection(),
            bucketLabel: "5-Hour"
        ) == false)
    }

    @Test("Burn rate alerts default (key unset) returns true when criteria met")
    func burnRateAlertsDefaultReturnsTrue() {
        let defaults = makeIsolatedDefaults()
        // Gate key intentionally unset.
        let service = NotificationService(defaults: defaults)

        #expect(service.shouldNotifyBurnRate(
            projection: validProjection(),
            bucketLabel: "5-Hour"
        ) == true)
    }
}
