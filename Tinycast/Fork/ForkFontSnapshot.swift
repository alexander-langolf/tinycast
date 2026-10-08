import AppKit

struct ForkFontSnapshot: Sendable, Hashable {
    let name: String
    let size: CGFloat

    init(_ font: NSFont) {
        name = font.fontName
        size = font.pointSize
    }

    var font: NSFont { NSFont(name: name, size: size) ?? .systemFont(ofSize: size) }
}
