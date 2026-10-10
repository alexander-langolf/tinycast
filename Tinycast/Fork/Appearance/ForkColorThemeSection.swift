import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The colour theme: pick or import one, adjust its ten colours, see it previewed, then apply it.
struct ForkColorThemeSection: View {
    @Environment(AppSettings.self) private var settings
    private var store: ForkThemeStore { ForkThemeStore.current! }
    /// Edited here and previewed; the app changes only on Apply.
    @State private var draft: ForkColorTheme?
    @State private var loaded = false
    @State private var isImporting = false

    private static let tinycastKey = "tinycast"

    var body: some View {
        let applied = store.tokens.colorTheme
        let palette = draft?.resolved()
        Section {
            Picker(selection: presetKey) {
                Text("Tinycast (default)").tag(Self.tinycastKey)
                ForEach(ForkColorThemePreset.Group.allCases, id: \.self) { group in
                    Section(group.title) {
                        ForEach(ForkColorThemePreset.all.filter { $0.group == group }) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                }
                if draft?.presetID == ForkColorTheme.customID {
                    Text("Custom").tag(ForkColorTheme.customID)
                }
            } label: {
                SettingsRowTitle(.appearanceColors, "Colour theme")
                Text("Looks the same in Light and Dark; Theme above applies to Tinycast only.")
            }
            ForkColorThemePreview(palette: palette, systemIsDark: systemIsDark)
            if let palette, !palette.adjusted.isEmpty {
                ContrastNote(adjusted: palette.adjusted)
            }
            if draft != nil {
                ForEach(ForkColorTheme.Slot.allCases, id: \.self) { slot in
                    ForkColorSlotRow(slot: slot, color: slotBinding(slot))
                }
                Toggle(isOn: gradientBinding) {
                    SettingsRowTitle(.appearanceColors, "Window gradient")
                    Text("Fades the palette from the background into the surface.")
                }
            }
            actions(applied: applied)
        } header: {
            SettingsSectionHeader(.appearanceColors)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = applied
        }
        // A file or a backup changed the applied theme; follow it unless there are edits pending.
        .onChange(of: applied) { old, new in
            if draft == old { draft = new }
        }
    }

    private func actions(applied: ForkColorTheme?) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button("Import Theme…") { isImporting = true }
                .popover(isPresented: $isImporting, arrowEdge: .bottom) {
                    ForkColorThemeImport { imported in
                        draft = imported
                        isImporting = false
                    }
                }
            Button("Copy Theme String") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(draft?.themeString ?? "", forType: .string)
            }
            .disabled(draft == nil)
            Spacer()
            Button("Revert") { draft = applied }
                .disabled(draft == applied)
            Button("Apply") { store.apply(draft) }
                .buttonStyle(.borderedProminent)
                .disabled(draft == applied)
        }
    }

    /// Tinycast's look is previewed in the appearance the Theme setting would pick.
    private var systemIsDark: Bool {
        switch settings.appearance {
        case .dark: true
        case .light: false
        case .system: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
    }

    private var presetKey: Binding<String> {
        Binding(
            get: { draft?.presetID ?? Self.tinycastKey },
            set: { key in
                guard key != draft?.presetID else { return }
                guard key != Self.tinycastKey else {
                    draft = nil
                    return
                }
                draft = ForkColorTheme(presetID: key, windowGradient: draft?.windowGradient ?? false)
            })
    }

    /// A preset slot set back to the preset's own value is no longer an override.
    private func slotBinding(_ slot: ForkColorTheme.Slot) -> Binding<ForkThemeValue.Color> {
        Binding(
            get: { draft?.baseSlots[slot] ?? .black },
            set: { color in
                guard var theme = draft else { return }
                theme.slots[slot] = theme.preset?.slots[slot] == color ? nil : color
                draft = theme
            })
    }

    private var gradientBinding: Binding<Bool> {
        Binding(
            get: { draft?.windowGradient ?? false },
            set: { draft?.windowGradient = $0 })
    }
}

/// Says which inks were raised to readable contrast, and from what.
private struct ContrastNote: View {
    let adjusted: [ForkColorTheme.Slot: Double]

    var body: some View {
        let names = ForkColorTheme.Slot.allCases.compactMap { slot in
            adjusted[slot].map { "\(slot.title) (\(String(format: "%.1f", $0)):1)" }
        }
        Label {
            Text("Adjusted for contrast: \(names.joined(separator: ", ")), raised to 4.5:1.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(.secondary)
        }
    }
}

/// Slack's import: a theme string, or a VS Code theme file.
private struct ForkColorThemeImport: View {
    let onImport: (ForkColorTheme) -> Void
    @State private var text = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Import theme").font(.headline)
            Text("Paste in a theme string")
                .foregroundStyle(.secondary)
            TextField("#124426, #350D36, #EEB317, #392104", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .lineLimit(2...4)
            Text("We'll adapt the colours as best we can to preserve contrast.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Choose VS Code Theme…", action: chooseFile)
                Spacer()
                Button("Import") {
                    guard let theme = ForkColorTheme(themeString: text) else {
                        failure = "No colours found: use hex values separated by commas."
                        return
                    }
                    onImport(theme)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: ForkColorThemeImportLayout.width)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        panel.message = "Choose a VS Code colour theme (.json)."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), let theme = try? ForkVSCodeTheme.theme(from: data) else {
            failure = "That file has no VS Code theme colours (no “colors” with “editor.background”)."
            return
        }
        onImport(theme)
    }
}

private enum ForkColorThemeImportLayout {
    static let width: CGFloat = 360
}
