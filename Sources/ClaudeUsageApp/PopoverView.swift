import SwiftUI
import ClaudeUsageCore
import UniformTypeIdentifiers

struct MenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    @StateObject private var authFlow = AuthFlowState()
    @State private var exportError: String?
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let usage = viewModel.usage {
                UsageDetailView(usage: usage, creditProjection: viewModel.creditProjection)

                if !viewModel.historyPoints.isEmpty {
                    UsageChartView(points: viewModel.historyPoints, isEnterprise: viewModel.isEnterprise)
                }
            } else if authFlow.isAwaitingCode {
                OAuthCodeEntryView(authFlow: authFlow, viewModel: viewModel)
            } else if viewModel.error == "No credential" {
                SignInPromptView(authFlow: authFlow)
            } else if let error = viewModel.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ProgressView("Loading...")
            }

            // Footer
            HStack(spacing: 12) {
                if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 9))
                }
                Spacer()
                if !viewModel.historyPoints.isEmpty {
                    Button { exportCSV() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Export CSV")
                }
                if viewModel.usage != nil {
                    Button { Task { await viewModel.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Refresh")
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
        .padding(14)
        .frame(width: 300)
    }

    private func exportCSV() {
        let csv = CSVExporter.export(viewModel.historyPoints)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "claude-usage.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Task { @MainActor in
                    exportError = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
