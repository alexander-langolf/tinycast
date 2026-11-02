import AppKit

@main
@MainActor
struct ForkLyraCardTests {
    static func main() {
        placement()
        appearanceMapping()
        responseStates()
        roundedMasks()
        caretArithmetic()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        cardContentAndAppearance()
        print("PASSED: Lyra placement, appearance, response states, card content, masks and caret arithmetic")
    }

    static func placement() {
        let visible = CGRect(x: 100, y: 100, width: 1000, height: 700)
        let caret = CGRect(x: 400, y: 300, width: 2, height: 20)
        let field = CGRect(x: 400, y: 300, width: 500, height: 100)
        let marker = CGSize(width: 80, height: 30)
        let card = CGSize(width: 400, height: 160)
        func origin(_ kind: ForkLyraSuggestionController.Kind, _ anchor: CGRect,
                    _ known: Bool, _ size: CGSize) -> CGPoint {
            ForkLyraSuggestionController.panelOrigin(kind: kind, anchor: anchor, caretKnown: known,
                                                     panelSize: size, visible: visible, mainHeight: 1000)
        }
        precondition(origin(.marker, caret, true, marker) == CGPoint(x: 408, y: 680),
                     "Known marker starts six points after the caret's trailing edge")
        precondition(origin(.marker, field, false, marker) == CGPoint(x: 408, y: 604),
                     "Unknown marker belongs at the field's lower-left corner")
        for kind in [ForkLyraSuggestionController.Kind.preview, .rewrite] {
            precondition(origin(kind, caret, true, card) == CGPoint(x: 388, y: 516))
            precondition(origin(kind, field, false, card) == CGPoint(x: 400, y: 436))
            let bottom = CGRect(x: 400, y: 850, width: 2, height: 20)
            precondition(origin(kind, bottom, true, card) == CGPoint(x: 388, y: 154),
                         "Cards flip above an anchor when there is no room below")
            let bottomField = CGRect(x: 400, y: 800, width: 500, height: 100)
            precondition(origin(kind, bottomField, false, card) == CGPoint(x: 400, y: 204))
            let fits = CGRect(x: 400, y: 712, width: 2, height: 20)
            precondition(origin(kind, fits, true, card) == CGPoint(x: 388, y: 104))
            let touchesEdge = CGRect(x: 400, y: 716, width: 2, height: 20)
            precondition(origin(kind, touchesEdge, true, card) == CGPoint(x: 388, y: 104),
                         "A card that fits exactly is clamped rather than flipped")
        }
        for kind in [ForkLyraSuggestionController.Kind.marker, .preview, .rewrite] {
            for known in [false, true] {
                let size = kind == .marker ? marker : card
                let left = origin(kind, CGRect(x: -500, y: 300, width: 2, height: 20), known, size)
                let right = origin(kind, CGRect(x: 2000, y: 300, width: 2, height: 20), known, size)
                let top = origin(kind, CGRect(x: 400, y: -500, width: 2, height: 20), known, size)
                let bottom = origin(kind, CGRect(x: 400, y: 2000, width: 2, height: 20), known, size)
                precondition(left.x == 104 && right.x + size.width == 1096)
                precondition(bottom.y == 104 && top.y + size.height == 796)
            }
        }
        let secondary = ForkLyraSuggestionController.panelOrigin(
            kind: .marker, anchor: CGRect(x: -700, y: 1100, width: 300, height: 100), caretKnown: false,
            panelSize: marker, visible: CGRect(x: -1000, y: -500, width: 900, height: 500), mainHeight: 1000)
        precondition(secondary == CGPoint(x: -692, y: -196),
                     "Accessibility conversion uses the main display height on a secondary display")
        let oversized = ForkLyraSuggestionController.panelOrigin(
            kind: .rewrite, anchor: caret, caretKnown: true,
            panelSize: CGSize(width: 2000, height: 1000), visible: visible, mainHeight: 1000)
        precondition(oversized == CGPoint(x: 104, y: 104))
    }

    static func appearanceMapping() {
        let cases: [(String?, NSAppearance.Name)] = [
            ("Dark", .darkAqua), (nil, .aqua), ("Light", .aqua), ("dark", .aqua), ("", .aqua), ("Other", .aqua)
        ]
        for (style, expected) in cases {
            precondition(ForkLyraSuggestionController.appearanceName(interfaceStyle: style) == expected)
        }
    }

    static func responseStates() {
        let texts: [(String?, Bool)] = [(nil, true), ("", true), ("partial", false), (" ", false)]
        for (text, loading) in texts {
            for complete in [false, true] {
                for error in [false, true] {
                    let state = ForkLyraSuggestionController.responseState(
                        text, isComplete: complete, isError: error)
                    precondition(state.loading == loading)
                    if !loading && complete && !error {
                        precondition(state.copyAvailable && state.copyText == text)
                    } else {
                        precondition(!state.copyAvailable && state.copyText == nil,
                                     "Loading, partial and error text cannot be copied")
                    }
                }
            }
        }
    }

    static func roundedMasks() {
        for radius in [CGFloat(0), 7, 14, 15.5] {
            let image = ForkLyraSuggestionController.roundedMask(radius: radius)
            let expectedEdge: CGFloat
            switch radius {
            case 0: expectedEdge = 1
            case 7: expectedEdge = 15
            case 14: expectedEdge = 29
            default: expectedEdge = 32
            }
            precondition(image.size == NSSize(width: expectedEdge, height: expectedEdge))
            precondition(image.capInsets.top == radius && image.capInsets.left == radius)
            precondition(image.capInsets.bottom == radius && image.capInsets.right == radius)
            precondition(image.resizingMode == .stretch)
        }
    }

    static func caretArithmetic() {
        let character = CGRect(x: 120, y: 250, width: 9, height: 18)
        let trailing = CGRect(x: 129, y: 250, width: 0, height: 18)
        precondition(ForkLyraFocusObserver.trailingCaret(character) == trailing)
        precondition(ForkLyraFocusObserver.rangeCaret(
            character, candidateLocation: 4, caret: 5, candidateIndex: 2) == trailing)
        precondition(ForkLyraFocusObserver.rangeCaret(
            character, candidateLocation: 4, caret: 5, candidateIndex: 1) == trailing,
                     "At the end of the field the previous character is the second candidate")
        precondition(ForkLyraFocusObserver.rangeCaret(
            character, candidateLocation: 5, caret: 5, candidateIndex: 1) == character)
        precondition(ForkLyraFocusObserver.rangeCaret(
            character, candidateLocation: 4, caret: 5, candidateIndex: 0) == character)
        precondition(ForkLyraFocusObserver.rangeCaret(
            character, candidateLocation: 0, caret: 0, candidateIndex: 0) == character)
        let fractional = CGRect(x: -10.5, y: -20, width: 3.25, height: 18)
        precondition(ForkLyraFocusObserver.trailingCaret(fractional)
                     == CGRect(x: -7.25, y: -20, width: 0, height: 18))
        precondition(ForkLyraFocusObserver.trailingCaret(trailing) == trailing)
        for width in [CGFloat(0), 1, 1.999, 2, 2.001, 9] {
            let rect = CGRect(x: 120, y: 250, width: width, height: 18)
            let selected = ForkLyraFocusObserver.selectedTextMarkerCaret(rect)
            if width < 2 {
                precondition(selected == rect)
            } else {
                precondition(selected == nil, "A selected text-marker range is not a caret at width two or above")
            }
        }
    }

    static func cardContentAndAppearance() {
        let controller = ForkLyraSuggestionController()
        let originalAppearance = NSApp.appearance
        defer {
            controller.dismiss()
            NSApp.appearance = originalAppearance
        }
        let expected: NSAppearance.Name = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            ? .darkAqua : .aqua
        NSApp.appearance = NSAppearance(named: expected == .darkAqua ? .aqua : .darkAqua)
        let anchor = CGRect(x: 400, y: 300, width: 500, height: 100)
        let original = "Original sentence"
        for kind in [ForkLyraSuggestionController.Kind.marker, .preview, .rewrite] {
            let previousWindows = Set(NSApp.windows.map { ObjectIdentifier($0) })
            switch kind {
            case .marker: controller.showMarker(at: anchor, caretKnown: false)
            case .preview: controller.showPreview("Replacement sentence", original: original)
            case .rewrite: controller.showRewrite(at: anchor, caretKnown: false, original: original)
            case .hidden: preconditionFailure("Hidden has no panel")
            }
            let created = NSApp.windows.filter { !previousWindows.contains(ObjectIdentifier($0)) }
            precondition(created.count == 1)
            let panel = created[0]
            precondition(panel.appearance?.name == expected,
                         "Every real Lyra panel must ignore Tinycast's conflicting application appearance")
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            let cocoa = ForkLyraSuggestionController.cocoaAnchor(anchor, mainHeight: mainHeight)
            let screen = NSScreen.screens.first { $0.frame.intersects(cocoa.insetBy(dx: -1, dy: -1)) }
                ?? NSScreen.main
            let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            precondition(panel.frame.origin == ForkLyraSuggestionController.panelOrigin(
                kind: kind, anchor: anchor, caretKnown: false, panelSize: panel.frame.size,
                visible: visible, mainHeight: mainHeight), "Real panels use the tested placement calculation")
            guard let background = panel.contentView as? NSVisualEffectView,
                  let stack = background.subviews.compactMap({ $0 as? NSStackView }).first else {
                preconditionFailure("Lyra uses a material background and a content stack")
            }
            precondition(background.maskImage?.resizingMode == .stretch)
            precondition((background.layer?.cornerRadius ?? 0) == 0,
                         "The rounded mask supplies the corners without a second layer border")
            if kind != .marker {
                inspectCard(stack, controller: controller, original: original, kind: kind)
            }
            controller.dismiss()
        }
    }

    static func inspectCard(_ stack: NSStackView, controller: ForkLyraSuggestionController,
                            original: String, kind: ForkLyraSuggestionController.Kind) {
        precondition(stack.arrangedSubviews.count == 1)
        guard let text = stack.arrangedSubviews.first as? NSStackView else {
            preconditionFailure("A card contains one text stack")
        }
        precondition(text.arrangedSubviews.count == 3, "A card has only original, loading and replacement rows")
        guard let originalLabel = text.arrangedSubviews[0] as? NSTextField,
              let loading = text.arrangedSubviews[1] as? NSStackView,
              let replacement = text.arrangedSubviews[2] as? NSStackView else {
            preconditionFailure("Card row types must match their content")
        }
        precondition(originalLabel.stringValue == original && originalLabel.maximumNumberOfLines == 2)
        precondition(loading.arrangedSubviews.count == 2 && replacement.arrangedSubviews.count == 4)
        let views = descendants(stack)
        let buttons = views.compactMap { $0 as? NSButton }
        precondition(buttons.count == 1 && buttons[0].accessibilityLabel() == String(localized: "Copy"),
                     "Copy is the only card button; Accept, Dismiss and mode chips are absent")
        precondition(!views.contains { $0 is NSSegmentedControl || $0 is NSPopUpButton })
        let labels = views.compactMap { $0 as? NSTextField }
        precondition(labels.count == 3, "Only original, loading and replacement labels exist; no mode tag")
        guard let scroll = replacement.arrangedSubviews[1] as? NSScrollView,
              let body = scroll.documentView as? NSTextField else {
            preconditionFailure("The replacement uses a scrollable text field")
        }
        let copy = buttons[0]
        if kind == .preview {
            precondition(body.stringValue == "Replacement sentence" && copy.isEnabled)
            precondition(loading.isHidden && !replacement.isHidden)
            return
        }
        precondition(!loading.isHidden && replacement.isHidden && !copy.isEnabled)
        let cases: [(String?, Bool, Bool, Bool, Bool)] = [
            (nil, false, false, true, false), (nil, true, false, true, false),
            (nil, false, true, true, false), (nil, true, true, true, false),
            ("", false, false, true, false), ("", true, false, true, false),
            ("", false, true, true, false), ("", true, true, true, false),
            ("Partial", false, false, false, false), ("Complete", true, false, false, true),
            ("Error", false, true, false, false), ("Error", true, true, false, false)
        ]
        for (value, complete, error, isLoading, copyable) in cases {
            controller.updateRewrite(value, isComplete: complete, isError: error)
            precondition(loading.isHidden == !isLoading && replacement.isHidden == isLoading)
            precondition(body.stringValue == (value ?? ""))
            precondition(body.textColor == (error ? NSColor.secondaryLabelColor : NSColor.labelColor))
            precondition(copy.isEnabled == copyable)
        }
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
