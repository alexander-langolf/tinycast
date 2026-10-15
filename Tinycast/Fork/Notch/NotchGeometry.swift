import CoreGraphics

struct NotchGeometry: Equatable, Sendable {
    static let virtualWidth: CGFloat = 200
    static let nominalMenuBarHeight: CGFloat = 24
    static let shoulder: CGFloat = 12
    static let radius: CGFloat = 16

    let panel: CGRect
    let collapsed: CGSize
    let expanded: CGSize
    let contentTop: CGFloat
    let isVirtual: Bool

    init(
        screen: CGRect, safeAreaTop: CGFloat, auxiliaryLeftMaxX: CGFloat?, auxiliaryRightMinX: CGFloat?,
        content: CGSize
    ) {
        let physical: (width: CGFloat, midX: CGFloat)? = {
            guard safeAreaTop > 0, let left = auxiliaryLeftMaxX, let right = auxiliaryRightMinX,
                right > left
            else { return nil }
            return (right - left, (left + right) / 2)
        }()
        isVirtual = physical == nil
        let width = physical?.width ?? min(Self.virtualWidth, screen.width)
        contentTop = physical == nil ? Self.nominalMenuBarHeight : safeAreaTop
        collapsed = CGSize(width: width, height: physical == nil ? 0 : safeAreaTop)
        let bodyWidth = min(max(content.width, width), max(screen.width - 2 * Self.shoulder, 0))
        let bodyHeight = min(contentTop + content.height, screen.height)
        expanded = CGSize(width: bodyWidth, height: bodyHeight)
        let panelWidth = bodyWidth + 2 * Self.shoulder
        let midX = physical?.midX ?? screen.midX
        panel = CGRect(
            x: min(max(midX - panelWidth / 2, screen.minX), screen.maxX - panelWidth),
            y: screen.maxY - bodyHeight, width: panelWidth, height: bodyHeight)
    }

    func path(expanded isExpanded: Bool) -> CGPath {
        let body = isExpanded ? expanded : collapsed
        return Self.path(
            in: CGRect(origin: .zero, size: panel.size), body: body,
            shoulder: isExpanded ? Self.shoulder : 0,
            radius: min(Self.radius, body.height / 2, body.width / 2))
    }

    /// Same element sequence for every input, so Core Animation can interpolate any two of them.
    static func path(in bounds: CGRect, body: CGSize, shoulder s: CGFloat, radius r: CGFloat) -> CGPath {
        let k: CGFloat = 0.5523
        let left = bounds.midX - body.width / 2
        let right = bounds.midX + body.width / 2
        let top = bounds.maxY
        let bottom = top - body.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left - s, y: top))
        path.addLine(to: CGPoint(x: right + s, y: top))
        path.addCurve(
            to: CGPoint(x: right, y: top - s), control1: CGPoint(x: right + s - k * s, y: top),
            control2: CGPoint(x: right, y: top - s + k * s))
        path.addLine(to: CGPoint(x: right, y: bottom + r))
        path.addCurve(
            to: CGPoint(x: right - r, y: bottom), control1: CGPoint(x: right, y: bottom + r - k * r),
            control2: CGPoint(x: right - r + k * r, y: bottom))
        path.addLine(to: CGPoint(x: left + r, y: bottom))
        path.addCurve(
            to: CGPoint(x: left, y: bottom + r), control1: CGPoint(x: left + r - k * r, y: bottom),
            control2: CGPoint(x: left, y: bottom + r - k * r))
        path.addLine(to: CGPoint(x: left, y: top - s))
        path.addCurve(
            to: CGPoint(x: left - s, y: top), control1: CGPoint(x: left, y: top - s + k * s),
            control2: CGPoint(x: left - s + k * s, y: top))
        path.closeSubpath()
        return path
    }
}
