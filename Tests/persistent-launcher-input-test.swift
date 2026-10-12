import AppKit
import SwiftUI

@main @MainActor
struct PersistentLauncherInputTests {
    static func main() {
        _ = NSApplication.shared
        let core = AppCore()
        let owner = PersistentLauncherCoordinator(core: core)
        let draft = Draft()
        let state = PaletteState()
        let panel = PalettePanel(rootView: SearchInput(draft: draft, state: state))
        panel.paletteState = state
        defer { owner.stop(); panel.orderOut(nil) }
        panel.contentView?.layoutSubtreeIfNeeded()
        guard let field = textField(in: panel.contentView!) else {
            fatalError("the retained SwiftUI input must mount")
        }
        precondition(owner.summon())
        draft.focusToken = UUID()
        owner.open(panel)
        precondition(owner.policy.phase == .opening, "the test must cover travel, not settled input")
        precondition(!owner.showsStatus && owner.headerImage != nil, "opening starts with the field")
        precondition(panel.alphaValue == 1, "the native input window must stay opaque during travel")
        precondition(panel.contentView?.layer?.opacity == 0, "only rendering is masked during travel")
        let accessory = NSTextField(frame: CGRect(x: 0, y: 0, width: 60, height: 30))
        panel.contentView?.addSubview(accessory)
        precondition(panel.makeFirstResponder(accessory))
        panel.makeKeyAndOrderFront(nil)
        precondition(panel.focusSearchField(), "the native search field can be focused synchronously")
        precondition(
            field.currentEditor() === panel.firstResponder,
            "summon must establish the search editor before yielding to the run loop")
        guard let editor = panel.firstResponder as? NSTextView else { fatalError("missing field editor") }
        panel.selectAllFieldEditorText()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "a",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        panel.sendEvent(event)
        precondition(editor.string == "a", "the first key reaches the mounted editor during travel")
        precondition(draft.text == "a", "immediate native input updates the real SwiftUI binding")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        let second = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "b",
            charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11)!
        panel.sendEvent(second)
        precondition(draft.text == "ab", "a deferred SwiftUI focus update cannot replace the first key")
        precondition(textField(in: panel.contentView!) === field, "input keeps its mounted field")
        editor.setMarkedText(
            "かな", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let selection = editor.selectedRange()
        precondition(panel.focusSearchField())
        precondition(editor.selectedRange() == selection, "an existing editor is not reselected")
        precondition(editor.hasMarkedText(), "repeated focus leaves composition intact")
        owner.reconcile()
        owner.finishOpening()
        precondition(panel.firstResponder === editor, "handoff keeps the same native editor")
        precondition(
            editor.selectedRange() == selection && editor.hasMarkedText(),
            "handoff preserves selection and marked text")
        precondition(panel.alphaValue == 1 && panel.contentView?.layer?.opacity == 1)
        precondition(panel.hasShadow && !panel.ignoresMouseEvents)
        precondition(owner.headerImage == nil, "handoff releases its temporary rendering")
        state.searchFieldFrame = .zero
        precondition(panel.makeFirstResponder(accessory))
        precondition(!panel.focusSearchField(), "a hidden header cannot steal a native editor's focus")
        precondition(accessory.currentEditor() === panel.firstResponder)
        precondition(owner.dismiss())
        owner.close(from: panel)
        precondition(owner.policy.phase == .closing)
        precondition(!owner.showsStatus, "status content waits until the field reaches the top")
        precondition(owner.headerImage != nil, "closing retains the mounted header rendering")
        precondition(owner.headerSize == CGSize(width: 750, height: 60))
        let closingImage = owner.headerImage
        draft.text = ""
        precondition(owner.headerImage === closingImage, "palette reset cannot replace the flight image")
        owner.reconcile()
        precondition(owner.headerImage != nil && !owner.showsStatus, "retarget keeps the captured field")
        PaletteMotion.reduceMotion = true
        precondition(owner.summon())
        owner.open(panel)
        precondition(owner.policy.phase == .active, "Reduce Motion settles synchronously")
        precondition(panel.alphaValue == 1 && panel.contentView?.layer?.opacity == 1)
        precondition(
            accessory.currentEditor() === panel.firstResponder,
            "animation completion cannot refocus a hidden search field")
        precondition(owner.dismiss())
        owner.close(from: panel)
        precondition(owner.policy.phase == .resting && owner.showsStatus)
        precondition(owner.headerImage == nil, "arrival releases the travelling field")
        print("persistent launcher native input presentation passed")
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap { textField(in: $0) }.first
    }
}

@MainActor @Observable private final class Draft {
    var text = "retained"
    var focusToken = UUID()
}
private struct SearchInput: View {
    @Bindable var draft: Draft
    let state: PaletteState
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Search", text: $draft.text)
            .textFieldStyle(.plain)
            .focused($focused)
            .frame(width: 400, height: 30)
            .onAppear { focused = true }
            .onChange(of: draft.focusToken) { focused = true }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                state.searchFieldFrame = $0
            }
    }
}
@MainActor final class AppCore {
    let settings = Settings()
    let paletteCoordinator = Coordinator()
    let ghosttyStatus = GhosttyStatusCoordinator()
    final class Settings {
        let interfaceSize = Size()
        var openOnCursorScreen = false
    }
    struct Size { var metrics: InterfaceMetrics { .standard } }
    final class Coordinator {
        func hidePalette(restoreFocus: Bool) {}
        func showPalette(mode: PaletteMode) {}
    }
}
struct InterfaceMetrics {
    static let standard = InterfaceMetrics()
    let size = Size()
    struct Size {
        let panelWidth: CGFloat = 750
        let compactHeight: CGFloat = 60
    }
}
@MainActor enum ForkTheme {
    static let current = Value()
    enum Token { case paletteCornerRadius }
    struct Value {
        var paletteScrim: Color { .clear }
        func points(_ token: Token, _ metrics: InterfaceMetrics) -> CGFloat { 16 }
    }
}
@MainActor final class GhosttyStatusCoordinator {
    var state: GhosttyStatusState = .closed
    var onChange: (() -> Void)?
    var tabs: [GhosttyTabSnapshot] = []
    var applicationIcon: NSImage?
    var associations: [GhosttyTerminalIdentity: GhosttyAgentKind] = [:]
    func setResting(_ value: Bool) {}
    func select(_ tab: GhosttyTabSnapshot) {}
}
struct GhosttyStatusBar: View {
    let coordinator: GhosttyStatusCoordinator
    let state: GhosttyStatusState
    let width: CGFloat
    let height: CGFloat
    let openLauncher: () -> Void
    let showOverflow: () -> Void
    let tooltip: (String?, CGRect) -> Void
    var body: some View { Color.clear.frame(width: width, height: height) }
}
struct GhosttyStatusCard: View {
    let tab: GhosttyTabSnapshot
    let agent: GhosttyAgentKind?
    let icon: NSImage?
    let height: CGFloat
    let width: CGFloat
    let tooltip: (String?, CGRect) -> Void
    let select: () -> Void
    var body: some View { Color.clear.frame(width: width, height: height) }
}
struct GhosttyStatusMetrics {
    let metrics: InterfaceMetrics
    let icon: CGFloat = 16
    let gap: CGFloat = 4
    let inset: CGFloat = 2
    let cardWidth: CGFloat = 120
    let rowHeight: CGFloat = 32
    let overflowMaxHeight: CGFloat = 300
    var restingHeight: CGFloat { metrics.size.compactHeight / 2 }
    func fit(count: Int, width: CGFloat) -> GhosttyStatusLayout {
        .fit(
            tabCount: count, width: width, launcherWidth: 28, cardWidth: cardWidth,
            overflowWidth: 30, gap: gap)
    }
}
@MainActor final class GhosttyStatusTooltipPresenter {
    func hover(_ text: String?, anchor: CGRect, metrics: InterfaceMetrics) {}
    func hide() {}
}
extension EnvironmentValues { @Entry var metrics: InterfaceMetrics = .standard }
struct GlassEffectView: View { var body: some View { Color.clear } }
struct PersistentLauncherHeader: View {
    let metrics: InterfaceMetrics
    var body: some View {
        Color.clear.frame(width: metrics.size.panelWidth, height: metrics.size.compactHeight)
    }
}
extension View { func forkAppearance() -> some View { self } }
@MainActor enum PaletteMotion {
    static var reduceMotion = false
    static let handoffDuration = 0.34
    static let windowSpring = Spring(duration: 0.34, bounce: 0)
}
extension NSScreen {
    static var underCursor: NSScreen? { screens.first }
    static var primary: NSScreen? { screens.first }
    var displayKey: String { localizedName }
}
@MainActor final class PaletteState {
    var menuOpen = false
    var onMenuOpenChanged: ((Bool) -> Void)?
    var isComposing = false
    var searchFieldFrame = CGRect.zero
    var mode = PaletteMode.launcher
    func notePointerMoved(to: CGPoint) {}
    func disarmHoverHighlight(pointerAt: CGPoint) {}
    func noteCommandHeld(_ held: Bool) {}
}
enum PaletteMode {
    case launcher, quicklinkEditor
    var isNativeEditor: Bool { self == .quicklinkEditor }
}
@MainActor enum ASCIIKeyboardLayout {
    static func character(for event: NSEvent) -> String? { nil }
}
@MainActor enum Theme {
    enum Colors { static let textPrimary = Color.white }
    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 500
    }
}
