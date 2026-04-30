import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(viewModel: appDelegate.viewModel)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notificationService = NotificationService()

    lazy var viewModel = UsageViewModel(
        credentialProvider: {
            try? OAuthCredential.fromKeychain()
        },
        notificationService: notificationService
    )

    lazy var widgetController = FloatingWidgetController(viewModel: viewModel)
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(
            viewModel: viewModel,
            widgetController: widgetController
        )
        notificationService.requestPermission()
        viewModel.startPolling()

        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in
                self?.viewModel.stopPolling()
            }
        }
        wsnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in
                self?.viewModel.startPolling()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopPolling()
    }
}
