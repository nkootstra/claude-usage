import AppKit
import SwiftUI
import ClaudeUsageCore

@MainActor
final class FloatingWidgetController {
    private var panel: NSPanel?
    private let viewModel: UsageViewModel

    var isVisible: Bool { panel?.isVisible ?? false }

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let widgetView = FloatingWidgetView(viewModel: viewModel) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: widgetView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 84, height: 84)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 84, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView

        // Restore saved position or default to top-right
        let x = UserDefaults.standard.double(forKey: "widgetX")
        let y = UserDefaults.standard.double(forKey: "widgetY")
        if x > 0 || y > 0 {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: screenFrame.maxX - 80,
                y: screenFrame.maxY - 80
            ))
        }

        // Save position on move
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            Task { @MainActor in
                guard let origin = panel?.frame.origin else { return }
                UserDefaults.standard.set(origin.x, forKey: "widgetX")
                UserDefaults.standard.set(origin.y, forKey: "widgetY")
            }
        }

        self.panel = panel
    }
}
