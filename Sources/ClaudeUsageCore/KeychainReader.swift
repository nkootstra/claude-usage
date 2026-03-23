import Foundation
import KeychainAccess

public enum KeychainReaderError: Error, Sendable {
    case noKeychainEntry
    case malformedJSON
    case missingAccessToken
}

public struct OAuthCredential: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Int64?
    public let subscriptionType: String?
    public let rateLimitTier: String?
    public let organizationUuid: String?

    /// Whether the access token has expired (expiresAt is epoch milliseconds)
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date().timeIntervalSince1970 * 1000 >= Double(expiresAt)
    }

    /// Parse from the raw Keychain JSON blob stored by Claude Code
    public static func fromKeychainData(_ data: Data) throws -> OAuthCredential {
        guard let topLevel = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KeychainReaderError.malformedJSON
        }

        guard let oauth = topLevel["claudeAiOauth"] as? [String: Any] else {
            throw KeychainReaderError.malformedJSON
        }

        guard let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty else {
            throw KeychainReaderError.missingAccessToken
        }

        return OAuthCredential(
            accessToken: accessToken,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: oauth["expiresAt"] as? Int64,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String,
            organizationUuid: topLevel["organizationUuid"] as? String
        )
    }

    /// Read credential: own keychain → file-based → Claude Code keychain (last resort).
    public static func fromKeychain() throws -> OAuthCredential {
        // 1. Try our own stored credential first (never triggers a keychain prompt)
        if let data = try? CredentialStore.keychain.getData("credentials") {
            if let credential = try? fromKeychainData(data) {
                return credential
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let filePaths = [
            home.appendingPathComponent(".claude/.credentials.json"),
            home.appendingPathComponent(".claude/credentials.json"),
        ]
        return try fromCredentialSources(filePaths: filePaths)
    }

    /// Read credential from file paths (tried in order). If none found, throws noKeychainEntry
    /// which triggers the sign-in UI.
    public static func fromCredentialSources(filePaths: [URL]) throws -> OAuthCredential {
        for path in filePaths {
            if let data = try? Data(contentsOf: path) {
                if let credential = try? fromKeychainData(data) {
                    return credential
                }
            }
        }
        throw KeychainReaderError.noKeychainEntry
    }
}

// MARK: - Credential Store (our own keychain entry via KeychainAccess)

public enum CredentialStore {
    nonisolated(unsafe) static let keychain = Keychain(
        service: "io.kootstra.claude-usage.credentials",
        accessGroup: "WQ8V5KRNUG.io.kootstra.claude-usage"
    )

    private static let signedOutKey = "io.kootstra.claude-usage.signedOut"

    /// Whether the user explicitly signed out (suppresses Claude Code keychain reads).
    public static var isSignedOut: Bool {
        get { UserDefaults.standard.bool(forKey: signedOutKey) }
        set { UserDefaults.standard.set(newValue, forKey: signedOutKey) }
    }

    public static func save(accessToken: String, refreshToken: String?, expiresIn: Int?) throws {
        let expiresAt = expiresIn.map { Int64(Date().timeIntervalSince1970 * 1000) + Int64($0) * 1000 }

        let json: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "refreshToken": refreshToken as Any,
                "expiresAt": expiresAt as Any,
            ] as [String: Any]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        try keychain.set(data, key: "credentials")
        // Clear signed-out flag so the app uses this credential
        isSignedOut = false
    }

    public static func delete() {
        try? keychain.remove("credentials")
        isSignedOut = true
    }
}
