import AppKit
import SwiftUI

/// Settings → Automation: who may automate Tinycast, how each agent registers, what it can reach,
/// the links any app may open, and where the audit trail lives.
struct AutomationSettingsView: View {
    var body: some View {
        Form {
            AutomationSettingsSection()
            AutomationConnectSection()
            AutomationCapabilitiesSection()
            AutomationLinksSection()
            AutomationFilesSection()
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.automation)
    }
}

/// One client and one agent picked, the exact line or file that agent needs, ready to copy.
private struct AutomationConnectSection: View {
    @Environment(AppCore.self) private var core
    @State private var clientID: UUID?
    @State private var setup = AutomationClientSetup.claudeCode

    private var automation: AutomationCoordinator { core.automation }

    private var client: AutomationClient? {
        let clients = automation.clients.clients
        return clients.first { $0.id == clientID } ?? clients.first
    }

    var body: some View {
        Section {
            if let client {
                Picker("Client", selection: clientSelection(default: client.id)) {
                    ForEach(automation.clients.clients) { Text($0.label).tag($0.id) }
                }
                Picker("Agent", selection: $setup) {
                    ForEach(AutomationClientSetup.allCases) { Text($0.title).tag($0) }
                }
                AutomationCopyBlock(text: setup.snippet(context(for: client)), caption: setup.placement)
            } else {
                Text("Create a client above, then its setup appears here.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            SettingsSectionHeader(.automationConnect)
        } footer: {
            Text(
                "The bridge reads the client's token from your login Keychain; macOS asks once "
                    + "whether it may. The path is this build's, so rebuilding elsewhere means registering again."
            )
        }
    }

    private func clientSelection(default id: UUID) -> Binding<UUID> {
        Binding(get: { clientID ?? id }, set: { clientID = $0 })
    }

    private func context(for client: AutomationClient) -> AutomationClientSetup.Context {
        AutomationClientSetup.Context(
            bridgePath: Bundle.main.bundleURL.appending(path: "Contents/Helpers/tinycast").path,
            clientID: client.id.uuidString, endpointURL: automation.endpointURL,
            keychainService: automation.clients.keychainService)
    }
}

/// Every tool and resource, the scope it needs, and whether each call asks you first.
private struct AutomationCapabilitiesSection: View {
    var body: some View {
        Section {
            ForEach(AutomationOperationCatalog.all, id: \.name) { operation in
                LabeledContent {
                    Text(badge(for: operation)).foregroundStyle(.secondary)
                } label: {
                    Text(operation.title)
                    Text("\(operation.name) · \(operation.summary)")
                }
            }
        } header: {
            SettingsSectionHeader(.automationCapabilities)
        } footer: {
            Text("A client sees only what its scopes allow. \"clipboard:read\" has no operation yet.")
        }
    }

    private func badge(for operation: AutomationOperation) -> String {
        let kind = operation.kind == .tool ? "tool" : "resource"
        let approval = operation.needsApproval ? " · asks you" : ""
        return "\(kind) · \(operation.scope.rawValue)\(approval)"
    }
}

/// The links any app may open: no token, no scopes, rate limited, and each one tryable from here.
private struct AutomationLinksSection: View {
    @Environment(AppCore.self) private var core

    private var channelScheme: String { Bundle.main.bundleIdentifier ?? "tinycast" }

    private var links: [(operation: AutomationOperation, example: String)] {
        AutomationOperationCatalog.all.compactMap { operation in
            guard let host = operation.linkHost else { return nil }
            let parameter = operation.inputSchema?.objectValue?["properties"]?.objectValue?.keys.sorted()
                .first
            let query = parameter.map { "?\($0)=Hello%20from%20a%20link" } ?? ""
            return (operation, "tinycast://\(host)\(query)")
        }
    }

    var body: some View {
        Section {
            ForEach(links, id: \.operation.name) { link in
                LabeledContent {
                    HStack {
                        Button("Copy") { Paster.copyPlainText(link.example) }
                        Button("Try") { open(link.example) }
                            .settingsEnabled(core.automation.isEnabled)
                    }
                } label: {
                    Text(link.operation.title)
                    Text(link.example).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                }
            }
        } header: {
            SettingsSectionHeader(.automationLinks)
        } footer: {
            Text(
                "Every Tinycast build claims tinycast://, and macOS picks one. \(channelScheme):// "
                    + "reaches only this build. Anything else, such as tinycast://terminal_run, is refused "
                    + "and audited.")
        }
    }

    /// Straight to this build's handler, so the try never lands on another installed copy.
    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        _ = core.automation.handleLink(url)
    }
}

private struct AutomationFilesSection: View {
    private var folder: URL {
        AppPaths.applicationSupport().appending(path: "Automation", directoryHint: .isDirectory)
    }

    var body: some View {
        Section {
            LabeledContent {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    .settingsEnabled(FileManager.default.fileExists(atPath: folder.path))
            } label: {
                Text("Automation folder")
                Text("audit.jsonl records every privileged call.")
            }
        } header: {
            SettingsSectionHeader(.automationFiles)
        }
    }
}

/// Monospaced, selectable text with a Copy button, for a line the user pastes somewhere else.
private struct AutomationCopyBlock: View {
    let text: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy") { Paster.copyPlainText(text) }
            }
            Text(caption).font(.callout).foregroundStyle(.secondary)
        }
    }
}

extension SettingsAnchor {
    static let automationClients = Self(tab: .automation, title: "Clients")
    static let automationConnect = Self(tab: .automation, title: "Connect an Agent")
    static let automationCapabilities = Self(tab: .automation, title: "What Clients Can Do")
    static let automationLinks = Self(tab: .automation, title: "Links")
    static let automationFiles = Self(tab: .automation, title: "Files")
}
