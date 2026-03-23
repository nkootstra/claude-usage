import Foundation
import Security
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

    /// Read credential from file-based sources first, then keychain as backup.
    public static func fromKeychain() throws -> OAuthCredential {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let filePaths = [
            home.appendingPathComponent(".claude/.credentials.json"),
            home.appendingPathComponent(".claude/credentials.json"),
        ]
        return try fromCredentialSources(filePaths: filePaths)
    }

    /// Read credential from the given file paths (tried in order), then keychain as backup.
    public static func fromCredentialSources(filePaths: [URL]) throws -> OAuthCredential {
        // Try file-based credential sources first (no keychain prompt)
        for path in filePaths {
            if let data = try? Data(contentsOf: path) {
                if let credential = try? fromKeychainData(data) {
                    return credential
                }
            }
        }
        // Fall back to Claude Code keychain entry
        if let data = readClaudeCodeKeychain() {
            return try fromKeychainData(data)
        }
        // Fall back to our own stored credential
        if let data = try? CredentialStore.keychain.getData("credentials") {
            return try fromKeychainData(data)
        }
        throw KeychainReaderError.noKeychainEntry
    }

    /// Raw Security API for reading Claude Code's entry (foreign keychain item with dynamic account name)
    private static func readClaudeCodeKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

// MARK: - Credential Store (our own keychain entry via KeychainAccess)

public enum CredentialStore {
    nonisolated(unsafe) static let keychain = Keychain(service: "io.kootstra.claude-usage.credentials")

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
    }

    public static func delete() {
        try? keychain.remove("credentials")
    }
}
