import SwiftUI

/// Which preference a picker edits; the list, title and fallback row follow from it.
enum ForkFontKind {
    case interface, monospaced

    var title: String { self == .interface ? "Interface font" : "Monospaced font" }
    var systemTitle: String { self == .interface ? "System" : "System Mono" }
    var subtitle: String {
        self == .interface
            ? "Applies to prose; code and symbols keep their system face."
            : "Applies to code and other fixed-width text; symbols keep their system face."
    }

    @MainActor var families: [String] {
        self == .interface ? FontCatalog.installedFamilies() : FontCatalog.monospacedFamilies()
    }
}

/// Each family previews in its own face, so the list is the specimen sheet as well as the picker.
struct ForkFontRow: View {
    var kind: ForkFontKind = .interface
    private var appearance: ForkAppearance { ForkAppearance.current! }
    @State private var isPicking = false

    private var family: String? {
        get { kind == .interface ? appearance.fontFamily : appearance.monoFontFamily }
        nonmutating set {
            if kind == .interface {
                appearance.fontFamily = newValue
            } else {
                appearance.monoFontFamily = newValue
            }
        }
    }

    var body: some View {
        SettingsRow(
            title: kind.title,
            subtitle: kind.subtitle,
            anchor: .generalAppearance
        ) {
            Button {
                isPicking = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(family ?? kind.systemTitle)
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
                FontPickerPopover(kind: kind, selection: family) {
                    family = $0
                    isPicking = false
                }
            }
        }
    }

    /// A family uninstalled since it was chosen must not draw the button in a missing face.
    private var previewFont: Font {
        guard let family, FontCatalog.isInstalled(family) else {
            return kind == .interface ? Theme.Typography.rowTrailing : .system(.callout, design: .monospaced)
        }
        return .custom(family, size: ForkFontLayout.specimenSize)
    }
}

/// Its own popover rather than a `Picker`: a few hundred families need a filter to be usable.
private struct FontPickerPopover: View {
    let kind: ForkFontKind
    let selection: String?
    let onSelect: (String?) -> Void

    @State private var query = ""
    /// Read when the popover opens, not when the row appears: the row's `onAppear` was unreliable.
    @State private var families: [String]

    init(kind: ForkFontKind, selection: String?, onSelect: @escaping (String?) -> Void) {
        self.kind = kind
        self.selection = selection
        self.onSelect = onSelect
        _families = State(initialValue: kind.families)
    }

    private var matches: [String] {
        guard !query.isEmpty else { return families }
        return families.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The row back to the default, which a filter must never be able to hide.
    private var matchesSystem: Bool {
        query.isEmpty || kind.systemTitle.localizedCaseInsensitiveContains(query)
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
                            title: kind.systemTitle,
                            font: kind == .interface
                                ? Theme.Typography.rowTitle : .system(.body, design: .monospaced),
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
