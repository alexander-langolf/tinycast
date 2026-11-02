import AppKit
import Foundation
import Network
import Observation

@MainActor
@Observable
final class ForkClaudeAccount {
    enum Phase: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case failed(String)
    }

    private(set) var phase = Phase.signedOut
    var sessionID: UUID { generation }
    let preferences: ForkClaudeAccountSettings
    nonisolated let transcript = ForkClaudeTranscript()
    @ObservationIgnored private let settings: AISettingsStore
    @ObservationIgnored private let store: ForkClaudeAccountStore
    @ObservationIgnored private var tokens: ForkClaudeAccountStore.Tokens?
    @ObservationIgnored private var login: ForkClaudeAccountLogin.Session?
    @ObservationIgnored private var callback: ForkClaudeAccountCallback?
    @ObservationIgnored private var loginTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<String, Error>?
    @ObservationIgnored private var versionTask: Task<String, Never>?
    @ObservationIgnored private var generation = UUID()

    init(settings: AISettingsStore, preferences: ForkClaudeAccountSettings = ForkClaudeAccountSettings()) {
        self.settings = settings
        self.preferences = preferences
        store = ForkClaudeAccountStore(account: preferences.connectionID)
    }

    isolated deinit {
        loginTask?.cancel()
        refreshTask?.cancel()
        versionTask?.cancel()
        callback?.cancel()
    }

    func start() {
        do {
            tokens = try store.load()
            if tokens != nil {
                phase = .signedIn
                settings.save(preferences.connection())
            } else {
                settings.removeConnection(id: preferences.connectionID)
            }
        } catch {
            phase = .failed(String(localized: "The Claude account could not be read from Keychain."))
            settings.removeConnection(id: preferences.connectionID)
        }
    }

    func signIn(copyCode: Bool = false) {
        stop()
        generation = UUID()
        let operation = generation
        phase = .signingIn
        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let redirect: String
                if copyCode {
                    redirect = ForkClaudeAccountLogin.copyRedirect
                } else {
                    var listener = ForkClaudeAccountCallback()
                    callback = listener
                    let port: UInt16
                    do {
                        port = try await listener.start(port: 53692)
                    } catch {
                        try Task.checkCancellation()
                        listener.cancel()
                        listener = ForkClaudeAccountCallback()
                        callback = listener
                        port = try await listener.start(port: .any)
                    }
                    redirect = "http://localhost:\(port)/callback"
                }
                try Task.checkCancellation()
                guard generation == operation else { return }
                let session = try ForkClaudeAccountLogin.prepare(redirectURI: redirect)
                login = session
                guard NSWorkspace.shared.open(session.authorizeURL) else {
                    throw ForkClaudeAccountLogin.Failure.unavailable
                }
                if let callback {
                    let input = try await callback.code()
                    try Task.checkCancellation()
                    guard generation == operation else { return }
                    try await complete(input, session: session, operation: operation)
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == operation else { return }
                loginFailed(error)
            }
        }
    }

    func submitCode(_ input: String) {
        guard phase == .signingIn, let login else { return }
        let operation = generation
        loginTask?.cancel()
        callback?.cancel()
        callback = nil
        loginTask = Task { [weak self] in
            do { try await self?.complete(input, session: login, operation: operation) }
            catch is CancellationError { return }
            catch {
                guard let self, self.generation == operation else { return }
                self.loginFailed(error)
            }
        }
    }

    private func complete(
        _ input: String, session: ForkClaudeAccountLogin.Session, operation: UUID
    ) async throws {
        let result = try await ForkClaudeAccountLogin.exchange(input, session: session)
        try Task.checkCancellation()
        guard generation == operation else { throw CancellationError() }
        do { try store.save(result) }
        catch { throw AIProviderError.unavailable(String(localized: "The Claude account could not be saved to Keychain.")) }
        tokens = result
        preferences.clearRefusals()
        settings.save(preferences.connection())
        phase = .signedIn
        callback?.cancel()
        callback = nil
        login = nil
        loginTask = nil
    }

    func signOut() {
        generation = UUID()
        stop()
        tokens = nil
        settings.removeConnection(id: preferences.connectionID)
        do {
            try store.remove()
            phase = .signedOut
        } catch {
            phase = .failed(String(localized: "The Claude account could not be removed from Keychain."))
        }
    }

    func stop() {
        loginTask?.cancel()
        loginTask = nil
        callback?.cancel()
        callback = nil
        login = nil
        refreshTask?.cancel()
        refreshTask = nil
        versionTask?.cancel()
    }

    func accessToken(sessionID: UUID? = nil, rejectedToken: String? = nil) async throws -> String {
        if let sessionID, sessionID != generation { throw ForkClaudeAccountLogin.Failure.rejected }
        if let refreshTask { return try await refreshTask.value }
        guard let tokens else { throw ForkClaudeAccountLogin.Failure.rejected }
        if tokens.expires > Date(), rejectedToken == nil || rejectedToken != tokens.access {
            return tokens.access
        }
        let operation = generation
        let task = Task { [weak self] () throws -> String in
            do {
                let result = try await ForkClaudeAccountLogin.refresh(tokens.refresh)
                try Task.checkCancellation()
                guard let self, self.generation == operation else { throw CancellationError() }
                do { try self.store.save(result) }
                catch { throw AIProviderError.unavailable(String(localized: "The refreshed Claude account could not be saved to Keychain.")) }
                self.tokens = result
                self.refreshTask = nil
                return result.access
            } catch {
                if let self, self.generation == operation {
                    self.refreshTask = nil
                    if case ForkClaudeAccountLogin.Failure.rejected = error { self.signOut() }
                }
                throw error
            }
        }
        refreshTask = task
        return try await task.value
    }

    func invalidate(rejectedToken: String, sessionID: UUID) {
        if generation == sessionID, tokens?.access == rejectedToken { signOut() }
    }

    func refreshCatalog() {
        guard tokens != nil else { return }
        preferences.clearRefusals()
        settings.save(preferences.connection())
    }

    func recordRefusal(model: String, effort: String?, sessionID: UUID) {
        guard generation == sessionID, tokens != nil else { return }
        preferences.refuse(model: model, effort: effort)
        settings.save(preferences.connection())
    }

    func provider(model: String, effort: String?, title: Bool = false) throws -> ForkClaudeAccountProvider {
        guard phase == .signedIn, tokens != nil else { throw ForkClaudeAccountLogin.Failure.rejected }
        guard let catalogModel = ForkClaudeCatalog.model(model),
            settings.connection(id: preferences.connectionID)?.models.contains(model) == true
        else { throw AIProviderError.unavailable(String(localized: "Choose an available Claude account model.")) }
        let options = settings.connection(id: preferences.connectionID)?.reasoningOptions?[model]
        guard title || options?.resolvedEffort(effort) != nil else {
            throw AIProviderError.unavailable(String(localized: "Refresh the Claude account to restore its effort levels."))
        }
        return ForkClaudeAccountProvider(
            account: self, sessionID: generation, model: catalogModel, effort: options?.resolvedEffort(effort) ?? "none", title: title)
    }

    func cliVersion() async -> String {
        if let versionTask { return await versionTask.value }
        let commandPath = settings.override(for: .claude).commandPath
        let task = Task { await ForkClaudeCLIVersion.read(commandPath: commandPath) }
        versionTask = task
        return await task.value
    }

    func title(describing description: String) async -> String? {
        guard let model = preferences.titleModel,
            let provider = try? provider(model: model, effort: "none", title: true)
        else { return nil }
        let request = AIRequest(
            instructions: ChatTitle.instructions,
            messages: [AIMessage(role: .user, text: description)])
        var text = ""
        do {
            for try await event in provider.stream(request) {
                if case .text(let delta) = event { text += delta }
            }
            try Task.checkCancellation()
            return ChatTitle.sanitize(text)
        } catch { return nil }
    }

    private func loginFailed(_ error: Error) {
        callback?.cancel()
        callback = nil
        login = nil
        loginTask = nil
        if let failure = error as? ForkClaudeAccountLogin.Failure {
            phase = .failed(failure.localizedDescription)
        } else if let failure = error as? AIProviderError {
            phase = .failed(failure.localizedDescription)
        } else {
            phase = .failed(ForkClaudeAccountLogin.Failure.unavailable.localizedDescription)
        }
    }

    #if DEBUG
    func debugSignInExpiry() async throws -> Date {
        signIn()
        while phase == .signingIn { try await Task.sleep(for: .milliseconds(100)) }
        guard phase == .signedIn, let tokens else { throw ForkClaudeAccountLogin.Failure.rejected }
        print("Claude account expiry: \(tokens.expires)")
        return tokens.expires
    }
    #endif
}
