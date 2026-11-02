import Foundation

@main
struct ForkCapabilityArgumentsTests {
    static func main() throws {
        for action in BuiltInQuickAction.allCases {
            let parsed = try ForkQuickActionArguments(arguments: ["action": .string(action.rawValue)])
            precondition(parsed.action == action && !parsed.apply && parsed.instruction == nil)
        }
        let rewrite = try ForkQuickActionArguments(arguments: [
            "action": .string("rewrite"), "instruction": .string("Keep my voice."), "apply": .bool(true)
        ])
        precondition(rewrite.apply && rewrite.instruction == "Keep my voice.")
        let invalidArguments: [[String: JSONValue]] = [
            [:], ["action": .string("unknown")], ["action": .bool(true)],
            ["action": .string("rewrite"), "apply": .string("true")],
            ["action": .string("rewrite"), "apply": .null],
            ["action": .string("rewrite"), "instruction": .number(1)],
            ["action": .string("rewrite"), "instruction": .string(String(repeating: "x", count: 16_385))],
            ["action": .string("translate"), "instruction": .string("Use a model.")],
            ["action": .string("rewrite"), "text": .string("Unaccepted input.")]
        ]
        for invalid in invalidArguments {
            do {
                _ = try ForkQuickActionArguments(arguments: invalid)
                preconditionFailure("Invalid arguments must fail before effects.")
            } catch is ForkQuickActionArguments.Failure {}
        }
        precondition(ForkSelectionOperations.operations.allSatisfy { $0.scope == .selection && !$0.needsApproval })
        precondition(AutomationSchemaValidator.validate(
            arguments: ["action": .string("rewrite"), "apply": .string("true")],
            against: ForkSelectionOperations.quickActionRun.inputSchema) != nil)
        precondition(AutomationSchemaValidator.validate(
            arguments: ["text": .string("private")], against: ForkSelectionOperations.selectionRead.inputSchema) != nil)

        let defaults = try ForkCallCLI.parse(["call", "hud_show"], environment: [:], defaultChannel: "dev")
        precondition(defaults.tool == "hud_show" && defaults.channel == "dev" && defaults.client == nil)
        precondition(String(decoding: defaults.arguments, as: UTF8.self) == "{}")
        let json = #"{"action":"rewrite","apply":true,"instruction":"Preserve \"quotes\".\n"}"#
        let parsed = try ForkCallCLI.parse(
            ["call", "quick_action_run", "--args", json, "--channel", "dev", "--client", "client-id"],
            environment: ["TINYCAST_CHANNEL": "stable", "TINYCAST_CLIENT": "other"], defaultChannel: "beta")
        precondition(parsed.tool == "quick_action_run" && parsed.channel == "dev" && parsed.client == "client-id")
        precondition(parsed.arguments == Data(json.utf8))
        let environment = try ForkCallCLI.parse(
            ["call", "hud_show"], environment: ["TINYCAST_CHANNEL": "beta", "TINYCAST_CLIENT": "saved"],
            defaultChannel: "stable")
        precondition(environment.channel == "beta" && environment.client == "saved")
        for invalid in [
            ["call"], ["call", "--args"], ["call", "hud_show", "--args"],
            ["call", "hud_show", "--args", "[]"], ["call", "hud_show", "--args", "null"],
            ["call", "hud_show", "--args", "bad json"], ["call", "hud_show", "--args", "1"],
            ["call", "hud_show", "--channel", "other"], ["call", "hud_show", "--client"],
            ["call", "hud_show", "--unknown"], ["call", "hud_show", "--args", "{}", "--args", "{}"],
            ["call", "hud_show", "--client", "--channel", "dev"]
        ] {
            do {
                _ = try ForkCallCLI.parse(invalid, environment: [:], defaultChannel: "dev")
                preconditionFailure("Invalid CLI arguments must fail before credentials or HTTP.")
            } catch is ForkCallCLI.Failure {}
        }
        print("Fork capability arguments: passed")
    }
}
