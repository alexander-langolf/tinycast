import Foundation

@main
struct AgentRunsTest {
    static func main() throws {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func decode(_ json: String) throws -> [AgentRun] {
            try JSONDecoder().decode([AgentRun].self, from: Data(json.utf8))
        }

        let json = """
            [
              {"id":"c1","agent":"claude","name":"Footer","cwd":"/tmp/a b",
               "state":"working","startedAt":1791456000123,"last":"Reading files",
               "attach":"claude --resume 'c1'"},
              {"id":"s1","agent":"subagent","name":"Review","cwd":"/tmp/review",
               "state":"blocked","startedAt":1791456000000,"last":null,"attach":null},
              {"id":"x1","agent":"codex","name":"Harness","cwd":"/tmp/tests",
               "state":"waiting_for_input","startedAt":1791456001000}
            ]
            """
        let runs = try decode(json)
        check("all kinds decode in source order", runs.map(\.agent) == [.claude, .subagent, .codex])
        check("ids survive decoding", runs.map(\.id) == ["c1", "s1", "x1"])
        check("name survives decoding", runs[0].name == "Footer")
        check("cwd preserves spaces", runs[0].cwd == "/tmp/a b")
        check("milliseconds are not rounded", runs[0].startedAt == 1_791_456_000_123)
        check("latest activity is decoded", runs[0].last == "Reading files")
        check("attach command stays literal", runs[0].attach == "claude --resume 'c1'")
        check("null optionals are absent", runs[1].last == nil && runs[1].attach == nil)
        check("omitted optionals are absent", runs[2].last == nil && runs[2].attach == nil)
        check("unknown states are retained", runs[2].state == "waiting_for_input")
        let empty = try decode("[]")
        check("an empty snapshot removes every run", empty.isEmpty && empty != runs)
        let unchanged = try decode(json)
        check("identical snapshots compare equal", unchanged == runs)
        for (before, after) in [
            ("Reading files", "Editing files"), ("working", "blocked"),
            ("Footer", "Launcher"), ("/tmp/a b", "/tmp/new"),
            ("1791456000123", "1791456000124"), ("--resume", "--continue")
        ] {
            let changed = try decode(json.replacingOccurrences(of: before, with: after))
            check("a change to \(before) changes the snapshot", changed != runs)
        }
        check("removing one run changes the snapshot", Array(runs.dropLast()) != runs)

        for invalid in [
            "not json", "{}", "[{}]",
            json.replacingOccurrences(of: "\"codex\"", with: "\"unknown\""),
            json.replacingOccurrences(of: "1791456000123", with: "\"yesterday\"")
        ] {
            do {
                _ = try decode(invalid)
                check("invalid input is rejected", false)
            } catch {
                check("invalid input is rejected", true)
            }
        }

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) failed")
        if failures > 0 { exit(1) }
    }
}
