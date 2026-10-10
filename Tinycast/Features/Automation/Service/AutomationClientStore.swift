import CryptoKit
import Foundation
import Observation
import Security
import os

/// Per-client bearer tokens. The secret lives only in the login Keychain, under a service named by
/// the bundle id so Dev and stable never share one; the metadata file holds no secret.
@MainActor
@Observable
final class AutomationClientStore {
    enum Failure: Error {
        case keychain
        case storage
    }

    static let keychainScope = "automation-clients"

    private(set) var clients: [AutomationClient] = []
    @ObservationIgnored private let keychain: KeychainSecretStore
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let now: () -> Date
    /// SHA-256 of each token, so a request is checked without touching the Keychain.
    @ObservationIgnored private var isMetadataLoaded = false
    @ObservationIgnored private var digests: [UUID: SHA256.Digest] = [:]
    @ObservationIgnored var onChange: ((_ revoked: UUID?) -> Void)?
    private nonisolated static let logger = Logger(subsystem: "com.tinycast", category: "Automation")

    init(
        keychain: KeychainSecretStore = KeychainSecretStore(scope: AutomationClientStore.keychainScope),
        directory: URL = AppPaths.applicationSupport().appending(
            path: "Automation", directoryHint: .isDirectory),
        now: @escaping () -> Date = { Date() }
    ) {
        self.keychain = keychain
        fileURL = directory.appending(path: "clients.json", directoryHint: .notDirectory)
        self.now = now
    }

    /// Labels, scopes and expiry only: what Settings lists. No Keychain access.
    func loadMetadata() {
        guard !isMetadataLoaded else { return }
        isMetadataLoaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode([AutomationClient].self, from: data) else {
            Self.logger.error("Could not read the automation client list")
            return
        }
        clients = stored
    }

    /// Reads every client's token once, off the main actor: the read can wait on a Keychain prompt.
    func loadDigests() async {
        loadMetadata()
        let keychain = keychain
        let ids = clients.map(\.id)
        let found = await Task.detached {
            var found: [UUID: SHA256.Digest] = [:]
            for id in ids {
                guard let token = try? keychain.secret(for: id) else {
                    Self.logger.error("No Keychain token for client \(id, privacy: .public)")
                    continue
                }
                found[id] = SHA256.hash(data: Data(token.utf8))
            }
            return found
        }.value
        let live = Set(clients.map(\.id))
        digests = found.filter { live.contains($0.key) }.merging(digests) { _, current in current }
    }

    /// The caller identity for this bearer, or nil: unknown, revoked, expired or not a token.
    func authenticate(bearer: String) -> AutomationClient? {
        guard let id = Self.clientID(in: bearer), let expected = digests[id],
            let client = clients.first(where: { $0.id == id }), !client.isExpired(at: now())
        else { return nil }
        return SHA256.hash(data: Data(bearer.utf8)) == expected ? client : nil
    }

    /// A client's current record, for rechecking authority after a wait.
    func current(_ id: UUID) -> AutomationClient? {
        guard let client = clients.first(where: { $0.id == id }), !client.isExpired(at: now()),
            digests[id] != nil
        else { return nil }
        return client
    }

    @discardableResult
    func create(
        label: String, scopes: Set<AutomationScope>, lifetime: TimeInterval?
    ) throws
        -> AutomationClient
    {
        loadMetadata()
        let created = now()
        let client = AutomationClient(
            id: UUID(), label: AutomationText.displaySafe(label, limit: 40), scopes: scopes,
            createdAt: created, expiresAt: lifetime.map { created.addingTimeInterval($0) })
        try store(token: Self.makeToken(for: client.id), for: client.id)
        clients.append(client)
        try persist()
        onChange?(nil)
        return client
    }

    /// A new secret under the same identity; the old one stops working at once.
    func rotate(_ id: UUID) throws {
        loadMetadata()
        guard clients.contains(where: { $0.id == id }) else { return }
        try store(token: Self.makeToken(for: id), for: id)
        onChange?(id)
    }

    func revoke(_ id: UUID) {
        loadMetadata()
        try? keychain.removeSecret(for: id)
        digests[id] = nil
        clients.removeAll { $0.id == id }
        try? persist()
        onChange?(id)
    }

    /// What `tinycast mcp --stdio` and `security find-generic-password` need to find the token.
    var keychainService: String {
        "\(Bundle.main.bundleIdentifier ?? "com.tinycast.app").\(Self.keychainScope)"
    }

    private func store(token: String, for id: UUID) throws {
        do {
            try keychain.setSecret(token, for: id)
        } catch {
            throw Failure.keychain
        }
        digests[id] = SHA256.hash(data: Data(token.utf8))
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(clients).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw Failure.storage
        }
    }

    /// `tcn_<client id>.<secret>`: the id lets the server find the digest; the secret is the proof.
    nonisolated static func makeToken(for id: UUID) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        let secret = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "tcn_\(id.uuidString).\(secret)"
    }

    nonisolated static func clientID(in token: String) -> UUID? {
        guard token.hasPrefix("tcn_"), let dot = token.firstIndex(of: ".") else { return nil }
        return UUID(uuidString: String(token[token.index(token.startIndex, offsetBy: 4)..<dot]))
    }
}
