// Runs `zsh -il` through the ZDOTDIR shim on a scratch HOME: marks, status, ⌃C, cwd, hang-up.
import Foundation
import Synchronization

final class Recorder: Sendable {
    let marks = Mutex<[TerminalMarkParser.Event]>([])
    let exited = Mutex(false)
}

@main
struct TerminalProcessTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)  \(detail())")
            failures += 1
        }
    }

    struct Run {
        let output: String
        let status: Int32?
        let marks: [TerminalMarkParser.Event]
    }

    static func main() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminal-process-test-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: home.appendingPathComponent("a b", isDirectory: true), withIntermediateDirectories: true)
        let files = [
            ".zshenv": "export TC_FROM_ZSHENV=env\n",
            ".zprofile": "export TC_FROM_ZPROFILE=profile\n",
            ".zshrc": "export TC_FROM_ZSHRC=rc\nPROMPT='> '\n"
        ]
        for (name, contents) in files {
            try? contents.write(to: home.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        setenv("HOME", home.path, 1)
        unsetenv("ZDOTDIR")

        guard let process = TerminalProcess.spawn(directory: home.path, columns: 80, shimRoot: root) else {
            print("FAIL  spawn")
            exit(1)
        }
        let (recorder, reader) = record(process)

        check("the first prompt arrives", await waitFor(recorder) { $0.contains(.promptReady) })

        let env = await run(
            process, recorder,
            "echo $TC_FROM_ZSHENV $TC_FROM_ZPROFILE $TC_FROM_ZSHRC; echo ZDOTDIR_SET=${+ZDOTDIR}")
        check(
            "all user startup files load through the shim", env.output.contains("env profile rc"),
            env.output.debugDescription)
        check(
            "ZDOTDIR stays unset when the user did not set it", env.output.contains("ZDOTDIR_SET=0"),
            env.output.debugDescription)
        check("a clean command reports 0", env.status == 0, String(describing: env.status))

        let long = await run(
            process, recorder, "echo -n " + String(repeating: "a", count: 30000) + " | wc -c")
        check(
            "a 30000-character command finishes without blocking pty reads",
            long.status == 0 && long.marks.contains(.promptReady)
                && long.output.trimmingCharacters(in: .whitespacesAndNewlines) == "30000",
            long.output.debugDescription)

        let failed = await run(process, recorder, "(exit 3)")
        check("a failing command reports its status", failed.status == 3, String(describing: failed.status))

        _ = await run(process, recorder, "cd 'a b'")
        let directory = recorder.marks.withLock { marks in
            marks.compactMap { mark -> String? in
                if case .workingDirectory(let path) = mark { return path }
                return nil
            }.last
        }
        check(
            "OSC 7 follows cd, spaces decoded", directory?.hasSuffix("/a b") == true,
            String(describing: directory))

        let start = count(recorder)
        process.send("sleep 30\r")
        check("the command starts", await waitFor(recorder, after: start) { $0.contains(.commandStarted) })
        process.send("\u{03}")
        check(
            "⌃C reaches the foreground job (job control)",
            await waitFor(recorder, after: start) { $0.contains(.commandFinished(status: 130)) })

        let tui = await run(process, recorder, #"printf '\e[?1049h'; printf '\e[?1049l'"#)
        check(
            "the alternate screen is reported",
            tui.marks.contains(.alternateScreen(true)) && tui.marks.contains(.alternateScreen(false)),
            "\(tui.marks)")

        let pidFile = root.appendingPathComponent("foreground.pid")
        let foregroundStart = count(recorder)
        process.send("/bin/sh -c 'trap \"\" HUP; echo $$ > \"\(pidFile.path)\"; exec sleep 321'\r")
        check(
            "the HUP-ignoring foreground job starts",
            await waitFor(recorder, after: foregroundStart) { $0.contains(.commandStarted) })
        let hasPID = await waitUntil(5) {
            guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return false }
            return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        }
        let foregroundPID = (try? String(contentsOf: pidFile, encoding: .utf8))
            .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        check("the foreground job records its own PID", hasPID && foregroundPID != nil)

        process.terminate()
        let shellExited = await waitUntil(5) { recorder.exited.withLock { $0 } }
        check("hang-up ends the shell", shellExited)
        if !shellExited { kill(process.processID, SIGKILL) }

        if let foregroundPID {
            let killed = await waitUntil(5) { kill(foregroundPID, 0) == -1 && errno == ESRCH }
            check("hang-up kills the HUP-ignoring foreground job after the shell exits", killed)
            if !killed { kill(foregroundPID, SIGKILL) }
        }

        let custom = root.appendingPathComponent("custom-zdotdir", isDirectory: true)
        try? FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        for (name, contents) in files {
            try? contents.write(to: custom.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        setenv("ZDOTDIR", custom.path, 1)
        if let restored = TerminalProcess.spawn(directory: home.path, columns: 80, shimRoot: root) {
            let (restoredRecorder, restoredReader) = record(restored)
            check(
                "the custom ZDOTDIR shell reaches its prompt",
                await waitFor(restoredRecorder) { $0.contains(.promptReady) })
            let restoredEnv = await run(
                restored, restoredRecorder,
                "echo $ZDOTDIR; echo $TC_FROM_ZSHENV $TC_FROM_ZPROFILE $TC_FROM_ZSHRC")
            check(
                "an inherited ZDOTDIR is restored and its startup files load",
                restoredEnv.output.contains(custom.path) && restoredEnv.output.contains("env profile rc"),
                restoredEnv.output.debugDescription)
            restored.terminate()
            check(
                "the custom ZDOTDIR shell exits",
                await waitUntil(5) { restoredRecorder.exited.withLock { $0 } })
            restoredReader.cancel()
        } else {
            check("spawn with a custom ZDOTDIR", false)
        }
        unsetenv("ZDOTDIR")

        reader.cancel()
        try? FileManager.default.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func record(_ process: TerminalProcess) -> (Recorder, Task<Void, Never>) {
        let recorder = Recorder()
        let reader = Task.detached {
            for await event in process.events {
                switch event {
                case .marks(let marks): recorder.marks.withLock { $0 += marks }
                case .exited: recorder.exited.withLock { $0 = true }
                }
            }
        }
        return (recorder, reader)
    }

    static func count(_ recorder: Recorder) -> Int { recorder.marks.withLock { $0.count } }

    static func waitUntil(_ seconds: Double, _ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    static func waitFor(
        _ recorder: Recorder, after start: Int = 0, timeout: Double = 10,
        _ predicate: @escaping @Sendable ([TerminalMarkParser.Event]) -> Bool
    ) async -> Bool {
        await waitUntil(timeout) { recorder.marks.withLock { predicate(Array($0.dropFirst(start))) } }
    }

    /// Sends one line and waits for its D mark and the prompt after it.
    static func run(_ process: TerminalProcess, _ recorder: Recorder, _ command: String) async -> Run {
        let start = count(recorder)
        process.send(command + "\r")
        _ = await waitFor(recorder, after: start) { marks in
            guard
                let finished = marks.firstIndex(where: { mark in
                    if case .commandFinished = mark { return true }
                    return false
                })
            else { return false }
            return marks[finished...].contains(.promptReady)
        }
        let marks = recorder.marks.withLock { Array($0.dropFirst(start)) }
        let output = marks.compactMap { mark -> String? in
            if case .output(let text) = mark { return text }
            return nil
        }.joined()
        let status = marks.compactMap { mark -> Int32? in
            if case .commandFinished(let status) = mark { return status }
            return nil
        }.first
        return Run(output: output, status: status, marks: marks)
    }
}
