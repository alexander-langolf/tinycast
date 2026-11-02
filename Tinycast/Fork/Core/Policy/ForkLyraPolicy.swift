import Foundation

struct ForkLyraPolicy: Sendable {
    struct Limits: Sendable {
        let minWords: Int
        let maxCharacters: Int

        func accepts(_ text: String) -> Bool {
            text.count <= maxCharacters && text.split(whereSeparator: { $0.isWhitespace }).count >= minWords
        }
    }

    struct Fix: Sendable {
        let limits: Limits
        let pauseMs: Int
        let punctuationEndsPause: Bool

        func delay(for text: String) -> Duration? {
            guard limits.accepts(text) else { return nil }
            let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last
            return punctuationEndsPause && last.map { ".!?".contains($0) } == true
                ? .zero : .milliseconds(pauseMs)
        }
    }

    struct Mode: Sendable {
        let name: ForkLyraMode
        let prompt: String
    }

    enum Route: Sendable, Equatable { case local, connection(UUID) }

    let fix: Fix
    let selection: Limits
    let modes: [Mode]
    let routing: [ForkLyraMode: Route]

    var availableModes: Set<ForkLyraMode> { Set(modes.map(\.name)) }
    var panelModes: [ForkLyraMode] { modes.map(\.name).filter { $0 != .fix } }

    static func decode(_ data: Data) throws -> Self {
        let failure = ForkPolicyFailure(file: "lyra.json", reason: .invalidValue)
        guard let json = JSONValue(data: data) else {
            throw ForkPolicyFailure(file: "lyra.json", reason: .invalidJSON)
        }
        func object(_ value: JSONValue?, keys: Set<String>) throws -> [String: JSONValue] {
            guard let object = value?.objectValue else { throw failure }
            guard Set(object.keys).isSubset(of: keys) else {
                throw ForkPolicyFailure(file: "lyra.json", reason: .unknownKey)
            }
            guard Set(object.keys) == keys else { throw failure }
            return object
        }
        func integer(_ value: JSONValue?, range: ClosedRange<Int>) throws -> Int {
            guard case .number(let number)? = value, number.isFinite, number.rounded() == number,
                number >= Double(range.lowerBound), number <= Double(range.upperBound) else { throw failure }
            return Int(number)
        }
        func limits(_ object: [String: JSONValue]) throws -> Limits {
            let minWords = try integer(object["minWords"], range: 1...10_000)
            let maxCharacters = try integer(object["maxCharacters"], range: 1...100_000)
            guard minWords <= maxCharacters else { throw failure }
            return Limits(minWords: minWords, maxCharacters: maxCharacters)
        }
        let root = try object(json, keys: ["schemaVersion", "fix", "selection", "modes", "routing"])
        _ = try integer(root["schemaVersion"], range: 1...1)
        let fix = try object(root["fix"], keys: ["minWords", "maxCharacters", "pauseMs", "punctuationEndsPause"])
        guard let punctuation = fix["punctuationEndsPause"]?.boolValue else { throw failure }
        let selection = try object(root["selection"], keys: ["minWords", "maxCharacters"])
        guard let entries = root["modes"]?.arrayValue, (1...16).contains(entries.count) else { throw failure }
        var modes: [Mode] = []
        for entry in entries {
            let entry = try object(entry, keys: ["name", "prompt"])
            guard let name = entry["name"]?.stringValue.flatMap(ForkLyraMode.init(rawValue:)),
                !modes.contains(where: { $0.name == name }), let prompt = entry["prompt"]?.stringValue,
                prompt.hasPrefix("prompts/"), validFilename(String(prompt.dropFirst(8))) else { throw failure }
            modes.append(Mode(name: name, prompt: prompt))
        }
        let routes = try object(root["routing"], keys: Set(modes.map(\.name.rawValue)))
        var routing: [ForkLyraMode: Route] = [:]
        for mode in modes {
            guard let route = routes[mode.name.rawValue]?.stringValue else { throw failure }
            if route == "local" { routing[mode.name] = .local }
            else if let id = UUID(uuidString: route) { routing[mode.name] = .connection(id) }
            else { throw failure }
        }
        return Self(fix: Fix(limits: try limits(fix), pauseMs: try integer(fix["pauseMs"], range: 0...60_000),
                             punctuationEndsPause: punctuation),
                    selection: try limits(selection), modes: modes, routing: routing)
    }

    static func validFilename(_ name: String) -> Bool {
        guard name.hasSuffix(".txt"), (5...68).contains(name.utf8.count) else { return false }
        return name.dropLast(4).utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
