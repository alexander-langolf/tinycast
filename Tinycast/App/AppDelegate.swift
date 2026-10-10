import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationRequestInFlight = false

    // FORK: previews
    static let isRunningForPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    /// Must land before the first scroll view exists, or the scroller switch shows as a flash.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // FORK: previews — Xcode's canvas hosts the app; starting AppCore there (hotkeys, Hyper Key, listeners) crashes it.
        guard !Self.isRunningForPreviews else { return }
        AppCore.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppCore.shared.handleOpenURL(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRunningForPreviews else { return }  // FORK: previews
        // The Hyper Key's HID-level caps remap outlives the process; give the key back.
        AppCore.shared.prepareForTermination()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.isRunningForPreviews { return .terminateNow }  // FORK: previews
        // The Dock icon only stands for the open windows, so its Quit closes them, not the agent.
        let activation = AppCore.shared.activationPolicy
        if isQuitFromDock, activation.hasOpenWindows {
            activation.closeAll()
            return .terminateCancel
        }
        guard !terminationRequestInFlight else { return .terminateLater }
        terminationRequestInFlight = true
        Task { @MainActor [weak self] in
            await AppCore.shared.stopDictationForTermination()
            // A 300 ms-debounced draft still has to reach disk, but it can no longer veto the quit.
            await AppCore.shared.flushNotesForTermination()
            self?.terminationRequestInFlight = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }

    /// The palette and Settings each close on their own; the agent outlives both.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ⌘Q and the menu-bar item call `terminate` directly; only an Apple Event names a sender.
    private var isQuitFromDock: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication,
            let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
    }
}
