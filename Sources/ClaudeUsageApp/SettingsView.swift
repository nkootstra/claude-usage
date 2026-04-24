import SwiftUI
import ClaudeUsageCore
import LaunchAtLogin

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

struct SettingsRootView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
            ThresholdsTab()
                .tabItem { Label("Thresholds", systemImage: "slider.horizontal.3") }
            AccountTab(viewModel: viewModel)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 420, height: 260)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("pollingMinutes") private var pollingMinutes = 5

    private let pollingOptions = [1, 5, 15, 30]

    var body: some View {
        Form {
            Picker("Poll interval", selection: $pollingMinutes) {
                ForEach(pollingOptions, id: \.self) { min in
                    Text("\(min) min").tag(min)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: pollingMinutes) { _, newValue in
                viewModel.updatePollingInterval(TimeInterval(newValue * 60))
            }

            LaunchAtLogin.Toggle("Launch at login")
        }
        .formStyle(.grouped)
    }
}

// MARK: - Thresholds

private struct ThresholdsTab: View {
    @AppStorage("warningThreshold") private var warningThreshold = 50.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 80.0
    @AppStorage("colorMode") private var colorMode = ColorMode.trafficLight

    var body: some View {
        Form {
            Picker("Color mode", selection: $colorMode) {
                ForEach(ColorMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Warning")
                Slider(value: $warningThreshold, in: 10...90, step: 5)
                    .tint(.orange)
                Text("\(Int(warningThreshold))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            .onChange(of: warningThreshold) { _, newValue in
                if newValue >= criticalThreshold {
                    criticalThreshold = min(newValue + 10, 100)
                }
            }

            HStack {
                Text("Critical")
                Slider(value: $criticalThreshold, in: 20...100, step: 5)
                    .tint(.red)
                Text("\(Int(criticalThreshold))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            .onChange(of: criticalThreshold) { _, newValue in
                if newValue <= warningThreshold {
                    warningThreshold = max(newValue - 10, 0)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Account

private struct AccountTab: View {
    @ObservedObject var viewModel: UsageViewModel

    private var isSignedIn: Bool { viewModel.usage != nil }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                if isSignedIn, let identifier = viewModel.profile?.displayIdentifier {
                    Text(identifier)
                        .font(.headline)
                    Text(viewModel.planTier.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(isSignedIn ? "Signed in" : "Signed out")
                        .font(.headline)
                }
                Text("v\(Bundle.main.shortVersionString)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 20)

            Spacer()

            HStack {
                Button("Sign Out") {
                    CredentialStore.delete()
                    viewModel.signOut()
                }
                .disabled(!isSignedIn)
                .foregroundStyle(isSignedIn ? .red : .secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
        }
    }
}
