import SwiftUI

struct FileNavigatorView: View {
    let selection: Int
    let scroll: ScrollIntent
    let openActions: () -> Void
    @Environment(FileNavigatorCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            if !coordinator.state.previewExpanded {
                VStack(spacing: 0) {
                    if coordinator.needsAccess {
                        Button(action: coordinator.grantAccess) {
                            Label("Grant access to this folder", systemImage: "lock.open")
                        }
                        .buttonStyle(.plain)
                        .font(metrics.typography.rowTitle)
                        .padding(metrics.spacing.md)
                        .accessibilityLabel("Grant access to this folder in Privacy settings")
                        Spacer(minLength: 0)
                    } else if coordinator.rows.isEmpty {
                        EmptyResults(text: emptyMessage)
                    } else {
                        FileNavigatorList(selection: selection, scroll: scroll, openActions: openActions)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: coordinator.state.preview ? metrics.size.clipboardListWidth : nil)
            }
            if coordinator.state.preview {
                if !coordinator.state.previewExpanded {
                    Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                }
                FileNavigatorPreview(
                    result: coordinator.previewResult, expanded: coordinator.state.previewExpanded,
                    scrollTarget: coordinator.previewScrollTarget)
            }
        }
        .overlay {
            if let result = coordinator.quickLookResult {
                FileSearchQuickLook(result: result) { coordinator.dismissQuickLook() }
            }
        }
    }

    private var emptyMessage: String {
        if !coordinator.status.isEmpty { return coordinator.status }
        if coordinator.isLoading { return "Loading…" }
        if case .global = coordinator.state.path { return "No files found" }
        return "No matching entries"
    }
}
