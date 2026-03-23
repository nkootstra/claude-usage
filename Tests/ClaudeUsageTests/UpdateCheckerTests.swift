import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("UpdateChecker")
struct UpdateCheckerTests {

    let releaseFixture = """
    {
        "tag_name": "v1.2.0",
        "html_url": "https://github.com/nkootstra/claude-usage/releases/tag/v1.2.0",
        "body": "Bug fixes and improvements"
    }
    """.data(using: .utf8)!

    @Test("Detects newer version available")
    func newerVersion() async throws {
        let session = MockURLSession { _ in
            (self.releaseFixture, HTTPURLResponse(
                url: URL(string: "https://api.github.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: session)
        let update = await checker.check(currentVersion: "1.0.0")

        #expect(update != nil)
        #expect(update?.version == "1.2.0")
        #expect(update?.releaseURL.absoluteString == "https://github.com/nkootstra/claude-usage/releases/tag/v1.2.0")
    }

    @Test("Returns nil when on latest version")
    func sameVersion() async throws {
        let session = MockURLSession { _ in
            (self.releaseFixture, HTTPURLResponse(
                url: URL(string: "https://api.github.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: session)
        let update = await checker.check(currentVersion: "1.2.0")
        #expect(update == nil)
    }

    @Test("Returns nil when running newer than latest release")
    func newerLocal() async throws {
        let session = MockURLSession { _ in
            (self.releaseFixture, HTTPURLResponse(
                url: URL(string: "https://api.github.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: session)
        let update = await checker.check(currentVersion: "2.0.0")
        #expect(update == nil)
    }

    @Test("Returns nil on network error")
    func networkError() async throws {
        let session = ThrowingMockSession(error: URLError(.notConnectedToInternet))

        let checker = UpdateChecker(session: session)
        let update = await checker.check(currentVersion: "1.0.0")
        #expect(update == nil)
    }

    @Test("Returns nil on malformed JSON")
    func malformedJSON() async throws {
        let session = MockURLSession { _ in
            ("not json".data(using: .utf8)!, HTTPURLResponse(
                url: URL(string: "https://api.github.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: session)
        let update = await checker.check(currentVersion: "1.0.0")
        #expect(update == nil)
    }

    @Test("Handles tag_name without v prefix")
    func noVPrefix() async throws {
        let fixture = """
        {
            "tag_name": "1.5.0",
            "html_url": "https://github.com/nkootstra/claude-usage/releases/tag/1.5.0",
            "body": "Release notes"
        }
        """.data(using: .utf8)!

        let session = MockURLSession { _ in
            (fixture, HTTPURLResponse(
                url: URL(string: "https://api.github.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: session)
        let update = await checker.check(currentVersion: "1.0.0")
        #expect(update?.version == "1.5.0")
    }

    @Test("Compares minor and patch versions correctly")
    func semverComparison() async throws {
        let fixture = """
        {
            "tag_name": "v1.0.1",
            "html_url": "https://github.com/nkootstra/claude-usage/releases/tag/v1.0.1",
            "body": "Patch"
        }
        """.data(using: .utf8)!

        let session = MockURLSession { _ in
            (fixture, HTTPURLResponse(
                url: URL(string: "https://api.github.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: session)

        let update = await checker.check(currentVersion: "1.0.0")
        #expect(update != nil)

        let noUpdate = await checker.check(currentVersion: "1.0.1")
        #expect(noUpdate == nil)
    }
}
