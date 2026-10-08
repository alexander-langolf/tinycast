// Pins the terminal instance's pure layer: shell marks, `$` queries, stack geometry, row counting.
import Foundation

@main
struct TerminalInstancesTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)  \(detail())")
            failures += 1
        }
    }

    static func main() {
        parser()
        phase()
        query()
        stack()
        rows()
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    static func parser() {
        var whole = TerminalMarkParser()
        check("prompt mark", whole.feed(bytes("\u{1B}]133;A\u{07}")) == [.promptReady])
        let command = whole.feed(
            bytes(
                "ls\r\n\u{1B}]133;C\u{07}hello\r\n\u{1B}]133;D;0\u{07}"
                    + "\u{1B}]7;file://mac/Users/me\u{07}\u{1B}]133;A\u{07}"))
        check(
            "a whole command in one read",
            command == [
                .commandStarted, .output("hello\r\n"), .commandFinished(status: 0),
                .workingDirectory("/Users/me"), .promptReady
            ], "\(command)")

        var outside = TerminalMarkParser()
        check(
            "prompt text outside a command is dropped",
            outside.feed(bytes("me@mac ~ % \u{1B}]133;C\u{07}")) == [.commandStarted])

        var split = TerminalMarkParser()
        var events: [TerminalMarkParser.Event] = []
        for byte in bytes("\u{1B}]133;C\u{07}\u{1B}]133;D;3\u{07}") { events += split.feed([byte]) }
        check(
            "marks split byte by byte", events == [.commandStarted, .commandFinished(status: 3)], "\(events)")

        var st = TerminalMarkParser()
        check(
            "ST-terminated OSC 7, percent-decoded",
            st.feed(bytes("\u{1B}]7;file://host/tmp/a%20b\u{1B}\\")) == [.workingDirectory("/tmp/a b")])

        var splitST = TerminalMarkParser()
        let first = splitST.feed(bytes("\u{1B}]7;file://h/tmp\u{1B}"))
        let second = splitST.feed(bytes("\\"))
        check(
            "ST split between ESC and backslash",
            first.isEmpty && second == [.workingDirectory("/tmp")], "\(first) \(second)")

        var sgr = TerminalMarkParser()
        _ = sgr.feed(bytes("\u{1B}]133;C\u{07}"))
        let head = sgr.feed(bytes("\u{1B}[3"))
        let tail = sgr.feed(bytes("1mred"))
        check(
            "SGR split across reads stays whole in the output",
            head.isEmpty && tail == [.output("\u{1B}[31mred")], "\(head) \(tail)")

        var tui = TerminalMarkParser()
        _ = tui.feed(bytes("\u{1B}]133;C\u{07}"))
        let screen = tui.feed(bytes("a\u{1B}[?1049hb\u{1B}[?1049lc"))
        check(
            "alternate screen on and off, kept out of the output",
            screen == [
                .output("a"), .alternateScreen(true), .output("b"), .alternateScreen(false), .output("c")
            ], "\(screen)")

        var utf = TerminalMarkParser()
        _ = utf.feed(bytes("\u{1B}]133;C\u{07}"))
        let lead = utf.feed([0xC3])
        let rest = utf.feed([0xA9, 0x21])
        check(
            "a scalar split across reads is held back", lead.isEmpty && rest == [.output("é!")],
            "\(lead) \(rest)")

        var status = TerminalMarkParser()
        check(
            "D without a status reads as 0, with one as itself",
            status.feed(bytes("\u{1B}]133;D\u{07}\u{1B}]133;D;127\u{07}"))
                == [.commandFinished(status: 0), .commandFinished(status: 127)])

        var runaway = TerminalMarkParser()
        _ = runaway.feed(
            bytes("\u{1B}]0;" + String(repeating: "x", count: TerminalMarkParser.pendingLimit + 10)))
        check(
            "an unterminated OSC past the limit cannot stall the marks",
            runaway.feed(bytes("\u{1B}]133;A\u{07}")) == [.promptReady])

        var other = TerminalMarkParser()
        _ = other.feed(bytes("\u{1B}]133;C\u{07}"))
        check("charset designations are dropped", other.feed(bytes("a\u{1B}(Bb")) == [.output("ab")])
        check("window titles are dropped", other.feed(bytes("\u{1B}]2;title\u{07}c")) == [.output("c")])
    }

    static func phase() {
        let starting = TerminalSessionPhase.starting
        check(
            "the first prompt makes the shell idle", starting.applying(.promptReady) == .idle(lastStatus: nil)
        )
        check(
            "a stray D while starting is ignored", starting.applying(.commandFinished(status: 1)) == .starting
        )
        let finished = TerminalSessionPhase.running.applying(.commandFinished(status: 2))
        check("D records the status", finished == .idle(lastStatus: 2))
        check("the prompt after D keeps the status", finished.applying(.promptReady) == .idle(lastStatus: 2))
        check(
            "a prompt with no D ends a run with no status",
            TerminalSessionPhase.running.applying(.promptReady) == .idle(lastStatus: nil))
        check("ended is final", TerminalSessionPhase.ended.applying(.promptReady) == .ended)
        check(
            "only a running or ended shell refuses a command",
            TerminalSessionPhase.starting.acceptsCommand
                && TerminalSessionPhase.idle(lastStatus: 0).acceptsCommand
                && !TerminalSessionPhase.running.acceptsCommand && !TerminalSessionPhase.ended.acceptsCommand)
    }

    static func query() {
        let cases: [(String, String?)] = [
            ("$ ls -la", "ls -la"),
            ("  $   git status  ", "git status"),
            ("$\tpwd", "pwd"),
            ("$", ""),
            ("$ ", ""),
            ("$100 in eur", nil),
            ("$ls", nil),
            ("ls $HOME", nil),
            ("", nil)
        ]
        for (input, expected) in cases {
            let actual = TerminalCommandQuery.command(in: input)
            check("query \(input.debugDescription)", actual == expected, "\(String(describing: actual))")
        }
    }

    static func stack() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let anchor = CGPoint(x: 100, y: 900)
        func slot(_ id: UUID, _ height: CGFloat, _ corner: CGPoint? = nil) -> TerminalInstanceStack.Slot {
            TerminalInstanceStack.Slot(id: id, height: height, detachedTopLeft: corner)
        }
        let frames = TerminalInstanceStack.frames(
            for: [slot(a, 64), slot(b, 200), slot(c, 64)], anchor: anchor, width: 750, gap: 8, floorY: 0)
        check(
            "the newest sits at the anchor",
            frames[a] == CGRect(x: 100, y: 836, width: 750, height: 64), "\(String(describing: frames[a]))")
        check("the next hangs one gap below", frames[b] == CGRect(x: 100, y: 628, width: 750, height: 200))
        check("heights accumulate", frames[c] == CGRect(x: 100, y: 556, width: 750, height: 64))

        let dragged = TerminalInstanceStack.frames(
            for: [slot(a, 64), slot(b, 200, CGPoint(x: 400, y: 500)), slot(c, 64)],
            anchor: anchor, width: 750, gap: 8, floorY: 0)
        check(
            "a dragged panel keeps its own top-left",
            dragged[b] == CGRect(x: 400, y: 300, width: 750, height: 200))
        check(
            "the stack closes up over a dragged panel",
            dragged[c] == CGRect(x: 100, y: 764, width: 750, height: 64))

        let low = TerminalInstanceStack.frames(
            for: [slot(a, 200), slot(b, 200)], anchor: CGPoint(x: 0, y: 300), width: 750, gap: 8, floorY: 0)
        check(
            "the stack never drops below the visible floor", low[a]?.minY == 100 && low[b]?.minY == 0,
            "\(low)")

        check(
            "an empty card is the bar alone",
            TerminalInstanceStack.cardHeight(
                barHeight: 64, rows: 0, rowHeight: 15, verticalInset: 4, maxOutput: 340)
                == 64)
        check(
            "rows grow the card under a divider",
            TerminalInstanceStack.cardHeight(
                barHeight: 64, rows: 3, rowHeight: 15, verticalInset: 4, maxOutput: 340)
                == 64 + 1 + 45 + 8)
        check(
            "output caps at the maximum",
            TerminalInstanceStack.cardHeight(
                barHeight: 64, rows: 100, rowHeight: 15, verticalInset: 4, maxOutput: 340)
                == 64 + 1 + 340)
    }

    static func rows() {
        func count(_ chunks: [String], columns: Int = 80, cap: Int = 30) -> Int {
            var counter = TerminalLineCounter(columns: columns, cap: cap)
            for chunk in chunks { counter.append(chunk) }
            return counter.rows
        }
        check("no text, no rows", count([]) == 0)
        check("an unfinished line is a row", count(["abc"]) == 1)
        check("a trailing newline adds no row", count(["abc\n"]) == 1)
        check("two lines", count(["abc\ndef"]) == 2)
        check("CRLF is one break", count(["a\r\nb\r\n"]) == 2)
        check(
            "SGR takes no columns",
            count(["\u{1B}[31m" + String(repeating: "x", count: 4) + "\u{1B}[0m"], columns: 4) == 1)
        check(
            "long lines wrap", count(["abcdefgh"], columns: 4) == 2 && count(["abcdefghi"], columns: 4) == 3)
        check("a carriage return redraws in place", count(["10%\r20%\r30%\n"]) == 1)
        check("chunks join", count(["ab", "c\nd"]) == 2)
        check("rows stop at the cap", count([String(repeating: "x\n", count: 100)], cap: 5) == 5)
    }
}
