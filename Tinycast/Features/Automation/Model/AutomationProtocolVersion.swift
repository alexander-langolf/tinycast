import Foundation

/// The MCP revisions this endpoint speaks: the stateless 2026-07-28 revision, plus the earlier
/// handshake revisions that Claude Code and Codex fall back to.
enum AutomationProtocolVersion {
    static let current = "2026-07-28"
    static let legacy = ["2025-11-25", "2025-06-18", "2025-03-26"]
    static let supported = [current] + legacy

    static func isLegacy(_ version: String) -> Bool { legacy.contains(version) }

    /// The revision a legacy `initialize` settles on: the client's own when known, else our newest.
    static func negotiatedLegacy(requested: String?) -> String {
        guard let requested, isLegacy(requested) else { return legacy[0] }
        return requested
    }
}
