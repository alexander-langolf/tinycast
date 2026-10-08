import AppKit
import Observation

/// Tab's chips in the compact bar: their state, what picking one does to the palette, the pill.
@MainActor
@Observable
final class PaletteChipsCoordinator {
    private(set) var state = PaletteChipsState()
    @ObservationIgnored private unowned let core: AppCore

    static let slotHint = "1–4"

    init(core: AppCore) {
        self.core = core
        trackPalette()
    }

    var isActive: Bool { state.isActive }
    var selected: PaletteChip? { state.selected }

    var available: Set<PaletteChip> {
        let all = Set(PaletteChip.allCases)
        return core.settings.clipboardEnabled ? all : all.subtracting([.clipboard])
    }

    /// The launcher kind a chip scopes root search to; Files and Clipboard open their own screens.
    var launcherKind: AppEntry.Kind? {
        switch state.selected {
        case .applications: .application
        case .shortcuts: .appleShortcut
        case .files, .clipboard, nil: nil
        }
    }

    func handleTab(collapsed: Bool) -> Bool { send(.tab(collapsed: collapsed)) }

    func handleSlot(_ index: Int) -> Bool { send(.slot(index)) }

    func handleEscape(queryEmpty: Bool, mode: PaletteMode) -> Bool {
        send(.escape(queryEmpty: queryEmpty, onChipScreen: isChipScreen(mode)))
    }

    func pick(_ chip: PaletteChip) { send(.pick(chip)) }

    func layout(_ metrics: InterfaceMetrics) -> PaletteChipsLayout {
        PaletteChipsLayout(
            panelWidth: metrics.size.panelWidth, chipSide: metrics.size.compactHeight,
            gap: metrics.spacing.md)
    }

    func paletteWidth(collapsed: Bool, metrics: InterfaceMetrics) -> CGFloat {
        state.isActive && collapsed ? layout(metrics).pillWidth : metrics.size.panelWidth
    }

    func paletteRadius(collapsed: Bool, metrics: InterfaceMetrics) -> CGFloat {
        state.isActive && collapsed ? metrics.size.compactHeight / 2 : metrics.radius.panel
    }

    /// Root search narrowed to the chip's kind; empty, the kind's name lists the whole category.
    func scopedResults(query: String, _ results: (String) -> AppIndex.Results) -> AppIndex.Results {
        guard let kind = launcherKind else { return results(query) }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return results(kind.descriptor.sectionTitle)
        }
        return AppIndex.Results(entries: results(query).entries.filter { $0.kind == kind })
    }

    private func isChipScreen(_ mode: PaletteMode) -> Bool {
        switch mode {
        case .launcher: true
        case .fileSearch: state.selected == .files
        case .clipboard: state.selected == .clipboard
        default: false
        }
    }

    @discardableResult
    private func send(_ event: PaletteChipsEvent) -> Bool {
        let transition = PaletteChipsMachine.reduce(state, event, available: available)
        guard transition.state != state || !transition.effects.isEmpty else { return transition.handled }
        state = transition.state
        for effect in transition.effects { apply(effect) }
        core.paletteCoordinator.syncPaletteSize()
        core.paletteChipsPresenter.update()
        return transition.handled
    }

    private func apply(_ effect: PaletteChipsEffect) {
        let palette = core.palette
        switch effect {
        case .open(.applications), .open(.shortcuts):
            palette.forceExpanded = true
        case .close(.applications), .close(.shortcuts):
            palette.forceExpanded = false
        case .open(.files):
            palette.pushCarryingQuery(mode: .fileSearch)
        case .open(.clipboard):
            palette.pushCarryingQuery(mode: .clipboard)
        case .close(.files), .close(.clipboard):
            if palette.mode != .launcher { _ = palette.pop() }
        }
    }

    private func trackPalette() {
        withObservationTracking {
            _ = core.palette.mode
            _ = core.palette.isVisible
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.trackPalette()
                self.paletteChanged()
            }
        }
    }

    /// A hide, a back step to the launcher, or a screen no chip opened.
    private func paletteChanged() {
        guard state.isActive else { return }
        guard core.palette.isVisible else {
            send(.reset)
            return
        }
        switch core.palette.mode {
        case .launcher: send(.returnedToLauncher)
        case .fileSearch where state.selected == .files: break
        case .clipboard where state.selected == .clipboard: break
        default: send(.reset)
        }
    }
}
