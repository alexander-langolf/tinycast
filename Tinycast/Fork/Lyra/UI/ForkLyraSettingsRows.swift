import SwiftUI

struct ForkLyraSettingsRows: View {
    let coordinator: ForkLyraCoordinator

    var body: some View {
        @Bindable var preferences = coordinator.preferences
        Section("Local Lyra") {
            Toggle("Enable Lyra", isOn: $preferences.enabled)
            Toggle("Fix as you type", isOn: $preferences.fixEnabled)
            TextField("Model path", text: $preferences.modelPath)
            LabeledContent { Text(verbatim: "⌥⌘R · ⌘⌘") } label: { Text("Rewrite panel") }
            Text("Fix: Tab to preview, Tab to apply.")
                .foregroundStyle(.secondary)
            Text(status)
                .foregroundStyle(.secondary)
        }
    }

    private var status: String {
        switch coordinator.server.snapshot.state {
        case .disabled: String(localized: "Disabled")
        case .checking, .loading: String(localized: "Loading…")
        case .running: String(localized: "Ready")
        case .notRunning, .failed: String(localized: "Unavailable")
        }
    }
}
