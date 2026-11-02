import AppKit
import Observation
import Synchronization

@main
struct MonacoCloseReturnsTest {
    @MainActor static var failures = 0

    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ["alpha.swift", "bravo.swift", "charlie.swift"].map { name in
            let url = directory.appendingPathComponent(name)
            try Data("let value = 1\n".utf8).write(to: url)
            return FileSearchResult(url: url, isDirectory: false, homeDirectory: directory)
        }
        await navigatorReturns(directory: directory, files: files)
        await navigatorGlobalReturns(files: files)
        await searchReturns(files: files)
        await closeChoices(files: files)
        await closeEntryPoints(file: files[0])
        await replacement(files: files)
        await missingFolder(directory: directory, file: files[0])
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    static func navigatorReturns(directory: URL, files: [FileSearchResult]) async {
        let core = AppCore()
        let input = directory.path + "/swift"
        core.fileNavigator.show(input: input)
        await wait { !core.fileNavigator.isLoading }
        core.fileNavigator.focus(0)
        core.fileNavigator.send(.pick)
        core.fileNavigator.focus(2)
        let picked = core.fileNavigator.state.picks
        let selected = core.fileNavigator.selected?.id
        try? await core.fileNavigator.edit([files[0]])
        expect(core.monacoEditor.session != nil && !core.palette.isVisible, "navigator opens editor")
        expect(core.fileNavigator.state.picks.isEmpty, "hide releases navigator picks")
        expect(core.palette.mode == .launcher, "immediate pop to root loses the preserved mode")
        _ = await core.monacoEditor.requestClose()
        await wait { !core.fileNavigator.isLoading }
        expect(core.palette.mode == .fileNavigator && core.palette.isVisible, "returns to navigator")
        expect(core.fileNavigator.state.input == input, "restores folder and filter input")
        expect(core.fileNavigator.state.filter == "swift", "restores parsed filter")
        expect(core.fileNavigator.state.picks == picked, "restores picks cleared by hide")
        expect(core.fileNavigator.selected?.id == selected, "restores focused row by identity")
        expect(core.monacoEditorPresenter.dismissedBeforeReturn, "dismisses editor before showing palette")
        core.fileNavigator.stop()
    }

    @MainActor
    static func searchReturns(files: [FileSearchResult]) async {
        for removed in [false, true] {
            let core = AppCore()
            core.fileIndexer.index.rows = files
            core.paletteCoordinator.showPalette(mode: .fileSearch, seeding: "swift")
            core.palette.fileSearchFilter = .documents
            core.fileSearch.search("swift", filter: .documents)
            await wait { core.fileSearch.state == .ready }
            core.palette.selection = 2
            let action = core.fileNavigator.editAction(for: files[2])
            action?.action()
            await wait { core.monacoEditor.session != nil }
            let searches = core.fileIndexer.index.searches
            if removed { core.fileIndexer.index.rows = Array(files.prefix(2)) }
            _ = await core.monacoEditor.requestClose()
            await wait { core.fileSearch.state == .ready }
            expect(core.palette.isVisible && core.palette.mode == .fileSearch, "returns to Search Files")
            expect(core.palette.query == "swift", "restores search query")
            expect(core.palette.fileSearchFilter == .documents, "restores type filter")
            expect(core.fileSearchCoordinator.editorReturnFilter == .documents, "mode reset keeps restored filter")
            expect(core.fileIndexer.index.searches > searches, "re-runs query after close")
            expect(core.fileIndexer.index.lastFilter == .documents, "refreshed query uses captured type filter")
            await wait { core.palette.selection == (removed ? 1 : 2) }
            expect(core.palette.selection == (removed ? 1 : 2), "keeps result or nearest surviving row")
            expect(core.fileSearchCoordinator.editorReturnSelection == core.palette.selection,
                "view landing honors the restored selection")
            core.palette.query = "different"
            expect(core.fileSearchCoordinator.editorReturnSelection == nil, "typing retires the restore")
        }
        let core = AppCore()
        core.fileIndexer.index.rows = files
        core.paletteCoordinator.showPalette(mode: .fileSearch, seeding: "swift")
        core.fileSearch.search("swift")
        await wait { core.fileSearch.state == .ready }
        core.palette.selection = 1
        try? await core.fileNavigator.edit([files[1]])
        core.fileIndexer.index.rows = [files[2], files[0], files[1]]
        _ = await core.monacoEditor.requestClose()
        await wait { core.fileSearch.state == .ready && core.palette.selection == 2 }
        expect(core.palette.selection == 2, "selection follows result identity through reordering")
    }

    @MainActor
    static func navigatorGlobalReturns(files: [FileSearchResult]) async {
        let core = AppCore()
        core.fileIndexer.index.rows = files
        core.fileNavigator.show(input: "swift")
        await wait { !core.fileNavigator.isLoading }
        core.fileNavigator.focus(2)
        try? await core.fileNavigator.edit([files[2]])
        _ = await core.monacoEditor.requestClose()
        await wait { !core.fileNavigator.isLoading && core.fileNavigator.selected?.id == files[2].id }
        expect(core.fileNavigator.state.input == "swift", "navigator also restores global words")
        core.fileNavigator.stop()
    }

    @MainActor
    static func closeChoices(files: [FileSearchResult]) async {
        for choice in [0, 1, 2] {
            let core = AppCore()
            core.choice = choice
            var returns = 0
            await core.monacoEditor.open(path: files[0].id, origin: { returns += 1 })
            core.monacoEditor.session?.apply(.dirty(true))
            let closed = await core.monacoEditor.requestClose()
            expect(closed == (choice != 2), "save and discard close; Cancel refuses")
            expect((core.monacoEditor.session == nil) == (choice != 2), "Cancel keeps editor session")
            expect(returns == (choice == 2 ? 0 : 1), "Cancel never restores the palette")
            expect(!core.palette.isVisible, "Cancel leaves palette hidden")
        }
        let core = AppCore()
        core.choice = 0
        var returns = 0
        await core.monacoEditor.open(path: files[0].id, origin: { returns += 1 })
        core.monacoEditor.session?.apply(.dirty(true))
        core.monacoEditor.session?.host.failsSnapshot = true
        let closed = await core.monacoEditor.requestClose()
        expect(!closed && core.monacoEditor.session != nil && returns == 0, "failed save keeps editor and origin")
        core.choice = 1
        _ = await core.monacoEditor.requestClose()
        expect(returns == 1, "later discard consumes the original return once")
        _ = await core.monacoEditor.requestClose()
        expect(returns == 1, "closing twice cannot restore twice")
    }

    @MainActor
    static func replacement(files: [FileSearchResult]) async {
        let core = AppCore()
        var first = 0
        var second = 0
        await core.monacoEditor.open(path: files[0].id, origin: { first += 1 })
        await core.monacoEditor.open(path: files[1].id, origin: { second += 1 })
        expect(first == 0 && second == 0, "replacement does not return between files")
        expect(core.monacoEditor.session?.document.path == files[1].id, "replacement loads second file")
        _ = await core.monacoEditor.requestClose()
        expect(first == 1 && second == 0, "replacement keeps first origin")
        await core.monacoEditor.open(path: files[0].id)
        await core.monacoEditor.open(path: files[1].id, origin: { second += 1 })
        _ = await core.monacoEditor.requestClose()
        expect(second == 0 && !core.palette.isVisible, "nil first origin stays nil on replacement")
        await core.monacoEditor.open(path: files[0].id, origin: { first += 1 })
        await core.monacoEditor.open(path: files[0].id, origin: { second += 1 })
        _ = await core.monacoEditor.requestClose()
        expect(first == 2 && second == 0, "refocusing same file keeps first origin")
        await core.monacoEditor.open(path: files[0].id, origin: { first += 1 })
        await core.monacoEditor.open(path: files[0].id + ".missing", origin: { second += 1 })
        expect(core.monacoEditor.session?.document.path == files[0].id, "failed replacement keeps original file")
        _ = await core.monacoEditor.requestClose()
        expect(first == 3 && second == 0, "failed replacement keeps first origin")
    }

    @MainActor
    static func closeEntryPoints(file: FileSearchResult) async {
        let core = AppCore()
        var returns = 0
        await core.monacoEditor.open(path: file.id, origin: { returns += 1 })
        core.monacoEditor.session?.host.onMessage?(.close)
        await wait { core.monacoEditor.session == nil }
        expect(returns == 1, "Esc's bridge message returns once")
        await core.monacoEditor.open(path: file.id, origin: { returns += 1 })
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w",
            isARepeat: false, keyCode: 13)!
        expect(core.monacoEditor.handleKey(event), "panel claims Command-W")
        await wait { core.monacoEditor.session == nil }
        expect(returns == 2, "Command-W returns once")
        await core.monacoEditor.open(path: file.id, origin: { returns += 1 })
        _ = await core.monacoEditor.requestClose()
        expect(returns == 3, "close button's requestClose path returns once")
    }

    @MainActor
    static func missingFolder(directory: URL, file: FileSearchResult) async {
        let folder = directory.appendingPathComponent("vanishing")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let core = AppCore()
        core.fileNavigator.show(input: folder.path + "/")
        await wait { !core.fileNavigator.isLoading }
        try? await core.fileNavigator.edit([file])
        try? FileManager.default.removeItem(at: folder)
        _ = await core.monacoEditor.requestClose()
        await wait { !core.fileNavigator.isLoading }
        expect(core.fileNavigator.state.path == .missing(folder.path), "deleted folder shows missing-folder state")
        expect(core.fileNavigator.rows.isEmpty && !core.fileNavigator.status.isEmpty,
            "missing folder has no stale rows and offers its recovery state")
        core.fileNavigator.stop()
    }

    @MainActor
    static func wait(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        expect(condition(), "asynchronous operation completes")
    }

    @MainActor
    static func expect(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("FAIL: \(message)") }
    }
}

// Platform stand-ins keep native windows, shared pasteboards and preferences out of this harness.
@MainActor final class FavoritesStore {
    func files(homeDirectory: URL) -> [FileSearchResult] { [] }
}

@MainActor final class AppCore {
    let palette = PaletteState()
    let favorites = FavoritesStore()
    let settings = AppSettings()
    let fileIndexer = FileIndexer()
    let forkAppearance = ForkAppearance()
    let terminalInstances = TerminalInstances()
    let monacoEditorPresenter = MonacoEditorPresenter()
    lazy var fileSearch = FileSearchSession(index: fileIndexer.index)
    lazy var windowController = PaletteWindowController(core: self)
    lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, settings: settings, appIndex: AppIndex(), fileSearch: fileSearch,
        menuSearch: MenuSearchSession(), windowSwitch: WindowSwitchSession(), windowController: windowController)
    lazy var fileSearchCoordinator = FileSearchCoordinator(
        settings: settings, appIndex: AppIndex(), session: fileSearch, indexer: fileIndexer,
        palette: palette, paletteCoordinator: paletteCoordinator, windowController: windowController, core: self)
    private let defaultsName = "monaco-close-returns-test." + UUID().uuidString
    lazy var fileNavigator = FileNavigatorCoordinator(
        core: self, defaults: UserDefaults(suiteName: defaultsName)!)
    lazy var monacoEditor = MonacoEditorCoordinator(core: self)
    var choice: Int? = 2
    func choose(title: String, message: String, symbol: String, options: [DialogAction], defaultIndex: Int) async -> Int? { choice }
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { false }
    func showMessage(_ message: String, tone: Tone = .neutral) {}
    func showNotice(title: String, message: String, symbol: String, tone: Tone) async {}
    isolated deinit { UserDefaults.standard.removePersistentDomain(forName: defaultsName) }
}

enum Tone { case neutral, danger }
struct DialogAction {
    enum Role { case destructive, cancel }
    let title: String
    var role: Role? = nil
}
@MainActor final class AppSettings {
    var fileSearchEnabled = true
    var fileSearchShowInLauncher = true
    var fileSearchScopes: [String] = []
    var fileSearchEffectiveIgnorePatterns: [String] = []
    var fileSearchIgnorePatterns: [String] = []
    var fileNavigatorEditorKind = FileNavigatorEditorKind.monaco
    var fileNavigatorEditor = ""
    var compactMode = false
}
enum PaletteMode { case launcher, fileNavigator, fileSearch, menuSearch, switchWindows }
@MainActor @Observable final class PaletteState {
    var mode = PaletteMode.launcher
    var query = ""
    var selection = 0
    var fileSearchFilter = FileSearchFilter.all
    var isVisible = false
    var forceExpanded = false
    var menuOpen = false
    var isComposing = false
    var commandArguments: [String: String] = [:]
    var argumentEntryID: String?
    var pendingArgumentEntryID: String?
    func prepare(mode: PaletteMode) { self.mode = mode; query = ""; selection = 0; fileSearchFilter = .all }
    func push(mode: PaletteMode) { prepare(mode: mode) }
    func replace(mode: PaletteMode) { prepare(mode: mode) }
    func rewriteQuery(_ query: String) { self.query = query }
    static func argumentKey(_ id: String, _ field: String) -> String { id + field }
}
@MainActor final class PaletteWindowController {
    unowned let core: AppCore
    init(core: AppCore) { self.core = core }
    var isVisible: Bool { core.palette.isVisible }
    var isPoppedToRoot: Bool { core.palette.mode == .launcher }
    var visibleFrame: CGRect? { nil }
    var anchorView: NSView? { nil }
    var previousApp: NSRunningApplication? { nil }
    var previousOwnWindow: NSWindow? { nil }
    func consumePreservedState() -> Bool { false }
    func show() {
        core.monacoEditorPresenter.dismissedBeforeReturn = !core.monacoEditorPresenter.isVisible
        core.palette.isVisible = true
    }
    func hide(restoreFocus: Bool) {
        core.fileNavigator.stop()
        core.palette.isVisible = false
        popToRootNow()
    }
    func popToRootNow() { core.fileSearch.cancel(); core.palette.prepare(mode: .launcher) }
    func applyCollapsed(_ collapsed: Bool) {}
    func beginDrag() {}
    func endDrag() {}
}
@MainActor final class MonacoEditorPresenter {
    var isVisible = false
    var dismissedBeforeReturn = false
    func present(_ session: MonacoEditorSession) { isVisible = true }
    func dismiss() { isVisible = false }
    func focus() {}
}
@MainActor final class MonacoWebHost {
    struct Options { let text: String; let language: String; let isDark: Bool; let fontFamily: String; let fontSize: Double }
    struct Snapshot { let text: String; let version: Int }
    var onMessage: ((MonacoBridgeMessage) -> Void)?
    var failsSnapshot = false
    func open(_ options: Options) {}
    func snapshot() async -> Snapshot? { failsSnapshot ? nil : Snapshot(text: "saved", version: 1) }
    func markSaved(version: Int) { onMessage?(.dirty(false)) }
    func setTheme(isDark: Bool) {}
    func setFont(family: String, size: Double) {}
}
@MainActor @Observable final class ForkAppearance { var monoFontFamily: String? }
enum ASCIIKeyboardLayout {
    static func character(for key: Int) -> String? { nil }
    static func character(for event: NSEvent) -> String? { nil }
}
@MainActor final class AppIndex {
    func setCommandsVisible(_ commands: [CommandID], _ visible: Bool) {}
    func refresh() async {}
}
enum CommandID { case searchFiles }
final class FileIndex: Sendable {
    private struct Storage: Sendable {
        var rows: [FileSearchResult] = []
        var searches = 0
        var lastFilter: FileSearchFilter?
    }
    private let storage = Mutex(Storage())
    var rows: [FileSearchResult] {
        get { storage.withLock { $0.rows } }
        set { storage.withLock { $0.rows = newValue } }
    }
    var searches: Int { storage.withLock { $0.searches } }
    var lastFilter: FileSearchFilter? { storage.withLock { $0.lastFilter } }
    func recent(filter: FileSearchFilter) -> [FileSearchResult] { rows }
    func search(_ query: FileSearchQuery.Prepared, filter: FileSearchFilter) -> [FileSearchResult] {
        storage.withLock { value in
            value.searches += 1
            value.lastFilter = filter
            return value.rows
        }
    }
}
@MainActor final class FileIndexer {
    let index = FileIndex()
    var onIndexChanged: (() -> Void)?
    var onRecentChanged: (() -> Void)?
    func setEnabled(_ enabled: Bool) {}
    func apply(_ policy: FileSearchPolicy) {}
    func rebuild() {}
    func refreshAccess() {}
}
@MainActor final class MenuSearchSession { func reset() {}; func filter(_ query: String) {} }
@MainActor final class WindowSwitchSession { func reset() {}; func filter(_ query: String) {} }
@MainActor final class FolderWatcher {
    func watch(_ folder: String, changed: @escaping @MainActor () -> Void) {}
    func stop() {}
}
@MainActor final class FileNavigatorPreviewScrollTarget {
    func clear() {}
    func scroll(resultID: String?, down: Bool, toEnd: Bool) {}
}
@MainActor final class TerminalInstance {
    let id = UUID()
    let session = TerminalSession()
    func begin(_ command: String) {}
}
@MainActor final class TerminalSession { let phase = TerminalPhase() }
struct TerminalPhase { var acceptsCommand: Bool { true } }
@MainActor final class TerminalInstances {
    var instances: [TerminalInstance] = []
    func open(command: String, directory: String, isEditor: Bool = false) {}
}
extension AppCore { var terminalInstancesPresenter: TerminalPresenter { TerminalPresenter() } }
@MainActor struct TerminalPresenter { func focus(_ id: UUID) {} }
enum GhosttyRenderer { static let isEnabled = false }
enum TerminalGhosttyLauncher { static func openShell(in folder: String, command: String = "") async throws {} }
enum IconCache { static func purgeFitted() {} }
enum Permissions { static func openFullDiskAccessSettings() {} }
enum Paster {
    static func copyPlainText(_ text: String) {}
    static func pasteFile(_ url: URL, previousApp: NSRunningApplication?) {}
}
enum AppLauncher { static func showInFinder(_ url: URL) {} }
enum PasteboardFiles { static func write(_ url: URL, to board: NSPasteboard) {} }
@MainActor struct PopoverMenuItem {
    let title: String
    let systemImage: String
    let action: () -> Void
}
enum RipgrepSubtreeScanner {
    static func scan(_ request: DirectoryLister.Request, executable: URL, patterns: [String],
        receive: @MainActor @Sendable (DirectoryLister.Batch) async -> Void) async throws {
        try await DirectoryLister.list(request, receive: receive)
    }
}
enum SubtreeWalker {
    static func walk(_ request: DirectoryLister.Request,
        receive: @MainActor @Sendable (DirectoryLister.Batch) async -> Void) async throws {
        try await DirectoryLister.list(request, receive: receive)
    }
}

/// `PaletteCoordinator.showArguments(of:values:)` names it; this harness never runs that path.
struct AppEntry { let id: String; let name: String }
