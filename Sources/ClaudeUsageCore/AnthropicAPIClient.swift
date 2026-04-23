import Foundation

public enum APIError: Error, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case networkError(any Error)
    case invalidResponse
}

/// Protocol for URLSession to enable testing
public protocol HTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSession {}

public struct TokenRefreshResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

public final class AnthropicAPIClient: Sendable {
    private let session: any HTTPSession
    private let baseURL: String

    public init(
        session: any HTTPSession = URLSession.shared,
        baseURL: String = "https://api.anthropic.com"
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchUsage(accessToken: String) async throws -> UsageResponse {
        guard let url = URL(string: "\(baseURL)/api/oauth/usage") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(ClaudeAPI.betaHeader, forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        default:
            throw APIError.serverError(http.statusCode)
        }
    }

    public func fetchProfile(accessToken: String) async throws -> ProfileResponse {
        guard let url = URL(string: "\(baseURL)/api/oauth/profile") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ClaudeAPI.betaHeader, forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(ProfileResponse.self, from: data)
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        default:
            throw APIError.serverError(http.statusCode)
        }
    }

    public func refreshToken(refreshToken: String) async throws -> TokenRefreshResponse {
        var request = URLRequest(url: ClaudeAPI.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(ClaudeAPI.clientId)"
        request.httpBody = body.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.serverError(http.statusCode)
        }

        return try JSONDecoder().decode(TokenRefreshResponse.self, from: data)
    }
}
