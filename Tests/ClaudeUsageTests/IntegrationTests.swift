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
        let apiCounter = FetchCounter()
        let credCounter = FetchCounter()

        let mockSession = MockURLSession { request in
            let path = request.url?.path ?? ""
            if path.contains("/profile") {
                return (Data(), HTTPURLResponse(
                    url: request.url!, statusCode: 500,
                    httpVersion: nil, headerFields: nil)!)
            }
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

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                credCounter.increment()
                if credCounter.value == 1 {
                    return OAuthCredential.mock(accessToken: "stale-token")
                }
                return OAuthCredential.mock(accessToken: "fresh-token")
            }
        )

        await vm.refresh()

        #expect(vm.error == nil)
        #expect(vm.menuBarText == "42%")
        #expect(apiCounter.value == 2)
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

        await vm.refresh()
        #expect(vm.error != nil)
        #expect(vm.usage == nil)

        await vm.refresh()
        #expect(vm.error == nil)
        #expect(vm.menuBarText == "42%")
        #expect(vm.currentBackoff == nil)
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

        #expect(countAtStop >= 2)

        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.value == countAtStop)
    }

    // MARK: - Sign out flow

    @Test("Sign out clears all ViewModel state")
    @MainActor
    func signOutClearsState() async throws {
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
        #expect(vm.usage != nil)

        vm.signOut()

        #expect(vm.usage == nil)
        #expect(vm.error == .noCredential)
        #expect(vm.lastUpdated == nil)
        #expect(vm.currentBackoff == nil)
        #expect(vm.creditProjection == nil)
    }

    // MARK: - No credential → error state

    @Test("No credential flows through entire pipeline as error")
    @MainActor
    func noCredentialPipeline() async throws {
        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(),
            credentialProvider: { nil }
        )

        await vm.refresh()

        #expect(vm.error == .noCredential)
        #expect(vm.usage == nil)
        #expect(vm.menuBarText == "--")
        #expect(vm.creditProjection == nil)
    }

    // MARK: - Model breakdown fields flow through

    @Test("Sonnet and Opus utilization flow from API to ViewModel")
    @MainActor
    func modelBreakdownFlowsThrough() async throws {
        let mockSession = MockURLSession { _ in
            (Self.highUsageFixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let vm = UsageViewModel(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        await vm.refresh()

        #expect(vm.usage?.sevenDaySonnet?.utilization == 40.0)
        #expect(vm.usage?.sevenDayOpus?.utilization == 20.0)
    }
}
