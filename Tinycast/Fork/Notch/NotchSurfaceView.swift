import AppKit
import SwiftUI

@MainActor
final class NotchSurfaceView: NSView {
    private static let slide: CFTimeInterval = 0.34
    private let container = NSView()
    private let effect = NSVisualEffectView()
    private let tint = NSView()
    private let shape = CAShapeLayer()
    private let content: NSHostingView<NotchBarView>
    private var geometry: NotchGeometry

    init(geometry: NotchGeometry, model: NotchBarModel) {
        self.geometry = geometry
        content = NSHostingView(rootView: NotchBarView(model: model))
        super.init(frame: CGRect(origin: .zero, size: geometry.panel.size))
        content.sizingOptions = []
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        container.wantsLayer = true
        container.layer?.mask = shape
        tint.wantsLayer = true
        tint.isHidden = true
        shape.fillColor = NSColor.black.cgColor
        container.addSubview(effect)
        container.addSubview(tint)
        addSubview(container)
        addSubview(content)
        apply(geometry, expanded: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ geometry: NotchGeometry, expanded: Bool) {
        self.geometry = geometry
        setFrameSize(geometry.panel.size)
        container.frame = bounds
        effect.frame = bounds
        tint.frame = bounds
        shape.frame = bounds
        content.frame = CGRect(
            x: NotchGeometry.shoulder, y: 0, width: geometry.expanded.width,
            height: max(geometry.expanded.height - geometry.contentTop, 0))
        place(expanded: expanded)
    }

    /// Nil falls back to the menu-material blur, which samples whatever window lies behind.
    func setBackdrop(_ color: NSColor?) {
        tint.isHidden = color == nil
        tint.layer?.backgroundColor = color?.cgColor
    }

    func place(expanded: Bool) {
        shape.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = geometry.path(expanded: expanded)
        CATransaction.commit()
        content.alphaValue = expanded ? 1 : 0
    }

    /// `isCurrent` lets a superseded request drop its completion instead of fighting the newer one.
    func transition(
        toExpanded expanded: Bool, reduceMotion: Bool, isCurrent: @escaping @MainActor () -> Bool
    ) {
        if reduceMotion {
            let alpha = content.alphaValue
            place(expanded: expanded)
            content.alphaValue = alpha
            fade(to: expanded ? 1 : 0, duration: 0.15, then: {})
            return
        }
        if expanded {
            slide(toExpanded: true) { [weak self] in
                guard isCurrent() else { return }
                self?.fade(to: 1, duration: 0.15, then: {})
            }
        } else {
            fade(to: 0, duration: 0.1) { [weak self] in
                guard isCurrent() else { return }
                self?.slide(toExpanded: false) {}
            }
        }
    }

    private func slide(toExpanded expanded: Bool, then completion: @escaping @MainActor () -> Void) {
        let from = shape.presentation()?.path ?? shape.path
        let target = geometry.path(expanded: expanded)
        shape.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        shape.path = target
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = from
        animation.toValue = target
        animation.duration = Self.slide
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        shape.add(animation, forKey: "path")
        CATransaction.commit()
    }

    private func fade(
        to alpha: CGFloat, duration: TimeInterval, then completion: @escaping @MainActor () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            content.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
