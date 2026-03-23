import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("PollingService")
struct PollingServiceTests {

    @MainActor
    private func makeService(
        session: MockURLSession,
        pollingInterval: TimeInterval = 0.1
    ) -> (PollingService, AnthropicAPIClient) {
        let apiClient = AnthropicAPIClient(session: session)
        let client = TokenRefreshingClient(
            apiClient: apiClient,
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )
        let service = PollingService(client: client, pollingInterval: pollingInterval)
        return (service, apiClient)
    }

    @Test("Start fires immediately and delivers result")
    @MainActor
    func startFiresImmediately() async throws {
        let fixture = """
        {
            "five_hour": { "utilization": 42.0, "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            return (fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let (service, _) = makeService(session: mockSession)
        var receivedResult: UsageFetchResult?

        service.onResult = { @MainActor result in
            if case .success(let fetch) = result {
                receivedResult = fetch
            }
        }

        service.start(fireImmediately: true)
        try await Task.sleep(for: .milliseconds(200))
        service.stop()

        #expect(receivedResult?.usage.fiveHour?.utilization == 42.0)
    }

    @Test("Stop cancels polling")
    @MainActor
    func stopCancelsPolling() async throws {
        let counter = FetchCounter()
        let fixture = """
        {
            "five_hour": { "utilization": 10.0, "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            counter.increment()
            return (fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let (service, _) = makeService(session: mockSession)
        service.onResult = { @MainActor _ in }

        service.start(fireImmediately: true)
        try await Task.sleep(for: .milliseconds(50))
        service.stop()

        let countAfterStop = counter.value
        try await Task.sleep(for: .milliseconds(300))

        // No additional fetches after stop
        #expect(counter.value == countAfterStop)
    }

    @Test("Backoff caps at 120")
    @MainActor
    func backoffCap() async throws {
        let service = PollingService(
            client: TokenRefreshingClient(
                apiClient: AnthropicAPIClient(),
                credentialProvider: { nil }
            ),
            pollingInterval: 30
        )

        for _ in 0..<15 {
            service.applyBackoff(baseInterval: 30)
        }

        #expect((service.currentBackoff ?? 0) <= 120)
        #expect((service.currentBackoff ?? 0) > 0)
    }

    @Test("resetBackoff clears backoff")
    @MainActor
    func resetBackoffClears() async throws {
        let service = PollingService(
            client: TokenRefreshingClient(
                apiClient: AnthropicAPIClient(),
                credentialProvider: { nil }
            ),
            pollingInterval: 300
        )

        service.applyBackoff(baseInterval: 300)
        #expect(service.currentBackoff != nil)

        service.resetBackoff()
        #expect(service.currentBackoff == nil)
    }

    @Test("updateInterval restarts polling")
    @MainActor
    func updateIntervalRestarts() async throws {
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

        let (service, _) = makeService(session: mockSession, pollingInterval: 10)
        service.onResult = { @MainActor _ in }

        service.start(fireImmediately: true)
        try await Task.sleep(for: .milliseconds(100))
        let countBefore = counter.value

        // Change to fast interval
        service.updateInterval(0.05)
        try await Task.sleep(for: .milliseconds(300))
        service.stop()

        // Should have fetched more times after interval change
        #expect(counter.value > countBefore)
    }
}
