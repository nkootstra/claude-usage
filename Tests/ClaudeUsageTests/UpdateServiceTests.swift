import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("UpdateService")
struct UpdateServiceTests {

    @Test("Fires callback when newer version found")
    @MainActor
    func findsNewerVersion() async throws {
        let json = """
        {
            "tag_name": "v99.0.0",
            "html_url": "https://github.com/test/repo/releases/tag/v99.0.0",
            "body": "Big update"
        }
        """.data(using: .utf8)!

        let mockSession = MockURLSession { _ in
            return (json, HTTPURLResponse(
                url: URL(string: "https://api.github.com/repos/test/releases/latest")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: mockSession, repoURL: "https://api.github.com/repos/test/releases/latest")
        let service = UpdateService(checker: checker)
        var receivedUpdate: UpdateInfo?

        service.onUpdate = { update in
            receivedUpdate = update
        }

        service.start()
        try await Task.sleep(for: .milliseconds(200))
        service.stop()

        #expect(receivedUpdate?.version == "99.0.0")
        #expect(receivedUpdate?.releaseNotes == "Big update")
    }

    @Test("Dismiss sets UserDefaults key")
    @MainActor
    func dismissSetsKey() async throws {
        let checker = UpdateChecker(repoURL: "https://invalid.test")
        let service = UpdateService(checker: checker)
        var receivedNil = false

        service.onUpdate = { update in
            if update == nil { receivedNil = true }
        }

        service.dismissUpdate(version: "1.2.3")

        let dismissed = UserDefaults.standard.string(forKey: "claude-usage.dismissedUpdateVersion")
        #expect(dismissed == "1.2.3")
        #expect(receivedNil == true)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "claude-usage.dismissedUpdateVersion")
    }

    @Test("Stop cancels update checking")
    @MainActor
    func stopCancels() async throws {
        let checker = UpdateChecker(repoURL: "https://invalid.test")
        let service = UpdateService(checker: checker)

        service.start()
        service.stop()
        // Just verify no crash
    }
}
