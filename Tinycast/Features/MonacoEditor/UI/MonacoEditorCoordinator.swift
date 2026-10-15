import AppKit
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class MonacoEditorCoordinator {
    private(set) var session: MonacoEditorSession?
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var isTrackingFont = false

    init(core: AppCore) {
        self.core = core
    }

    /// Replaces the open file after asking about unsaved changes; the palette closes only on success.
    func open(path: String) async {
        if let session, session.document.path == path {
            core.monacoEditorPresenter.focus()
            return
        }
        guard await requestClose() else { return }
        switch await MonacoFileIO.load(path: path) {
        case .failure(let failure):
            core.showMessage(failure.message, tone: .danger)
        case .success(let loaded):
            let session = MonacoEditorSession(document: loaded.document)
            session.host.onMessage = { [weak self, weak session] message in
                guard let self, let session, self.session === session else { return }
                self.handle(message, in: session)
            }
            self.session = session
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            core.monacoEditorPresenter.present(session)
            session.host.open(
                MonacoWebHost.Options(
                    text: loaded.text, language: loaded.document.language, isDark: isDark,
                    fontFamily: fontFamily, fontSize: Self.fontSize))
            observeAppearance()
        }
    }

    /// False when the user cancels or a save fails, so the caller keeps the editor.
    func requestClose() async -> Bool {
        guard let session else { return true }
        if session.isDirty {
            let choice = await core.choose(
                title: "Save changes to “\(session.document.name)”?",
                message: "Your changes are lost if you don't save them.", symbol: "doc.badge.ellipsis",
                options: [
                    DialogAction(title: "Save"), DialogAction(title: "Don't Save", role: .destructive),
                    DialogAction(title: "Cancel", role: .cancel)
                ], defaultIndex: 0)
            switch choice {
            case 0:
                await save()
                guard self.session === session, !session.isDirty else { return false }
            case 1: break
            default: return false
            }
        }
        guard self.session === session else { return true }
        close()
        return true
    }

    func save() async {
        guard let session, !session.isSaving else { return }
        session.isSaving = true
        defer { session.isSaving = false }
        guard let snapshot = await session.host.snapshot(), self.session === session else { return }
        let path = session.document.path
        if session.document.changedOnDisk(modified: MonacoFileIO.modificationDate(path: path)) {
            let overwrite = await core.confirm(
                title: "“\(session.document.name)” changed on disk",
                message: "Saving replaces the version on disk with yours.",
                symbol: "exclamationmark.triangle",
                confirmTitle: "Overwrite")
            guard overwrite, self.session === session else { return }
        }
        do {
            let modified = try await MonacoFileIO.save(text: snapshot.text, path: path)
            guard self.session === session else { return }
            session.document = MonacoDocument(path: path, modified: modified)
            session.host.markSaved(version: snapshot.version)
        } catch {
            core.showMessage("Couldn't save: \(error.localizedDescription)", tone: .danger)
        }
    }

    /// ⌘S and ⌘W, claimed ahead of the page so they work wherever focus sits in the panel.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else {
            return false
        }
        let letter =
            ASCIIKeyboardLayout.character(for: Int(event.keyCode))
            ?? event.charactersIgnoringModifiers?.lowercased()
        switch letter {
        case "s": Task { await save() }
        case "w": Task { _ = await requestClose() }
        default: return false
        }
        return true
    }

    private func handle(_ message: MonacoBridgeMessage, in session: MonacoEditorSession) {
        session.apply(message)
        switch message {
        case .save: Task { await save() }
        case .close: Task { _ = await requestClose() }
        case .ready, .dirty: break
        }
    }

    private func close() {
        session?.host.onMessage = nil
        session = nil
        appearanceObservation = nil
        core.monacoEditorPresenter.dismiss()
    }

    // MARK: - Appearance

    private static let fontSize = 13.0

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var fontFamily: String {
        let fallback = "ui-monospace, \"SF Mono\", Menlo, monospace"
        guard let family = core.forkAppearance.monoFontFamily else { return fallback }
        return "\"\(family)\", \(fallback)"
    }

    private func observeAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.applyAppearance() }
        }
        guard !isTrackingFont else { return }
        isTrackingFont = true
        trackFont()
    }

    private func trackFont() {
        withObservationTracking {
            _ = core.forkAppearance.monoFontFamily
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.session != nil else {
                    self.isTrackingFont = false
                    return
                }
                self.trackFont()
                self.applyAppearance()
            }
        }
    }

    private func applyAppearance() {
        guard let session else { return }
        session.host.setTheme(isDark: isDark)
        session.host.setFont(family: fontFamily, size: Self.fontSize)
    }
}
