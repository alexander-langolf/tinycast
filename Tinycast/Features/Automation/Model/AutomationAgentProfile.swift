import Foundation

/// A launch grant written by the user: a named command a client may ask to start, and nothing else.
/// Clients choose the profile and supply the prompt; they never supply the command.
struct AutomationAgentProfile: Codable, Equatable, Sendable {
    let name: String
    var title: String?
    /// A bare executable name or an absolute path.
    let command: String
    /// Each may contain `{prompt}`, replaced by the prompt as a single quoted word.
    var arguments: [String] = []

    static let promptToken = "{prompt}"

    var isValid: Bool {
        Self.matches(name, #"^[a-z0-9_-]{1,32}$"#)
            && Self.matches(command, #"^[A-Za-z0-9._/+-]{1,200}$"#)
            && arguments.allSatisfy { $0.count <= 200 }
    }

    /// The exact line the shell will run, with every word single-quoted.
    func shellLine(prompt: String) -> String {
        let words = [command] + arguments.map { $0.replacingOccurrences(of: Self.promptToken, with: prompt) }
        return words.map(Self.quote).joined(separator: " ")
    }

    static func quote(_ word: String) -> String {
        if matches(word, #"^[A-Za-z0-9._/+=:,@%-]+$"#) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Invalid entries are dropped, never repaired.
    static func decode(_ data: Data) -> [AutomationAgentProfile] {
        guard let profiles = try? JSONDecoder().decode([AutomationAgentProfile].self, from: data) else {
            return []
        }
        var seen = Set<String>()
        return profiles.filter { $0.isValid && seen.insert($0.name).inserted }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
