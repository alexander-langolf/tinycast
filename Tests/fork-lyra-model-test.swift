import Foundation

@main
struct ForkLyraModelTests {
    static func main() throws {
        let snapshot = try ForkPolicySnapshot.load(directory: URL(filePath: "server"))
        let policy = snapshot.policy
        let modes = Set(policy.modes.map(\.name))
        precondition(policy.fix.delay(for: "one two") == nil)
        precondition(policy.fix.delay(for: "one two three") == .milliseconds(500))
        precondition(policy.fix.delay(for: "one two three. \n") == .zero)
        precondition(policy.fix.delay(for: "one two three!") == .zero)
        precondition(policy.fix.delay(for: "one two three?") == .zero)
        precondition(policy.fix.delay(for: "one two " + String(repeating: "x", count: 992)) != nil)
        precondition(policy.fix.delay(for: "one two " + String(repeating: "x", count: 993)) == nil)
        precondition(policy.selection.accepts("one two three"))
        precondition(policy.selection.accepts("one two three."))
        precondition(!policy.selection.accepts("one two"))
        precondition(policy.selection.accepts("one two " + String(repeating: "x", count: 992)))
        precondition(!policy.selection.accepts("one two " + String(repeating: "x", count: 993)))
        precondition(ForkLyraText.clean("<think>private</think><input>  Result. </input> \n") == "Result.")
        precondition(ForkLyraText.clean("<think>unfinished") == "")
        precondition(ForkLyraText.clean("<INPUT>Reply</INPUT>") == "Reply")
        precondition(ForkLyraText.normalized("a \n b\t c") == "a b c")
        precondition(policy.modes.map(\.name.rawValue) == ["fix", "refine", "professional", "friendly"])
        for mode in policy.modes { precondition(snapshot.prompts[mode.name]?.isEmpty == false) }
        for mode in policy.modes.map(\.name) {
            let parsed = try ForkLyraArguments(arguments: ["mode": .string(mode.rawValue)], modes: modes)
            precondition(parsed.mode == mode && parsed.target == .automatic && !parsed.apply)
        }
        let apply = try ForkLyraArguments(arguments: ["mode": .string("friendly"), "target": .string("selection"), "apply": .bool(true)], modes: modes)
        precondition(apply.apply && apply.target == .selection)
        let invalid: [[String: JSONValue]] = [
            [:], ["mode": .string("unknown")], ["mode": .bool(true)],
            ["mode": .string("fix"), "target": .string("unknown")],
            ["mode": .string("fix"), "target": .null],
            ["mode": .string("fix"), "apply": .number(1)],
            ["mode": .string("fix"), "apply": .null],
            ["mode": .string("fix"), "text": .string("must not be accepted")]
        ]
        for arguments in invalid {
            do { _ = try ForkLyraArguments(arguments: arguments, modes: modes); preconditionFailure("invalid arguments accepted") }
            catch is ForkLyraArguments.Failure { }
        }
        precondition(ForkPrimitiveOperations.marker.scope == .selection)
        precondition(!ForkPrimitiveOperations.marker.needsApproval)
        precondition(ForkPrimitiveOperations.marker.linkHost == nil)
        precondition(ForkPrimitiveOperations.result.scope == .selection)
        precondition(ForkPrimitiveOperations.modelComplete.scope == .model)
        precondition(ForkLyraOperations.rewrite.scope == .selection)
        precondition(!ForkLyraOperations.rewrite.needsApproval)
        print("PASSED: Lyra trigger, cleaning, prompts and arguments")
    }
}
