import AppKit

extension NSAttributedString.Key {
    /// Set over a whole line so the paragraph TextKit vends carries it at index 0.
    static let noteBlockDecoration = NSAttributedString.Key("tinycast.note.blockDecoration")
}

/// What `NoteBlockLayoutFragment` draws for one line; immutable so it can cross to the layout pass.
final class NoteBlockDecoration: NSObject, Sendable {
    enum Shape: Sendable, Equatable, Hashable {
        enum CodeRow: Sendable, Hashable { case top, middle, bottom, single }
        case code(CodeRow, language: String?)
        case quote(depth: Int)
        case rule
        case bullet(level: Int)
        /// The source's own label, such as `3.` or `3)`.
        case ordered(level: Int, label: String)
        case task(level: Int, checked: Bool)
    }

    let shape: Shape
    /// Band, bar, rule, bullet or box.
    let fill: NSColor
    /// Number text or language label; a checkmark is cut out of the box instead.
    let ink: NSColor
    let bodyFont: NSFont
    let labelFont: NSFont
    var bodyPointSize: CGFloat { bodyFont.pointSize }

    init(shape: Shape, fill: NSColor, ink: NSColor, bodyFont: NSFont, labelFont: NSFont) {
        self.shape = shape
        self.fill = fill
        self.ink = ink
        self.bodyFont = bodyFont
        self.labelFont = labelFont
    }

    /// Value equality, so restyling a line to the same look does not read as a change.
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NoteBlockDecoration else { return false }
        return shape == other.shape && fill == other.fill && ink == other.ink
            && bodyFont == other.bodyFont && labelFont == other.labelFont
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(shape)
        hasher.combine(fill)
        hasher.combine(ink)
        hasher.combine(bodyFont)
        hasher.combine(labelFont)
        return hasher.finalize()
    }
}
