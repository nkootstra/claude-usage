import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("OAuth PKCE Flow")
struct OAuthFlowTests {

    @Test("Generates valid PKCE verifier and challenge")
    func pkceGeneration() throws {
        let pkce = PKCEChallenge.generate()

        // Verifier should be base64url, 43+ chars
        #expect(pkce.verifier.count >= 43)
        #expect(!pkce.verifier.contains("+"))
        #expect(!pkce.verifier.contains("/"))
        #expect(!pkce.verifier.contains("="))

        // Challenge should also be base64url
        #expect(pkce.challenge.count >= 43)
        #expect(!pkce.challenge.contains("+"))
        #expect(!pkce.challenge.contains("/"))
        #expect(!pkce.challenge.contains("="))

        // Verifier and challenge should differ
        #expect(pkce.verifier != pkce.challenge)
    }

    @Test("Builds correct authorization URL")
    func authorizationURL() throws {
        let pkce = PKCEChallenge.generate()
        let url = OAuthFlow.authorizationURL(challenge: pkce.challenge, state: "test-state")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let queryItems = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        #expect(components.host == "claude.ai")
        #expect(components.path == "/oauth/authorize")
        #expect(queryItems["client_id"] == "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        #expect(queryItems["response_type"] == "code")
        #expect(queryItems["code_challenge"] == pkce.challenge)
        #expect(queryItems["code_challenge_method"] == "S256")
        #expect(queryItems["state"] == "test-state")
        #expect(queryItems["scope"]?.contains("user:inference") == true)
    }

    @Test("Exchanges code for token")
    func tokenExchange() async throws {
        let mockSession = MockURLSession { request in
            let response = """
            {
                "access_token": "new-token",
                "refresh_token": "new-refresh",
                "expires_in": 3600,
                "token_type": "bearer"
            }
            """.data(using: .utf8)!

            return (response, HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }

        let flow = OAuthFlow(session: mockSession)
        let result = try await flow.exchangeCode(
            code: "auth-code",
            state: "state-123",
            verifier: "verifier-abc"
        )

        #expect(result.accessToken == "new-token")
        #expect(result.refreshToken == "new-refresh")
    }

    @Test("Parses code#state format from callback")
    func parseCallback() throws {
        let (code, state) = OAuthFlow.parseCallback("abc123#state456")
        #expect(code == "abc123")
        #expect(state == "state456")
    }

    @Test("Parses code-only format from callback")
    func parseCallbackCodeOnly() throws {
        let (code, state) = OAuthFlow.parseCallback("abc123")
        #expect(code == "abc123")
        #expect(state == nil)
    }

    // MARK: - Edge cases

    @Test("Parses empty callback string")
    func parseEmptyCallback() throws {
        let (code, state) = OAuthFlow.parseCallback("")
        #expect(code == "")
        #expect(state == nil)
    }

    @Test("Parses callback with multiple # characters")
    func parseCallbackMultipleHashes() throws {
        let (code, state) = OAuthFlow.parseCallback("code#state#extra")
        #expect(code == "code")
        #expect(state == "state#extra")
    }

    @Test("Trims whitespace from callback")
    func parseCallbackWhitespace() throws {
        let (code, state) = OAuthFlow.parseCallback("  abc123#state456  ")
        #expect(code == "abc123")
        #expect(state == "state456")
    }

    @Test("Parses callback where code is empty but state exists")
    func parseCallbackEmptyCode() throws {
        let (code, state) = OAuthFlow.parseCallback("#state456")
        #expect(code == "")
        #expect(state == "state456")
    }

    @Test("Each PKCE generation is unique")
    func pkceUniqueness() throws {
        let a = PKCEChallenge.generate()
        let b = PKCEChallenge.generate()
        #expect(a.verifier != b.verifier)
        #expect(a.challenge != b.challenge)
    }

    @Test("Token exchange throws on non-200 response")
    func tokenExchangeFailure() async throws {
        let mockSession = MockURLSession { _ in
            return (Data(), HTTPURLResponse(
                url: URL(string: "https://platform.claude.com/v1/oauth/token")!,
                statusCode: 400, httpVersion: nil, headerFields: nil)!)
        }

        let flow = OAuthFlow(session: mockSession)
        await #expect(throws: APIError.self) {
            try await flow.exchangeCode(code: "bad", state: "s", verifier: "v")
        }
    }

    @Test("Token exchange throws on malformed JSON response")
    func tokenExchangeMalformedResponse() async throws {
        let mockSession = MockURLSession { _ in
            return ("not json".data(using: .utf8)!, HTTPURLResponse(
                url: URL(string: "https://platform.claude.com/v1/oauth/token")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let flow = OAuthFlow(session: mockSession)
        do {
            _ = try await flow.exchangeCode(code: "code", state: "s", verifier: "v")
            Issue.record("Expected decoding error")
        } catch {
            #expect(error is DecodingError)
        }
    }
}
