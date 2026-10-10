import SwiftUI

/// Who may automate Tinycast: the clients, their scopes, and when their tokens lapse.
struct AutomationSettingsSection: View {
    @Environment(AppCore.self) private var core
    @State private var label = ""
    @State private var scopes: Set<AutomationScope> = [.agentsRead, .ui]
    @State private var lifetime = Lifetime.days90
    @State private var notice: String?

    private var automation: AutomationCoordinator { core.automation }

    enum Lifetime: String, CaseIterable, Identifiable {
        case days30, days90, days365, never

        var id: Self { self }

        var title: String {
            switch self {
            case .days30: "30 days"
            case .days90: "90 days"
            case .days365: "1 year"
            case .never: "No expiry"
            }
        }

        var seconds: TimeInterval? {
            switch self {
            case .days30: 30 * 86_400
            case .days90: 90 * 86_400
            case .days365: 365 * 86_400
            case .never: nil
            }
        }
    }

    var body: some View {
        Section {
            @Bindable var automation = automation
            Toggle(isOn: $automation.isEnabled) {
                Text("Allow automation")
                Text(statusText).foregroundStyle(.secondary)
            }
            .task { await automation.clients.loadMetadata() }
            ForEach(automation.clients.clients) { client in
                clientRow(client)
            }
            TextField("New client name", text: $label, prompt: Text("e.g. Claude Code"))
                .textFieldStyle(.roundedBorder)
            DisclosureGroup("Scopes for the new client") {
                ForEach(AutomationScope.allCases, id: \.self) { scope in
                    Toggle(scope.title, isOn: binding(for: scope))
                }
            }
            Picker("Token lifetime", selection: $lifetime) {
                ForEach(Lifetime.allCases) { Text($0.title).tag($0) }
            }
            Button("Create Client") { Task { await create() } }
                .settingsEnabled(createBlocker == nil)
            if let createBlocker {
                Text(createBlocker).foregroundStyle(.secondary)
            }
            if let notice {
                Text(notice).textSelection(.enabled).foregroundStyle(.secondary)
            }
        } header: {
            Text("Automation")
        } footer: {
            Text(
                "Each client has its own token, kept in your login Keychain and never in a file. "
                    + "Commands and agent launches always ask you first.")
        }
    }

    /// Why Create Client is disabled, said next to it rather than left for the user to guess.
    private var createBlocker: String? {
        let unnamed = label.trimmingCharacters(in: .whitespaces).isEmpty
        switch (unnamed, scopes.isEmpty) {
        case (true, true): return "Name the client and choose at least one scope to create it."
        case (true, false): return "Name the client to create it."
        case (false, true): return "Choose at least one scope to create the client."
        case (false, false): return nil
        }
    }

    private var statusText: String {
        guard automation.isEnabled else { return "Off. Nothing is listening." }
        switch automation.server?.status {
        case .listening?: return "Listening on \(automation.endpointURL)"
        case .failed(let message)?: return message
        default: return "Starting…"
        }
    }

    private func clientRow(_ client: AutomationClient) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(client.label)
                Text(summary(of: client)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Rotate Token") { Task { await rotate(client) } }
            Button("Revoke", role: .destructive) { revoke(client) }
        }
    }

    private func summary(of client: AutomationClient) -> String {
        let scopes = client.scopes.sorted().map(\.rawValue).joined(separator: ", ")
        let expiry = client.expiresAt.map { "expires \($0.formatted(date: .abbreviated, time: .omitted))" }
        return [scopes, expiry ?? "no expiry", client.id.uuidString].joined(separator: " · ")
    }

    private func binding(for scope: AutomationScope) -> Binding<Bool> {
        Binding(
            get: { scopes.contains(scope) },
            set: { isOn in
                if isOn { scopes.insert(scope) } else { scopes.remove(scope) }
            })
    }

    private func create() async {
        do {
            let client = try await automation.createClient(
                label: label, scopes: scopes, lifetime: lifetime.seconds)
            label = ""
            notice =
                "Created “\(client.label)”. Register it with: tinycast mcp --stdio --client \(client.id.uuidString)"
        } catch {
            notice = "Could not create the client: the Keychain refused the token."
        }
    }

    private func rotate(_ client: AutomationClient) async {
        do {
            try await automation.clients.rotate(client.id)
            notice = "Rotated “\(client.label)”. The old token no longer works."
        } catch {
            notice = "Could not rotate the token."
        }
    }

    private func revoke(_ client: AutomationClient) {
        Task {
            let confirmed = await core.confirm(
                title: "Revoke “\(client.label)”?",
                message: "Anything using its token stops working immediately.", symbol: "key",
                confirmTitle: "Revoke")
            if confirmed { await automation.clients.revoke(client.id) }
        }
    }
}
