import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("Burn Rate Notifications")
struct BurnRateNotificationTests {

    // Use unique labels per test to avoid UserDefaults state leaking between parallel tests
    private func uniqueLabel(_ base: String = "test") -> String {
        "\(base)-\(UUID().uuidString.prefix(8))"
    }

    @Test("Notifies when projected to hit 100% within 60 minutes")
    func notifiesWhenClose() {
        let label = uniqueLabel()
        let service = NotificationService()

        let projection = BurnRateProjection(
            velocityPerHour: 80,
            projectedExhaustionDate: Date().addingTimeInterval(45 * 60),
            minutesUntilExhaustion: 45
        )

        #expect(service.shouldNotifyBurnRate(projection: projection, bucketLabel: label) == true)
    }

    @Test("Does not notify when projection is beyond 60 minutes")
    func doesNotNotifyWhenFar() {
        let label = uniqueLabel()
        let service = NotificationService()

        let projection = BurnRateProjection(
            velocityPerHour: 10,
            projectedExhaustionDate: Date().addingTimeInterval(3 * 3600),
            minutesUntilExhaustion: 180
        )

        #expect(service.shouldNotifyBurnRate(projection: projection, bucketLabel: label) == false)
    }

    @Test("Does not notify when velocity is zero or negative")
    func doesNotNotifyNegative() {
        let label = uniqueLabel()
        let service = NotificationService()

        let projection = BurnRateProjection(
            velocityPerHour: -5,
            projectedExhaustionDate: nil,
            minutesUntilExhaustion: nil
        )

        #expect(service.shouldNotifyBurnRate(projection: projection, bucketLabel: label) == false)
    }

    @Test("Does not repeat notification for same cycle")
    func doesNotRepeat() {
        let label = uniqueLabel()
        let service = NotificationService()

        let projection = BurnRateProjection(
            velocityPerHour: 80,
            projectedExhaustionDate: Date().addingTimeInterval(30 * 60),
            minutesUntilExhaustion: 30
        )

        #expect(service.shouldNotifyBurnRate(projection: projection, bucketLabel: label) == true)
        service.markBurnRateNotified(bucketLabel: label)
        #expect(service.shouldNotifyBurnRate(projection: projection, bucketLabel: label) == false)
    }

    @Test("Resets notification state when usage drops")
    func resetsOnDrop() {
        let label = uniqueLabel()
        let service = NotificationService()

        service.markBurnRateNotified(bucketLabel: label)
        service.resetBurnRateNotification(bucketLabel: label)

        let projection = BurnRateProjection(
            velocityPerHour: 90,
            projectedExhaustionDate: Date().addingTimeInterval(20 * 60),
            minutesUntilExhaustion: 20
        )

        #expect(service.shouldNotifyBurnRate(projection: projection, bucketLabel: label) == true)
    }
}
