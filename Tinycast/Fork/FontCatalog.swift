import AppKit

/// The font families this Mac can draw text with; the system face is this setting's absence.
enum FontCatalog {
    @MainActor
    static func installedFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Families with at least one fixed-pitch face, for the monospaced setting.
    @MainActor
    static func monospacedFamilies() -> [String] {
        let manager = NSFontManager.shared
        let fixedPitch = NSFontTraitMask.fixedPitchFontMask.rawValue
        return installedFamilies().filter { family in
            (manager.availableMembers(ofFontFamily: family) ?? []).contains {
                $0.count >= 4 && (($0[3] as? NSNumber)?.uintValue ?? 0) & fixedPitch != 0
            }
        }
    }

    /// A family the user picked before uninstalling the font must not outvote the system face.
    @MainActor
    static func isInstalled(_ family: String) -> Bool {
        NSFontManager.shared.availableMembers(ofFontFamily: family) != nil
    }
}
