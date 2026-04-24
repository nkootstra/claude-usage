import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("UsageResponseCache")
struct UsageResponseCacheTests {

    private func tempFileURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-stats-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last-usage.json")
    }

    private func sampleResponse() -> UsageResponse {
        UsageResponse(
            fiveHour: UsageBucket(utilization: 42.0, resetsAt: "2026-03-22T12:00:00+00:00"),
            sevenDay: UsageBucket(utilization: 17.0, resetsAt: "2026-03-27T12:00:00+00:00"),
            sevenDaySonnet: nil,
            sevenDayOpus: nil,
            extraUsage: nil
        )
    }

    @Test("Round-trip: save then load returns equivalent data")
    func roundTrip() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = UsageResponseCache(fileURL: url)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let original = CachedUsageResponse(fetchedAt: fetchedAt, response: sampleResponse())

        cache.save(original)

        let loaded = cache.load()
        #expect(loaded != nil)
        #expect(loaded?.fetchedAt.timeIntervalSince1970 == fetchedAt.timeIntervalSince1970)
        #expect(loaded?.response.fiveHour?.utilization == 42.0)
        #expect(loaded?.response.sevenDay?.utilization == 17.0)
    }

    @Test("Missing file returns nil without throwing")
    func missingFile() {
        let url = tempFileURL()
        let cache = UsageResponseCache(fileURL: url)

        #expect(cache.load() == nil)
    }

    @Test("Corrupt file returns nil")
    func corruptFile() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "not valid json".data(using: .utf8)!.write(to: url)

        let cache = UsageResponseCache(fileURL: url)
        #expect(cache.load() == nil)
    }

    @Test("Clear removes the cached file")
    func clearRemovesFile() {
        let url = tempFileURL()
        let cache = UsageResponseCache(fileURL: url)
        cache.save(CachedUsageResponse(fetchedAt: Date(), response: sampleResponse()))
        #expect(FileManager.default.fileExists(atPath: url.path) == true)

        cache.clear()
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        #expect(cache.load() == nil)
    }

    @Test("Clear on missing file is a no-op")
    func clearNoOp() {
        let url = tempFileURL()
        let cache = UsageResponseCache(fileURL: url)
        cache.clear()
        #expect(cache.load() == nil)
    }
}
