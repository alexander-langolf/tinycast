import SwiftUI

/// The typed, history and suggestion rows, one scrolling list under the search field.
struct ChromeSearchList: View {
    @Environment(\.metrics) private var metrics
    let rows: [GoogleSearchRow]
    let selectedID: String?
    let scroll: ScrollIntent
    let onActivate: (GoogleSearchRow) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        ChromeSearchRowView(row: row, selected: row.id == selectedID)
                            .selectionFrame(row.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(row) }
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
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: selectedID == rows.first?.id, proxy: proxy)
        }
    }
}

private struct ChromeSearchRowView: View {
    @Environment(\.metrics) private var metrics
    let row: GoogleSearchRow
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        content
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.rowVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
            )
            .armedHover($hovered)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        switch row {
        case .typed(let text):
            line(text, symbol: "magnifyingglass", detail: "Search Google")
        case .history(let text):
            line(text, symbol: "clock.arrow.circlepath", detail: nil)
        case .page(let title, let url, let detail):
            line(title, symbol: "globe", brand: ChromeSearchHostIcon.asset(for: url), detail: detail)
        case .website(let title, let url, let detail):
            line(
                title, symbol: "globe", brand: ChromeSearchHostIcon.asset(for: url),
                detail: detail.isEmpty ? url.absoluteString : detail)
        case .suggestion(let text):
            line(text, symbol: "magnifyingglass", detail: nil)
        }
    }

    private func line(
        _ title: String, symbol: String, brand: String? = nil, detail: String?
    ) -> some View {
        HStack(spacing: metrics.spacing.lg) {
            icon(symbol: symbol, brand: brand)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .foregroundStyle(.secondary)
            Text(title).font(metrics.typography.rowTitle).lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            if let detail, !detail.isEmpty {
                Text(detail).font(metrics.typography.rowTrailing).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func icon(symbol: String, brand: String?) -> some View {
        if let brand {
            Image(ForkAssets.name(brand))  // FORK: named-asset
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .padding(1)
        } else {
            Image(systemName: symbol)
        }
    }
}

/// The full-panel prompt shown before anything is typed.
struct ChromeSearchStatusView: View {
    @Environment(\.metrics) private var metrics
    let symbol: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: metrics.spacing.sm) {
            Image(systemName: symbol).font(.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(title).font(metrics.typography.rowTitle).foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, metrics.spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
