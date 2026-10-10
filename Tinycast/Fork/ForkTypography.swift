import AppKit
import SwiftUI
import os

nonisolated final class ForkTypography: Sendable {
    static let shared = ForkTypography()

    private struct Key: Hashable {
        let family: String
        let size: CGFloat
        let weight: Int
        let traits: UInt
    }

    private struct State {
        var family: String?
        var monoFamily: String?
        var cache: [Key: NSFont] = [:]
        var metadata: [NSFontDescriptor: (traits: NSFontTraitMask, weight: Int)] = [:]

        mutating func face(_ base: NSFont) -> NSFont { face(base, family: family) }

        mutating func face(_ base: NSFont, family: String?) -> NSFont {
            guard let family else { return base }
            let points = base.pointSize
            let info = fontMetadata(base)
            let traits = info.traits
            let weight = info.weight
            let key = Key(family: family, size: points, weight: weight, traits: traits.rawValue)
            if let font = cache[key] { return font }
            let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
            let candidates = members.compactMap { member -> (String, Int, UInt)? in
                guard member.count >= 4, let name = member[0] as? String,
                    let weight = member[2] as? NSNumber, let traits = member[3] as? NSNumber
                else { return nil }
                return (name, weight.intValue, traits.uintValue)
            }
            let shapeMask =
                NSFontTraitMask.italicFontMask.rawValue
                | NSFontTraitMask.condensedFontMask.rawValue | NSFontTraitMask.expandedFontMask.rawValue
            let ranked = candidates.sorted {
                let leftShape = (($0.2 ^ traits.rawValue) & shapeMask).nonzeroBitCount
                let rightShape = (($1.2 ^ traits.rawValue) & shapeMask).nonzeroBitCount
                if leftShape != rightShape { return leftShape < rightShape }
                let leftWeight = abs($0.1 - weight), rightWeight = abs($1.1 - weight)
                return leftWeight == rightWeight ? $0.0 < $1.0 : leftWeight < rightWeight
            }
            let font = ranked.lazy.compactMap { NSFont(name: $0.0, size: points) }.first ?? base
            cache[key] = font
            return font
        }

        private mutating func fontMetadata(_ font: NSFont) -> (traits: NSFontTraitMask, weight: Int) {
            if let info = metadata[font.fontDescriptor] { return info }
            let manager = NSFontManager.shared
            let info = (manager.traits(of: font), manager.weight(of: font))
            metadata[font.fontDescriptor] = info
            return info
        }
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    private init() {}

    var family: String? {
        get { state.withLock { $0.family } }
        set { state.withLock { $0.family = newValue } }
    }

    var monoFamily: String? {
        get { state.withLock { $0.monoFamily } }
        set { state.withLock { $0.monoFamily = newValue } }
    }

    func face(_ base: NSFont) -> NSFont {
        state.withLockUnchecked { $0.face(base) }
    }

    /// `base` is a system monospaced font, so its traits and weight carry over to the chosen family.
    func monoFace(_ base: NSFont) -> NSFont {
        state.withLockUnchecked { $0.face(base, family: $0.monoFamily) }
    }

    static func resolveMono(_ base: NSFont) -> NSFont {
        shared.monoFace(base)
    }

    static func resolve(_ base: NSFont) -> NSFont {
        shared.face(base)
    }

    static func prose(_ base: Font, matching system: NSFont, weight: Font.Weight?) -> Font {
        guard shared.family != nil else { return base }
        guard let weight else { return Font(resolve(system)) }
        let weights: [(Font.Weight, NSFont.Weight)] = [
            (.ultraLight, .ultraLight), (.thin, .thin), (.light, .light), (.regular, .regular),
            (.medium, .medium), (.semibold, .semibold), (.bold, .bold), (.heavy, .heavy), (.black, .black)
        ]
        let value = weights.first { $0.0 == weight }?.1 ?? .regular
        return Font(resolve(.systemFont(ofSize: system.pointSize, weight: value)))
    }

    static func prose(_ base: Font, style: NSFont.TextStyle, weight: NSFont.Weight? = nil) -> Font {
        guard shared.family != nil else { return base }
        let preferred = NSFont.preferredFont(forTextStyle: style)
        let system = weight.map { NSFont.systemFont(ofSize: preferred.pointSize, weight: $0) } ?? preferred
        return Font(resolve(system))
    }

    static func prose(_ base: Font, size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        guard shared.family != nil else { return base }
        return Font(resolve(.systemFont(ofSize: size, weight: weight)))
    }
}
