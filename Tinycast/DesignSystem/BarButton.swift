import SwiftUI

/// AppKit resolves the named base symbol directly, without inheriting a button variant.
private struct HeaderMenuSymbol: View {
    let name: String
    let size: CGFloat

    var body: some View {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        if let image = NSImage(
            systemSymbolName: SystemSymbolName.resolve(name), accessibilityDescription: nil
        )?
        .withSymbolConfiguration(configuration) {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: size, height: size)
        }
    }
}

// FORK: bar-button
// `BarButtonChrome` and `BarButton` moved to BarButtonChrome.swift so the preview target can compile them.

/// A header control that states the active choice and opens an in-window menu.
struct HeaderMenuButton: View {
    let title: String
    let icon: PopoverMenuIcon
    /// A symbol's point size before scaling; a menu beside a brand mark matches the mark instead.
    let symbolSize: CGFloat
    let isOpen: Bool
    let help: String
    let action: () -> Void
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String, icon: PopoverMenuIcon, symbolSize: CGFloat = Theme.Typography.menuSymbolSize,
        isOpen: Bool, help: String, action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.symbolSize = symbolSize
        self.isOpen = isOpen
        self.help = help
        self.action = action
    }

    init(
        title: String, systemImage: String, symbolSize: CGFloat = Theme.Typography.menuSymbolSize,
        isOpen: Bool, help: String, action: @escaping () -> Void
    ) {
        self.init(
            title: title, icon: .symbol(systemImage), symbolSize: symbolSize, isOpen: isOpen,
            help: help, action: action)
    }

    var body: some View {
        BarButton(chrome: .rounded, action: action) {
            HStack(spacing: metrics.spacing.sm) {
                switch icon {
                case .blank:
                    EmptyView()
                case .symbol(let name):
                    HeaderMenuSymbol(name: name, size: metrics.scaled(symbolSize))
                case .asset(let name):
                    Image(ForkAssets.name(name))  // FORK: named-asset
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: metrics.size.barBrandIcon, height: metrics.size.barBrandIcon)
                case .file(let path):
                    MenuFileIcon(path: path)
                case .thumbnail(let id, let data):
                    MenuThumbnail(id: id, data: data)
                }
                Text(title)
                    .font(metrics.typography.bar)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // One glyph rotates rather than swapping, so opening the menu cannot shift the layout.
                Image(systemName: "chevron.down")
                    .font(metrics.typography.disclosure)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .help(help)
    }
}
