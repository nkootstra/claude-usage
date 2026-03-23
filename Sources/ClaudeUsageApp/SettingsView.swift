import SwiftUI
import ClaudeUsageCore
import LaunchAtLogin

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("pollingMinutes") private var pollingMinutes = 5
    @AppStorage("warningThreshold") private var warningThreshold = 50.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 80.0
    @AppStorage("colorMode") private var colorMode = ColorMode.trafficLight

    enum ColorMode: String, CaseIterable {
        case trafficLight = "traffic_light"
        case singleColor = "single_color"

        var label: LocalizedStringKey {
            switch self {
            case .trafficLight: return "Traffic light"
            case .singleColor: return "Single color"
            }
        }
    }

    private let pollingOptions = [1, 5, 15, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.usage != nil {
                // Polling section
                Text("Polling")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Picker("Poll interval", selection: $pollingMinutes) {
                    ForEach(pollingOptions, id: \.self) { min in
                        Text("\(min)m").tag(min)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: pollingMinutes) { _, newValue in
                    viewModel.updatePollingInterval(TimeInterval(newValue * 60))
                }

                LaunchAtLogin.Toggle("Launch at login")

                Divider()

                // Thresholds section
                Text("Thresholds")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Picker("Color mode", selection: $colorMode) {
                    ForEach(ColorMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ThresholdSlider(
                    label: "Warning",
                    value: $warningThreshold,
                    range: 10...90,
                    color: .orange
                )
                .onChange(of: warningThreshold) { _, newValue in
                    if newValue >= criticalThreshold {
                        criticalThreshold = min(newValue + 10, 100)
                    }
                }

                ThresholdSlider(
                    label: "Critical",
                    value: $criticalThreshold,
                    range: 20...100,
                    color: .red
                )
                .onChange(of: criticalThreshold) { _, newValue in
                    if newValue <= warningThreshold {
                        warningThreshold = max(newValue - 10, 0)
                    }
                }

                Divider()
            }

            // Account section
            ZStack {
                Text("v\(Bundle.main.shortVersionString)")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)

                HStack {
                    if viewModel.usage != nil {
                        Button("Sign Out") {
                            CredentialStore.delete()
                            viewModel.signOut()
                        }
                        .foregroundStyle(.red)
                    }

                    Spacer()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .padding(.top, 4)
    }
}

// MARK: - Threshold Slider

private struct ThresholdSlider: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .frame(width: 52, alignment: .leading)
            Slider(value: $value, in: range, step: 5)
                .tint(color)
            Text("\(Int(value))%")
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }
}
