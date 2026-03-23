import SwiftUI
import ClaudeUsageCore
import LaunchAtLogin

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("pollingMinutes") private var pollingMinutes = 5
    @AppStorage("notifyAt80") private var notifyAt80 = true
    @AppStorage("notifyAt95") private var notifyAt95 = true

    private let pollingOptions = [1, 5, 15, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            Toggle("Notify at 80%", isOn: $notifyAt80)
            Toggle("Notify at 95%", isOn: $notifyAt95)

            Divider()

            HStack {
                Button("Sign Out") {
                    CredentialStore.delete()
                    viewModel.signOut()
                }
                .foregroundStyle(.red)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.top, 4)
    }
}
