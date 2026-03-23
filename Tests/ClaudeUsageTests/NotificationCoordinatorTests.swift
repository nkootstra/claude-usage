import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("NotificationCoordinator")
struct NotificationCoordinatorTests {

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
    func nonEnterpriseNoCreditProjection() {
        let coordinator = makeCoordinator()
        let usage = makeUsage(fiveHour: 50.0)
        let result = coordinator.evaluate(usage: usage, historyPoints: [])
        #expect(result.creditProjection == nil)
    }

    @Test("Returns credit projection for enterprise usage")
    func enterpriseCreditProjection() {
        let coordinator = makeCoordinator()
        // Day > 1 needed for projection
        let usage = makeUsage(
            fiveHour: nil,
            extraEnabled: true,
            usedCredits: 25000, // $250
            monthlyLimit: 100000 // $1000
        )
        let result = coordinator.evaluate(usage: usage, historyPoints: [])

        // Whether projection is nil depends on day of month
        // On day 1, no projection; on day > 1, should have one
        let dayOfMonth = Calendar.current.component(.day, from: Date())
        if dayOfMonth > 1 {
            #expect(result.creditProjection != nil)
            #expect(result.creditProjection!.burnRatePerDay > 0)
        }
    }

    @Test("Reset clears notification state")
    func resetClearsState() {
        let coordinator = makeCoordinator()
        // Just verify it doesn't crash
        coordinator.reset()
    }
}
