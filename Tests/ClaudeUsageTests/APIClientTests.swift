import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("AnthropicAPIClient")
struct APIClientTests {

    let usageFixture = """
    {
        "five_hour": { "utilization": 42.0, "resets_at": "2026-03-22T12:00:00+00:00" },
        "seven_day": { "utilization": 17.0, "resets_at": "2026-03-27T12:00:00+00:00" },
        "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
    }
    """.data(using: .utf8)!

    @Test("Sends correct headers and parses usage response")
    func fetchUsageSuccess() async throws {
        let mockSession = MockURLSession { request in
            // Verify request
            #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")

            return (self.usageFixture, HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }

        let client = AnthropicAPIClient(session: mockSession)
        let usage = try await client.fetchUsage(accessToken: "test-token")

        #expect(usage.fiveHour?.utilization == 42.0)
        #expect(usage.sevenDay?.utilization == 17.0)
    }

    @Test("Returns unauthorized error on 401")
    func fetchUsage401() async throws {
        let mockSession = MockURLSession { request in
            return (Data(), HTTPURLResponse(
                url: request.url!, statusCode: 401,
                httpVersion: nil, headerFields: nil)!)
        }

        let client = AnthropicAPIClient(session: mockSession)
        await #expect(throws: APIError.self) {
            try await client.fetchUsage(accessToken: "bad-token")
        }
    }

    @Test("Returns rateLimited error on 429 with retry-after")
    func fetchUsage429() async throws {
        let mockSession = MockURLSession { request in
            return (Data(), HTTPURLResponse(
                url: request.url!, statusCode: 429,
                httpVersion: nil, headerFields: ["Retry-After": "60"])!)
        }

        let client = AnthropicAPIClient(session: mockSession)
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected APIError.rateLimited")
        } catch let error as APIError {
            if case .rateLimited(let retryAfter) = error {
                #expect(retryAfter == 60)
            } else {
                Issue.record("Expected rateLimited, got \(error)")
            }
        }
    }

    @Test("Refreshes token successfully")
    func refreshToken() async throws {
        let mockSession = MockURLSession { request in
            #expect(request.url?.absoluteString == "https://platform.claude.com/v1/oauth/token")
            #expect(request.httpMethod == "POST")

            let response = """
            {
                "access_token": "new-access-token",
                "refresh_token": "new-refresh-token",
                "expires_in": 3600,
                "token_type": "bearer"
            }
            """.data(using: .utf8)!

            return (response, HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }

        let client = AnthropicAPIClient(session: mockSession)
        let result = try await client.refreshToken(refreshToken: "old-refresh")

        #expect(result.accessToken == "new-access-token")
        #expect(result.refreshToken == "new-refresh-token")
        #expect(result.expiresIn == 3600)
    }

    @Test("Returns error on refresh failure")
    func refreshTokenFails() async throws {
        let mockSession = MockURLSession { request in
            return (Data(), HTTPURLResponse(
                url: request.url!, statusCode: 400,
                httpVersion: nil, headerFields: nil)!)
        }

        let client = AnthropicAPIClient(session: mockSession)
        await #expect(throws: APIError.self) {
            try await client.refreshToken(refreshToken: "bad-token")
        }
    }

    // MARK: - Edge cases

    @Test("429 without Retry-After header returns nil retryAfter")
    func fetchUsage429NoRetryAfter() async throws {
        let mockSession = MockURLSession { _ in
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }

        let client = AnthropicAPIClient(session: mockSession)
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected rateLimited")
        } catch let error as APIError {
            if case .rateLimited(let retryAfter) = error {
                #expect(retryAfter == nil)
            } else {
                Issue.record("Expected rateLimited, got \(error)")
            }
        }
    }

    @Test("429 with non-numeric Retry-After returns nil retryAfter")
    func fetchUsage429InvalidRetryAfter() async throws {
        let mockSession = MockURLSession { _ in
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "not-a-number"])!)
        }

        let client = AnthropicAPIClient(session: mockSession)
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected rateLimited")
        } catch let error as APIError {
            if case .rateLimited(let retryAfter) = error {
                #expect(retryAfter == nil)
            } else {
                Issue.record("Expected rateLimited, got \(error)")
            }
        }
    }

    @Test("500 returns serverError")
    func fetchUsage500() async throws {
        let mockSession = MockURLSession { _ in
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }

        let client = AnthropicAPIClient(session: mockSession)
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected serverError")
        } catch let error as APIError {
            if case .serverError(let code) = error {
                #expect(code == 500)
            } else {
                Issue.record("Expected serverError, got \(error)")
            }
        }
    }

    @Test("200 with corrupted JSON throws decoding error")
    func fetchUsageCorruptedJSON() async throws {
        let mockSession = MockURLSession { _ in
            return ("not json".data(using: .utf8)!, HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let client = AnthropicAPIClient(session: mockSession)
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected decoding error")
        } catch {
            // DecodingError from JSONDecoder — not wrapped in APIError
            #expect(error is DecodingError)
        }
    }

    @Test("Network error wraps underlying error")
    func fetchUsageNetworkError() async throws {
        let mockSession = ThrowingMockSession(error: URLError(.notConnectedToInternet))

        let client = AnthropicAPIClient(session: mockSession)
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected networkError")
        } catch let error as APIError {
            if case .networkError = error {
                // correct
            } else {
                Issue.record("Expected networkError, got \(error)")
            }
        }
    }
}
