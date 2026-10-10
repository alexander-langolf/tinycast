import Foundation

/// FORK: libghostty prototype. The switch between the ghostty grid and upstream's `TerminalLogView`.
///
/// `defaults write <bundle id> forkTerminalGhostty -bool NO` brings the old log back for comparison;
/// the choice is read when an instance opens.
enum GhosttyRenderer {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "forkTerminalGhostty") as? Bool ?? true
    }
}
