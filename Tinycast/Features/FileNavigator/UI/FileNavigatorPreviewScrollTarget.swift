import AppKit
import PDFKit
import QuickLookUI

@MainActor
final class FileNavigatorPreviewScrollTarget {
    private weak var root: NSView?
    private var resultID: String?

    func attach(_ view: NSView, resultID: String?) {
        root = view
        self.resultID = resultID
    }

    func clear(_ view: NSView? = nil) {
        guard view == nil || root === view else { return }
        root = nil
        resultID = nil
    }

    func scroll(resultID: String?, down: Bool, toEnd: Bool) {
        guard let root, let resultID, self.resultID == resultID else { return }
        root.layoutSubtreeIfNeeded()
        if let pdf = descendant(PDFView.self, in: root) {
            if let scrollView = descendant(NSScrollView.self, in: pdf) {
                scroll(scrollView, down: down, toEnd: toEnd)
            } else if toEnd {
                if down { pdf.goToLastPage(nil) } else { pdf.goToFirstPage(nil) }
            } else {
                if down { pdf.goToNextPage(nil) } else { pdf.goToPreviousPage(nil) }
            }
        } else if let quickLook = descendant(QLPreviewView.self, in: root) {
            if let scrollView = descendant(NSScrollView.self, in: quickLook) {
                scroll(scrollView, down: down, toEnd: toEnd)
            }
        } else if let text = descendant(NSTextView.self, in: root),
            let scrollView = text.enclosingScrollView
        {
            if let container = text.textContainer { text.layoutManager?.ensureLayout(for: container) }
            scroll(scrollView, down: down, toEnd: toEnd)
        }
    }

    private func scroll(_ scrollView: NSScrollView, down: Bool, toEnd: Bool) {
        guard let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let minimum = document.bounds.minY
        let maximum = max(minimum, document.bounds.maxY - clip.bounds.height)
        let towardsMaximum = down == document.isFlipped
        var origin = clip.bounds.origin
        if toEnd {
            origin.y = towardsMaximum ? maximum : minimum
        } else {
            origin.y += (towardsMaximum ? 1 : -1) * clip.bounds.height * 0.9
            origin.y = min(maximum, max(minimum, origin.y))
        }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        guard !view.isHidden else { return nil }
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = descendant(type, in: child) { return match }
        }
        return nil
    }
}
