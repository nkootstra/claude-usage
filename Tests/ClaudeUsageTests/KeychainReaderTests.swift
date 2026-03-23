import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("KeychainReader")
struct KeychainReaderTests {

    let keychainFixture = """
    {
        "claudeAiOauth": {
            "accessToken": "sk-ant-oat01-test-token",
            "refreshToken": "sk-ant-ort01-test-refresh",
            "expiresAt": 1774149581012,
            "scopes": ["user:profile", "user:inference"],
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_5x"
        },
        "organizationUuid": "org-uuid-123"
    }
    """.data(using: .utf8)!

    @Test("Parses credential from keychain JSON")
    func parseCredential() throws {
        let credential = try OAuthCredential.fromKeychainData(keychainFixture)

        #expect(credential.accessToken == "sk-ant-oat01-test-token")
        #expect(credential.refreshToken == "sk-ant-ort01-test-refresh")
        #expect(credential.subscriptionType == "max")
        #expect(credential.rateLimitTier == "default_claude_max_5x")
        #expect(credential.organizationUuid == "org-uuid-123")
    }

    @Test("Detects token is not expired")
    func tokenNotExpired() throws {
        let futureMs = Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000
        let json = makeOAuthJSON(accessToken: "token", expiresAt: futureMs)
        let credential = try OAuthCredential.fromKeychainData(json)
        #expect(credential.isExpired == false)
    }

    @Test("Detects token is expired")
    func tokenExpired() throws {
        let pastMs = Int64(Date().timeIntervalSince1970 * 1000) - 3_600_000
        let json = makeOAuthJSON(accessToken: "token", expiresAt: pastMs)
        let credential = try OAuthCredential.fromKeychainData(json)
        #expect(credential.isExpired == true)
    }

    @Test("Throws when JSON has no claudeAiOauth key")
    func missingOAuthKey() throws {
        let json = """
        { "somethingElse": {} }
        """.data(using: .utf8)!

        #expect(throws: KeychainReaderError.self) {
            try OAuthCredential.fromKeychainData(json)
        }
    }

    @Test("Throws when accessToken is missing")
    func missingAccessToken() throws {
        let json = """
        { "claudeAiOauth": { "refreshToken": "refresh" } }
        """.data(using: .utf8)!

        #expect(throws: KeychainReaderError.self) {
            try OAuthCredential.fromKeychainData(json)
        }
    }

    // MARK: - Edge cases

    @Test("Throws on empty Data")
    func emptyData() throws {
        #expect(throws: KeychainReaderError.self) {
            try OAuthCredential.fromKeychainData(Data())
        }
    }

    @Test("Throws on non-JSON data")
    func nonJSONData() throws {
        let data = "not json at all".data(using: .utf8)!
        #expect(throws: KeychainReaderError.self) {
            try OAuthCredential.fromKeychainData(data)
        }
    }

    @Test("Throws when accessToken is empty string")
    func emptyAccessToken() throws {
        let json = """
        { "claudeAiOauth": { "accessToken": "" } }
        """.data(using: .utf8)!

        #expect(throws: KeychainReaderError.self) {
            try OAuthCredential.fromKeychainData(json)
        }
    }

    @Test("Token with no expiresAt is never expired")
    func noExpiresAt() throws {
        let json = """
        { "claudeAiOauth": { "accessToken": "token" } }
        """.data(using: .utf8)!

        let credential = try OAuthCredential.fromKeychainData(json)
        #expect(credential.isExpired == false)
        #expect(credential.expiresAt == nil)
    }

    @Test("Token expiring exactly now is considered expired")
    func expiresAtExactlyNow() throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let json = makeOAuthJSON(accessToken: "token", expiresAt: nowMs)
        let credential = try OAuthCredential.fromKeychainData(json)
        // >= comparison means exactly-now is expired
        #expect(credential.isExpired == true)
    }

    @Test("Very old expiresAt (epoch 1ms) is expired")
    func veryOldExpiration() throws {
        let json = makeOAuthJSON(accessToken: "token", expiresAt: 1)
        let credential = try OAuthCredential.fromKeychainData(json)
        #expect(credential.isExpired == true)
    }

    @Test("Far future expiresAt is not expired")
    func farFutureExpiration() throws {
        let json = makeOAuthJSON(accessToken: "token", expiresAt: 9_999_999_999_999)
        let credential = try OAuthCredential.fromKeychainData(json)
        #expect(credential.isExpired == false)
    }

    @Test("Optional fields default to nil when missing")
    func optionalFieldsNil() throws {
        let json = """
        { "claudeAiOauth": { "accessToken": "token" } }
        """.data(using: .utf8)!

        let credential = try OAuthCredential.fromKeychainData(json)
        #expect(credential.refreshToken == nil)
        #expect(credential.subscriptionType == nil)
        #expect(credential.rateLimitTier == nil)
        #expect(credential.organizationUuid == nil)
    }

    @Test("Ignores unknown fields in claudeAiOauth")
    func unknownFieldsInOAuth() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "token",
                "someNewField": "value",
                "anotherField": 42
            }
        }
        """.data(using: .utf8)!

        let credential = try OAuthCredential.fromKeychainData(json)
        #expect(credential.accessToken == "token")
    }

    // MARK: - File-based credential reading

    @Test("Reads credential from file when it exists")
    func readFromFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cred-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent(".credentials.json")
        try keychainFixture.write(to: file)

        let credential = try OAuthCredential.fromCredentialSources(filePaths: [file])
        #expect(credential.accessToken == "sk-ant-oat01-test-token")
    }

    @Test("Tries first file path before second")
    func fileOrderPriority() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cred-order-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = dir.appendingPathComponent("first.json")
        let second = dir.appendingPathComponent("second.json")

        let firstJSON = makeOAuthJSON(accessToken: "from-first", expiresAt: 9_999_999_999_999)
        let secondJSON = makeOAuthJSON(accessToken: "from-second", expiresAt: 9_999_999_999_999)
        try firstJSON.write(to: first)
        try secondJSON.write(to: second)

        let credential = try OAuthCredential.fromCredentialSources(filePaths: [first, second])
        #expect(credential.accessToken == "from-first")
    }

    @Test("Skips missing first file and reads second")
    func fallsToSecondFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cred-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let missing = dir.appendingPathComponent("missing.json")
        let present = dir.appendingPathComponent("present.json")
        let json = makeOAuthJSON(accessToken: "from-fallback", expiresAt: 9_999_999_999_999)
        try json.write(to: present)

        let credential = try OAuthCredential.fromCredentialSources(filePaths: [missing, present])
        #expect(credential.accessToken == "from-fallback")
    }

    @Test("Skips malformed file and falls through to next source")
    func skipsMalformedFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cred-bad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bad = dir.appendingPathComponent("bad.json")
        let good = dir.appendingPathComponent("good.json")
        try "not valid json".data(using: .utf8)!.write(to: bad)
        try makeOAuthJSON(accessToken: "from-good", expiresAt: 9_999_999_999_999).write(to: good)

        let credential = try OAuthCredential.fromCredentialSources(filePaths: [bad, good])
        #expect(credential.accessToken == "from-good")
    }

    // MARK: - Sign-out flag (UserDefaults only — avoids keychain access in tests)

    @Test("isSignedOut defaults to false")
    func signedOutDefaultFalse() throws {
        let key = "io.kootstra.claude-usage.signedOut"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        #expect(CredentialStore.isSignedOut == false)
    }

    @Test("isSignedOut can be set to true")
    func signedOutSetTrue() throws {
        let key = "io.kootstra.claude-usage.signedOut"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        CredentialStore.isSignedOut = true
        #expect(CredentialStore.isSignedOut == true)
    }

    @Test("isSignedOut can be cleared")
    func signedOutCleared() throws {
        let key = "io.kootstra.claude-usage.signedOut"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        CredentialStore.isSignedOut = true
        CredentialStore.isSignedOut = false
        #expect(CredentialStore.isSignedOut == false)
    }

    // MARK: - Helper

    private func makeOAuthJSON(accessToken: String, expiresAt: Int64) -> Data {
        """
        { "claudeAiOauth": { "accessToken": "\(accessToken)", "expiresAt": \(expiresAt) } }
        """.data(using: .utf8)!
    }
}
