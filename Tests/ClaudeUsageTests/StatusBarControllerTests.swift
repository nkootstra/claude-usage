import AppKit
import Foundation
import Testing
@testable import ClaudeUsageApp
@testable import ClaudeUsageCore

@Suite("StatusBarController")
@MainActor
struct StatusBarControllerTests {
    @Test("UserDefaults changes posted off main actor do not crash label observer")
    func backgroundUserDefaultsNotification() async throws {
        let viewModel = UsageViewModel(
            credentialProvider: { OAuthCredential.mock(accessToken: "token") },
            cache: nil
        )
        let controller = StatusBarController(
            viewModel: viewModel,
            widgetController: FloatingWidgetController(viewModel: viewModel)
        )

        _ = controller
        await Task.detached {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }.value

        try await Task.sleep(for: .milliseconds(100))
    }
}
