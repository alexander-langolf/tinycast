import SwiftUI

struct ForkClaudeAccountSettingsRows: View {
    let account: ForkClaudeAccount
    @State private var code = ""

    var body: some View {
        Section {
            LabeledContent {
                HStack {
                    if account.phase == .signedIn {
                        Button("Refresh") { account.refreshCatalog() }
                    } else {
                        Button("Sign In") { account.signIn() }
                            .disabled(account.phase == .signingIn)
                    }
                    Button("Sign Out") { account.signOut() }
                        .disabled(account.phase == .signedOut)
                }
            } label: {
                Text("Claude account")
                Text(status).foregroundStyle(.secondary)
            }
            if account.phase != .signedIn {
                Button("Use Copy Code") { account.signIn(copyCode: true) }
                if account.phase == .signingIn {
                    SecureField("code#state", text: $code)
                        .onSubmit(submit)
                    Button("Submit Code", action: submit).disabled(code.isEmpty)
                }
            }
            ClaudeUsageSettingsRow()
        } header: {
            Text("Account")
        }
        .onChange(of: account.phase) { _, phase in
            if phase != .signingIn { code = "" }
        }
    }

    private var status: String {
        switch account.phase {
        case .signedOut: return String(localized: "Sign in required")
        case .signingIn: return String(localized: "Complete sign-in in your browser, or paste the sign-in code.")
        case .signedIn: return String(localized: "Signed in")
        case .failed(let message): return message
        }
    }

    private func submit() {
        account.submitCode(code)
        code = ""
    }
}
