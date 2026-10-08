// PROTOTYPE (throwaway, UI branch) — Tinycast "$ command → terminal instance" + Spotlight-style palette.
// Not production code: no tests, minimal error handling, Swift 5 mode, one file.
//
// Plan: three instance variants (A Grow / B Bar + card / C Ticker pill) switchable from the floating
// bottom bar, plus the Spotlight-like empty palette with Tab → pill + category chips (Liquid Glass morph).
// Every instance is a REAL persistent `zsh -i` on its own pty (forkpty), with OSC 133/7 marks injected
// through a ZDOTDIR shim so the panel knows when a command starts/ends, its exit status and the cwd.
//
// Run:  ./run-mock.sh   (add --demo for a scripted 9 s smoke run, --variant=A|B|C to start on a variant)
//       or: swift -swift-version 5 TerminalInstanceMock.swift
//
// Palette keys: type to search · "$ cmd" + ↩ spawns an instance · ⇥ pill+chips · ⌘1–⌘4 pick a chip · ⎋ back/close
// Instance keys: ↩ run next command in the same session · ⌃C interrupt · ⎋ collapse/expand output
//                ⌘P pin/unpin · ⌘O open cwd in kitty · ⌘W close (kills the session)
import AppKit
import Darwin
import Observation
import SwiftUI

// MARK: - Shared prototype state (surfaced in the bottom bar)

enum InstanceVariant: Int, CaseIterable {
    case grow, card, ticker
    var label: String {
        switch self {
        case .grow: "A · Grow (bar becomes a card)"
        case .card: "B · Bar + detached output card"
        case .ticker: "C · Ticker pill (last line inline)"
        }
    }
}

@Observable final class Proto {
    static let shared = Proto()
    var variant: InstanceVariant = .grow
    var hideListUntilTyping = true
    var log: [String] = []
    func note(_ s: String) {
        log.append(s)
        if log.count > 4 { log.removeFirst() }
        print("[state] \(s)")
    }
}

enum M {
    static let barHeight: CGFloat = 56
    static let width: CGFloat = 680
    static let pillWidth: CGFloat = 330
    static let chip: CGFloat = 56
    static let gap: CGFloat = 10
    static let maxOutput: CGFloat = 340
}

// MARK: - Session: persistent zsh on a pty

@Observable final class ShellSession {
    var output = ""            // only the bytes between OSC 133;C and 133;D, escapes stripped
    var running = false
    var lastStatus: Int32?
    var cwd: String
    var altScreen = false      // a TUI (vim, less, top) asked for the alternate screen → hand off to kitty
    var ready = false
    @ObservationIgnored private var fd: Int32 = -1
    @ObservationIgnored private(set) var pid: pid_t = 0
    @ObservationIgnored private var inOutput = false
    @ObservationIgnored private var queued: [String] = []
    @ObservationIgnored private var carry = ""

    init(cwd: String = NSHomeDirectory()) {
        self.cwd = cwd
        spawn()
    }

    private static let shim: String = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tc-proto-zdotdir").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let home = NSHomeDirectory()
        try? "_tc=$ZDOTDIR; ZDOTDIR=\(home); [[ -f \(home)/.zshenv ]] && source \(home)/.zshenv; ZDOTDIR=$_tc\n"
            .write(toFile: dir + "/.zshenv", atomically: true, encoding: .utf8)
        try? """
            ZDOTDIR=\(home); [[ -f \(home)/.zshrc ]] && source \(home)/.zshrc
            _tc_precmd() { local s=$?; printf '\\e]133;D;%s\\a\\e]7;file://%s%s\\a' $s $HOST $PWD }
            _tc_preexec() { printf '\\e]133;C\\a' }
            precmd_functions+=(_tc_precmd); preexec_functions+=(_tc_preexec)
            setopt no_prompt_sp   # its "%" + padding would land inside the captured output
            printf '\\e]133;A\\a'
            """.write(toFile: dir + "/.zshrc", atomically: true, encoding: .utf8)
        return dir
    }()

    private func spawn() {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["ZDOTDIR"] = Self.shim
        env["TINYCAST"] = "1"
        env["PAGER"] = "cat"; env["GIT_PAGER"] = "cat"   // a pager would block the panel
        env.removeValue(forKey: "KITTY_WINDOW_ID")
        let args: [String] = ["/bin/zsh", "-i"]
        let argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        var size = winsize(ws_row: 40, ws_col: 96, ws_xpixel: 0, ws_ypixel: 0)
        let dir = strdup(cwd)
        var master: Int32 = 0
        let child = forkpty(&master, nil, nil, &size)
        if child == 0 {
            chdir(dir)
            execve("/bin/zsh", argv, envp)
            _exit(127)
        }
        pid = child
        fd = master
        let fdCopy = master
        Thread.detachNewThread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 16384)
            while true {
                let n = read(fdCopy, &buf, buf.count)
                if n <= 0 { break }
                let chunk = String(decoding: buf[0..<n], as: UTF8.self)
                DispatchQueue.main.async { self?.ingest(chunk) }
            }
            DispatchQueue.main.async { self?.running = false }
        }
    }

    func run(_ command: String) {
        guard ready else { queued.append(command); return }
        running = true
        lastStatus = nil
        output = ""
        altScreen = false
        send(command + "\r")
    }

    func interrupt() { send("\u{03}") }
    private func send(_ s: String) { _ = s.withCString { write(fd, $0, strlen($0)) } }

    func terminate() {
        if pid > 0 { kill(-pid, SIGHUP); kill(pid, SIGHUP) }
        close(fd)
        var st: Int32 = 0
        _ = waitpid(pid, &st, WNOHANG)
    }

    // Tiny "terminal": split on OSC marks, keep only command output, strip CSI/OSC.
    private func ingest(_ chunk: String) {
        var s = carry + chunk
        carry = ""
        // Hold back an escape sequence cut at the chunk edge: an OSC without its BEL/ST, or a bare CSI.
        if let osc = s.range(of: "\u{1B}]", options: .backwards),
            !s[osc.upperBound...].contains("\u{07}"), !s[osc.upperBound...].contains("\u{1B}\\")
        {
            carry = String(s[osc.lowerBound...]); s = String(s[..<osc.lowerBound])
        } else if let esc = s.lastIndex(of: "\u{1B}"), s.distance(from: esc, to: s.endIndex) < 16,
            !s[s.index(after: esc)...].contains(where: { $0.isLetter || $0 == "~" || $0 == "\\" })
        {
            carry = String(s[esc...]); s = String(s[..<esc])
        }
        let pattern = #/\x1B\](133;[A-D](?:;(\d+))?|7;file:\/\/[^\/]*([^\x07]*))\x07/#
        var rest = Substring(s)
        while let m = rest.firstMatch(of: pattern) {
            if inOutput { append(rest[..<m.range.lowerBound]) }
            let tag = m.output.1
            if tag.hasPrefix("133;A") {
                ready = true
                let q = queued; queued = []
                q.forEach(run)
            } else if tag.hasPrefix("133;C") {
                inOutput = true
            } else if tag.hasPrefix("133;D") {
                inOutput = false
                running = false
                lastStatus = Int32(m.output.2 ?? "0") ?? 0
                if !ready { ready = true }
            } else if let path = m.output.3 {
                cwd = String(path).removingPercentEncoding ?? String(path)
            }
            rest = rest[m.range.upperBound...]
        }
        if inOutput { append(rest) }
    }

    private func append(_ raw: Substring) {
        if raw.contains("\u{1B}[?1049h") { altScreen = true }
        var t = String(raw)
        t = t.replacing(#/\x1B\[[0-9;?]*[ -\/]*[@-~]/#, with: "")
        t = t.replacing(#/\x1B\][^\x07\x1B]*(\x07|\x1B\\)/#, with: "")
        t = t.replacing(#/\x1Bk[^\x1B]*\x1B\\/#, with: "")
        t = t.replacing(#/\x1B[=>()][0-9A-B]?/#, with: "")
        t = t.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "")
        output += t
        if output.count > 200_000 { output = String(output.suffix(150_000)) }
    }
}

// MARK: - Instance model + window

@Observable final class InstanceModel: Identifiable {
    let id = UUID()
    let session = ShellSession()
    var input: String
    var lastCommand: String
    var pinned = true
    var expanded = true
    init(command: String) {
        input = command
        lastCommand = command
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class InstanceController: NSObject, NSWindowDelegate {
    let model: InstanceModel
    let panel: KeyPanel
    var height: CGFloat = M.barHeight
    weak var manager: InstanceManager?

    init(command: String, manager: InstanceManager) {
        self.model = InstanceModel(command: command)
        self.manager = manager
        panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: M.width, height: M.barHeight),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        applyPin()
        let view = InstanceView(
            model: model,
            onHeight: { [weak self] h in self?.setHeight(h) },
            onAction: { [weak self] a in self?.perform(a) })
        panel.contentView = NSHostingView(rootView: view)
        model.session.run(command)
        Proto.shared.note("instance \(model.id.uuidString.prefix(4)) created, runs `\(command)`, pinned")
    }

    enum Action { case submit, close, togglePin, toggleExpand, interrupt, openInKitty }

    func perform(_ a: Action) {
        switch a {
        case .submit:
            let cmd = model.input.trimmingCharacters(in: .whitespaces)
            guard !cmd.isEmpty, !model.session.running else { return }
            model.lastCommand = cmd
            model.expanded = true
            model.session.run(cmd)
            Proto.shared.note("same session runs `\(cmd)` (cwd \(model.session.cwd))")
        case .close:
            model.session.terminate()
            panel.orderOut(nil)
            manager?.remove(self)
            Proto.shared.note("instance closed, session killed")
        case .togglePin:
            model.pinned.toggle()
            applyPin()
            Proto.shared.note(model.pinned ? "pinned (level .floating)" : "unpinned (level .normal — regular z-order)")
        case .toggleExpand:
            model.expanded.toggle()
        case .interrupt:
            model.session.interrupt()
        case .openInKitty:
            openInKitty(cwd: model.session.cwd)
        }
    }

    private func applyPin() {
        panel.level = model.pinned ? .floating : .normal
    }

    func setHeight(_ h: CGFloat) {
        guard abs(h - height) > 0.5 else { return }
        height = h
        manager?.layout(animated: true)
    }

    // Sent only when the user starts a drag, never for setFrame — so programmatic layout never "unstacks".
    func windowWillMove(_ notification: Notification) { manager?.noteUserMoved(self) }
}

func openInKitty(cwd: String) {
    // Prefer the running kitty's remote-control socket (allow_remote_control yes, listen_on unix:/tmp/kitty.sock).
    let socks = (try? FileManager.default.contentsOfDirectory(atPath: "/tmp"))?
        .filter { $0.hasPrefix("kitty.sock") }.map { "unix:/tmp/" + $0 } ?? []
    if let sock = ProcessInfo.processInfo.environment["KITTY_LISTEN_ON"] ?? socks.first {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/kitty")
        p.arguments = ["@", "--to", sock, "launch", "--type=tab", "--cwd", cwd]
        try? p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0 {
            NSRunningApplication.runningApplications(withBundleIdentifier: "net.kovidgoyal.kitty").first?.activate()
            Proto.shared.note("kitty @ launch --type=tab --cwd \(cwd)  (new shell, NOT the same session)")
            return
        }
    }
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.createsNewApplicationInstance = true
    cfg.arguments = ["--directory", cwd]
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/kitty.app"), configuration: cfg)
    Proto.shared.note("opened new kitty instance at \(cwd) (no socket)")
}

@MainActor final class InstanceManager {
    var instances: [InstanceController] = []
    var anchorTop: CGFloat = 0
    var anchorX: CGFloat = 0
    private var moved = Set<ObjectIdentifier>()
    private var laying = false

    func spawn(command: String, top: CGFloat, x: CGFloat) {
        anchorTop = top; anchorX = x
        let c = InstanceController(command: command, manager: self)
        instances.insert(c, at: 0)  // newest on top of the stack, at the palette's position
        layout(animated: false)
        c.panel.makeKeyAndOrderFront(nil)
    }

    func remove(_ c: InstanceController) {
        instances.removeAll { $0 === c }
        layout(animated: true)
    }

    func noteUserMoved(_ c: InstanceController) {
        if !laying { moved.insert(ObjectIdentifier(c)) }  // dragged away → leaves the stack
    }

    func layout(animated: Bool) {
        laying = true
        defer { laying = false }
        var top = anchorTop
        for c in instances {
            let h = c.height
            if moved.contains(ObjectIdentifier(c)) {
                var f = c.panel.frame
                f.origin.y = f.maxY - h; f.size.height = h
                c.panel.setFrame(f, display: true)
                continue
            }
            let f = NSRect(x: anchorX, y: top - h, width: M.width, height: h)
            if animated, c.panel.isVisible {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    c.panel.animator().setFrame(f, display: true)
                }
            } else {
                c.panel.setFrame(f, display: true)
            }
            if !c.panel.isVisible { c.panel.orderFront(nil) }
            top -= h + M.gap
        }
    }
}

// MARK: - Instance view (three variants)

struct InstanceView: View {
    @Bindable var model: InstanceModel
    var proto = Proto.shared
    let onHeight: (CGFloat) -> Void
    let onAction: (InstanceController.Action) -> Void
    @FocusState private var focused: Bool

    private var s: ShellSession { model.session }
    private var lines: Int { s.output.isEmpty ? 0 : s.output.split(separator: "\n", omittingEmptySubsequences: false).count }
    private var outputHeight: CGFloat { min(CGFloat(lines) * 15 + 24, M.maxOutput) }
    // Ticker starts collapsed (last line inline); ⎋ toggles, so "expanded" reads inverted there.
    private var showsOutput: Bool {
        guard !s.output.isEmpty else { return false }
        return proto.variant == .ticker ? !model.expanded : model.expanded
    }

    private var desiredHeight: CGFloat {
        guard showsOutput else { return M.barHeight }
        switch proto.variant {
        case .grow, .ticker: return M.barHeight + outputHeight
        case .card: return M.barHeight + 8 + outputHeight
        }
    }

    var body: some View {
        Group {
            switch proto.variant {
            case .grow, .ticker:
                VStack(spacing: 0) {
                    bar
                    if showsOutput { Divider().opacity(0.4); outputView }
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(borderColor, lineWidth: 1))
            case .card:
                VStack(spacing: 8) {
                    bar
                        .glassEffect(.regular, in: Capsule())
                        .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                    if showsOutput {
                        outputView
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    }
                }
            }
        }
        .frame(width: M.width, height: desiredHeight, alignment: .top)
        .onChange(of: desiredHeight, initial: true) { _, h in onHeight(h) }
        .onAppear { focused = true }
        .onChange(of: s.running) { _, running in
            if !running { model.input = ""; focused = true }
        }
        .background(KeyCatcher { ev in handleKey(ev) })
    }

    private var borderColor: Color {
        if s.running { return .accentColor.opacity(0.7) }
        if let st = s.lastStatus, st != 0 { return .red.opacity(0.6) }
        return .white.opacity(0.28)
    }

    private var bar: some View {
        HStack(spacing: 10) {
            statusGlyph.frame(width: 22)
            if s.running {
                Text(model.lastCommand).font(.system(size: 20, design: .monospaced)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("next command in this session", text: $model.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, design: .monospaced))
                    .focused($focused)
                    .onSubmit { onAction(.submit) }
            }
            if proto.variant == .ticker, !showsOutput, let last = lastLine {
                Text(last).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).frame(maxWidth: 220, alignment: .trailing)
            }
            Text(shortCwd).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            if s.altScreen {
                Text("TUI → ⌘O").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
            }
            iconButton(model.pinned ? "pin.fill" : "pin.slash", help: model.pinned ? "Unpin (⌘P)" : "Pin on top (⌘P)") { onAction(.togglePin) }
            iconButton("arrow.up.forward.app", help: "Open cwd in kitty (⌘O)") { onAction(.openInKitty) }
            iconButton("xmark", help: "Close (⌘W)") { onAction(.close) }
        }
        .padding(.horizontal, 18)
        .frame(height: M.barHeight)
    }

    private var lastLine: String? {
        s.output.split(separator: "\n").last.map(String.init)
    }

    @ViewBuilder private var statusGlyph: some View {
        if s.running {
            ProgressView().controlSize(.small)
        } else if let st = s.lastStatus, st != 0 {
            Text("\(st)").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.red)
        } else {
            Image(systemName: "dollarsign").font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    private var shortCwd: String {
        let home = NSHomeDirectory()
        return s.cwd.hasPrefix(home) ? "~" + s.cwd.dropFirst(home.count) : s.cwd
    }

    private func iconButton(_ name: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 13, weight: .medium)).frame(width: 26, height: 26) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(help)
    }

    private var outputView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(s.output)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                Color.clear.frame(height: 1).id("end")
            }
            .onChange(of: s.output) { proxy.scrollTo("end", anchor: .bottom) }
        }
        .frame(height: outputHeight)
    }

    private func handleKey(_ ev: NSEvent) -> Bool {
        let cmd = ev.modifierFlags.contains(.command)
        let chars = ev.charactersIgnoringModifiers ?? ""
        if cmd && chars == "w" { onAction(.close); return true }
        if cmd && chars == "p" { onAction(.togglePin); return true }
        if cmd && chars == "o" { onAction(.openInKitty); return true }
        if ev.modifierFlags.contains(.control) && chars == "c" { onAction(.interrupt); return true }
        if ev.keyCode == 53 { onAction(.toggleExpand); return true }
        return false
    }
}

/// Local key monitor scoped to the hosting window — more reliable than onKeyPress through a field editor.
struct KeyCatcher: NSViewRepresentable {
    let handler: (NSEvent) -> Bool
    func makeNSView(context: Context) -> NSView {
        let v = MonitorView()
        v.handler = handler
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { (v as? MonitorView)?.handler = handler }
    final class MonitorView: NSView {
        var handler: ((NSEvent) -> Bool)?
        var monitor: Any?
        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
                guard let self, ev.window === self.window, let h = self.handler else { return ev }
                return h(ev) ? nil : ev
            }
        }
    }
}

// MARK: - Palette (Spotlight-like)

enum Category: Int, CaseIterable, Identifiable {
    case applications, files, shortcuts, clipboard
    var id: Int { rawValue }
    var title: String { ["Applications", "Files", "Shortcuts", "Clipboard"][rawValue] }
    var symbol: String { ["square.grid.2x2", "folder", "square.stack.3d.up", "list.clipboard"][rawValue] }
}

@Observable final class PaletteModel {
    var query = ""
    var chips = false
    var category: Category?
    var selected = 0
    var isCommand: Bool { query.hasPrefix("$") }
    var command: String { String(query.dropFirst()).trimmingCharacters(in: .whitespaces) }

    static let items: [(String, String, Category)] = [
        ("Safari", "safari", .applications), ("Slack", "number", .applications), ("kitty", "terminal", .applications),
        ("Obsidian", "book.closed", .applications), ("System Settings", "gearshape", .applications),
        ("AGENDA.md", "doc.text", .files), ("tinycast", "folder", .files), ("Screenshot 2026-10-08.png", "photo", .files),
        ("Toggle Dark Mode", "circle.lefthalf.filled", .shortcuts), ("Focus: Work", "moon", .shortcuts),
        ("git push --force-with-lease", "doc.on.clipboard", .clipboard), ("https://claude.ai/…", "link", .clipboard),
    ]

    var results: [(String, String, Category)] {
        if isCommand { return [] }
        let q = query.lowercased()
        return Self.items.filter { (category == nil || $0.2 == category) && (q.isEmpty || $0.0.lowercased().contains(q)) }
    }
    var showsList: Bool {
        if isCommand { return !command.isEmpty }
        if Proto.shared.hideListUntilTyping && query.isEmpty && category == nil { return false }
        return !results.isEmpty
    }
}

struct PaletteView: View {
    @Bindable var model: PaletteModel
    var proto = Proto.shared
    let onHeight: (CGFloat) -> Void
    let onRunCommand: (String) -> Void
    let onClose: () -> Void
    @Namespace private var glass
    @FocusState private var focused: Bool

    private var listHeight: CGFloat {
        if model.isCommand { return 52 }
        return CGFloat(min(model.results.count, 7)) * 40 + 12
    }
    private var desiredHeight: CGFloat { M.barHeight + (model.showsList ? 8 + listHeight : 0) }

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: M.gap) {
                    field
                        .frame(width: model.chips ? M.pillWidth : M.width, height: M.barHeight)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: model.chips ? M.barHeight / 2 : 20))
                        .glassEffectID("bar", in: glass)
                    if model.chips {
                        ForEach(Category.allCases) { cat in chip(cat) }
                    }
                }
                if model.showsList {
                    list
                        .frame(width: M.width, height: listHeight)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                        .glassEffectID("list", in: glass)
                }
            }
        }
        .frame(width: M.width, height: desiredHeight, alignment: .topLeading)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.chips)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: model.showsList)
        .onChange(of: desiredHeight, initial: true) { _, h in onHeight(h) }
        .onAppear { focused = true }
        .background(KeyCatcher { ev in handleKey(ev) })
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isCommand ? "terminal" : "magnifyingglass")
                .font(.system(size: 19, weight: .medium)).foregroundStyle(model.isCommand ? Color.accentColor : .secondary)
            if let cat = model.category {
                Label(cat.title, systemImage: cat.symbol).font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .lineLimit(1).fixedSize()
            }
            TextField(model.chips ? "Search" : "Spotlight-style search · “$ cmd” runs a terminal", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit(submit)
            if model.chips {
                hint(model.category.map { "⌘\($0.rawValue + 1)" } ?? "⌘1")
            } else if model.isCommand && !model.command.isEmpty {
                hint("↩ new terminal")
            }
        }
        .padding(.horizontal, 16)
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.08)))
    }

    private func chip(_ cat: Category) -> some View {
        Button { pick(cat) } label: {
            Image(systemName: cat.symbol).font(.system(size: 19, weight: .medium))
                .frame(width: M.chip, height: M.chip)
                .foregroundStyle(model.category == cat ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .glassEffect(model.category == cat ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular.interactive(), in: Circle())
        .glassEffectID(cat.id, in: glass)
        .help("\(cat.title)  ⌘\(cat.rawValue + 1)")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isCommand {
                row(symbol: "terminal", title: "Run “\(model.command)” in a new terminal instance", trailing: "↩", selected: true)
            } else {
                ForEach(Array(model.results.prefix(7).enumerated()), id: \.offset) { i, item in
                    row(symbol: item.1, title: item.0, trailing: item.2.title, selected: i == model.selected)
                }
            }
        }
        .padding(6)
    }

    private func row(symbol: String, title: String, trailing: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 22)
            Text(title).lineLimit(1)
            Spacer()
            Text(trailing).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.28) : .clear))
    }

    private func pick(_ cat: Category) {
        if !model.chips { model.chips = true }
        model.category = model.category == cat ? nil : cat
        model.selected = 0
        Proto.shared.note("category → \(model.category?.title ?? "none")")
    }

    private func submit() {
        if model.isCommand {
            guard !model.command.isEmpty else { return }
            onRunCommand(model.command)
        } else if !model.results.isEmpty {
            Proto.shared.note("would launch \(model.results[min(model.selected, model.results.count - 1)].0)")
        }
    }

    private func handleKey(_ ev: NSEvent) -> Bool {
        let cmd = ev.modifierFlags.contains(.command)
        if ev.keyCode == 48 {  // Tab
            model.chips.toggle()
            if !model.chips { model.category = nil }
            Proto.shared.note(model.chips ? "⇥ → pill + chips" : "⇥ → full bar")
            return true
        }
        if cmd, let n = Int(ev.charactersIgnoringModifiers ?? ""), (1...4).contains(n) {
            pick(Category(rawValue: n - 1)!)
            return true
        }
        if ev.keyCode == 125 { model.selected = min(model.selected + 1, max(model.results.count - 1, 0)); return true }
        if ev.keyCode == 126 { model.selected = max(model.selected - 1, 0); return true }
        if ev.keyCode == 53 {  // Esc: category → chips → query → close
            if model.category != nil { model.category = nil }
            else if model.chips { model.chips = false }
            else if !model.query.isEmpty { model.query = "" }
            else { onClose() }
            return true
        }
        return false
    }
}

@MainActor final class PaletteController {
    let model = PaletteModel()
    let panel: KeyPanel
    let instances = InstanceManager()
    var topLeft: NSPoint

    init() {
        let screen = NSScreen.main!.visibleFrame
        topLeft = NSPoint(x: screen.midX - M.width / 2, y: screen.maxY - screen.height * 0.22)
        panel = KeyPanel(
            contentRect: NSRect(x: topLeft.x, y: topLeft.y - M.barHeight, width: M.width + 4 * (M.chip + M.gap), height: M.barHeight),
            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // glass draws its own; a window shadow would outline the transparent frame
        panel.level = .floating
        panel.hidesOnDeactivate = false
        let view = PaletteView(
            model: model,
            onHeight: { [weak self] h in self?.resize(h) },
            onRunCommand: { [weak self] c in self?.runCommand(c) },
            onClose: { [weak self] in self?.hide() })
        panel.contentView = NSHostingView(rootView: view)
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            // Spotlight behaviour: losing focus closes the palette.
            MainActor.assumeIsolated { if self?.panel.isVisible == true { self?.hide() } }
        }
    }

    func resize(_ h: CGFloat) {
        panel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - h, width: panel.frame.width, height: h), display: true)
    }

    func show() {
        model.query = ""
        model.chips = false
        model.category = nil
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        Proto.shared.note("palette shown")
    }

    func hide() {
        panel.orderOut(nil)
        Proto.shared.note("palette closed")
    }

    func runCommand(_ command: String) {
        // The new instance takes the palette's exact spot; the palette closes because it lost focus.
        instances.spawn(command: command, top: topLeft.y, x: topLeft.x)
        hide()
    }
}

// MARK: - Prototype switcher (floating bottom bar)

struct SwitcherView: View {
    var proto = Proto.shared
    let onPalette: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Text(proto.variant.label).font(.system(size: 12, weight: .medium)).frame(width: 250)
                Button { step(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                Divider().frame(height: 16)
                Toggle("Hide list until typing", isOn: Bindable(proto).hideListUntilTyping)
                    .toggleStyle(.checkbox).font(.system(size: 12))
                Divider().frame(height: 16)
                Button("Show palette", action: onPalette).buttonStyle(.glass)
            }
            Text(proto.log.last ?? "state log appears here (also printed to stdout)")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .frame(width: 720, height: 76)
    }
    func step(_ d: Int) {
        let all = InstanceVariant.allCases
        proto.variant = all[(proto.variant.rawValue + d + all.count) % all.count]
        proto.note("variant → \(proto.variant.label)")
    }
}

// MARK: - App

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var palette: PaletteController!
    var switcher: NSPanel!

    func applicationDidFinishLaunching(_ n: Notification) {
        palette = PaletteController()
        let screen = NSScreen.main!.visibleFrame
        switcher = NSPanel(
            contentRect: NSRect(x: screen.midX - 360, y: screen.minY + 24, width: 720, height: 76),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        switcher.isOpaque = false
        switcher.backgroundColor = .clear
        switcher.level = .statusBar
        switcher.hidesOnDeactivate = false
        switcher.collectionBehavior = [.canJoinAllSpaces]
        switcher.contentView = NSHostingView(rootView: SwitcherView(onPalette: { [weak self] in self?.palette.show() }))
        switcher.orderFront(nil)
        for a in CommandLine.arguments where a.hasPrefix("--variant=") {
            Proto.shared.variant = ["A": .grow, "B": .card, "C": .ticker][String(a.dropFirst(10))] ?? .grow
        }
        palette.show()
        if CommandLine.arguments.contains("--demo") { demo() }
    }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        palette.show()
        return false
    }

    func applicationWillTerminate(_ n: Notification) {
        palette.instances.instances.forEach { $0.model.session.terminate() }
    }

    /// Scripted smoke run: chips morph, then two instances, a follow-up command, unpin, then quit.
    func demo() {
        let steps: [(Double, () -> Void)] = [
            (0.8, { self.palette.model.chips = true }),
            (1.6, { self.palette.model.category = .files }),
            (2.1, { self.shot(self.palette.panel, "chips") }),
            (2.4, { self.palette.model.chips = false; self.palette.model.category = nil; self.palette.model.query = "$ pwd" }),
            (3.0, { self.palette.runCommand("pwd") }),
            (4.0, { self.palette.show(); self.palette.model.query = "$ for i in 1 2 3; do echo tick $i; sleep 0.4; done" }),
            (4.6, { self.palette.runCommand("for i in 1 2 3; do echo tick $i; sleep 0.4; done") }),
            (6.8, { let c = self.palette.instances.instances.last!; c.model.input = "cd /tmp && ls | head -3; (exit 2)"; c.perform(.submit) }),
            (7.5, { for (i, c) in self.palette.instances.instances.enumerated() { self.shot(c.panel, "instance\(i)") } }),
            (7.8, { self.palette.instances.instances.first!.perform(.togglePin) }),
            (8.5, { self.report(); NSApp.terminate(nil) }),
        ]
        for (t, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { f() } } }
    }

    /// Window-only capture (never the whole screen) into .build/, for the demo's evidence.
    func shot(_ w: NSWindow, _ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l\(w.windowNumber)", ".build/demo-\(Proto.shared.variant.rawValue)-\(name).png"]
        try? p.run(); p.waitUntilExit()
    }

    func report() {
        for (i, c) in palette.instances.instances.enumerated() {
            let s = c.model.session
            print("[demo] instance \(i): cmd=`\(c.model.lastCommand)` running=\(s.running) status=\(s.lastStatus.map(String.init) ?? "nil") cwd=\(s.cwd) pinned=\(c.model.pinned) level=\(c.panel.level.rawValue) frame=\(c.panel.frame.integral)")
            print("[demo]   output: \(s.output.debugDescription)")
        }
        print("[demo] palette visible=\(palette.panel.isVisible)")
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
