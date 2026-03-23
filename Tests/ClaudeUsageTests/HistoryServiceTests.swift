import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("HistoryService")
struct HistoryServiceTests {

    private func makeService() -> HistoryService {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-usage-history-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = UsageHistoryStore(directory: dir)
        return HistoryService(store: store)
    }

    private func makeUsage(
        fiveHour: Double = 42.0,
        sevenDay: Double = 17.0
    ) -> UsageResponse {
        // Build a minimal UsageResponse via JSON decoding
        let json = """
        {
            "five_hour": { "utilization": \(fiveHour), "resets_at": null },
            "seven_day": { "utilization": \(sevenDay), "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """
        return try! JSONDecoder().decode(UsageResponse.self, from: json.data(using: .utf8)!)
    }

    @Test("Records and loads a data point")
    func recordAndLoad() async throws {
        let service = makeService()
        let usage = makeUsage(fiveHour: 55.0, sevenDay: 20.0)

        await service.record(from: usage)
        let points = await service.loadPoints()

        #expect(points.count == 1)
        #expect(points[0].fiveHourUtilization == 55.0)
        #expect(points[0].sevenDayUtilization == 20.0)
    }

    @Test("Records multiple points in order")
    func multiplePointsOrdered() async throws {
        let service = makeService()

        await service.record(from: makeUsage(fiveHour: 10.0))
        await service.record(from: makeUsage(fiveHour: 20.0))
        await service.record(from: makeUsage(fiveHour: 30.0))

        let points = await service.loadPoints()
        #expect(points.count == 3)
        #expect(points[0].fiveHourUtilization == 10.0)
        #expect(points[2].fiveHourUtilization == 30.0)
    }

    @Test("Maps optional fields correctly")
    func optionalFields() async throws {
        let service = makeService()
        let json = """
        {
            "five_hour": { "utilization": 50.0, "resets_at": null },
            "seven_day": { "utilization": 25.0, "resets_at": null },
            "seven_day_sonnet": { "utilization": 30.0, "resets_at": null },
            "seven_day_opus": { "utilization": 15.0, "resets_at": null },
            "extra_usage": { "is_enabled": true, "monthly_limit": 50000, "used_credits": 25000, "utilization": 50.0 }
        }
        """
        let usage = try JSONDecoder().decode(UsageResponse.self, from: json.data(using: .utf8)!)

        await service.record(from: usage)
        let points = await service.loadPoints()

        #expect(points[0].sonnetUtilization == 30.0)
        #expect(points[0].opusUtilization == 15.0)
        #expect(points[0].extraUsageUtilization == 50.0)
        #expect(points[0].extraUsedCents == 25000)
        #expect(points[0].extraLimitCents == 50000)
    }
}
