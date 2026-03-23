import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("TokenRefreshingClient")
struct TokenRefreshingClientTests {

    let fixture = """
    {
        "five_hour": { "utilization": 42.0, "resets_at": "2026-03-22T12:00:00+00:00" },
        "seven_day": null,
        "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
    }
    """.data(using: .utf8)!

    @Test("Fetches with valid token on first try")
    func happyPath() async throws {
        let mockSession = MockURLSession { _ in
            return (self.fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "valid") }
        )

        let result = try await client.fetchUsage()
        #expect(result.usage.fiveHour?.utilization == 42.0)
        #expect(result.backoff == nil)
    }

    @Test("Re-reads credential when token is expired before calling API")
    func reReadsOnExpiry() async throws {
        let counter = FetchCounter()

        let mockSession = MockURLSession { _ in
            return (self.fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let expiredMs = Int64(Date().timeIntervalSince1970 * 1000) - 1000

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                counter.increment()
                if counter.value == 1 {
                    return OAuthCredential.mock(accessToken: "expired", expiresAt: expiredMs)
                }
                return OAuthCredential.mock(accessToken: "fresh")
            }
        )

        let result = try await client.fetchUsage()
        #expect(counter.value == 2)
        #expect(result.usage.fiveHour?.utilization == 42.0)
    }

    @Test("Retries with fresh credential on 401")
    func retriesOn401() async throws {
        let counter = FetchCounter()
        let apiCounter = FetchCounter()

        let mockSession = MockURLSession { request in
            apiCounter.increment()
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth.contains("stale") {
                return (Data(), HTTPURLResponse(
                    url: request.url!, statusCode: 401,
                    httpVersion: nil, headerFields: nil)!)
            }
            return (self.fixture, HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                counter.increment()
                if counter.value == 1 { return OAuthCredential.mock(accessToken: "stale") }
                return OAuthCredential.mock(accessToken: "fresh")
            }
        )

        let result = try await client.fetchUsage()
        #expect(apiCounter.value == 2)
        #expect(result.usage.fiveHour?.utilization == 42.0)
    }

    @Test("Returns backoff on 429 with Retry-After")
    func backoffOn429() async throws {
        let mockSession = MockURLSession { _ in
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "120"])!)
        }

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        do {
            _ = try await client.fetchUsage()
            Issue.record("Expected error")
        } catch let error as TokenRefreshingClientError {
            if case .backoff(let interval) = error {
                #expect(interval == 120)
            } else {
                Issue.record("Expected backoff, got \(error)")
            }
        }
    }

    @Test("Throws noCredential when provider returns nil")
    func noCredential() async throws {
        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(),
            credentialProvider: { nil }
        )

        await #expect(throws: TokenRefreshingClientError.self) {
            try await client.fetchUsage()
        }
    }

    // MARK: - Edge cases

    @Test("Provider returns same expired token twice — still calls API")
    func sameExpiredTokenTwice() async throws {
        let expiredMs = Int64(Date().timeIntervalSince1970 * 1000) - 1000

        let mockSession = MockURLSession { _ in
            return (self.fixture, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                // Always returns expired token — still usable if API accepts it
                OAuthCredential.mock(accessToken: "expired", expiresAt: expiredMs)
            }
        )

        // Should still attempt the API call with the expired token
        let result = try await client.fetchUsage()
        #expect(result.usage.fiveHour?.utilization == 42.0)
    }

    @Test("Fresh token also gets 401 — throws unauthorized")
    func freshTokenAlso401() async throws {
        let counter = FetchCounter()

        let mockSession = MockURLSession { _ in
            // Always returns 401 regardless of token
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                counter.increment()
                // Return different tokens each time
                return OAuthCredential.mock(accessToken: "token-\(counter.value)")
            }
        )

        do {
            _ = try await client.fetchUsage()
            Issue.record("Expected unauthorized")
        } catch let error as TokenRefreshingClientError {
            if case .unauthorized = error {
                // Correct — gave up after retry
            } else {
                Issue.record("Expected unauthorized, got \(error)")
            }
        }
    }

    @Test("Server error results in .other error")
    func serverError() async throws {
        let mockSession = MockURLSession { _ in
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        do {
            _ = try await client.fetchUsage()
            Issue.record("Expected other error")
        } catch let error as TokenRefreshingClientError {
            if case .other(let msg) = error {
                #expect(msg.contains("503"))
            } else {
                Issue.record("Expected other, got \(error)")
            }
        }
    }

    @Test("429 without Retry-After defaults to 60s backoff")
    func backoffDefaultsTo60() async throws {
        let mockSession = MockURLSession { _ in
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: { OAuthCredential.mock(accessToken: "token") }
        )

        do {
            _ = try await client.fetchUsage()
            Issue.record("Expected backoff")
        } catch let error as TokenRefreshingClientError {
            if case .backoff(let interval) = error {
                #expect(interval == 60)
            } else {
                Issue.record("Expected backoff, got \(error)")
            }
        }
    }

    @Test("Refreshes own token via refresh endpoint when expired and refresh token exists")
    func refreshesOwnTokenOnExpiry() async throws {
        let expiredMs = Int64(Date().timeIntervalSince1970 * 1000) - 1000
        let apiCounter = FetchCounter()

        let mockSession = MockURLSession { request in
            apiCounter.increment()
            let urlPath = request.url?.path ?? ""

            // Token refresh endpoint
            if urlPath.contains("/oauth/token") {
                let refreshResponse = """
                {
                    "access_token": "refreshed-token",
                    "refresh_token": "new-refresh",
                    "expires_in": 3600,
                    "token_type": "Bearer"
                }
                """.data(using: .utf8)!
                return (refreshResponse, HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!)
            }

            // Usage endpoint
            return (self.fixture, HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }

        let credentialCounter = FetchCounter()

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                credentialCounter.increment()
                if credentialCounter.value <= 1 {
                    // First call: return expired token with refresh token
                    return OAuthCredential.mock(
                        accessToken: "expired",
                        refreshToken: "my-refresh-token",
                        expiresAt: expiredMs
                    )
                }
                // After refresh: CredentialStore.save was called, return the refreshed token
                return OAuthCredential.mock(accessToken: "refreshed-token")
            }
        )

        let result = try await client.fetchUsage()
        // Should have called: 1) token refresh endpoint, 2) usage endpoint
        #expect(apiCounter.value == 2)
        #expect(result.usage.fiveHour?.utilization == 42.0)
    }

    @Test("On 401, tries token refresh before re-reading credential provider")
    func refreshesOnUnauthorized() async throws {
        let apiCounter = FetchCounter()

        let mockSession = MockURLSession { request in
            apiCounter.increment()
            let urlPath = request.url?.path ?? ""

            // Token refresh endpoint
            if urlPath.contains("/oauth/token") {
                let refreshResponse = """
                {
                    "access_token": "refreshed-token",
                    "refresh_token": "new-refresh",
                    "expires_in": 3600,
                    "token_type": "Bearer"
                }
                """.data(using: .utf8)!
                return (refreshResponse, HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!)
            }

            // Usage endpoint — first call returns 401, subsequent calls succeed
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth.contains("stale") {
                return (Data(), HTTPURLResponse(
                    url: request.url!, statusCode: 401,
                    httpVersion: nil, headerFields: nil)!)
            }
            return (self.fixture, HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }

        let credentialCounter = FetchCounter()

        let client = TokenRefreshingClient(
            apiClient: AnthropicAPIClient(session: mockSession),
            credentialProvider: {
                credentialCounter.increment()
                if credentialCounter.value <= 1 {
                    return OAuthCredential.mock(
                        accessToken: "stale",
                        refreshToken: "my-refresh-token"
                    )
                }
                return OAuthCredential.mock(accessToken: "refreshed-token")
            }
        )

        let result = try await client.fetchUsage()
        // Should have called: 1) usage (401), 2) token refresh, 3) usage (200)
        #expect(apiCounter.value == 3)
        #expect(result.usage.fiveHour?.utilization == 42.0)
    }
}
