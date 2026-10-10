import AppKit
import Carbon.HIToolbox
import GhosttyVt
import SwiftUI

/// FORK: libghostty prototype. Draws a `GhosttyTerminalGrid` with Core Text and forwards wheel and keys.
struct GhosttyGridView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> GhosttyGridNSView {
        let view = GhosttyGridNSView()
        view.session = session
        return view
    }

    func updateNSView(_ view: GhosttyGridNSView, context: Context) {
        view.session = session
        // Reading the revision here is what makes SwiftUI call this again after each change.
        _ = session.grid?.revision
        view.needsDisplay = true
        if session.phase == .running, view.window?.firstResponder !== view {
            view.window?.makeFirstResponder(view)
        }
    }
}

final class GhosttyGridNSView: NSView {
    weak var session: TerminalSession?
    private var scrollRemainder: CGFloat = 0
    private var reportedColumns = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

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
                        rect.fill()
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
                let rect = CGRect(
                    x: origin.x + CGFloat(cursor.x) * cellWidth, y: origin.y + CGFloat(cursor.y) * rowHeight,
                    width: cellWidth, height: rowHeight)
                NSColor.controlAccentColor.withAlphaComponent(0.6).setFill()
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

    override func scrollWheel(with event: NSEvent) {
        let rowHeight = TerminalInstanceMetrics.rowHeight
        let lines =
            event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / rowHeight : event.scrollingDeltaY * 3
        scrollRemainder += lines
        let whole = Int(scrollRemainder.rounded(.towardZero))
        guard whole != 0 else { return }
        scrollRemainder -= CGFloat(whole)
        // Positive wheel delta reveals older rows, which is up in ghostty's terms.
        session?.grid?.scroll(by: -whole)
    }

    override func keyDown(with event: NSEvent) {
        guard let session, session.phase == .running, let grid = session.grid else { return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.contains(.command) else { return }
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
