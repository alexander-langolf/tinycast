import SwiftUI

struct ForkLyraSettingsRows: View {
    let coordinator: ForkLyraCoordinator

    var body: some View {
        @Bindable var preferences = coordinator.preferences
        Section("Local Lyra") {
            Toggle("Enable Lyra", isOn: $preferences.enabled)
            TextField("Model path", text: $preferences.modelPath)
            Text("Open Rewrite with Lyra to fix the selection or whole field.")
                .foregroundStyle(.secondary)
            Text("Tab or Enter applies the result.")
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
