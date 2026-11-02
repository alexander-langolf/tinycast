import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ClaudeUsageCoordinator {
    let settings: ClaudeUsageSettings
    private(set) var labelText = ""
    private(set) var hasSnapshot = false
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var snapshot: ClaudeUsageSnapshot?
    private(set) var settingsRequest: UUID?

    @ObservationIgnored private let account: ForkClaudeAccount
    @ObservationIgnored private let showSettings: () -> Void
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NotificationToken?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var observationID = UUID()
    @ObservationIgnored private var nextPoll: Date?
    @ObservationIgnored private var rateLimitedUntil: Date?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var isPolling = false
    @ObservationIgnored private var accountSession: UUID?

    init(account: ForkClaudeAccount, showSettings: @escaping () -> Void) {
        self.account = account
        self.showSettings = showSettings
        settings = ClaudeUsageSettings()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    isolated deinit {
        pollTask?.cancel()
        fetchTask?.cancel()
        session.invalidateAndCancel()
    }

    var isSignedIn: Bool { account.phase == .signedIn }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observationID = UUID()
        settings.onChange = { [weak self] in self?.applyLifecycle() }
        observeLifecycle(id: observationID)
        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = NotificationToken(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh(trigger: .wake) }
            }, center: center)
        applyLifecycle()
    }

    func stop() {
        isRunning = false
        observationID = UUID()
        cancelPolling()
        settings.onChange = nil
        wakeObserver = nil
    }

    func refresh() {
        refresh(trigger: .manual)
    }

    func signIn() {
        account.signIn()
    }

    func openAccountSettings() {
        settingsRequest = UUID()
        showSettings()
    }

    func consumeSettingsRequest() -> Bool {
        guard settingsRequest != nil else { return false }
        settingsRequest = nil
        return true
    }

    var accountConnectionID: UUID { account.preferences.connectionID }

    private var canFetch: Bool {
        isRunning && ClaudeUsagePollPolicy.isEnabled(
            inserted: settings.display != .disabled, signedIn: isSignedIn)
    }

    private func observeLifecycle(id: UUID) {
        withObservationTracking {
            _ = account.phase
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.observationID == id else { return }
                self.observeLifecycle(id: id)
                self.applyLifecycle()
            }
        }
    }

    private func applyLifecycle() {
        if accountSession != account.sessionID {
            cancelPolling()
            accountSession = account.sessionID
            clearSnapshot()
        }
        guard canFetch else {
            cancelPolling()
            if !isSignedIn { clearSnapshot() }
            updateLabel()
            return
        }
        updateLabel()
        guard !isPolling else { return }
        isPolling = true
        schedulePoll(after: Date())
        refresh(trigger: .activation)
    }

    private func cancelPolling() {
        generation = UUID()
        isPolling = false
        pollTask?.cancel()
        pollTask = nil
        fetchTask?.cancel()
        fetchTask = nil
        nextPoll = nil
        rateLimitedUntil = nil
    }

    private func schedulePoll(after now: Date) {
        pollTask?.cancel()
        let deadline = ClaudeUsagePollPolicy.nextPoll(after: now)
        nextPoll = deadline
        pollTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            guard let self, self.canFetch else { return }
            self.refresh(trigger: .timer)
            self.schedulePoll(after: Date())
        }
    }

    private func refresh(trigger: ClaudeUsagePollPolicy.Trigger) {
        guard isRunning, ClaudeUsagePollPolicy.shouldFetch(
            trigger: trigger, inserted: settings.display != .disabled, signedIn: isSignedIn,
            now: Date(), nextPoll: nextPoll, rateLimitedUntil: rateLimitedUntil)
        else { return }
        fetchTask?.cancel()
        generation = UUID()
        let operation = generation
        let accountID = account.sessionID
        fetchTask = Task { [weak self] in
            await self?.fetch(operation: operation, accountID: accountID)
        }
    }

    private func isCurrent(operation: UUID, accountID: UUID) -> Bool {
        !Task.isCancelled && canFetch && generation == operation && account.sessionID == accountID
    }

    private func fetch(operation: UUID, accountID: UUID) async {
        guard isCurrent(operation: operation, accountID: accountID) else { return }
        do {
            var token = try await account.accessToken(sessionID: accountID)
            for attempt in 0...1 {
                guard isCurrent(operation: operation, accountID: accountID) else { return }
                var request = URLRequest(
                    url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 30)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await session.data(for: request)
                guard isCurrent(operation: operation, accountID: accountID) else { return }
                guard let response = response as? HTTPURLResponse else { throw Failure.malformed }
                if response.statusCode == 401, attempt == 0 {
                    token = try await account.accessToken(sessionID: accountID, rejectedToken: token)
                    continue
                }
                guard response.statusCode == 200 else { throw Failure.status(response.statusCode) }
                let decoded: ClaudeUsageSnapshot
                do { decoded = try JSONDecoder().decode(ClaudeUsageSnapshot.self, from: data) }
                catch { throw Failure.malformed }
                if snapshot != decoded { snapshot = decoded }
                if !hasSnapshot { hasSnapshot = true }
                let now = Date()
                if lastUpdated != now { lastUpdated = now }
                if lastError != nil { lastError = nil }
                rateLimitedUntil = nil
                updateLabel()
                return
            }
        } catch {
            guard isCurrent(operation: operation, accountID: accountID) else { return }
            let message: String
            switch error {
            case Failure.status(429):
                let now = Date()
                rateLimitedUntil = nextPoll.flatMap { $0 > now ? $0 : nil }
                    ?? ClaudeUsagePollPolicy.nextPoll(after: now)
                message = String(localized: "Claude usage is rate limited. Waiting for the next refresh.")
            case Failure.status(let code):
                message = String(localized: "Claude usage request failed (\(code)).")
            case Failure.malformed:
                message = String(localized: "Claude usage could not be read. Try again.")
            default:
                message = String(localized: "Claude usage could not be refreshed. Check your connection.")
            }
            if lastError != message { lastError = message }
        }
    }

    private func clearSnapshot() {
        if snapshot != nil { snapshot = nil }
        if hasSnapshot { hasSnapshot = false }
        if lastUpdated != nil { lastUpdated = nil }
        if lastError != nil { lastError = nil }
    }

    private func updateLabel() {
        let text = ClaudeUsageFormat.label(snapshot: snapshot, display: settings.display, locale: .current)
        if labelText != text { labelText = text }
    }

    private enum Failure: Error {
        case status(Int)
        case malformed
    }
}
