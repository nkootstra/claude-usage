import Foundation

public enum TokenRefreshingClientError: Error, Sendable {
    case noCredential
    case unauthorized
    case backoff(TimeInterval)
    case other(String)
}

public struct UsageFetchResult: Sendable {
    public let usage: UsageResponse
    public let backoff: TimeInterval?
}

/// Wraps AnthropicAPIClient with credential resolution, token retry, and backoff logic.
/// Keeps the ViewModel free from auth/retry concerns.
public final class TokenRefreshingClient: Sendable {
    private let apiClient: AnthropicAPIClient
    private let credentialProvider: CredentialProvider

    public init(apiClient: AnthropicAPIClient, credentialProvider: @escaping CredentialProvider) {
        self.apiClient = apiClient
        self.credentialProvider = credentialProvider
    }

    public func fetchUsage() async throws -> UsageFetchResult {
        var credential = try resolveCredential()

        // If expired, re-read (Claude Code may have refreshed it)
        if credential.isExpired {
            credential = try resolveCredential()
        }

        do {
            let usage = try await apiClient.fetchUsage(accessToken: credential.accessToken)
            return UsageFetchResult(usage: usage, backoff: nil)
        } catch let error as APIError {
            return try await handleAPIError(error, originalCredential: credential)
        }
    }

    private func resolveCredential() throws -> OAuthCredential {
        guard let credential = credentialProvider() else {
            throw TokenRefreshingClientError.noCredential
        }
        return credential
    }

    private func handleAPIError(
        _ error: APIError,
        originalCredential: OAuthCredential
    ) async throws -> UsageFetchResult {
        switch error {
        case .unauthorized:
            // Try re-reading credential (Claude Code may have refreshed the token)
            if let fresh = credentialProvider(), fresh.accessToken != originalCredential.accessToken {
                do {
                    let usage = try await apiClient.fetchUsage(accessToken: fresh.accessToken)
                    return UsageFetchResult(usage: usage, backoff: nil)
                } catch {
                    throw TokenRefreshingClientError.unauthorized
                }
            }
            throw TokenRefreshingClientError.unauthorized

        case .rateLimited(let retryAfter):
            throw TokenRefreshingClientError.backoff(retryAfter ?? 60)

        case .serverError(let code):
            throw TokenRefreshingClientError.other("Server error: \(code)")

        case .networkError(let underlying):
            throw TokenRefreshingClientError.other("Network error: \(underlying.localizedDescription)")

        case .invalidResponse:
            throw TokenRefreshingClientError.other("Invalid response")
        }
    }
}
