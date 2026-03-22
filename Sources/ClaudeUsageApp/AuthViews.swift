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

        let url = OAuthFlow.authorizationURL(challenge: pkce.challenge, state: state)
        NSWorkspace.shared.open(url)
        isAwaitingCode = true
    }
}

struct SignInPromptView: View {
    @ObservedObject var authFlow: AuthFlowState

    var body: some View {
        VStack(spacing: 8) {
            Text("No Claude Code credentials found")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Text("Paste the authorization code:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Code", text: $codeText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
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
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func exchangeCode() async {
        guard let pkce = authFlow.pkce, let state = authFlow.state else {
            authFlow.error = "No pending flow"
            return
        }

        let (code, returnedState) = OAuthFlow.parseCallback(codeText)
        if let returnedState, returnedState != state {
            authFlow.error = "State mismatch — try again"
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
            authFlow.isAwaitingCode = false
            authFlow.error = nil
            authFlow.pkce = nil
            authFlow.state = nil
            viewModel.startPolling()
        } catch {
            authFlow.error = "Exchange failed: \(error.localizedDescription)"
        }
    }
}
