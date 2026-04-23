import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("UsageViewModel")
struct UsageViewModelTests {

    @Test("Shows percentage from successful fetch")
    @MainActor
    func successfulFetch() async throws {
        let fixture = """
        {
            "five_hour": { "utilization": 42.0, "resets_at": "2026-03-22T12:00:00+00:00" },
            "seven_day": { "utilization": 17.0, "resets_at": "2026-03-27T12:00:00+00:00" },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            return (fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        await vm.refresh()

        #expect(vm.menuBarText == "42%")
        #expect(vm.usage?.fiveHour?.utilization == 42.0)
        #expect(vm.usage?.sevenDay?.utilization == 17.0)
        #expect(vm.error == nil)
    }

    @Test("Shows dash when no credential available")
    @MainActor
    func noCredential() async throws {
        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(),
            credentialProvider: { nil }
        )

        await vm.refresh()

        #expect(vm.menuBarText == "--")
        #expect(vm.usage == nil)
    }

    @Test("Shows dash when API returns error")
    @MainActor
    func apiError() async throws {
        let mockSession = MockURLSession { _ in
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        await vm.refresh()

        #expect(vm.menuBarText == "--")
        #expect(vm.error != nil)
    }

    @Test("Re-reads keychain when token is expired")
    @MainActor
    func reReadsKeychainOnExpiry() async throws {
        let expiredMs = Int64(Date().timeIntervalSince1970 * 1000) - 1000
        let counter = FetchCounter()

        let fixture = """
        {
            "five_hour": { "utilization": 5.0, "resets_at": "2026-03-22T12:00:00+00:00" },
            "seven_day": null,
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            return (fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                counter.increment()
                // First call returns expired, second returns fresh
                if counter.value == 1 {
                    return OAuthCredential.mock(
                        accessToken: "expired-token",
                        expiresAt: expiredMs
                    )
                }
                return OAuthCredential.mock(
                    accessToken: "fresh-token",
                    expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000
                )
            }
        )

        await vm.refresh()

        // credentialProvider called for: stale usage fetch, fresh usage re-read, profile fetch
        #expect(counter.value >= 2)
        #expect(vm.menuBarText == "5%")
    }

    @Test("Retries with fresh token on 401")
    @MainActor
    func retriesOn401() async throws {
        let counter = FetchCounter()
        let fixture = """
        {
            "five_hour": { "utilization": 99.0, "resets_at": "2026-03-22T12:00:00+00:00" },
            "seven_day": null,
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let apiCounter = FetchCounter()
        let mockSession = MockURLSession { request in
            let path = request.url?.path ?? ""
            if path.contains("/profile") {
                return (Data(), HTTPURLResponse(
                    url: request.url!, statusCode: 500,
                    httpVersion: nil, headerFields: nil)!)
            }
            apiCounter.increment()
            let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
            // First call with stale token → 401, second with fresh → 200
            if token.contains("stale") {
                return (Data(), HTTPURLResponse(
                    url: request.url!, statusCode: 401,
                    httpVersion: nil, headerFields: nil)!)
            }
            return (fixture, HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                counter.increment()
                if counter.value == 1 {
                    return OAuthCredential.mock(accessToken: "stale-token")
                }
                return OAuthCredential.mock(accessToken: "fresh-token")
            }
        )

        await vm.refresh()

        #expect(vm.menuBarText == "99%")
        #expect(apiCounter.value == 2) // tried stale, then fresh
    }

    @Test("Backs off on 429 then resets on success")
    @MainActor
    func backoffAndReset() async throws {
        let apiCounter = FetchCounter()
        let fixture = """
        {
            "five_hour": { "utilization": 10.0, "resets_at": "2026-03-22T12:00:00+00:00" },
            "seven_day": null,
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            apiCounter.increment()
            // First call → 429 with Retry-After, second → 200
            if apiCounter.value == 1 {
                return (Data(), HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                    statusCode: 429, httpVersion: nil,
                    headerFields: ["Retry-After": "1"])!)
            }
            return (fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            pollingInterval: 0.1
        )

        // First refresh → 429, should set error and backoff
        await vm.refresh()
        #expect(vm.error != nil)
        #expect((vm.currentBackoff ?? 0) > 0.1) // backed off beyond normal interval

        // Second refresh → 200, should reset backoff
        await vm.refresh()
        #expect(vm.error == nil)
        #expect(vm.menuBarText == "10%")
        #expect(vm.currentBackoff == nil) // reset
    }

    @Test("Starts polling and updates on interval")
    @MainActor
    func polling() async throws {
        let counter = FetchCounter()
        let fixture = """
        {
            "five_hour": { "utilization": 10.0, "resets_at": "2026-03-22T12:00:00+00:00" },
            "seven_day": { "utilization": 5.0, "resets_at": "2026-03-27T12:00:00+00:00" },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            counter.increment()
            return (fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            pollingInterval: 0.1
        )

        vm.startPolling()
        try await Task.sleep(for: .milliseconds(600))
        vm.stopPolling()

        // Should have fetched at least 2 times (immediate + 1 timer fire)
        // CI runners can be slow, so we keep the threshold low
        #expect(counter.value >= 2)
        #expect(vm.menuBarText == "10%")
    }

    // MARK: - Edge cases

    @Test("menuBarText shows -- when fiveHour bucket is nil")
    @MainActor
    func menuBarTextNilFiveHour() async throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": { "utilization": 50.0, "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            return (json, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        await vm.refresh()
        #expect(vm.menuBarText == "--")
        #expect(vm.usage?.sevenDay?.utilization == 50.0)
    }

    @Test("Backoff caps at 120 seconds")
    @MainActor
    func backoffCap() async throws {
        let mockSession = MockURLSession { _ in
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            pollingInterval: 30
        )

        // Trigger multiple failures to escalate backoff
        for _ in 0..<10 {
            await vm.refresh()
        }

        // Should never exceed 120
        #expect((vm.currentBackoff ?? 0) <= 120)
        #expect((vm.currentBackoff ?? 0) > 0)
    }

    @Test("startPolling called twice cancels previous polling")
    @MainActor
    func doubleStartPolling() async throws {
        let counter = FetchCounter()
        let fixture = """
        {
            "five_hour": { "utilization": 5.0, "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            counter.increment()
            return (fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            pollingInterval: 0.1
        )

        vm.startPolling()
        try await Task.sleep(for: .milliseconds(100))
        vm.startPolling() // should cancel first, start fresh
        try await Task.sleep(for: .milliseconds(500))
        vm.stopPolling()

        // Should still have gotten results (not deadlocked/crashed)
        #expect(vm.menuBarText == "5%")
    }

    @Test("Records history point on successful fetch")
    @MainActor
    func recordsHistory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-usage-vm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fixture = """
        {
            "five_hour": { "utilization": 42.0, "resets_at": "2026-03-22T12:00:00+00:00" },
            "seven_day": { "utilization": 17.0, "resets_at": "2026-03-27T12:00:00+00:00" },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            return (fixture, HTTPURLResponse(
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

        #expect(vm.historyPoints.count == 1)
        #expect(vm.historyPoints[0].fiveHourUtilization == 42.0)
        #expect(vm.historyPoints[0].sevenDayUtilization == 17.0)
    }

    @Test("Successful refresh clears previous error")
    @MainActor
    func successClearsPreviousError() async throws {
        let apiCounter = FetchCounter()
        let fixture = """
        {
            "five_hour": { "utilization": 20.0, "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            apiCounter.increment()
            if apiCounter.value == 1 {
                return (Data(), HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                    statusCode: 503, httpVersion: nil, headerFields: nil)!)
            }
            return (fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        await vm.refresh()
        #expect(vm.error != nil)

        await vm.refresh()
        #expect(vm.error == nil)
        #expect(vm.menuBarText == "20%")
        #expect(vm.currentBackoff == nil)
    }
}

// Test helper
extension OAuthCredential {
    static func mock(
        accessToken: String = "test-token",
        refreshToken: String? = nil,
        expiresAt: Int64? = nil,
        subscriptionType: String? = "pro"
    ) -> OAuthCredential {
        OAuthCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            subscriptionType: subscriptionType,
            rateLimitTier: nil,
            organizationUuid: nil
        )
    }
}
