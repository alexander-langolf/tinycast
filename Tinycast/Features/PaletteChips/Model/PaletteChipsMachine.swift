import Foundation

/// The four Spotlight-style categories Tab reveals beside the compact bar, in ⌘1…⌘4 order.
enum PaletteChip: Int, CaseIterable, Sendable {
    case applications
    case files
    case shortcuts
    case clipboard

    var title: String {
        switch self {
        case .applications: "Applications"
        case .files: "Files"
        case .shortcuts: "Shortcuts"
        case .clipboard: "Clipboard"
        }
    }

    var systemImage: String {
        switch self {
        case .applications: "square.grid.2x2"
        case .files: "folder"
        case .shortcuts: "square.stack.3d.up"
        case .clipboard: "list.clipboard"
        }
    }
}

struct PaletteChipsState: Equatable, Sendable {
    var isActive = false
    var selected: PaletteChip?
}

enum PaletteChipsEvent: Equatable, Sendable {
    /// ⇥; only the collapsed compact bar turns chips on or off.
    case tab(collapsed: Bool)
    /// ⌘1…⌘n as a zero-based slot.
    case slot(Int)
    case pick(PaletteChip)
    /// ⎋; `onChipScreen` is false on any screen the chips did not open.
    case escape(queryEmpty: Bool, onChipScreen: Bool)
    /// Back on the launcher by the palette's own back step or Tab.
    case returnedToLauncher
    /// Hidden, or moved to a screen no chip owns.
    case reset
}

enum PaletteChipsEffect: Equatable, Sendable {
    case open(PaletteChip)
    case close(PaletteChip)
}

struct PaletteChipsTransition: Equatable, Sendable {
    var state: PaletteChipsState
    /// False leaves the key to the palette's own handler.
    var handled: Bool
    var effects: [PaletteChipsEffect] = []
}

enum PaletteChipsMachine {
    static func reduce(
        _ state: PaletteChipsState, _ event: PaletteChipsEvent,
        available: Set<PaletteChip> = Set(PaletteChip.allCases)
    ) -> PaletteChipsTransition {
        switch event {
        case .tab(let collapsed):
            guard collapsed else { return PaletteChipsTransition(state: state, handled: false) }
            return PaletteChipsTransition(state: PaletteChipsState(isActive: !state.isActive), handled: true)
        case .slot(let index):
            guard state.isActive else { return PaletteChipsTransition(state: state, handled: false) }
            // While chips are up every ⌘digit is theirs, so ⌘5 never launches a hidden favourite.
            guard PaletteChip.allCases.indices.contains(index) else {
                return PaletteChipsTransition(state: state, handled: true)
            }
            return reduce(state, .pick(PaletteChip.allCases[index]), available: available)
        case .pick(let chip):
            guard state.isActive else { return PaletteChipsTransition(state: state, handled: false) }
            guard available.contains(chip) else { return PaletteChipsTransition(state: state, handled: true) }
            if state.selected == chip {
                return PaletteChipsTransition(
                    state: PaletteChipsState(isActive: true), handled: true, effects: [.close(chip)])
            }
            let closing = state.selected.map { [PaletteChipsEffect.close($0)] } ?? []
            return PaletteChipsTransition(
                state: PaletteChipsState(isActive: true, selected: chip), handled: true,
                effects: closing + [.open(chip)])
        case .escape(let queryEmpty, let onChipScreen):
            guard state.isActive, queryEmpty, onChipScreen else {
                return PaletteChipsTransition(state: state, handled: false)
            }
            if let selected = state.selected {
                return PaletteChipsTransition(
                    state: PaletteChipsState(isActive: true), handled: true, effects: [.close(selected)])
            }
            return PaletteChipsTransition(state: PaletteChipsState(), handled: true)
        case .returnedToLauncher:
            guard state.selected == .files || state.selected == .clipboard else {
                return PaletteChipsTransition(state: state, handled: false)
            }
            return PaletteChipsTransition(state: PaletteChipsState(isActive: state.isActive), handled: false)
        case .reset:
            return PaletteChipsTransition(state: PaletteChipsState(), handled: false)
        }
    }
}
