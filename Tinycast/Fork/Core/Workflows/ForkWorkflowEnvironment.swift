import Foundation

enum ForkWorkflowEnvironment {
    static func values(
        inherited: [String: String], token: String, clientToken: String,
        tinycastPort: UInt16, serverPort: UInt16, diagnostics: String
    ) -> [String: String] {
        inherited.merging([
            "TINYCAST_SERVER_TOKEN": token, "TINYCAST_TOKEN": clientToken,
            "TINYCAST_PORT": String(tinycastPort), "TINYCAST_SERVER_PORT": String(serverPort),
            "TINYCAST_DIAGNOSTICS_DIRECTORY": diagnostics
        ]) { _, value in value }
    }
}
