import Foundation

struct ForkLyraMode: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        guard (1...32).contains(rawValue.utf8.count), rawValue.utf8.allSatisfy({
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { return nil }
        self.rawValue = rawValue
    }

    static let fix = Self(rawValue: "fix")!
    static let refine = Self(rawValue: "refine")!
    static let professional = Self(rawValue: "professional")!
    static let friendly = Self(rawValue: "friendly")!
}

enum ForkLyraText {
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "(?s)<think>.*?(?:</think>|$)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</?input>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
