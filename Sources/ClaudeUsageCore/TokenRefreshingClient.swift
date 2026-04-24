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

/// Wraps AnthropicAPIClient with credential resolution, token refresh, and backoff logic.
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

        // If expired, try to refresh the token via the OAuth endpoint first,
        // then fall back to re-reading the credential provider (Claude Code may have refreshed it).
        if credential.isExpired {
            if let refreshed = await refreshOwnToken(credential) {
                credential = refreshed
            } else {
                let reread = try resolveCredential()
                // If re-read returns the same (still-expired) token, sending it
                // to the API just burns a request on a known-dead credential —
                // and the server often responds with 429, trapping us in a
                // backoff loop. Surface as unauthorized so the UI can prompt
                // re-auth instead.
                if reread.accessToken == credential.accessToken && reread.isExpired {
                    throw TokenRefreshingClientError.unauthorized
                }
                credential = reread
            }
        }

        do {
            let usage = try await apiClient.fetchUsage(accessToken: credential.accessToken)
            return UsageFetchResult(usage: usage, backoff: nil)
        } catch let error as APIError {
            return try await handleAPIError(error, originalCredential: credential)
        }
    }

    public func fetchProfile() async throws -> ProfileResponse {
        var credential = try resolveCredential()
        if credential.isExpired {
            if let refreshed = await refreshOwnToken(credential) {
                credential = refreshed
            } else {
                credential = try resolveCredential()
            }
        }
        do {
            return try await apiClient.fetchProfile(accessToken: credential.accessToken)
        } catch APIError.unauthorized {
            if let refreshed = await refreshOwnToken(credential) {
                return try await apiClient.fetchProfile(accessToken: refreshed.accessToken)
            }
            throw TokenRefreshingClientError.unauthorized
        }
    }

    private func resolveCredential() throws -> OAuthCredential {
        guard let credential = credentialProvider() else {
            throw TokenRefreshingClientError.noCredential
        }
        return credential
    }

    /// Attempt to refresh our own OAuth token using the refresh_token grant.
    /// Returns the new credential on success, nil if there's no refresh token or the refresh fails.
    private func refreshOwnToken(_ credential: OAuthCredential) async -> OAuthCredential? {
        guard let refreshToken = credential.refreshToken else { return nil }

        do {
            let response = try await apiClient.refreshToken(refreshToken: refreshToken)
            try CredentialStore.save(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken ?? refreshToken,
                expiresIn: response.expiresIn
            )
            // Re-read from store so the credential is fully formed
            return credentialProvider()
        } catch APIError.unauthorized {
            // Refresh token was rejected — drop it so we don't retry forever.
            CredentialStore.clearStoredCredential()
            return nil
        } catch APIError.serverError(let code) where code == 400 {
            // 400 on the refresh_token grant means the token itself is invalid.
            CredentialStore.clearStoredCredential()
            return nil
        } catch {
            return nil
        }
    }

    private func handleAPIError(
        _ error: APIError,
        originalCredential: OAuthCredential
    ) async throws -> UsageFetchResult {
        switch error {
        case .unauthorized:
            // Try refreshing our own token first
            if let refreshed = await refreshOwnToken(originalCredential) {
                do {
                    let usage = try await apiClient.fetchUsage(accessToken: refreshed.accessToken)
                    return UsageFetchResult(usage: usage, backoff: nil)
                } catch {
                    throw TokenRefreshingClientError.unauthorized
                }
            }
            // Fall back to re-reading credential (Claude Code may have refreshed the token)
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
