import CryptoKit
import Foundation
import Security

enum ForkClaudeAccountLogin {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let copyRedirect = "https://platform.claude.com/oauth/code/callback"
    static let scopes = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

    struct Session: Sendable {
        let verifier: String
        let redirectURI: String
        let authorizeURL: URL
    }

    enum Failure: LocalizedError {
        case invalidCode
        case stateMismatch
        case listener
        case rejected
        case unavailable

        var errorDescription: String? {
            switch self {
            case .invalidCode: return String(localized: "Paste the complete code#state sign-in code.")
            case .stateMismatch: return String(localized: "The sign-in state does not match. Start sign-in again.")
            case .listener: return String(localized: "The sign-in callback could not start. Use Copy Code sign-in.")
            case .rejected: return String(localized: "Sign in to your Claude account again.")
            case .unavailable: return String(localized: "Claude account sign-in could not complete. Try again.")
            }
        }
    }

    static func prepare(redirectURI: String) throws -> Session {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw Failure.unavailable
        }
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var url = URLComponents(string: "https://claude.ai/oauth/authorize")!
        url.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: verifier)
        ]
        return Session(verifier: verifier, redirectURI: redirectURI, authorizeURL: url.url!)
    }

    static func parseCode(_ input: String, state: String) throws -> String {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { throw Failure.invalidCode }
        guard parts[1] == state else { throw Failure.stateMismatch }
        return String(parts[0])
    }

    static func exchange(_ input: String, session: Session) async throws -> ForkClaudeAccountStore.Tokens {
        let code = try parseCode(input, state: session.verifier)
        return try await post([
            "grant_type": "authorization_code", "client_id": clientID,
            "code": code, "state": session.verifier, "redirect_uri": session.redirectURI,
            "code_verifier": session.verifier
        ])
    }

    static func refresh(_ token: String) async throws -> ForkClaudeAccountStore.Tokens {
        try await post(["grant_type": "refresh_token", "client_id": clientID, "refresh_token": token])
    }

    private static func post(_ body: [String: String]) async throws -> ForkClaudeAccountStore.Tokens {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: tokenURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Task.checkCancellation()
            throw Failure.unavailable
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw Failure.unavailable }
        guard (200...299).contains(response.statusCode) else {
            if [400, 401, 403].contains(response.statusCode) { throw Failure.rejected }
            throw Failure.unavailable
        }
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double
        }
        guard let result = try? JSONDecoder().decode(Response.self, from: data),
            !result.access_token.isEmpty, !result.refresh_token.isEmpty,
            result.expires_in.isFinite, result.expires_in > 0
        else { throw Failure.unavailable }
        return ForkClaudeAccountStore.Tokens(
            access: result.access_token, refresh: result.refresh_token,
            expiresIn: result.expires_in, now: Date())
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
