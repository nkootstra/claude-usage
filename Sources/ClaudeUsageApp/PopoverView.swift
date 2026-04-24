import SwiftUI
import ClaudeUsageCore

struct MenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    var widgetController: FloatingWidgetController?
    @StateObject private var authFlow = AuthFlowState()
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.usage != nil, viewModel.profile != nil {
                HStack(spacing: 4) {
                    Spacer()
                    Text(viewModel.planTier.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            if let usage = viewModel.usage {
                UsageDetailView(usage: usage, creditProjection: viewModel.creditProjection)
            } else if authFlow.isAwaitingCode {
                OAuthCodeEntryView(authFlow: authFlow, viewModel: viewModel)
            } else if let error = viewModel.error {
                UsageErrorView(error: error, authFlow: authFlow) {
                    Task { await viewModel.refresh() }
                }
            } else {
                ProgressView("Loading...")
            }

            // Footer
            HStack(spacing: 8) {
                if let lastUpdated = viewModel.lastUpdated {
                    Text(lastUpdated, style: .relative)
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 9))
                        .monospacedDigit()
                }

                if let update = viewModel.availableUpdate {
                    Link(destination: update.releaseURL) {
                        HStack(spacing: 3) {
                            Circle().fill(.orange).frame(width: 5, height: 5)
                            Text("v\(update.version)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Download update")
                }

                Spacer()

                if viewModel.usage != nil {
                    Button { Task { await viewModel.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Refresh")

                    if let widgetController {
                        Button {
                            widgetController.toggle()
                        } label: {
                            Image(systemName: widgetController.isVisible ? "pin.slash" : "pin")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(widgetController.isVisible ? .primary : .secondary)
                        .help(widgetController.isVisible ? "Unpin widget" : "Pin widget")
                    }
                }
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Settings")
            }
            .font(.system(size: 12))
        }
        .padding(12)
        .frame(width: 260)
    }
}
