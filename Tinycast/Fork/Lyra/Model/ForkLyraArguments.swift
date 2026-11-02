import Foundation

struct ForkLyraArguments: Sendable {
    enum Target: String, Sendable { case automatic, selection, field }
    enum Failure: String, Error, CustomStringConvertible {
        case unknownArgument = "Unknown Lyra argument."
        case invalidMode = "mode must name an enabled policy mode."
        case invalidTarget = "target must be automatic, selection or field."
        case invalidApply = "apply must be a boolean."
        var description: String { rawValue }
    }

    let mode: ForkLyraMode
    let target: Target
    let apply: Bool

    init(arguments: [String: JSONValue], modes: Set<ForkLyraMode>) throws {
        guard Set(arguments.keys).isSubset(of: ["mode", "target", "apply"]) else { throw Failure.unknownArgument }
        guard let name = arguments["mode"]?.stringValue, let mode = ForkLyraMode(rawValue: name), modes.contains(mode)
        else { throw Failure.invalidMode }
        self.mode = mode
        if let value = arguments["target"] {
            guard let name = value.stringValue, let target = Target(rawValue: name) else { throw Failure.invalidTarget }
            self.target = target
        } else { target = .automatic }
        if let value = arguments["apply"] {
            guard let apply = value.boolValue else { throw Failure.invalidApply }
            self.apply = apply
        } else { apply = false }
    }
}
