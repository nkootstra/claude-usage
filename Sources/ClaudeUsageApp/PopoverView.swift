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
            if authFlow.isAwaitingCode {
                OAuthCodeEntryView(authFlow: authFlow, viewModel: viewModel)
            } else if let usage = viewModel.usage {
                if let error = viewModel.error {
                    StaleDataBanner(error: error, authFlow: authFlow) {
                        Task { await viewModel.refresh() }
                    }
                }
                UsageDetailView(usage: usage, creditProjection: viewModel.creditProjection)
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

/// Inline warning shown above cached usage when the most recent fetch failed.
/// Without this the detail view hides auth/rate-limit errors behind stale data.
private struct StaleDataBanner: View {
    let error: UsageError
    @ObservedObject var authFlow: AuthFlowState
    let onRetry: () -> Void

    private var needsReauth: Bool { error.isAuthError }

    private var message: String {
        switch error {
        case .noCredential, .unauthorized: return "Session expired — data may be stale"
        case .rateLimited: return "Rate limited — showing cached data"
        case .networkError: return "Offline — showing cached data"
        case .unknown: return "Can't refresh — showing cached data"
        }
    }

    private var tint: Color {
        switch error {
        case .noCredential, .unauthorized: return .orange
        case .rateLimited: return .yellow
        case .networkError, .unknown: return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(message)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if needsReauth {
                Button("Sign in") { authFlow.startFlow() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tint)
            } else {
                Button("Retry") { onRetry() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(tint.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}
