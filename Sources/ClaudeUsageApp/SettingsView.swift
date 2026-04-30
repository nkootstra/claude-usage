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

enum MenuBarLayoutOption: String, CaseIterable {
    case fiveHourOnly   // 5h% only
    case dual           // 5h% · 7d%

    var label: LocalizedStringKey {
        switch self {
        case .fiveHourOnly: return "5-hour"
        case .dual: return "5-hour + 7-day"
        }
    }
}

enum EnterpriseDisplayOption: String, CaseIterable {
    case dollars
    case percent

    var label: LocalizedStringKey {
        switch self {
        case .dollars: return "Dollars"
        case .percent: return "Percent"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
            DisplayTab(viewModel: viewModel)
                .tabItem { Label("Display", systemImage: "paintbrush") }
            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
            AccountTab(viewModel: viewModel)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 440, height: 340)
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

// MARK: - Display

private struct DisplayTab: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("menuBarLayout") private var menuBarLayout = MenuBarLayoutOption.fiveHourOnly.rawValue
    @AppStorage("colorMode") private var colorMode = ColorMode.trafficLight
    @AppStorage("warningThreshold") private var warningThreshold = 50.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 80.0
    @AppStorage("enterpriseShowPct") private var enterpriseShowPct = false

    var body: some View {
        Form {
            Section {
                Picker("Menu bar", selection: $menuBarLayout) {
                    ForEach(MenuBarLayoutOption.allCases, id: \.rawValue) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.isEnterprise {
                    Picker("Enterprise display", selection: enterpriseDisplayBinding) {
                        ForEach(EnterpriseDisplayOption.allCases, id: \.rawValue) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
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
            } footer: {
                Text("Used for menu bar colors and notification triggers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// `@AppStorage` stores Bool; the picker takes `EnterpriseDisplayOption.rawValue`.
    /// Bridge the two so the picker selects the right segment.
    private var enterpriseDisplayBinding: Binding<String> {
        Binding(
            get: { enterpriseShowPct ? EnterpriseDisplayOption.percent.rawValue : EnterpriseDisplayOption.dollars.rawValue },
            set: { enterpriseShowPct = ($0 == EnterpriseDisplayOption.percent.rawValue) }
        )
    }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    @AppStorage("notificationThresholdAlerts") private var thresholdAlerts = true
    @AppStorage("notificationBurnRateAlerts") private var burnRateAlerts = true

    var body: some View {
        Form {
            Section {
                Toggle("Threshold alerts", isOn: $thresholdAlerts)
            } footer: {
                Text("Notify when 5-hour usage crosses the warning or critical level set in Display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Burn rate alert", isOn: $burnRateAlerts)
            } footer: {
                Text("Notify once when projected to exhaust the 5-hour bucket within 60 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
