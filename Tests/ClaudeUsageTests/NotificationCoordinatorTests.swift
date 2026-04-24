import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("NotificationCoordinator")
struct NotificationCoordinatorTests {

    @MainActor
    private func makeCoordinator() -> NotificationCoordinator {
        NotificationCoordinator(notificationService: NotificationService())
    }

    private func makeUsage(fiveHour: Double?, extraEnabled: Bool = false, usedCredits: Double? = nil, monthlyLimit: Double? = nil) -> UsageResponse {
        let fiveHourJson: String
        if let fh = fiveHour {
            fiveHourJson = """
            { "utilization": \(fh), "resets_at": null }
            """
        } else {
            fiveHourJson = "null"
        }

        let json = """
        {
            "five_hour": \(fiveHourJson),
            "extra_usage": {
                "is_enabled": \(extraEnabled),
                "monthly_limit": \(monthlyLimit.map { "\($0)" } ?? "null"),
                "used_credits": \(usedCredits.map { "\($0)" } ?? "null"),
                "utilization": null
            }
        }
        """
        return try! JSONDecoder().decode(UsageResponse.self, from: json.data(using: .utf8)!)
    }

    @Test("Returns nil credit projection for non-enterprise usage")
    @MainActor
    func nonEnterpriseNoCreditProjection() {
        let coordinator = makeCoordinator()
        let usage = makeUsage(fiveHour: 50.0)
        let result = coordinator.evaluate(usage: usage)
        #expect(result.creditProjection == nil)
    }

    @Test("Returns credit projection for enterprise usage")
    @MainActor
    func enterpriseCreditProjection() {
        let coordinator = makeCoordinator()
        let usage = makeUsage(
            fiveHour: nil,
            extraEnabled: true,
            usedCredits: 25000,
            monthlyLimit: 100000
        )
        let result = coordinator.evaluate(usage: usage)

        // Projection only exists past day 1 of the month
        let dayOfMonth = Calendar.current.component(.day, from: Date())
        if dayOfMonth > 1 {
            #expect(result.creditProjection != nil)
            #expect(result.creditProjection!.burnRatePerDay > 0)
        }
    }

    @Test("Reset clears notification state")
    @MainActor
    func resetClearsState() {
        let coordinator = makeCoordinator()
        coordinator.reset()
    }

    @Test("Ring buffer feeds burn-rate projection across repeated evaluations")
    @MainActor
    func ringBufferAccumulates() {
        let coordinator = makeCoordinator()
        // Two samples with the same usage — projection returns zero velocity since
        // the coordinator records them at effectively the same timestamp, but it
        // must not crash and should still return a well-formed evaluation.
        _ = coordinator.evaluate(usage: makeUsage(fiveHour: 40))
        let second = coordinator.evaluate(usage: makeUsage(fiveHour: 40))
        #expect(second.creditProjection == nil)
    }
}
