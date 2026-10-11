import SwiftUI

struct FileNavigatorPreview: View {
    let result: FileSearchResult?
    let expanded: Bool
    let scrollTarget: FileNavigatorPreviewScrollTarget
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics

    var body: some View {
        Host(
            content: AnyView(
                preview.environment(palette).environment(\.metrics, metrics)),
            resultID: result?.id, scrollTarget: scrollTarget
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var preview: some View {
        if !expanded {
            FileSearchPreview(result: result)
        } else if let result {
            if result.isDirectory {
                Image(systemName: "folder")
                    .font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if palette.isVisible, !palette.fileSearchQuickLook {
                FileSearchSurface(url: result.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.radius.card))
                    .padding(metrics.spacing.md)
            }
        } else {
            Color.clear
        }
    }

    private struct Host: NSViewRepresentable {
        let content: AnyView
        let resultID: String?
        let scrollTarget: FileNavigatorPreviewScrollTarget

        final class View: NSHostingView<AnyView>, KeyboardFocusRefusing {}

        func makeCoordinator() -> FileNavigatorPreviewScrollTarget { scrollTarget }

        func makeNSView(context: Context) -> View {
            let view = View(rootView: content)
            view.sizingOptions = []
            return view
        }

        func updateNSView(_ view: View, context: Context) {
            view.rootView = content
            scrollTarget.attach(view, resultID: resultID)
        }

        static func dismantleNSView(_ view: View, coordinator: FileNavigatorPreviewScrollTarget) {
            coordinator.clear(view)
            view.rootView = AnyView(EmptyView())
        }
    }
}
