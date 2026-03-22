import Foundation
import CryptoKit

public struct PKCEChallenge: Sendable {
    public let verifier: String
    public let challenge: String

    public static func generate() -> PKCEChallenge {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncoded()
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64URLEncoded()
        return PKCEChallenge(verifier: verifier, challenge: challenge)
    }
}

public struct OAuthFlow: Sendable {
    private static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    private static let scopes = "user:profile user:inference"

    private let session: any HTTPSession

    public init(session: any HTTPSession = URLSession.shared) {
        self.session = session
    }

    public static func authorizationURL(challenge: String, state: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "claude.ai"
        components.path = "/oauth/authorize"
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: ClaudeAPI.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        // Safe: all components are well-formed constants + user-provided base64url strings
        return components.url!
    }

    /// Parse "code#state" callback format
    public static func parseCallback(_ raw: String) -> (code: String, state: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hashIndex = trimmed.firstIndex(of: "#") else {
            return (trimmed, nil)
        }
        let code = String(trimmed[trimmed.startIndex..<hashIndex])
        let state = String(trimmed[trimmed.index(after: hashIndex)...])
        return (code, state.isEmpty ? nil : state)
    }

    public func exchangeCode(code: String, state: String, verifier: String) async throws -> TokenRefreshResponse {
        var request = URLRequest(url: ClaudeAPI.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": ClaudeAPI.clientId,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.unauthorized
        }

        return try JSONDecoder().decode(TokenRefreshResponse.self, from: data)
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
