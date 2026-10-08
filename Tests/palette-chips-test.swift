// Pins the Tab chips: when they turn on, what each key does at each level, and the pill geometry.
import Foundation

@main
struct PaletteChipsTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)  \(detail())")
            failures += 1
        }
    }

    static func main() {
        machine()
        layout()
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func reduce(
        _ state: PaletteChipsState, _ event: PaletteChipsEvent,
        available: Set<PaletteChip> = Set(PaletteChip.allCases)
    ) -> PaletteChipsTransition {
        PaletteChipsMachine.reduce(state, event, available: available)
    }

    static func machine() {
        let off = PaletteChipsState()
        let on = PaletteChipsState(isActive: true)
        check(
            "Tab in the compact bar turns chips on",
            reduce(off, .tab(collapsed: true)) == PaletteChipsTransition(state: on, handled: true))
        check(
            "Tab again turns them off",
            reduce(on, .tab(collapsed: true)) == PaletteChipsTransition(state: off, handled: true))
        check(
            "Tab outside the compact bar stays the palette's",
            !reduce(off, .tab(collapsed: false)).handled && !reduce(on, .tab(collapsed: false)).handled)
        check("⌘1 without chips is a favourite", !reduce(off, .slot(0)).handled)

        let files = reduce(on, .slot(1))
        check(
            "⌘2 opens Files",
            files
                == PaletteChipsTransition(
                    state: PaletteChipsState(isActive: true, selected: .files), handled: true,
                    effects: [.open(.files)]),
            "\(files)")
        check(
            "the same chip again closes it",
            reduce(files.state, .slot(1))
                == PaletteChipsTransition(state: on, handled: true, effects: [.close(.files)]))
        check(
            "another chip closes the first, then opens",
            reduce(files.state, .slot(0)).effects == [.close(.files), .open(.applications)])
        check(
            "⌘5 while chips are up is swallowed",
            reduce(on, .slot(4)) == PaletteChipsTransition(state: on, handled: true))
        check("a click picks like its digit", reduce(on, .pick(.shortcuts)).effects == [.open(.shortcuts)])
        check("a click with chips off does nothing", !reduce(off, .pick(.files)).handled)
        check(
            "an unavailable chip does nothing",
            reduce(on, .slot(3), available: [.applications, .files, .shortcuts])
                == PaletteChipsTransition(state: on, handled: true))

        let apps = PaletteChipsState(isActive: true, selected: .applications)
        check(
            "⎋ with a query is the palette's",
            !reduce(apps, .escape(queryEmpty: false, onChipScreen: true)).handled)
        check(
            "⎋ closes the category first",
            reduce(apps, .escape(queryEmpty: true, onChipScreen: true))
                == PaletteChipsTransition(state: on, handled: true, effects: [.close(.applications)]))
        check(
            "⎋ then turns chips off",
            reduce(on, .escape(queryEmpty: true, onChipScreen: true))
                == PaletteChipsTransition(state: off, handled: true))
        check(
            "⎋ with chips off is the palette's",
            !reduce(off, .escape(queryEmpty: true, onChipScreen: true)).handled)
        check(
            "⎋ on a screen the chips did not open is the palette's",
            !reduce(on, .escape(queryEmpty: true, onChipScreen: false)).handled)
        check(
            "leaving Files by its own back step clears the chip",
            reduce(files.state, .returnedToLauncher).state == on)
        check(
            "returning to the launcher keeps a launcher chip", reduce(apps, .returnedToLauncher).state == apps
        )
        check(
            "reset turns everything off without effects",
            reduce(apps, .reset) == PaletteChipsTransition(state: off, handled: false))
    }

    static func layout() {
        let layout = PaletteChipsLayout(panelWidth: 750, chipSide: 64, gap: 8)
        check("four chips and three gaps", layout.barWidth == 4 * 64 + 3 * 8)
        check(
            "pill, gap and chips fill the bar's width", layout.pillWidth + layout.gap + layout.barWidth == 750
        )
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let pill = CGRect(x: 400, y: 736, width: layout.pillWidth, height: 64)
        check(
            "chips sit right of the pill, top-aligned",
            layout.chipsFrame(beside: pill, pill: true, visibleFrame: screen)
                == CGRect(x: 400 + layout.pillWidth + 8, y: 736, width: layout.barWidth, height: 64))
        let expanded = CGRect(x: 1000, y: 525, width: 750, height: 475)
        check(
            "an expanded palette at the right edge puts them on its left",
            layout.chipsFrame(beside: expanded, pill: false, visibleFrame: screen).maxX == 1000 - 8)
        let offTop = CGRect(x: 100, y: 990, width: 750, height: 64)
        check(
            "chips stay on screen",
            layout.chipsFrame(beside: offTop, pill: true, visibleFrame: screen).maxY <= 1000)
    }
}
