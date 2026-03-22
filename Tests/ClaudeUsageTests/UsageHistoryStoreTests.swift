import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("UsageHistoryStore")
struct UsageHistoryStoreTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-usage-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makePoint(
        hoursAgo: Double = 0,
        fiveHour: Double = 10.0,
        sevenDay: Double = 5.0
    ) -> UsageDataPoint {
        UsageDataPoint(
            timestamp: Date().addingTimeInterval(-hoursAgo * 3600),
            fiveHourUtilization: fiveHour,
            sevenDayUtilization: sevenDay
        )
    }

    @Test("Records a point and loads it back")
    func recordAndLoad() async throws {
        let dir = try makeTempDir()
        let store = UsageHistoryStore(directory: dir)

        try await store.record(makePoint(fiveHour: 42.0, sevenDay: 17.0))

        let loaded = try await store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].fiveHourUtilization == 42.0)
        #expect(loaded[0].sevenDayUtilization == 17.0)
    }

    @Test("Appends multiple points in order")
    func appendsInOrder() async throws {
        let dir = try makeTempDir()
        let store = UsageHistoryStore(directory: dir)

        try await store.record(makePoint(fiveHour: 10.0))
        try await store.record(makePoint(fiveHour: 20.0))
        try await store.record(makePoint(fiveHour: 30.0))

        let loaded = try await store.load()
        #expect(loaded.count == 3)
        #expect(loaded[0].fiveHourUtilization == 10.0)
        #expect(loaded[2].fiveHourUtilization == 30.0)
    }

    @Test("Prune removes points older than 30 days")
    func pruneOld() async throws {
        let dir = try makeTempDir()
        let store = UsageHistoryStore(directory: dir)

        // 31 days ago
        try await store.record(makePoint(hoursAgo: 31 * 24, fiveHour: 99.0))
        // 1 hour ago
        try await store.record(makePoint(hoursAgo: 1, fiveHour: 5.0))

        try await store.prune()

        let loaded = try await store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].fiveHourUtilization == 5.0)
    }

    @Test("Prune after record removes old points")
    func pruneAfterRecord() async throws {
        let dir = try makeTempDir()
        let store = UsageHistoryStore(directory: dir)

        try await store.record(makePoint(hoursAgo: 31 * 24, fiveHour: 99.0))
        try await store.record(makePoint(fiveHour: 5.0))
        try await store.prune()

        let loaded = try await store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].fiveHourUtilization == 5.0)
    }

    @Test("Load from nonexistent file returns empty")
    func loadNonexistent() async throws {
        let dir = try makeTempDir()
        let store = UsageHistoryStore(directory: dir)

        let loaded = try await store.load()
        #expect(loaded.isEmpty)
    }

    @Test("Corrupted file returns empty gracefully")
    func corruptedFile() async throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("history.json")
        try "not valid json {{{".data(using: .utf8)!.write(to: file)

        let store = UsageHistoryStore(directory: dir)
        let loaded = try await store.load()
        #expect(loaded.isEmpty)
    }

    @Test("Persists across store instances")
    func persistsAcrossInstances() async throws {
        let dir = try makeTempDir()

        let store1 = UsageHistoryStore(directory: dir)
        try await store1.record(makePoint(fiveHour: 42.0))

        // New instance reads from same file
        let store2 = UsageHistoryStore(directory: dir)
        let loaded = try await store2.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].fiveHourUtilization == 42.0)
    }
}
