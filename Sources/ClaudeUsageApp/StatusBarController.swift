import AppKit
import Combine
import SwiftUI
import ClaudeUsageCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let viewModel: UsageViewModel
    private let widgetController: FloatingWidgetController
    private var labelHostingView: NSHostingView<MenuBarLabel>?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: UsageViewModel, widgetController: FloatingWidgetController) {
        self.viewModel = viewModel
        self.widgetController = widgetController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        observeLabelSizeChanges()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let hostingView = NSHostingView(rootView: MenuBarLabel(viewModel: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        labelHostingView = hostingView

        button.target = self
        button.action = #selector(statusItemClicked(_:))

        updateStatusItemLength()
    }

    private func configurePopover() {
        let content = MenuContentView(
            viewModel: viewModel,
            widgetController: widgetController
        )
        popover.contentViewController = NSHostingController(rootView: content)
        popover.behavior = .transient
        popover.animates = true
    }

    /// The status button's intrinsic width is zero (no title/image), so
    /// `NSStatusItem.variableLength` would clip the SwiftUI label. Push the
    /// hosting view's measured width back into `statusItem.length` whenever
    /// the model — or the enterprise $/% display preference — changes.
    private func observeLabelSizeChanges() {
        viewModel.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.updateStatusItemLength()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.updateStatusItemLength()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemLength() {
        guard let hostingView = labelHostingView else { return }
        let width = hostingView.intrinsicContentSize.width
        guard width.isFinite, width > 0 else { return }
        statusItem.length = ceil(width)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        // Activating the app ensures focusable controls (e.g. the OAuth code field)
        // receive keyboard input — without this, .accessory apps swallow text events.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // AppKit auto-focuses the first focusable subview (the update Link) on
        // open, which paints a focus ring around `v1.2.0`. Clear it so the
        // popover opens with no focus ring; clicking a control still focuses it.
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }
}
