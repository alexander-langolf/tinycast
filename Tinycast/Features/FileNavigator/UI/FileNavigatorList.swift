import SwiftUI

struct FileNavigatorList: View {
    let selection: Int
    let scroll: ScrollIntent
    let openActions: () -> Void
    @Environment(FileNavigatorCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    private var selectedID: String? {
        coordinator.rows.indices.contains(selection) ? coordinator.rows[selection].id : nil
    }

    private var title: String {
        let picks = coordinator.state.picks.count
        let mode = coordinator.state.subtree ? "Search Below" : "Files"
        return picks == 0 ? mode : "\(mode) · \(picks) picked"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: title, isFirst: true)
                    ForEach(coordinator.rows) { result in
                        FileNavigatorRow(
                            result: result, selected: result.id == selectedID,
                            picked: coordinator.state.picks.contains { $0.id == result.id },
                            showsParent: coordinator.state.subtree || isGlobal
                        )
                        .selectionFrame(result.id == selectedID)
                        .contentShape(Rectangle())
                        .onRowClick(
                            select: { select(result) },
                            activate: {
                                select(result)
                                coordinator.send(.enter)
                                if coordinator.state.panel == .actions { openActions() }
                            }
                        )
                        .onRightClick {
                            select(result); openActions()
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(scroll, row: selectedID, atOrigin: selection == 0, proxy: proxy)
        }
    }

    private var isGlobal: Bool {
        if case .global = coordinator.state.path { return true }
        return false
    }

    private func select(_ result: FileSearchResult) {
        coordinator.focus(coordinator.rows.firstIndex(of: result) ?? 0)
    }
}

private struct FileNavigatorRow: View {
    let result: FileSearchResult
    let selected: Bool
    let picked: Bool
    let showsParent: Bool
    @Environment(\.metrics) private var metrics
    @State private var image: NSImage?
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let image {
                    Image(nsImage: image).resizable()
                } else {
                    SymbolImage(name: result.isDirectory ? "folder" : "doc", size: metrics.size.resultRowIcon)
                }
            }
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(result.name + (result.isDirectory ? "/" : ""))
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsParent {
                    Text(result.parentPath)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
            if picked {
                SymbolImage(name: "checkmark.circle.fill", size: metrics.size.resultRowIcon)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.rowVertical)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.name)
        .accessibilityValue(picked ? "Picked, \(result.parentPath)" : result.parentPath)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: IconRequest(result.id)) {
            image = await IconCache.loadFittedAsync(forFile: result.id)
        }
    }
}
