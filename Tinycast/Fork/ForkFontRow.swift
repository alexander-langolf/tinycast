import SwiftUI

/// Each family previews in its own face, so the list is the specimen sheet as well as the picker.
struct ForkFontRow: View {
    private var appearance: ForkAppearance { ForkAppearance.current! }
    @State private var families: [String] = []
    @State private var isPicking = false

    var body: some View {
        SettingsRow(
            title: "Interface font",
            subtitle: "Applies to prose; code and symbols keep their system face.",
            anchor: .generalAppearance
        ) {
            Button {
                isPicking = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(appearance.fontFamily ?? Self.systemTitle)
                        .font(previewFont)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Theme.Typography.disclosure)
                        .foregroundStyle(.secondary)
                }
                .frame(width: ForkFontLayout.field, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isPicking, arrowEdge: .bottom) {
                FontPickerPopover(families: families, selection: appearance.fontFamily) {
                    appearance.fontFamily = $0
                    isPicking = false
                }
            }
            .onAppear { families = FontCatalog.installedFamilies() }
        }
    }

    private static let systemTitle = "System"

    /// A family uninstalled since it was chosen must not draw the button in a missing face.
    private var previewFont: Font {
        guard let family = appearance.fontFamily, FontCatalog.isInstalled(family) else {
            return Theme.Typography.rowTrailing
        }
        return .custom(family, size: ForkFontLayout.specimenSize)
    }
}

/// Its own popover rather than a `Picker`: a few hundred families need a filter to be usable.
private struct FontPickerPopover: View {
    let families: [String]
    let selection: String?
    let onSelect: (String?) -> Void

    @State private var query = ""

    private static let systemTitle = "System"

    private var matches: [String] {
        guard !query.isEmpty else { return families }
        return families.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The row back to the default, which a filter must never be able to hide.
    private var matchesSystem: Bool {
        query.isEmpty || Self.systemTitle.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsFilterField(prompt: "Search fonts\u{2026}", query: $query)
                .padding(Theme.Spacing.md)
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    if matchesSystem {
                        row(
                            title: Self.systemTitle, font: Theme.Typography.rowTitle,
                            isSelected: selection == nil
                        ) {
                            onSelect(nil)
                        }
                    }
                    ForEach(matches, id: \.self) { family in
                        row(
                            title: family,
                            font: .custom(family, size: ForkFontLayout.specimenSize),
                            isSelected: family == selection
                        ) {
                            onSelect(family)
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
            }
        }
        .frame(width: ForkFontLayout.width, height: ForkFontLayout.height)
    }

    private func row(
        title: String, font: Font, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(Theme.Typography.disclosure)
                    .opacity(isSelected ? 1 : 0)
                Text(title)
                    .font(font)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private enum ForkFontLayout {
    static let field: CGFloat = 150
    static let width: CGFloat = 240
    static let height: CGFloat = 280
    static let specimenSize: CGFloat = 13
}
