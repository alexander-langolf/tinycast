import AppKit
import ApplicationServices

@MainActor
struct ForkLyraTextSnapshot {
    let element: AXUIElement
    let pid: pid_t
    let value: String
    let selection: NSRange
    let role: String
    let anchor: CGRect // Accessibility coordinates: origin at the top of the main display.
    let caretKnown: Bool // false: the app reports no caret bounds, and anchor is the whole field.

    var wholeRange: NSRange { NSRange(location: 0, length: value.utf16.count) }
    var targetRange: NSRange { selection.length > 0 ? selection : wholeRange }
    var targetText: String { (value as NSString).substring(with: targetRange) }

    func isCurrent() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = ForkLyraFocusObserver.focusedElement(), CFEqual(element, focused),
              let current = ForkLyraFocusObserver.snapshot(focused) else { return false }
        return current.value == value && current.selection == selection
    }
}

@MainActor
final class ForkLyraFocusObserver: ForkSelectionSource {
    let kind = ForkSelection.Kind.accessibility

    func read(from app: NSRunningApplication) async -> ForkSelection? {
        guard let focused = Self.focusedElement(), let snapshot = Self.snapshot(focused),
            snapshot.pid == app.processIdentifier, snapshot.isCurrent() else { return nil }
        return ForkSelection(text: snapshot.targetText, source: kind)
    }

    enum Change { case focus, value, selection }
    var onChange: ((ForkLyraTextSnapshot?, Change) -> Void)?
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var field: AXUIElement?
    private var workspaceToken: NotificationToken?
    private var pid: pid_t = 0

    func start() {
        guard workspaceToken == nil else { return }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.2)
        let center = NSWorkspace.shared.notificationCenter
        workspaceToken = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.activate() }
        }, center: center)
        activate()
    }

    func stop() {
        detach()
        workspaceToken = nil
    }

    private func activate() {
        guard workspaceToken != nil else { return }
        detach()
        onChange?(nil, .focus)
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              front.bundleIdentifier != "net.kovidgoyal.kitty" else { return }
        pid = front.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        application = app
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var created: AXObserver?
        let result = AXObserverCreate(pid, { observer, _, notification, context in
            guard let context else { return }
            let monitor = Unmanaged<ForkLyraFocusObserver>.fromOpaque(context).takeUnretainedValue()
            let name = notification as String
            let identity = UInt(bitPattern: Unmanaged.passUnretained(observer).toOpaque())
            Task { @MainActor [weak monitor] in
                guard let monitor, let current = monitor.observer, monitor.workspaceToken != nil,
                    UInt(bitPattern: Unmanaged.passUnretained(current).toOpaque()) == identity else { return }
                monitor.refresh(name == kAXValueChangedNotification ? .value :
                    name == kAXSelectedTextChangedNotification ? .selection : .focus)
            }
        }, &created)
        guard result == .success, let created else {
            return
        }
        observer = created
        let context = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(created, app, kAXFocusedUIElementChangedNotification as CFString, context)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        refresh(.focus)
    }

    private func refresh(_ change: Change) {
        var focusedPID: pid_t = 0
        guard let focused = Self.focusedElement(), AXUIElementGetPid(focused, &focusedPID) == .success,
              focusedPID == pid else {
            unwatchField()
            onChange?(nil, .focus)
            return
        }
        let changed = field.map { !CFEqual($0, focused) } ?? true
        if changed {
            unwatchField()
            field = focused
            if let observer {
                let context = Unmanaged.passUnretained(self).toOpaque()
                for name in [kAXValueChangedNotification, kAXSelectedTextChangedNotification] {
                    _ = AXObserverAddNotification(observer, focused, name as CFString, context)
                }
            }
        }
        onChange?(Self.snapshot(focused), changed ? .focus : change)
    }

    private func unwatchField() {
        if let observer, let field {
            for name in [kAXValueChangedNotification, kAXSelectedTextChangedNotification] {
                AXObserverRemoveNotification(observer, field, name as CFString)
            }
        }
        field = nil
    }

    private func detach() {
        unwatchField()
        if let observer {
            if let application {
                AXObserverRemoveNotification(observer, application, kAXFocusedUIElementChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        application = nil
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func focusedElement() -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func snapshot(_ element: AXUIElement) -> ForkLyraTextSnapshot? {
        var process: pid_t = 0
        guard AXUIElementGetPid(element, &process) == .success,
              process != ProcessInfo.processInfo.processIdentifier,
              let role = attribute(element, kAXRoleAttribute) as? String else { return nil }
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        guard !role.localizedCaseInsensitiveContains("secure"),
              !subrole.localizedCaseInsensitiveContains("secure"),
              (attribute(element, "AXProtectedContent") as? Bool) != true,
              let text = attribute(element, kAXValueAttribute) as? String,
              let rangeValue = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range),
              range.location >= 0, range.length >= 0,
              range.location <= text.utf16.count, range.length <= text.utf16.count - range.location else { return nil }
        let selection = NSRange(location: range.location, length: range.length)
        let caret = caretBounds(element, selection: selection, count: text.utf16.count)
        return ForkLyraTextSnapshot(element: element, pid: process, value: text, selection: selection, role: role,
                            anchor: caret.rect, caretKnown: caret.known)
    }

    private static func caretBounds(_ element: AXUIElement, selection: NSRange, count: Int) -> (rect: CGRect, known: Bool) {
        let caret = min(NSMaxRange(selection), count)
        var candidates = [CFRange(location: caret, length: 0)]
        if caret < count { candidates.append(CFRange(location: caret, length: 1)) }
        if caret > 0 { candidates.append(CFRange(location: caret - 1, length: 1)) }
        for (index, candidate) in candidates.enumerated() {
            var range = candidate
            guard let parameter = AXValueCreate(.cfRange, &range) else { continue }
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         parameter, &value) == .success,
               let value, CFGetTypeID(value) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.height > 0,
                   rect.origin.x.isFinite, rect.origin.y.isFinite {
                    return (rangeCaret(rect, candidateLocation: candidate.location,
                                       caret: caret, candidateIndex: index), true)
                }
            }
        }
        if let rect = textMarkerCaret(element) { return (rect, true) }
        var point = CGPoint.zero
        var size = CGSize.zero
        if let p = attribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
           let s = attribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID(),
           AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) {
            return (CGRect(origin: point, size: size), false)
        }
        return (CGRect(origin: CGPoint(x: 40, y: 80), size: CGSize(width: 0, height: 20)), true)
    }

    /// Chromium and WebKit fields (Slack, browsers) answer text-marker queries when range bounds fail.
    private static func textMarkerCaret(_ element: AXUIElement) -> CGRect? {
        guard let selected = attribute(element, "AXSelectedTextMarkerRange") else { return nil }
        func bounds(_ range: CFTypeRef) -> CGRect? {
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString,
                                                             range, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.height > 0,
                  rect.origin.x.isFinite, rect.origin.y.isFinite else { return nil }
            return rect
        }
        func parameterized(_ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success
                ? value : nil
        }
        if let rect = bounds(selected), let caret = selectedTextMarkerCaret(rect) { return caret }
        // A collapsed caret often has no bounds, so measure the character before it and take its trailing edge.
        guard let end = parameterized("AXEndTextMarkerForTextMarkerRange", selected),
              let previous = parameterized("AXPreviousTextMarkerForTextMarker", end),
              let range = parameterized("AXTextMarkerRangeForUnorderedTextMarkers", [previous, end] as CFArray),
              let rect = bounds(range) else { return nil }
        return trailingCaret(rect)
    }

    static func selectedTextMarkerCaret(_ rect: CGRect) -> CGRect? {
        rect.width < 2 ? rect : nil
    }

    static func rangeCaret(_ rect: CGRect, candidateLocation: Int, caret: Int, candidateIndex: Int) -> CGRect {
        if candidateIndex > 0 && candidateLocation < caret { return trailingCaret(rect) }
        return rect
    }

    static func trailingCaret(_ bounds: CGRect) -> CGRect {
        var rect = bounds
        rect.origin.x = rect.maxX
        rect.size.width = 0
        return rect
    }
}
