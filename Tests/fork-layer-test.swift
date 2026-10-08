import AppKit
import Observation
import SwiftUI
import Synchronization

@main @MainActor
struct ForkLayerTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        let defaults = UserDefaults(suiteName: "com.tinycast.fork-layer-test.\(UUID())")!
        let appearance = ForkAppearance(defaults: defaults)
        ForkTypography.shared.family = "Unseeded"
        appearance.start()
        expect(ForkTypography.shared.family == nil, "start seeds the shared family")
        expect(Theme.Typography.rowTitle == .body, "nil family preserves the upstream token")
        expect(InterfaceMetrics.standard.typography.rowTitle == .body, "System preserves standard prose")
        let manager = NSFontManager.shared
        let family = manager.availableFontFamilies.first {
            !$0.hasPrefix(".") && (manager.availableMembers(ofFontFamily: $0)?.count ?? 0) > 0
        }!
        let invalidated = Mutex(false)
        withObservationTracking {
            _ = ForkAppearance.current?.fontFamily
        } onChange: {
            invalidated.withLock { $0 = true }
        }
        appearance.fontFamily = family
        expect(invalidated.withLock { $0 }, "hosting scopes observe the current family")
        expect(defaults.string(forKey: "interfaceFont") == family, "existing defaults key persists")
        expect(ForkTypography.shared.family == family, "font changes publish the shared family")
        let base = NSFont.systemFont(ofSize: 17, weight: .bold)
        let face = ForkTypography.shared.face(base)
        expect(face.familyName == family, "prose uses the selected installed family")
        expect(ForkTypography.shared.face(base) === face, "cache preserves identity")
        let detachedIdentity = await Task.detached {
            ForkTypography.shared.family = family
            return ObjectIdentifier(ForkTypography.shared.face(.systemFont(ofSize: 17, weight: .bold)))
        }.value
        expect(detachedIdentity == ObjectIdentifier(face), "detached face lookup preserves cached identity")
        let detachedProse = await Task.detached {
            let metrics = InterfaceMetrics.standard.typography
            return metrics.rowTitle == Font(metrics.textNSFont(.body))
        }.value
        expect(detachedProse, "nonisolated metrics resolve the shared family")
        expect(Theme.Typography.rowTitle == .body, "Settings tokens ignore the selected family")
        expect(Theme.Typography.noteTitle == .headline, "Theme remains upstream typography")
        for scale in [CGFloat(1), 1.2] {
            let metrics = InterfaceMetrics(scale: scale).typography
            let system = NSFont.preferredFont(forTextStyle: .body)
            let size = scale == 1 ? system.pointSize : (system.pointSize * scale).rounded()
            let expected = ForkTypography.shared.face(
                NSFont(descriptor: system.fontDescriptor, size: size)!)
            expect(metrics.rowTitle == Font(expected), "SwiftUI prose uses the family at scale \(scale)")
            expect(metrics.textNSFont(.body).familyName == family, "AppKit prose shares the family")
            expect(metrics.textNSFont(.body).pointSize == size, "AppKit prose preserves scaling")
            expect(metrics.searchFieldNSFont.familyName == family, "search uses the family")
            expect(metrics.searchField == Font(metrics.searchFieldNSFont), "search frameworks agree")
            expect(metrics.chipNSFont.familyName == family, "chip measurement uses the family")
            expect(metrics.chip == Font(metrics.chipNSFont), "chip rendering and measurement agree")
            expect(metrics.noteTitle == metrics.panelTitle, "Notes title uses the headline path")
            let weighted = metrics.textNSFont(.callout, weight: .medium)
            expect(metrics.bar == Font(weighted), "weighted prose shares the AppKit face")
            let code = metrics.textNSFont(.body, monospaced: true)
            expect(
                code == NSFont.monospacedSystemFont(ofSize: code.pointSize, weight: .regular),
                "code keeps the system monospaced face")
            let symbols = [metrics.headerIcon, metrics.disclosure, metrics.menuIcon, metrics.barSymbol]
            let swiftCode = [metrics.code, metrics.inlineCode]
            appearance.fontFamily = nil
            expect(
                symbols == [metrics.headerIcon, metrics.disclosure, metrics.menuIcon, metrics.barSymbol],
                "symbols ignore the selected family at scale \(scale)")
            expect(swiftCode == [metrics.code, metrics.inlineCode], "SwiftUI code ignores the family")
            appearance.fontFamily = family
        }
        expect(
            InterfaceMetrics.standard.typography.code == Theme.Typography.code,
            "standard code preserves the upstream token")
        expect(
            InterfaceMetrics.standard.typography.inlineCode == Theme.Typography.inlineCode,
            "standard inline code preserves the upstream token")
        appearance.fontFamily = "Tinycast-Uninstalled-\(UUID())"
        let absent = ForkTypography.shared.face(base)
        expect(absent === base, "missing family retains the exact system face")

        let sparse = manager.availableFontFamilies.first { candidate in
            guard !candidate.hasPrefix("."), let members = manager.availableMembers(ofFontFamily: candidate)
            else { return false }
            let shapeMask =
                NSFontTraitMask.italicFontMask.rawValue
                | NSFontTraitMask.condensedFontMask.rawValue | NSFontTraitMask.expandedFontMask.rawValue
            return !members.isEmpty
                && members.allSatisfy {
                    ($0[2] as? NSNumber)?.intValue != manager.weight(of: base)
                        && (($0[3] as? NSNumber)?.uintValue ?? 0) & shapeMask == 0
                }
        }
        expect(sparse != nil, "an installed family exercises unavailable-weight fallback")
        if let sparse, let members = manager.availableMembers(ofFontFamily: sparse) {
            let nearest = members.compactMap { ($0[2] as? NSNumber)?.intValue }
                .map { abs($0 - manager.weight(of: base)) }.min()!
            appearance.fontFamily = sparse
            let resolved = ForkTypography.shared.face(base)
            expect(resolved.familyName == sparse, "missing bold face stays in its family")
            expect(
                abs(manager.weight(of: resolved) - manager.weight(of: base)) == nearest,
                "missing weight chooses the nearest available member")
        }

        appearance.fontFamily = family

        let selection = Theme.Colors.selection
        let menuHover = Theme.Colors.menuHover
        let pair = ForkColors.Pair(dark: .srgbInk(1, alpha: 0.10), light: .srgbInk(0, alpha: 0.09))
        for name in [NSAppearance.Name.darkAqua, .aqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let original = NSColor(selection).usingColorSpace(.sRGB)!
                let alpha = name == .darkAqua ? 0.10 : 0.09
                expect(abs(original.alphaComponent - alpha) < 0.0001, "nil override keeps upstream alpha")
            }
        }
        appearance.colors.pairs[pair] = .init(dark: .red, light: .blue)
        for (name, expected) in [(NSAppearance.Name.darkAqua, NSColor.red), (.aqua, .blue)] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                expect(
                    NSColor(selection).usingColorSpace(.sRGB) == expected.usingColorSpace(.sRGB),
                    "existing colour token resolves the current override for \(name.rawValue)")
                expect(
                    NSColor(menuHover).usingColorSpace(.sRGB) == expected.usingColorSpace(.sRGB),
                    "equal upstream pairs share an override")
                let row = NSColor(Theme.Colors.rowHover).usingColorSpace(.sRGB)!
                let alpha = name == .darkAqua ? 0.05 : 0.045
                expect(abs(row.alphaComponent - alpha) < 0.0001, "other colour pairs stay upstream")
            }
        }
        appearance.colors.pairs.removeValue(forKey: pair)
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            expect(
                abs(NSColor(selection).usingColorSpace(.sRGB)!.alphaComponent - 0.10) < 0.0001,
                "removing an override restores an existing token")
        }
        appearance.fontFamily = nil
        expect(ForkTypography.shared.family == nil, "System clears the shared family")
        expect(defaults.object(forKey: "interfaceFont") == nil, "System removes the persisted choice")
        expect(InterfaceMetrics.standard.typography.rowTitle == .body, "System restores the upstream token")
        expect(
            InterfaceMetrics.standard.typography.searchFieldNSFont == Theme.Typography.searchFieldNSFont,
            "System restores the AppKit search font")
        print("fork-layer-test: \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
