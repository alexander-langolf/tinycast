import AppKit
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class FileNavigatorCoordinator {
    private(set) var state: FileNavigatorState
    private(set) var rows: [FileSearchResult] = []
    private(set) var previewResult: FileSearchResult?
    private(set) var quickLookResult: FileSearchResult?
    private(set) var status = ""
    private(set) var needsAccess = false
    private(set) var isLoading = false
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private let home: String
    @ObservationIgnored private let watcher = FolderWatcher()
    @ObservationIgnored private let globalSearch = FileSearchSession()
    @ObservationIgnored private var folders: Set<String>
    @ObservationIgnored private var lastVerifiedFolder: String?
    @ObservationIgnored private var candidates: [FileSearchResult] = []
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var previewWork: Task<Void, Never>?
    @ObservationIgnored private var actionWork: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var actionIdentity = UUID()
    @ObservationIgnored private var active = false
    @ObservationIgnored private weak var origin: TerminalInstance?
    @ObservationIgnored private var watchedFolder: String?
    /// The folder listing `candidates` holds in full, so a new filter re-ranks instead of re-listing.
    @ObservationIgnored private var listed: Listing?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let persistencePrefix: String

    private struct Listing: Equatable {
        let folder: String
        let showHidden: Bool
        let subtree: Bool
    }

    init(core: AppCore) {
        self.core = core
        home = FileManager.default.homeDirectoryForCurrentUser.path
        state = FileNavigatorState(home: home)
        folders = ["/", home]
        persistencePrefix = (Bundle.main.bundleIdentifier ?? "com.tinycast.app") + ".fileNavigator."
        state.bookmarks = defaults.stringArray(forKey: persistencePrefix + "bookmarks") ?? []
        state.recent = defaults.stringArray(forKey: persistencePrefix + "recent") ?? []
    }

    static func isPathQuery(_ query: String) -> Bool {
        query.hasPrefix("~/") || query.hasPrefix("/")
    }

    func show(input: String? = nil, origin: TerminalInstance? = nil) {
        self.origin = origin
        state.picks = []
        state.panel = nil
        state.isOpen = true
        let initial = input ?? FileNavigatorPath.directoryInput(state.recent.first ?? home, home: home)
        core.paletteCoordinator.showPalette(mode: .fileNavigator, seeding: initial)
        updateInput(initial, force: true)
    }

    func routeRootQuery(_ query: String) {
        guard Self.isPathQuery(query) else { return }
        origin = nil
        state.picks = []
        state.panel = nil
        state.isOpen = true
        core.palette.replace(mode: .fileNavigator)
        core.palette.query = query
        core.palette.forceExpanded = true
        updateInput(query, force: true)
    }

    func resume() {
        guard core.palette.mode == .fileNavigator else { return }
        updateInput(core.palette.query, force: !active)
    }

    func stop() {
        active = false
        revision = UUID()
        work?.cancel()
        work = nil
        previewWork?.cancel()
        previewWork = nil
        actionWork?.cancel()
        watcher.stop()
        watchedFolder = nil
        globalSearch.cancel()
        rows = []
        candidates = []
        listed = nil
        folders = ["/", home, state.folder, FileNavigatorPath.parent(state.folder)]
        state.picks = []
        previewResult = nil
        quickLookResult = nil
        state.panel = nil
        isLoading = false
        IconCache.purgeFitted()
    }

    isolated deinit {
        work?.cancel()
        previewWork?.cancel()
        actionWork?.cancel()
    }

    func updateInput(_ input: String, force: Bool = false) {
        guard force || !active || state.input != input else { return }
        state.isOpen = true
        let pending = state.pendingFocus
        let previousFolder = state.folder
        let previousFocus = selected?.id
        state.setInput(input, home: home, folders: folders)
        state.pendingFocus = pending
        if force {
            load(preserving: previousFolder == state.folder ? previousFocus : nil)
        } else {
            listOrRerank()
        }
    }

    private func listOrRerank() {
        guard case .folder(let folder, _) = state.path,
            listed == Listing(folder: folder, showHidden: state.showHidden, subtree: state.subtree)
        else { load(); return }
        rerank()
    }

    private func rerank() {
        revision = UUID()
        let revision = revision
        let input = state.input
        let filter = state.filter
        let candidates = candidates
        actionWork?.cancel()
        work?.cancel()
        state.panel = nil
        work = Task { [weak self] in
            let ranked: [FileSearchResult]
            do { ranked = try await DirectoryLister.rank(candidates, filter: filter) } catch { return }
            guard let self, self.accepts(revision, input: input), !Task.isCancelled else { return }
            self.rows = ranked
            self.state.focus = 0
            self.core.palette.selection = 0
            self.schedulePreview()
        }
    }

    private func load(preserving focus: String? = nil) {
        active = true
        revision = UUID()
        let revision = revision
        actionWork?.cancel()
        work?.cancel()
        globalSearch.cancel()
        state.panel = nil
        status = ""
        needsAccess = false
        isLoading = true
        listed = nil
        rows = []
        candidates = []
        previewResult = nil
        previewWork?.cancel()
        quickLookResult = nil
        if case .global(let query) = state.path {
            watcher.stop()
            watchedFolder = nil
            globalSearch.apply(
                scopes: core.settings.fileSearchScopes, ignorePatterns: core.settings.fileSearchIgnorePatterns
            )
            globalSearch.search(query)
            observeGlobal(revision: revision)
            return
        }
        guard let candidate = FileNavigatorPath.candidate(state.input, home: home) else { return }
        let request = DirectoryLister.Request(
            folder: candidate.folder, home: home, showHidden: state.showHidden,
            ignore: FileSearchIgnoreList(
                patterns: FileSearchIgnoreList.defaults + core.settings.fileSearchIgnorePatterns),
            pickedPaths: state.picks.map(\.id))
        let input = state.input
        let subtree = state.subtree && candidate.folder == state.folder
        state.subtree = subtree
        if watchedFolder != candidate.folder {
            watcher.stop()
            watchedFolder = nil
        }
        work = Task { [weak self] in
            do {
                let receive: @MainActor @Sendable (DirectoryLister.Batch) async -> Void = {
                    [weak self] batch in
                    await self?.receive(
                        batch, request: request, input: input, revision: revision, focus: focus)
                }
                if subtree {
                    try await SubtreeWalker.walk(request, receive: receive)
                } else {
                    try await DirectoryLister.list(request, receive: receive)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.accepts(revision, input: input), !Task.isCancelled else { return }
                self.rows = []
                await self.showFailure(error, folder: request.folder, revision: revision, input: input)
            }
        }
    }

    private func accepts(_ revision: UUID, input: String) -> Bool {
        active && self.revision == revision && state.input == input
            && core.palette.mode == .fileNavigator && core.palette.isVisible
    }

    private func receive(
        _ batch: DirectoryLister.Batch, request: DirectoryLister.Request, input: String,
        revision: UUID, focus: String?
    ) async {
        guard accepts(revision, input: input), !Task.isCancelled else { return }
        folders.insert(request.folder)
        folders.insert(FileNavigatorPath.parent(request.folder))
        folders.formUnion(batch.rows.filter(\.isDirectory).map(\.id))
        let pending = state.pendingFocus
        let subtree = state.subtree
        state.setInput(input, home: home, folders: folders)
        state.subtree = subtree
        state.pendingFocus = pending
        candidates.append(contentsOf: batch.rows)
        let filter = state.filter
        let ranked: [FileSearchResult]
        do { ranked = try await DirectoryLister.rank(candidates, filter: filter) } catch { return }
        guard accepts(revision, input: input), state.folder == request.folder, !Task.isCancelled else {
            return
        }
        lastVerifiedFolder = request.folder
        rows = ranked
        if let wanted = pending ?? focus, let index = rows.firstIndex(where: { $0.id == wanted }) {
            state.focus = index
            core.palette.selection = index
        } else {
            state.focus = min(core.palette.selection, max(0, rows.count - 1))
            core.palette.selection = state.focus
        }
        state.removeVanished(batch.vanished)
        if batch.isFinal {
            state.pendingFocus = nil
            isLoading = false
            listed = Listing(folder: request.folder, showHidden: request.showHidden, subtree: subtree)
            persist()
            if watchedFolder != request.folder {
                watchedFolder = request.folder
                watcher.watch(request.folder) { [weak self] in
                    guard let self, self.active else { return }
                    self.updateInput(self.state.input, force: true)
                }
            }
        }
        schedulePreview()
    }

    private func observeGlobal(revision: UUID) {
        guard active, self.revision == revision else { return }
        withObservationTracking {
            rows = globalSearch.results
            isLoading = globalSearch.state == .searching
            status = globalSearch.state == .failed ? "File search is unavailable" : ""
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.active, self.revision == revision else { return }
                self.observeGlobal(revision: revision)
            }
        }
        focus(core.palette.selection)
    }

    private func showFailure(_ error: any Error, folder: String, revision: UUID, input: String) async {
        guard accepts(revision, input: input), !Task.isCancelled else { return }
        previewWork?.cancel()
        previewResult = nil
        quickLookResult = nil
        candidates = []
        watcher.stop()
        watchedFolder = nil
        let failure = error as? DirectoryLister.Failure ?? DirectoryLister.failure(error, folder: folder)
        switch failure {
        case .missing(let folder):
            let recovery: String
            do {
                recovery = try await DirectoryLister.recoveryFolder(
                    from: lastVerifiedFolder ?? home, home: home)
            } catch { return }
            guard accepts(revision, input: input), !Task.isCancelled else { return }
            folders.remove(folder)
            folders.insert(recovery)
            state.folder = recovery
            state.path = .missing(folder)
            state.filter = "\0"
            state.pendingFocus = nil
            state.subtree = false
            status = "No folder \(FileNavigatorPath.display(folder, home: home))"
        case .denied:
            needsAccess = true
            status = "Grant access to this folder in Privacy & Security"
        case .unreadable(let message): status = message
        }
        isLoading = false
    }

    var selected: FileSearchResult? {
        rows.indices.contains(core.palette.selection) ? rows[core.palette.selection] : nil
    }

    var targets: [FileSearchResult] { state.targets(focused: selected) }

    func focus(_ index: Int) {
        state.focus = min(max(0, index), max(0, rows.count - 1))
        core.palette.selection = state.focus
        schedulePreview()
    }

    private func schedulePreview() {
        previewWork?.cancel()
        guard active, state.preview, let selected else { previewResult = nil; return }
        let revision = revision
        previewWork = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(90)) } catch { return }
            guard let self, self.active, self.revision == revision, self.selected?.id == selected.id,
                self.state.preview, !Task.isCancelled
            else { return }
            self.previewResult = selected
        }
    }

    func send(_ event: FileNavigatorState.Event) {
        state.focus = core.palette.selection
        let previousInput = state.input
        let previousHidden = state.showHidden
        let previousSubtree = state.subtree
        state.reduce(event, rows: rows, home: home, folders: folders)
        if !state.isOpen {
            core.paletteCoordinator.hidePalette()
            core.paletteCoordinator.popToRootNow()
            return
        }
        core.palette.selection = state.focus
        if state.input != previousInput {
            core.palette.rewriteQuery(state.input)
            listOrRerank()
        } else if state.showHidden != previousHidden || state.subtree != previousSubtree {
            load()
        } else {
            schedulePreview()
        }
    }

    func closePanel() { state.panel = nil }

    func chooseFolder(_ folder: String) {
        state.panel = nil
        core.palette.rewriteQuery(FileNavigatorPath.directoryInput(folder, home: home))
        updateInput(core.palette.query, force: true)
    }

    func grantAccess() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
        else { return }
        NSWorkspace.shared.open(url)
    }

    func perform(_ action: FileNavigatorAction) {
        let targets = targets
        let folder = state.folder
        let revision = revision
        actionWork?.cancel()
        actionIdentity = UUID()
        let identity = actionIdentity
        actionWork = Task { [weak self] in
            do {
                let missing = try await FileNavigatorActionsAdapter.validate(targets, folder: folder)
                guard let self, self.accepts(revision, input: self.state.input),
                    self.actionIdentity == identity,
                    self.state.folder == folder, self.targets == targets, !Task.isCancelled
                else { return }
                guard missing.isEmpty else {
                    self.core.showMessage("An item is no longer available", tone: .danger)
                    return
                }
                self.state.panel = nil
                try await self.run(action, targets: targets, folder: folder)
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.actionIdentity == identity, !Task.isCancelled else { return }
                self.core.showMessage(error.localizedDescription, tone: .danger)
            }
        }
    }

    private func run(_ action: FileNavigatorAction, targets: [FileSearchResult], folder: String) async throws
    {
        switch action {
        case .edit:
            let files = targets.filter { !$0.isDirectory }
            guard let first = files.first else { return }
            let directory = FileNavigatorPath.parent(first.id)
            let command = FileNavigatorActionsAdapter.editorCommand(
                files, folder: directory, override: core.settings.fileNavigatorEditor)
            if GhosttyRenderer.isEnabled {
                core.terminalInstances.open(command: command, directory: directory, isEditor: true)
            } else {
                try await TerminalGhosttyLauncher.openShell(in: directory, command: command)
                core.paletteCoordinator.hidePalette(restoreFocus: false)
            }
        case .openDefault: try await FileNavigatorActionsAdapter.open(targets, core: core)
        case .ghostty:
            try await TerminalGhosttyLauncher.openShell(in: folder)
            core.paletteCoordinator.hidePalette(restoreFocus: false)
        case .terminal: core.terminalInstances.open(command: ":", directory: folder)
        case .quickLook: quickLookResult = targets.first
        case .copyPath: FileNavigatorActionsAdapter.copyPaths(targets, core: core)
        case .copyRelative:
            Paster.copyPlainText(
                targets.map { FileNavigatorPath.relative($0.id, to: folder) }.joined(separator: "\n"))
            core.showMessage("Copied relative paths")
        case .reveal: FileNavigatorActionsAdapter.reveal(targets, core: core)
        case .searchBelow:
            core.palette.rewriteQuery(FileNavigatorPath.directoryInput(folder, home: home))
            state.setInput(core.palette.query, home: home, folders: folders)
            state.subtree = true
            load()
        case .agent:
            Paster.copyPlainText(
                "File context (absolute paths):\n" + targets.map(\.id).joined(separator: "\n"))
            core.showMessage("Context copied — paste into an agent")
        case .bookmark:
            if !state.bookmarks.contains(folder) { state.bookmarks.append(folder) }
            persist()
            core.showMessage("Bookmarked folder")
        }
    }

    private func persist() {
        state.recent = [state.folder] + state.recent.filter { $0 != state.folder }.prefix(9)
        defaults.set(state.bookmarks, forKey: persistencePrefix + "bookmarks")
        defaults.set(state.recent, forKey: persistencePrefix + "recent")
    }

    func dismissQuickLook() { quickLookResult = nil }

    func cdToOrigin() {
        guard let origin, core.terminalInstances.instances.contains(where: { $0 === origin }),
            origin.session.phase.acceptsCommand
        else { core.showMessage("No originating terminal is ready for cd", tone: .danger); return }
        let directory = state.folder
        performOriginChange(origin, directory: directory)
    }

    private func performOriginChange(_ origin: TerminalInstance, directory: String) {
        actionWork?.cancel()
        let revision = revision
        actionWork = Task { [weak self, weak origin] in
            do {
                let missing = try await FileNavigatorActionsAdapter.validate([], folder: directory)
                guard let self, let origin, self.revision == revision, self.active, !Task.isCancelled,
                    self.state.folder == directory,
                    self.core.terminalInstances.instances.contains(where: { $0 === origin }),
                    origin.session.phase.acceptsCommand
                else { return }
                guard missing.isEmpty else {
                    self.core.showMessage("Folder is no longer available", tone: .danger); return
                }
                origin.begin("cd -- " + FileNavigatorPath.quote(directory))
                self.core.paletteCoordinator.hidePalette(restoreFocus: false)
                self.core.terminalInstancesPresenter.focus(origin.id)
            } catch is CancellationError { return } catch {
                self?.core.showMessage(error.localizedDescription, tone: .danger)
            }
        }
    }

    func handleKey(_ event: NSEvent, openActions: () -> Void) -> Bool {
        guard core.palette.mode == .fileNavigator, !core.palette.menuOpen, !core.palette.isComposing else {
            return false
        }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key =
            ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
        if flags == .control, key == "g" { cdToOrigin(); return true }
        if flags == .command {
            switch key {
            case "a": send(.selectAll)
            case "b": send(.bookmarks); openActions()
            case "y": send(.togglePreview)
            case ".": send(.hidden)
            case "o": perform(.ghostty)
            case "t": perform(.terminal)
            case "f": send(.subtree)
            default: return false
            }
            return true
        }
        if flags.isEmpty, Int(event.keyCode) == kVK_Space {
            // Words searching everywhere are typed, spaces included; only browsing picks.
            if case .global = state.path { return false }
            send(.pick)
            return true
        }
        if flags.isEmpty, Int(event.keyCode) == kVK_Delete, core.palette.query.isEmpty {
            return true
        }
        if flags.isEmpty, Int(event.keyCode) == kVK_Escape {
            if quickLookResult != nil { dismissQuickLook() } else { send(.escape) }
            return true
        }
        if Int(event.keyCode) == kVK_Tab, flags.isEmpty || flags == .shift {
            send(flags == .shift ? .shiftTab : .tab)
            return true
        }
        return false
    }
}
