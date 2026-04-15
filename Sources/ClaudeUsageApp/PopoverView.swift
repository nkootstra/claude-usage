import SwiftUI
import ClaudeUsageCore

struct MenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    var widgetController: FloatingWidgetController?
    @StateObject private var authFlow = AuthFlowState()
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            // Update banner
            if let update = viewModel.availableUpdate {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Link("v\(update.version) available", destination: update.releaseURL)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        viewModel.dismissUpdate()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                }
            }

            // Footer
            HStack(spacing: 12) {
                if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 9))
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
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(showSettings ? .primary : .secondary)
                .help("Settings")
            }
            .font(.system(size: 12))

            if showSettings {
                Divider()
                SettingsView(viewModel: viewModel)
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
