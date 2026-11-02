import Foundation

struct ForkQuickActionArguments: Sendable {
    enum Failure: String, Error, CustomStringConvertible {
        case unknownArgument = "Unknown Quick Action argument."
        case invalidAction = "action must be fixGrammar, rewrite, translate or summarize."
        case invalidInstruction = "instruction must be a string of at most 16384 characters."
        case invalidApply = "apply must be a boolean."
        case translationInstruction = "translate uses the configured language and does not accept instruction."

        var description: String { rawValue }
    }

    let action: BuiltInQuickAction
    let instruction: String?
    let apply: Bool

    init(arguments: [String: JSONValue]) throws {
        guard Set(arguments.keys).isSubset(of: ["action", "instruction", "apply"]) else {
            throw Failure.unknownArgument
        }
        guard let name = arguments["action"]?.stringValue, let action = BuiltInQuickAction(rawValue: name)
        else { throw Failure.invalidAction }
        self.action = action
        if let value = arguments["instruction"] {
            guard let instruction = value.stringValue, instruction.count <= 16_384 else {
                throw Failure.invalidInstruction
            }
            guard !action.usesTranslationFramework else { throw Failure.translationInstruction }
            self.instruction = instruction
        } else {
            instruction = nil
        }
        if let value = arguments["apply"] {
            guard let apply = value.boolValue else { throw Failure.invalidApply }
            self.apply = apply
        } else {
            apply = false
        }
    }
}
