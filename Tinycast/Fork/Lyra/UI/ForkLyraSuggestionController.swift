import AppKit

@MainActor
private final class ForkLyraPassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ForkLyraSuggestionController {
    enum Kind { case hidden, marker, preview, rewrite }
    private(set) var kind: Kind = .hidden { didSet { if kind != oldValue { onKindChange?(kind) } } }
    var onKindChange: ((Kind) -> Void)?
    var onDismiss: (() -> Void)?
    private(set) var copyOnly = false
    private let pasteboard: NSPasteboard
    private var mouseAnchor: CGPoint?
    private var panel: NSPanel?
    private var card: NSStackView?
    private var bodyLabel: NSTextField?
    private var bodyHeight: NSLayoutConstraint?
    private var replacementRow: NSStackView?
    private var loadingRow: NSStackView?
    private var copyButton: PassiveButton?
    private var copyText: String?
    private var anchor = CGRect.zero
    private var caretKnown = true
    private var expiry: Task<Void, Never>?
    private let cardWidth: CGFloat = 400
    private let inset: CGFloat = 14
    private var contentWidth: CGFloat { cardWidth - inset * 2 }
    private var replacementWidth: CGFloat { contentWidth - 18 - 32 }

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func showMarker(at anchor: CGRect, caretKnown: Bool) {
        mouseAnchor = nil
        copyOnly = false
        self.anchor = anchor
        self.caretKnown = caretKnown
        kind = .marker
        let title = label(String(localized: "Fix"), size: 12, weight: .semibold)
        let key = label("⇥", size: 10.5, weight: .medium)
        key.textColor = .secondaryLabelColor
        let keycap = NSBox()
        keycap.boxType = .custom
        keycap.titlePosition = .noTitle
        keycap.borderWidth = 0
        keycap.cornerRadius = 4
        keycap.fillColor = .quaternaryLabelColor
        keycap.contentViewMargins = NSSize(width: 4, height: 1)
        keycap.contentView = key
        keycap.widthAnchor.constraint(equalToConstant: 20).isActive = true
        keycap.heightAnchor.constraint(equalToConstant: 17).isActive = true
        key.alignment = .center
        let row = NSStackView(views: [symbol("sparkles", tint: .controlAccentColor), title, keycap])
        row.alignment = .centerY
        row.spacing = 6
        makePanel(width: ceil(row.fittingSize.width) + 20, views: [row])
        expiry?.cancel()
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.onDismiss?()
        }
    }

    func showPreview(_ text: String, original: String) {
        expiry?.cancel()
        kind = .preview
        showCard(original: original)
        updateBody(text, isComplete: true)
    }

    func showRewrite(at anchor: CGRect, caretKnown: Bool, original: String) {
        expiry?.cancel()
        mouseAnchor = nil
        copyOnly = false
        self.anchor = anchor
        self.caretKnown = caretKnown
        kind = .rewrite
        showCard(original: original)
    }

    func showRewrite(near mouse: CGPoint, original: String) {
        expiry?.cancel()
        mouseAnchor = mouse
        copyOnly = true
        kind = .rewrite
        showCard(original: original)
    }

    func acceptRewrite(apply: () -> Void) {
        guard kind == .rewrite, copyText != nil else { return }
        guard copyOnly else { apply(); return }
        copyClicked()
        dismiss()
        onDismiss?()
    }

    private func showCard(original: String) {
        let originalLabel = NSTextField(wrappingLabelWithString: "")
        originalLabel.attributedStringValue = NSAttributedString(string: original, attributes: [
            .font: ForkTypography.resolve(.systemFont(ofSize: 13)),
            .foregroundColor: NSColor.secondaryLabelColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: NSColor.systemRed
        ])
        originalLabel.maximumNumberOfLines = 2
        originalLabel.lineBreakMode = .byTruncatingTail
        originalLabel.preferredMaxLayoutWidth = contentWidth
        originalLabel.isSelectable = false

        let body = NSTextField(wrappingLabelWithString: "")
        body.font = ForkTypography.resolve(.systemFont(ofSize: 15, weight: .semibold))
        body.isSelectable = false
        body.maximumNumberOfLines = 0
        body.preferredMaxLayoutWidth = replacementWidth
        bodyLabel = body
        let copy = iconButton("doc.on.doc", label: String(localized: "Copy"), action: #selector(copyClicked))
        copyButton = copy
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let replacement = NSStackView(views: [
            symbol("arrow.turn.down.right", tint: .secondaryLabelColor), scroll(body), spacer, copy
        ])
        replacement.alignment = .top
        replacement.spacing = 6
        replacementRow = replacement

        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .small
        progress.widthAnchor.constraint(equalToConstant: 14).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 14).isActive = true
        progress.startAnimation(nil)
        let loadingLabel = label(String(localized: "Reading your text…"), size: 14)
        loadingLabel.textColor = .secondaryLabelColor
        let loading = NSStackView(views: [progress, loadingLabel])
        loading.spacing = 8
        loading.alignment = .centerY
        loadingRow = loading

        let text = NSStackView(views: [originalLabel, loading, replacement])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        originalLabel.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        replacement.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        makePanel(width: cardWidth, views: [text])
        updateBody(nil)
    }

    func updateRewrite(_ text: String?, isComplete: Bool = false, isError: Bool = false) {
        guard kind == .rewrite else { return }
        updateBody(text, isComplete: isComplete, isError: isError)
    }

    private func updateBody(_ text: String?, isComplete: Bool = false, isError: Bool = false) {
        let state = Self.responseState(text, isComplete: isComplete, isError: isError)
        loadingRow?.isHidden = !state.loading
        replacementRow?.isHidden = state.loading
        bodyLabel?.stringValue = text ?? ""
        bodyLabel?.textColor = isError ? .secondaryLabelColor : .labelColor
        if let bodyLabel {
            let cap: CGFloat = kind == .preview ? 160 : 205
            let height = bodyLabel.cell?.cellSize(forBounds: CGRect(
                x: 0, y: 0, width: replacementWidth, height: .greatestFiniteMagnitude)).height ?? 20
            bodyHeight?.constant = min(cap, max(20, ceil(height)))
        }
        copyButton?.isEnabled = state.copyAvailable
        copyText = state.copyText
        fitPanel()
    }

    static func responseState(_ text: String?, isComplete: Bool, isError: Bool)
        -> (loading: Bool, copyAvailable: Bool, copyText: String?) {
        let loading = text == nil || text?.isEmpty == true
        let available = isComplete && !isError && !loading
        return (loading, available, available ? text : nil)
    }

    func dismiss() {
        expiry?.cancel()
        expiry = nil
        panel?.orderOut(nil)
        panel = nil
        card = nil
        bodyLabel = nil
        bodyHeight = nil
        replacementRow = nil
        loadingRow = nil
        copyButton = nil
        copyText = nil
        copyOnly = false
        mouseAnchor = nil
        kind = .hidden
    }

    func containsMouse() -> Bool { panel?.frame.contains(NSEvent.mouseLocation) ?? false }

    @objc private func copyClicked() {
        guard let copyText else { return }
        pasteboard.clearContents()
        pasteboard.setString(copyText, forType: .string)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = ForkTypography.resolve(.systemFont(ofSize: size, weight: weight))
        return field
    }

    private func symbol(_ name: String, tint: NSColor) -> NSImageView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image.contentTintColor = tint
        image.setAccessibilityElement(false)
        image.widthAnchor.constraint(equalToConstant: 12).isActive = true
        image.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return image
    }

    private func iconButton(_ symbol: String, label: String, action: Selector) -> PassiveButton {
        let button = PassiveButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
                                   target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    private func scroll(_ field: NSTextField) -> NSScrollView {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        view.scrollerStyle = .overlay
        view.autohidesScrollers = true
        view.documentView = field
        field.translatesAutoresizingMaskIntoConstraints = false
        let height = view.heightAnchor.constraint(equalToConstant: 20)
        bodyHeight = height
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: view.contentView.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: view.contentView.trailingAnchor),
            field.topAnchor.constraint(equalTo: view.contentView.topAnchor),
            view.widthAnchor.constraint(equalToConstant: replacementWidth),
            height
        ])
        return view
    }

    private func makePanel(width: CGFloat, views: [NSView]) {
        panel?.orderOut(nil)
        let created = ForkLyraPassivePanel(contentRect: CGRect(x: 0, y: 0, width: width, height: 30),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        created.level = .floating
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.becomesKeyOnlyIfNeeded = true
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        // The card sits over another app, so it follows the system appearance, not Tinycast's colour theme.
        created.appearance = NSAppearance(named: Self.appearanceName(
            interfaceStyle: UserDefaults.standard.string(forKey: "AppleInterfaceStyle")))
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        let horizontalInset: CGFloat = kind == .marker ? 10 : inset
        let verticalInset: CGFloat = kind == .marker ? 7 : inset
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: width - horizontalInset * 2),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: horizontalInset),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -horizontalInset),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: verticalInset),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -verticalInset)
        ])
        created.contentView = background
        panel = created
        card = stack
        fitPanel()
        created.orderFrontRegardless()
    }

    private func fitPanel() {
        guard let panel, let card else { return }
        let width = panel.frame.width
        let height = ceil(card.fittingSize.height) + (kind == .marker ? 14 : inset * 2)
        panel.setContentSize(CGSize(width: width, height: height))
        // A mask image, not a layer corner radius, so the window shadow follows the rounded shape.
        (panel.contentView as? NSVisualEffectView)?.maskImage = Self.roundedMask(radius: kind == .marker ? height / 2 : 14)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.invalidateShadow()
        if let mouseAnchor {
            let screen = NSScreen.screens.first { $0.frame.contains(mouseAnchor) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            panel.setFrameOrigin(Self.mousePanelOrigin(
                mouseAnchor, panelSize: CGSize(width: width, height: height), visible: visible))
            return
        }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let caret = Self.cocoaAnchor(anchor, mainHeight: mainHeight)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(caret.insetBy(dx: -1, dy: -1)) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(Self.panelOrigin(kind: kind, anchor: anchor, caretKnown: caretKnown,
                                             panelSize: CGSize(width: width, height: height),
                                             visible: visible, mainHeight: mainHeight))
    }

    static func appearanceName(interfaceStyle: String?) -> NSAppearance.Name {
        interfaceStyle == "Dark" ? .darkAqua : .aqua
    }

    static func mousePanelOrigin(_ mouse: CGPoint, panelSize: CGSize, visible: CGRect) -> CGPoint {
        let x = min(max(mouse.x + 12, visible.minX + 4), max(visible.minX + 4, visible.maxX - panelSize.width - 4))
        var y = mouse.y - panelSize.height - 12
        if y < visible.minY + 4 { y = mouse.y + 12 }
        y = min(max(y, visible.minY + 4), max(visible.minY + 4, visible.maxY - panelSize.height - 4))
        return CGPoint(x: x, y: y)
    }

    static func cocoaAnchor(_ anchor: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: anchor.minX, y: mainHeight - anchor.maxY, width: anchor.width, height: anchor.height)
    }

    static func panelOrigin(kind: Kind, anchor: CGRect, caretKnown: Bool, panelSize: CGSize,
                            visible: CGRect, mainHeight: CGFloat) -> CGPoint {
        let caret = cocoaAnchor(anchor, mainHeight: mainHeight)
        let width = panelSize.width
        let height = panelSize.height
        var x: CGFloat
        var y: CGFloat
        if kind == .marker {
            // Without a caret the anchor is the whole field; its lower-left corner sits near where typing starts.
            x = caretKnown ? caret.maxX + 6 : caret.minX + 8
            y = caretKnown ? caret.minY : caret.minY + 4
        } else {
            x = caretKnown ? caret.minX - 12 : caret.minX
            y = caret.minY - height - 4
            if y < visible.minY { y = caret.maxY + 4 }
        }
        x = min(max(x, visible.minX + 4), max(visible.minX + 4, visible.maxX - width - 4))
        y = min(max(y, visible.minY + 4), max(visible.minY + 4, visible.maxY - height - 4))
        return CGPoint(x: x, y: y)
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Clicks reach it while the host app keeps focus.
    private final class PassiveButton: NSButton {
        override var acceptsFirstResponder: Bool { false }
        override var needsPanelToBecomeKey: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
