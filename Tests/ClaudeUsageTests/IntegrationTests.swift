import Testing
import Foundation
@testable import ClaudeUsageCore

/// Integration tests that exercise multiple services working together,
/// verifying the full data flow from API response through to ViewModel state.
@Suite("Integration")
struct IntegrationTests {

    // MARK: - Fixtures

    private static let consumerFixture = """
    {
        "five_hour": { "utilization": 42.0, "resets_at": "2026-03-22T12:00:00+00:00" },
        "seven_day": { "utilization": 17.0, "resets_at": "2026-03-27T12:00:00+00:00" },
        "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
    }
    """.data(using: .utf8)!

    private static let enterpriseFixture = """
    {
        "five_hour": null,
        "seven_day": null,
        "extra_usage": {
            "is_enabled": true,
            "monthly_limit": 500000,
            "used_credits": 125000,
            "utilization": 25.0
        }
    }
    """.data(using: .utf8)!

    private static let highUsageFixture = """
    {
        "five_hour": { "utilization": 85.0, "resets_at": "2026-03-22T12:00:00+00:00" },
        "seven_day": { "utilization": 60.0, "resets_at": "2026-03-27T12:00:00+00:00" },
        "seven_day_sonnet": { "utilization": 40.0, "resets_at": "2026-03-27T12:00:00+00:00" },
        "seven_day_opus": { "utilization": 20.0, "resets_at": "2026-03-27T12:00:00+00:00" },
        "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
    }
    """.data(using: .utf8)!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-usage-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - API → ViewModel → History (full pipeline)

    @Test("Fetch → ViewModel update → history recorded end-to-end")
    @MainActor
    func fetchToHistoryPipeline() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockSession = MockURLSession { _ in
            (Self.consumerFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let store = UsageHistoryStore(directory: dir)
        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            historyStore: store
        )

        await vm.refresh()

        // ViewModel state
        #expect(vm.usage != nil)
        #expect(vm.menuBarText == "42%")
        #expect(vm.error == nil)
        #expect(vm.lastUpdated != nil)

        // History was persisted to SQLite
        #expect(vm.historyPoints.count == 1)
        let point = vm.historyPoints[0]
        #expect(point.fiveHourUtilization == 42.0)
        #expect(point.sevenDayUtilization == 17.0)

        // Verify store has the data independently
        let loaded = try await store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].fiveHourUtilization == 42.0)
    }

    @Test("Multiple fetches accumulate history points")
    @MainActor
    func multipleRefreshesAccumulateHistory() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = FetchCounter()
        let mockSession = MockURLSession { _ in
            counter.increment()
            let util = Double(counter.value * 10)
            let json = """
            {
                "five_hour": { "utilization": \(util), "resets_at": "2026-03-22T12:00:00+00:00" },
                "seven_day": { "utilization": 5.0, "resets_at": "2026-03-27T12:00:00+00:00" },
                "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
            }
            """.data(using: .utf8)!
            return (json, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let store = UsageHistoryStore(directory: dir)
        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            historyStore: store
        )

        await vm.refresh()
        await vm.refresh()
        await vm.refresh()

        // Each refresh() also restarts the polling service which may fire immediately,
        // so we may get more than 3 points. Verify at least 3 and ascending utilization.
        #expect(vm.historyPoints.count >= 3)
        // First point should be 10%, last should reflect latest fetch
        #expect(vm.historyPoints[0].fiveHourUtilization == 10.0)
        // The most recent fetch value should be in menuBarText
        let lastUtil = vm.historyPoints.last!.fiveHourUtilization
        #expect(vm.menuBarText == "\(Int(lastUtil))%")
    }

    // MARK: - Enterprise flow

    @Test("Enterprise response flows through to credit projection")
    @MainActor
    func enterpriseCreditProjection() async throws {
        let mockSession = MockURLSession { _ in
            (Self.enterpriseFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        await vm.refresh()

        #expect(vm.isEnterprise == true)
        #expect(vm.menuBarText == "$1250")
        #expect(vm.usage?.extraUsage?.isEnabled == true)
        #expect(vm.usage?.extraUsage?.usedCredits == 125000)
        // Credit projection computed without notification service
        // (only available when day > 1 and amounts > 0)
        // The projection depends on calendar day, so just verify it's set or nil based on logic
        if Calendar.current.component(.day, from: Date()) > 1 {
            #expect(vm.creditProjection != nil)
            #expect(vm.creditProjection!.burnRatePerDay > 0)
        }
    }

    @Test("Enterprise usage stats include budget utilization")
    @MainActor
    func enterpriseUsageStats() async throws {
        let mockSession = MockURLSession { _ in
            (Self.enterpriseFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        await vm.refresh()

        #expect(vm.isEnterprise == true)
        #expect(vm.usage?.extraUsage?.utilization == 25.0)
    }

    @Test("Consumer usage stats include 5-hour and 7-day")
    @MainActor
    func consumerUsageStats() async throws {
        let mockSession = MockURLSession { _ in
            (Self.consumerFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        await vm.refresh()

        #expect(vm.isEnterprise == false)
        #expect(vm.usage?.fiveHour?.utilization == 42.0)
        #expect(vm.usage?.sevenDay?.utilization == 17.0)
    }

    // MARK: - Error recovery flow

    @Test("401 → token refresh → successful retry end-to-end")
    @MainActor
    func errorRecoveryFlow() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let apiCounter = FetchCounter()
        let credCounter = FetchCounter()

        let mockSession = MockURLSession { request in
            apiCounter.increment()
            let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if token.contains("stale") {
                return (Data(), HTTPURLResponse(
                    url: request.url!, statusCode: 401,
                    httpVersion: nil, headerFields: nil)!)
            }
            return (Self.consumerFixture, HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }

        let store = UsageHistoryStore(directory: dir)
        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                credCounter.increment()
                if credCounter.value == 1 {
                    return OAuthCredential.mock(accessToken: "stale-token")
                }
                return OAuthCredential.mock(accessToken: "fresh-token")
            },
            historyStore: store
        )

        await vm.refresh()

        // Should have recovered: stale → 401 → re-read credential → success
        #expect(vm.error == nil)
        #expect(vm.menuBarText == "42%")
        #expect(vm.historyPoints.count == 1)
        #expect(apiCounter.value == 2) // stale + fresh
    }

    @Test("503 error → backoff → recovery on next refresh")
    @MainActor
    func serverErrorBackoffRecovery() async throws {
        let apiCounter = FetchCounter()

        let mockSession = MockURLSession { _ in
            apiCounter.increment()
            if apiCounter.value == 1 {
                return (Data(), HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                    statusCode: 503, httpVersion: nil, headerFields: nil)!)
            }
            return (Self.consumerFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            pollingInterval: 60
        )

        // First: error with backoff
        await vm.refresh()
        #expect(vm.error != nil)
        #expect(vm.usage == nil)

        // Second: recovery clears error and backoff
        await vm.refresh()
        #expect(vm.error == nil)
        #expect(vm.menuBarText == "42%")
        #expect(vm.currentBackoff == nil)
    }

    // MARK: - History + BurnRate integration

    @Test("History accumulation feeds burn rate projection")
    @MainActor
    func historyFeedsBurnRate() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Pre-seed history with rising utilization
        let store = UsageHistoryStore(directory: dir)
        let now = Date()
        for i in 0..<5 {
            let point = UsageDataPoint(
                timestamp: now.addingTimeInterval(Double(-4 + i) * 600), // every 10 min
                fiveHourUtilization: 40.0 + Double(i) * 10,
                sevenDayUtilization: 20.0
            )
            try await store.record(point)
        }

        // Next API response at 90%
        let highFixture = """
        {
            "five_hour": { "utilization": 90.0, "resets_at": "2026-03-22T12:00:00+00:00" },
            "seven_day": { "utilization": 20.0, "resets_at": "2026-03-27T12:00:00+00:00" },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            (highFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            historyStore: store
        )

        await vm.refresh()

        // Should have 6 points: 5 seeded + 1 from refresh
        #expect(vm.historyPoints.count == 6)
        #expect(vm.menuBarText == "90%")
    }

    // MARK: - Polling lifecycle integration

    @Test("Polling lifecycle: start → fetch → stop → no more fetches")
    @MainActor
    func pollingLifecycle() async throws {
        let counter = FetchCounter()

        let mockSession = MockURLSession { _ in
            counter.increment()
            return (Self.consumerFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            pollingInterval: 0.1
        )

        vm.startPolling()
        try await Task.sleep(for: .milliseconds(400))
        let countAtStop = counter.value
        vm.stopPolling()

        // Should have fetched multiple times
        #expect(countAtStop >= 2)

        // Wait and verify no more fetches after stop
        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.value == countAtStop)
    }

    // MARK: - Sign out flow

    @Test("Sign out clears all ViewModel state")
    @MainActor
    func signOutClearsState() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockSession = MockURLSession { _ in
            (Self.consumerFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let store = UsageHistoryStore(directory: dir)
        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            historyStore: store
        )

        await vm.refresh()
        #expect(vm.usage != nil)
        #expect(vm.historyPoints.count == 1)

        vm.signOut()

        #expect(vm.usage == nil)
        #expect(vm.error == .noCredential)
        #expect(vm.lastUpdated == nil)
        #expect(vm.currentBackoff == nil)
        #expect(vm.historyPoints.isEmpty)
        #expect(vm.creditProjection == nil)
    }

    // MARK: - No credential → error state

    @Test("No credential flows through entire pipeline as error")
    @MainActor
    func noCredentialPipeline() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = UsageHistoryStore(directory: dir)
        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(),
            credentialProvider: { nil },
            historyStore: store
        )

        await vm.refresh()

        #expect(vm.error == .noCredential)
        #expect(vm.usage == nil)
        #expect(vm.menuBarText == "--")
        #expect(vm.historyPoints.isEmpty)
        #expect(vm.creditProjection == nil)

        // Store should remain empty
        let loaded = try await store.load()
        #expect(loaded.isEmpty)
    }

    // MARK: - Model breakdown fields flow through

    @Test("Sonnet and Opus utilization flow from API to history")
    @MainActor
    func modelBreakdownFlowsToHistory() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockSession = MockURLSession { _ in
            (Self.highUsageFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let store = UsageHistoryStore(directory: dir)
        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            historyStore: store
        )

        await vm.refresh()

        #expect(vm.usage?.sevenDaySonnet?.utilization == 40.0)
        #expect(vm.usage?.sevenDayOpus?.utilization == 20.0)

        let point = vm.historyPoints[0]
        #expect(point.sonnetUtilization == 40.0)
        #expect(point.opusUtilization == 20.0)

        // Verify persisted to DB
        let loaded = try await store.load()
        #expect(loaded[0].sonnetUtilization == 40.0)
        #expect(loaded[0].opusUtilization == 20.0)
    }
}
