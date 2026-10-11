import AppKit
import Carbon.HIToolbox
import GhosttyVt
import SwiftUI

struct GhosttyGridView: NSViewRepresentable {
    let session: TerminalSession
    var isEditor = false  // FORK: file-navigator

    func makeNSView(context: Context) -> GhosttyGridNSView {
        let view = GhosttyGridNSView()
        view.session = session
        view.isEditor = isEditor  // FORK: file-navigator
        return view
    }

    func updateNSView(_ view: GhosttyGridNSView, context: Context) {
        view.session = session
        view.isEditor = isEditor  // FORK: file-navigator
        // Reading the revision here is what makes SwiftUI call this again after each change.
        _ = session.grid?.revision
        view.needsDisplay = true
        let startedRunning = session.phase == .running && !view.wasRunning
        view.wasRunning = session.phase == .running
        if startedRunning, view.window?.firstResponder !== view {
            view.window?.makeFirstResponder(view)
        }
    }
}

@MainActor
final class GhosttyGridNSView: NSView {
    weak var session: TerminalSession?
    var isEditor = false  // FORK: file-navigator
    var wasRunning = false
    private var scrollRemainder = CGPoint.zero
    private var wasCapturingMouse = false
    private var mouseTrackingArea: NSTrackingArea?
    private var pressedButtons: [Int: GhosttyMouseButton] = [:]
    private var reportedColumns = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTrackingArea { removeTrackingArea(mouseTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .inVisibleRect, .activeAlways],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        mouseTrackingArea = area
    }

    override func layout() {
        super.layout()
        let columns = max(
            20,
            Int(
                (bounds.width - TerminalInstanceMetrics.logInset.width * 2)
                    / TerminalInstanceMetrics.characterWidth))
        guard columns != reportedColumns else { return }
        reportedColumns = columns
        session?.resizeTerminal(columns: columns)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let session, let snapshot = session.grid?.snapshot, let bar = session.grid?.scrollbar else {
            return
        }
        let rowHeight = TerminalInstanceMetrics.rowHeight
        let cellWidth = TerminalInstanceMetrics.characterWidth
        let origin = CGPoint(
            x: TerminalInstanceMetrics.logInset.width, y: TerminalInstanceMetrics.logInset.height)
        let defaultInk = NSColor(Theme.Colors.textPrimary)
        let isRunning = session.phase == .running
        let scale = window?.backingScaleFactor ?? 2
        /// Edges snap to device pixels, so fractional cell widths share edges instead of leaving seams.
        func pixelRect(column: Int, row: Int) -> CGRect {
            func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
            let left = snap(origin.x + CGFloat(column) * cellWidth)
            let right = snap(origin.x + CGFloat(column + 1) * cellWidth)
            let top = snap(origin.y + CGFloat(row) * rowHeight)
            let bottom = snap(origin.y + CGFloat(row + 1) * rowHeight)
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (y, row) in snapshot.rows.enumerated() {
                let top = origin.y + CGFloat(y) * rowHeight
                guard top + rowHeight >= dirtyRect.minY, top <= dirtyRect.maxY else { continue }
                for (x, cell) in row.enumerated() {
                    let rect = CGRect(
                        x: origin.x + CGFloat(x) * cellWidth, y: top, width: cellWidth, height: rowHeight)
                    var ink: NSColor = cell.foreground.map(Self.color) ?? defaultInk
                    var fill: NSColor? = cell.background.map(Self.color)
                    if cell.inverse {
                        fill = ink
                        ink = cell.background.map(Self.color) ?? NSColor(white: 0.08, alpha: 1)
                    }
                    if cell.faint { ink = ink.withAlphaComponent(0.55) }
                    if let fill {
                        fill.setFill()
                        pixelRect(column: x, row: y).fill()
                    }
                    guard !cell.text.isEmpty, cell.text != " " else { continue }
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: Self.font(bold: cell.bold, italic: cell.italic), .foregroundColor: ink
                    ]
                    if cell.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    if cell.strikethrough {
                        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    }
                    (cell.text as NSString).draw(at: rect.origin, withAttributes: attributes)
                }
            }
            if isRunning, snapshot.cursorVisible, let cursor = snapshot.cursor {
                let rect = pixelRect(column: cursor.x, row: cursor.y)
                (ForkTheme.current.palette?.nsColor(.accent) ?? NSColor.controlAccentColor)
                    .withAlphaComponent(0.6).setFill()
                rect.fill()
            }
            if bar.total > bar.len, bar.total > 0 {
                let track = bounds.height - origin.y * 2
                let knobHeight = max(12, track * CGFloat(bar.len) / CGFloat(bar.total))
                let knobY =
                    origin.y + (track - knobHeight) * CGFloat(bar.offset) / CGFloat(bar.total - bar.len)
                defaultInk.withAlphaComponent(0.25).setFill()
                NSBezierPath(
                    roundedRect: CGRect(x: bounds.width - 6, y: knobY, width: 3, height: knobHeight),
                    xRadius: 1.5,
                    yRadius: 1.5
                ).fill()
            }
        }
    }

    private static func color(_ rgb: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    private static func font(bold isBold: Bool, italic isItalic: Bool) -> NSFont {
        let faces = TerminalInstanceMetrics.faces
        return switch (isBold, isItalic) {
        case (true, true): faces.boldItalic
        case (true, false): faces.bold
        case (false, true): faces.italic
        case (false, false): faces.regular
        }
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) { pressMouse(event) }
    override func rightMouseDown(with event: NSEvent) { pressMouse(event) }
    override func otherMouseDown(with event: NSEvent) { pressMouse(event) }
    override func mouseUp(with event: NSEvent) { releaseMouse(event) }
    override func rightMouseUp(with event: NSEvent) { releaseMouse(event) }
    override func otherMouseUp(with event: NSEvent) { releaseMouse(event) }
    override func mouseDragged(with event: NSEvent) { dragMouse(event) }
    override func rightMouseDragged(with event: NSEvent) { dragMouse(event) }
    override func otherMouseDragged(with event: NSEvent) { dragMouse(event) }

    override func mouseMoved(with event: NSEvent) {
        forwardMouse(event, action: GHOSTTY_MOUSE_ACTION_MOTION, button: pressedButtons.values.first)
    }

    private func pressMouse(_ event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        guard let button = Self.mouseButton(event.buttonNumber) else { return }
        pressedButtons[event.buttonNumber] = button
        forwardMouse(event, action: GHOSTTY_MOUSE_ACTION_PRESS, button: button)
    }

    private func releaseMouse(_ event: NSEvent) {
        guard let button = pressedButtons.removeValue(forKey: event.buttonNumber) else { return }
        forwardMouse(event, action: GHOSTTY_MOUSE_ACTION_RELEASE, button: button)
    }

    private func dragMouse(_ event: NSEvent) {
        forwardMouse(
            event, action: GHOSTTY_MOUSE_ACTION_MOTION, button: pressedButtons[event.buttonNumber])
    }

    private func forwardMouse(
        _ event: NSEvent, action: GhosttyMouseAction, button: GhosttyMouseButton?
    ) {
        guard let session, session.phase == .running, let grid = session.grid, grid.capturesMouse else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let inset = TerminalInstanceMetrics.logInset
        var size = GhosttyMouseEncoderSize()
        size.size = MemoryLayout<GhosttyMouseEncoderSize>.size
        let position: GhosttyMousePosition
        if grid.reportsMousePixels {
            let scale = window?.backingScaleFactor ?? 2
            size.screen_width = UInt32(max(1, bounds.width * scale))
            size.screen_height = UInt32(max(1, bounds.height * scale))
            size.cell_width = UInt32(max(1, (TerminalInstanceMetrics.characterWidth * scale).rounded()))
            size.cell_height = UInt32(max(1, (TerminalInstanceMetrics.rowHeight * scale).rounded()))
            size.padding_left = UInt32(inset.width * scale)
            size.padding_right = size.padding_left
            size.padding_top = UInt32(inset.height * scale)
            size.padding_bottom = size.padding_top
            position = GhosttyMousePosition(x: Float(point.x * scale), y: Float(point.y * scale))
        } else {
            size.screen_width = UInt32(grid.columns)
            size.screen_height = UInt32(grid.rows)
            size.cell_width = 1
            size.cell_height = 1
            position = GhosttyMousePosition(
                x: Float((point.x - inset.width) / TerminalInstanceMetrics.characterWidth),
                y: Float((point.y - inset.height) / TerminalInstanceMetrics.rowHeight))
        }
        session.sendInput(
            grid.encodeMouse(
                action: action, button: button, mods: Self.mouseModifiers(event.modifierFlags),
                position: position, size: size, anyButtonPressed: !pressedButtons.isEmpty))
    }

    private static func mouseButton(_ number: Int) -> GhosttyMouseButton? {
        switch number {
        case 0: GHOSTTY_MOUSE_BUTTON_LEFT
        case 1: GHOSTTY_MOUSE_BUTTON_RIGHT
        case 2: GHOSTTY_MOUSE_BUTTON_MIDDLE
        case 3: GHOSTTY_MOUSE_BUTTON_EIGHT
        case 4: GHOSTTY_MOUSE_BUTTON_NINE
        case 5: GHOSTTY_MOUSE_BUTTON_SIX
        case 6: GHOSTTY_MOUSE_BUTTON_SEVEN
        case 7: GHOSTTY_MOUSE_BUTTON_FOUR
        case 8: GHOSTTY_MOUSE_BUTTON_FIVE
        case 9: GHOSTTY_MOUSE_BUTTON_TEN
        case 10: GHOSTTY_MOUSE_BUTTON_ELEVEN
        default: nil
        }
    }

    private static func mouseModifiers(_ flags: NSEvent.ModifierFlags) -> GhosttyMods {
        var mods: GhosttyMods = 0
        if flags.contains(.shift) { mods |= GhosttyMods(GHOSTTY_MODS_SHIFT) }
        if flags.contains(.control) { mods |= GhosttyMods(GHOSTTY_MODS_CTRL) }
        if flags.contains(.option) { mods |= GhosttyMods(GHOSTTY_MODS_ALT) }
        if flags.contains(.command) { mods |= GhosttyMods(GHOSTTY_MODS_SUPER) }
        return mods
    }

    override func scrollWheel(with event: NSEvent) {
        guard let grid = session?.grid else { return }
        let capturesMouse = session?.phase == .running && grid.capturesMouse
        if capturesMouse != wasCapturingMouse || event.phase == .began
            || event.phase == .cancelled || event.momentumPhase == .cancelled
        {
            scrollRemainder = .zero
        }
        wasCapturingMouse = capturesMouse
        if event.phase == .cancelled || event.momentumPhase == .cancelled { return }
        let rowHeight = TerminalInstanceMetrics.rowHeight
        scrollRemainder.y += event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / rowHeight : event.scrollingDeltaY * 3
        scrollRemainder.x += event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaX / TerminalInstanceMetrics.characterWidth : event.scrollingDeltaX
        let vertical = Int(scrollRemainder.y.rounded(.towardZero))
        let horizontal = Int(scrollRemainder.x.rounded(.towardZero))
        scrollRemainder.y -= CGFloat(vertical)
        scrollRemainder.x -= CGFloat(horizontal)
        if capturesMouse {
            for _ in 0..<abs(vertical) {
                forwardMouse(
                    event, action: GHOSTTY_MOUSE_ACTION_PRESS,
                    button: vertical > 0 ? GHOSTTY_MOUSE_BUTTON_FOUR : GHOSTTY_MOUSE_BUTTON_FIVE)
            }
            for _ in 0..<abs(horizontal) {
                forwardMouse(
                    event, action: GHOSTTY_MOUSE_ACTION_PRESS,
                    button: horizontal > 0 ? GHOSTTY_MOUSE_BUTTON_SIX : GHOSTTY_MOUSE_BUTTON_SEVEN)
            }
        } else {
            grid.scroll(by: -vertical)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let session, session.phase == .running, let grid = session.grid else { return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // FORK: file-navigator
        if flags.contains(.command) {
            guard isEditor, flags.isDisjoint(with: [.control, .option]),
                let letter = editorControlLetter(event), let key = Self.letterKey(letter)
            else { return }
            grid.scrollToBottom()
            session.sendInput(grid.encode(key: key, mods: GhosttyMods(GHOSTTY_MODS_CTRL)))
            return
        }
        var mods: GhosttyMods = 0
        if flags.contains(.shift) { mods |= GhosttyMods(GHOSTTY_MODS_SHIFT) }
        if flags.contains(.control) { mods |= GhosttyMods(GHOSTTY_MODS_CTRL) }
        if flags.contains(.option) { mods |= GhosttyMods(GHOSTTY_MODS_ALT) }
        var bytes: [UInt8] = []
        if let key = Self.specialKey(event.keyCode) {
            bytes = grid.encode(key: key, mods: mods)
        } else if flags.contains(.control),
            let letter = event.charactersIgnoringModifiers?.unicodeScalars.first,
            letter.isASCII, (0x40...0x7F).contains(letter.value)
        {
            bytes = [UInt8(letter.value & 0x1F)]
        } else if let text = event.characters, !text.isEmpty {
            bytes = Array(text.utf8)
            if flags.contains(.option), let base = event.charactersIgnoringModifiers {
                bytes = [0x1B] + Array(base.utf8)
            }
        }
        guard !bytes.isEmpty else { return }
        grid.scrollToBottom()
        session.sendInput(bytes)
    }

    // FORK: file-navigator
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditor, session?.phase == .running, event.modifierFlags.contains(.command),
            event.modifierFlags.isDisjoint(with: [.control, .option]), editorControlLetter(event) != nil
        else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    private func editorControlLetter(_ event: NSEvent) -> String? {
        let letter =
            ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased() ?? ""
        return TerminalEditorKey.controlLetter(letter, shift: event.modifierFlags.contains(.shift))
    }

    private static func letterKey(_ letter: String) -> GhosttyKey? {
        switch letter {
        case "s": GHOSTTY_KEY_S
        case "z": GHOSTTY_KEY_Z
        case "y": GHOSTTY_KEY_Y
        case "x": GHOSTTY_KEY_X
        case "c": GHOSTTY_KEY_C
        case "v": GHOSTTY_KEY_V
        case "a": GHOSTTY_KEY_A
        case "f": GHOSTTY_KEY_F
        default: nil
        }
    }

    private static func specialKey(_ code: UInt16) -> GhosttyKey? {
        switch Int(code) {
        case kVK_UpArrow: GHOSTTY_KEY_ARROW_UP
        case kVK_DownArrow: GHOSTTY_KEY_ARROW_DOWN
        case kVK_LeftArrow: GHOSTTY_KEY_ARROW_LEFT
        case kVK_RightArrow: GHOSTTY_KEY_ARROW_RIGHT
        case kVK_Home: GHOSTTY_KEY_HOME
        case kVK_End: GHOSTTY_KEY_END
        case kVK_PageUp: GHOSTTY_KEY_PAGE_UP
        case kVK_PageDown: GHOSTTY_KEY_PAGE_DOWN
        case kVK_ForwardDelete: GHOSTTY_KEY_DELETE
        case kVK_Delete: GHOSTTY_KEY_BACKSPACE
        case kVK_Return, kVK_ANSI_KeypadEnter: GHOSTTY_KEY_ENTER
        case kVK_Tab: GHOSTTY_KEY_TAB
        case kVK_Escape: GHOSTTY_KEY_ESCAPE
        default: nil
        }
    }
}
