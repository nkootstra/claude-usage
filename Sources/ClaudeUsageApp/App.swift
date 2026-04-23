import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                viewModel: appDelegate.viewModel,
                widgetController: appDelegate.widgetController
            )
        } label: {
            MenuBarLabel(viewModel: appDelegate.viewModel)
        }
        .menuBarExtraStyle(.window)

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
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
