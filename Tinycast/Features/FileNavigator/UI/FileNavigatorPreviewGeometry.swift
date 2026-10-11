import AppKit

enum FileNavigatorPreviewGeometry {
    @MainActor
    static func frame(_ frame: NSRect, metrics: InterfaceMetrics, visibleFrame: NSRect?) -> NSRect {
        let chrome = metrics.size.compactHeight + metrics.size.bottomBarHeight
        let desiredHeight = metrics.scaled(680) + chrome
        let height = min(desiredHeight, visibleFrame?.height ?? desiredHeight)
        var expanded = frame
        expanded.size.height = height
        expanded.origin.y = frame.maxY - height
        if let visibleFrame {
            expanded.origin.y = max(visibleFrame.minY, min(expanded.minY, visibleFrame.maxY - height))
        }
        return expanded
    }
}
