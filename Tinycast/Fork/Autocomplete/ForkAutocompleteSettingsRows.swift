import SwiftUI

struct ForkAutocompleteSettingsRows: View {
    let coordinator: ForkAutocompleteCoordinator
    @State private var newBundleID = ""

    var body: some View {
        @Bindable var preferences = coordinator.preferences
        return Section {
            Toggle(isOn: $preferences.enabled) {
                SettingsRowTitle(.inlineAutocomplete, "Inline autocomplete")
            }
            Stepper(value: $preferences.confidencePercent, in: 0...100, step: 5) {
                SettingsRowTitle(.inlineAutocomplete, "Minimum confidence")
                Text(Double(preferences.confidencePercent) / 100, format: .percent)
            }
            LabeledContent {
                VStack(alignment: .leading) {
                    ForEach(preferences.excludedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(verbatim: bundleID)
                            Spacer()
                            Button {
                                preferences.excludedBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .help("Remove")
                            .accessibilityLabel("Remove")
                        }
                    }
                    HStack {
                        TextField("Bundle ID", text: $newBundleID)
                            .onSubmit { addBundleID() }
                        Button("Add") { addBundleID() }
                            .disabled(!canAddBundleID)
                    }
                }
            } label: {
                SettingsRowTitle(.inlineAutocomplete, "Excluded app bundle IDs")
            }
            Text(coordinator.ready ? String(localized: "Ready") : String(localized: "Unavailable"))
                .foregroundStyle(.secondary)
        } header: {
            SettingsSectionHeader(.inlineAutocomplete)
        }
    }

    private var bundleID: String { newBundleID.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canAddBundleID: Bool {
        !bundleID.isEmpty && !bundleID.contains(where: \.isWhitespace)
            && !coordinator.preferences.excludedBundleIDs.contains(bundleID)
    }

    private func addBundleID() {
        guard canAddBundleID else { return }
        coordinator.preferences.excludedBundleIDs.append(bundleID)
        newBundleID = ""
    }
}
