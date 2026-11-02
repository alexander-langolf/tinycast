import AppKit

@MainActor
final class ForkWorkspaceAppControl: ForkAppControl {
    private var observation: NotificationToken?
    private var generation = 0

    func isRunning(bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
    }

    func launch(bundleID: String) throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let span = ForkTrace.begin(.appSupervision, category: .supervision, step: .launch)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard let error else { return }
            span.end(.failed, fields: .init(bundleID: bundleID, errorCode: (error as NSError).code))
        }
    }

    func observeTermination(bundleID: String, handler: @escaping @MainActor () -> Void) {
        generation += 1
        let mine = generation
        let center = NSWorkspace.shared.notificationCenter
        observation = NotificationToken(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    app.bundleIdentifier == bundleID
                else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == mine else { return }
                    handler()
                }
            }, center: center)
    }

    func stopObservingTermination() { generation += 1; observation = nil }
}
