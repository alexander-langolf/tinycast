import AppKit

@main @MainActor
struct PersistentLauncherLifecycleTests {
    static func main() {
        let state = PaletteState()
        let settings = AppSettings()
        let index = AppIndex()
        let files = FileSearchSession()
        let menus = MenuSearchSession()
        let windows = WindowSwitchSession()
        let controller = PaletteWindowController(state: state)
        let coordinator = PaletteCoordinator(
            palette: state, settings: settings, appIndex: index, fileSearch: files,
            menuSearch: menus, windowSwitch: windows, windowController: controller)
        precondition(!coordinator.isVisible && !state.isVisible)
        precondition(index.refreshes == 0 && files.queries.isEmpty && controller.starts == 0)
        controller.canShow = false
        coordinator.showPalette(mode: .fileSearch, seeding: "blocked")
        precondition(
            state.mode == .launcher && files.queries.isEmpty && controller.starts == 0,
            "suspended or stopped presentation cannot start feature work")
        controller.canShow = true
        coordinator.showPalette(mode: .fileSearch, seeding: "project")
        precondition(state.mode == .fileSearch && state.query == "project")
        precondition(files.queries == ["project"] && controller.starts == 1)
        state.selection = 4
        let focus = state.focusToken
        controller.policy.complete(controller.policy.identity)
        precondition(state.query == "project" && state.selection == 4 && state.focusToken == focus)
        coordinator.hidePalette(restoreFocus: false)
        coordinator.hidePalette(restoreFocus: true)
        precondition(controller.ends == 1 && controller.restorations == 0)
        precondition(files.cancellations == 1, "duplicate dismissal must not repeat search teardown")
        precondition(!coordinator.isVisible && !state.isVisible)
        coordinator.togglePalette()
        precondition(state.mode == .fileSearch && state.query == "project" && state.selection == 4)
        precondition(controller.starts == 2, "closing reversal starts exactly one new session")
        coordinator.hidePalette()
        precondition(controller.restorations == 1)
        coordinator.showPalette(mode: .launcher)
        precondition(state.mode == .launcher && state.query.isEmpty, "click requests the main launcher")
        coordinator.showPalette(mode: .ai, seeding: "new question")
        precondition(controller.starts == 3, "active navigation does not restart the session")
        precondition(state.mode == .ai && state.query == "new question")
        precondition(state.backStack.last?.mode == .launcher)
        precondition(state.pop(), "Escape navigation keeps the session")
        precondition(coordinator.isVisible && controller.ends == 2)
        print("persistent launcher coordinator lifecycle passed")
    }
}

@MainActor final class AppSettings { var compactMode = true }
@MainActor final class AppIndex {
    var refreshes = 0
    func refresh() async { refreshes += 1 }
}
@MainActor final class FileSearchSession {
    var queries: [String] = []
    var cancellations = 0
    func search(_ query: String) { queries.append(query) }
    func cancel() { cancellations += 1 }
}
@MainActor final class MenuSearchSession {
    func filter(_ query: String) {}
    func reset() {}
}
@MainActor final class WindowSwitchSession {
    func filter(_ query: String) {}
    func reset() {}
}
struct AppEntry { let id: String; let name: String }
@MainActor final class PaletteWindowController {
    let state: PaletteState
    var policy = PersistentLauncherPolicy()
    var canShow = true
    var starts = 0
    var ends = 0
    var restorations = 0
    var preserved = false
    var isPoppedToRoot = false
    var isVisible: Bool { policy.isActive }
    var visibleFrame: CGRect? { nil }
    var anchorView: NSView? { nil }
    var previousApp: NSRunningApplication? { nil }
    var previousOwnWindow: NSWindow? { nil }
    init(state: PaletteState) { self.state = state }
    func consumePreservedState() -> Bool {
        defer { preserved = false }
        return preserved
    }
    func show() {
        if policy.summon() { starts += 1 }
        state.noteVisible(true)
    }
    func hide(restoreFocus: Bool) {
        guard policy.dismiss() else { return }
        ends += 1
        if restoreFocus { restorations += 1 }
        preserved = true
        state.noteVisible(false)
    }
    func popToRootNow() { state.prepare(mode: .launcher) }
    func applyCollapsed(_ collapsed: Bool) {}
    func beginDrag() {}
    func endDrag() {}
}
