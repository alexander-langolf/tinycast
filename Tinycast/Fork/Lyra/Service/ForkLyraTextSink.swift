import AppKit
import ApplicationServices

@MainActor
final class ForkLyraTextSink: ForkTextSink {
    private let snapshot: ForkLyraTextSnapshot
    private let range: NSRange
    private let clipboardManager: ClipboardManager

    init(snapshot: ForkLyraTextSnapshot, range: NSRange, clipboardManager: ClipboardManager) {
        self.snapshot = snapshot
        self.range = range
        self.clipboardManager = clipboardManager
    }

    func replaceSelection(in app: NSRunningApplication, with text: String) async -> Bool {
        guard app.processIdentifier == snapshot.pid else { return false }
        do { try await apply(text, to: snapshot, range: range); return true }
        catch { return false }
    }

    private(set) var busy = false

    func apply(_ replacement: String, to snapshot: ForkLyraTextSnapshot, range: NSRange) async throws {
        guard !busy else { throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite.")) }
        guard snapshot.isCurrent() else { throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite.")) }
        busy = true
        defer { busy = false }
        let expected = (snapshot.value as NSString).replacingCharacters(in: range, with: replacement)
        try Task.checkCancellation()
        let selected = select(range, in: snapshot.element)
        let written = selected && AXUIElementSetAttributeValue(snapshot.element, kAXSelectedTextAttribute as CFString,
                                                              replacement as CFString) == .success
        let afterWrite = currentValue(snapshot)
        let afterSelection = currentSelection(snapshot)
        if written {
            try await Task.sleep(for: .milliseconds(80))
            if isFocused(snapshot), currentValue(snapshot) == expected {
                ForkTrace.begin(.lyra, category: .lyra, step: .accessibility).end(.success, fields: .init(length: replacement.count))
                return
            }
        }
        try Task.checkCancellation()
        guard isFocused(snapshot), currentSelection(snapshot) == afterSelection,
              let observed = currentValue(snapshot), observed == snapshot.value || observed == afterWrite else {
            throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite."))
        }
        let wholeField = range == snapshot.wholeRange
        var pasteRange = range
        if observed != snapshot.value && !wholeField {
            let original = snapshot.value as NSString
            let prefix = original.substring(to: range.location)
            let suffix = original.substring(from: NSMaxRange(range))
            let length = observed.utf16.count - prefix.utf16.count - suffix.utf16.count
            guard observed.hasPrefix(prefix), observed.hasSuffix(suffix), length >= 0 else {
                throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite."))
            }
            pasteRange = NSRange(location: range.location, length: length)
        }
        guard select(pasteRange, in: snapshot.element) || wholeField else {
            throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite."))
        }
        let clipboard = NSPasteboard.general
        try Task.checkCancellation()
        guard isFocused(snapshot), currentValue(snapshot) == observed else {
            throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite."))
        }
        clipboardManager.prepareForTinycastPasteboardMutation()
        guard let lease = TemporaryPasteboardLease.begin(text: replacement, pasteboard: clipboard,
            onMutation: { clipboardManager.synchronizeAfterTinycastPasteboardMutation(changeCount: $0) })
        else { throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite.")) }
        let selectAll = wholeField ? "keystroke \"a\" using command down\n" : ""
        let source = """
        tell application "System Events"
            \(selectAll)keystroke "v" using command down
        end tell
        """
        var scriptError: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&scriptError)
        let paste = ForkTrace.begin(.lyra, category: .lyra, step: .paste)
        var pasted = false
        defer { paste.end(pasted ? .success : .failed) }
        await Task { @MainActor in try? await Task.sleep(for: .milliseconds(500)) }.value
        switch lease.restoreIfOwned() {
        case .restored(let changeCount): clipboardManager.synchronizeAfterTinycastPasteboardMutation(changeCount: changeCount)
        case .superseded: break
        case .failed: throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite."))
        }
        if scriptError != nil { throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite.")) }
        guard isFocused(snapshot), currentValue(snapshot) == expected else {
            throw AIProviderError.unavailable(String(localized: "The focused text changed. Request a new rewrite."))
        }
        pasted = true
    }

    private func select(_ range: NSRange, in element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    private func isFocused(_ snapshot: ForkLyraTextSnapshot) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid &&
            ForkLyraFocusObserver.focusedElement().map { CFEqual($0, snapshot.element) } == true
    }

    private func currentSelection(_ snapshot: ForkLyraTextSnapshot) -> NSRange? {
        guard let value = ForkLyraFocusObserver.attribute(snapshot.element, kAXSelectedTextRangeAttribute),
            CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func currentValue(_ snapshot: ForkLyraTextSnapshot) -> String? {
        ForkLyraFocusObserver.attribute(snapshot.element, kAXValueAttribute) as? String
    }
}
