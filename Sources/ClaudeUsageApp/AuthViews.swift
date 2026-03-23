import SwiftUI
import ClaudeUsageCore

@MainActor
final class AuthFlowState: ObservableObject {
    @Published var isAwaitingCode = false
    @Published var error: String?
    var pkce: PKCEChallenge?
    var state: String?

    func startFlow() {
        let pkce = PKCEChallenge.generate()
        let state = PKCEChallenge.generate().verifier
        self.pkce = pkce
        self.state = state
        self.error = nil

        let url = OAuthFlow.authorizationURL(challenge: pkce.challenge, state: state)
        NSWorkspace.shared.open(url)
        isAwaitingCode = true
    }

    func reset() {
        isAwaitingCode = false
        error = nil
        pkce = nil
        state = nil
    }
}

struct SignInPromptView: View {
    @ObservedObject var authFlow: AuthFlowState

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("Sign in to track your Claude usage")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Sign in with Claude") {
                authFlow.startFlow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}

struct OAuthCodeEntryView: View {
    @ObservedObject var authFlow: AuthFlowState
    @ObservedObject var viewModel: UsageViewModel
    @State private var codeText = ""
    @State private var isExchanging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Paste the authorization code:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    authFlow.reset()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            }

            HStack(spacing: 6) {
                TextField("Code", text: $codeText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button {
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        codeText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Paste from clipboard")

                Button("Submit") {
                    isExchanging = true
                    Task {
                        await exchangeCode()
                        isExchanging = false
                    }
                }
                .disabled(codeText.isEmpty || isExchanging)
                .controlSize(.small)
            }

            if let error = authFlow.error {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(error)
                        .font(.caption2)
                }
                .foregroundStyle(.red)
            }
        }
    }

    private func exchangeCode() async {
        guard let pkce = authFlow.pkce, let state = authFlow.state else {
            authFlow.error = "No pending flow. Try signing in again."
            return
        }

        let (code, returnedState) = OAuthFlow.parseCallback(codeText)
        if let returnedState, returnedState != state {
            authFlow.error = "State mismatch. Try signing in again."
            return
        }

        let flow = OAuthFlow()
        do {
            let token = try await flow.exchangeCode(code: code, state: state, verifier: pkce.verifier)
            try CredentialStore.save(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresIn: token.expiresIn
            )
            authFlow.reset()
            viewModel.startPolling()
        } catch {
            authFlow.error = "Exchange failed. Check the code and try again."
        }
    }
}

/// Structured error view that maps UsageError to actionable UI
struct UsageErrorView: View {
    let error: UsageError
    @ObservedObject var authFlow: AuthFlowState
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let action = actionButton {
                action
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var iconName: String {
        switch error {
        case .noCredential, .unauthorized: return "person.crop.circle.badge.xmark"
        case .rateLimited: return "clock.badge.exclamationmark"
        case .networkError: return "wifi.exclamationmark"
        case .unknown: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch error {
        case .noCredential, .unauthorized: return .orange
        case .rateLimited: return .yellow
        case .networkError, .unknown: return .red
        }
    }

    private var title: String {
        switch error {
        case .noCredential: return "Not signed in"
        case .unauthorized: return "Session expired"
        case .rateLimited: return "Rate limited"
        case .networkError: return "Connection issue"
        case .unknown: return "Something went wrong"
        }
    }

    private var subtitle: String {
        switch error {
        case .noCredential:
            return "Sign in to see your Claude usage."
        case .unauthorized:
            return "Your session expired. Sign in again."
        case .rateLimited(let retryIn):
            return "Too many requests. Retrying in \(Int(retryIn))s."
        case .networkError(let msg):
            return "Can't reach Claude. \(msg)"
        case .unknown(let msg):
            return msg
        }
    }

    @ViewBuilder
    private var actionButton: (some View)? {
        switch error {
        case .noCredential, .unauthorized:
            Button("Sign in with Claude") {
                authFlow.startFlow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .rateLimited, .networkError, .unknown:
            if let onRetry {
                Button("Retry Now") {
                    onRetry()
                }
                .controlSize(.small)
            }
        }
    }
}
