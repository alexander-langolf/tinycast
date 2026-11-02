import Foundation

struct ForkClaudeAccountStore: Sendable {
    struct Tokens: Codable, Sendable {
        let access: String
        let refresh: String
        let expires: Date

        init(access: String, refresh: String, expiresIn: TimeInterval, now: Date) {
            self.access = access
            self.refresh = refresh
            expires = now.addingTimeInterval(expiresIn - 300)
        }
    }

    let account: UUID
    var keychain = KeychainSecretStore.claudeAccount

    func load() throws -> Tokens? {
        guard let text = try keychain.secret(for: account) else { return nil }
        return try JSONDecoder().decode(Tokens.self, from: Data(text.utf8))
    }

    func save(_ tokens: Tokens) throws {
        let data = try JSONEncoder().encode(tokens)
        guard let text = String(data: data, encoding: .utf8) else {
            throw KeychainSecretStore.StoreError.invalidEncoding
        }
        try keychain.setSecret(text, for: account)
    }

    func remove() throws { try keychain.removeSecret(for: account) }
}
