// PROTOTYPE (throwaway) — question 1b: our own pty running a persistent interactive zsh.
// Shows: push-based streaming (no polling), session state kept across commands, command-finished +
// exit status + cwd detection via OSC 133/OSC 7 marks injected through a ZDOTDIR shim (the same trick
// kitty's shell integration uses), and the data an "open in kitty" handoff needs.
// Run: swift spike-own-pty.swift
import Darwin
import Foundation

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

// ZDOTDIR shim: load the user's real zsh config, then add our marks. Nothing in ~ is touched.
let shim = FileManager.default.temporaryDirectory.appendingPathComponent("tc-proto-zdotdir")
try? FileManager.default.createDirectory(at: shim, withIntermediateDirectories: true)
let home = NSHomeDirectory()
try! """
_tc=$ZDOTDIR; ZDOTDIR=\(home); [[ -f \(home)/.zshenv ]] && source \(home)/.zshenv; ZDOTDIR=$_tc
""".write(to: shim.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
try! """
ZDOTDIR=\(home); [[ -f \(home)/.zshrc ]] && source \(home)/.zshrc
_tc_precmd() { local s=$?; printf '\\e]133;D;%s\\a\\e]7;file://%s%s\\a\\e]133;A\\a' $s $HOST $PWD }
_tc_preexec() { printf '\\e]133;C\\a' }
precmd_functions+=(_tc_precmd); preexec_functions+=(_tc_preexec)
""".write(to: shim.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)

var parent: Int32 = 0
var size = winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
var env = ProcessInfo.processInfo.environment
env["TERM"] = "xterm-256color"; env["ZDOTDIR"] = shim.path; env["TINYCAST"] = "1"
env.removeValue(forKey: "KITTY_WINDOW_ID"); env.removeValue(forKey: "KITTY_LISTEN_ON")
let argList: [String] = ["/bin/zsh", "-i"]
let argv: [UnsafeMutablePointer<CChar>?] = argList.map { strdup($0) } + [nil]
let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
var pid: pid_t = 0
let t0 = now()
let usePosixSpawn = CommandLine.arguments.contains("--spawn")
if usePosixSpawn {
    // What Platform/PseudoTerminal.swift does (minus its EOF write). FINDING: Darwin applies the file
    // actions before setsid, so the tty never becomes the controlling terminal -> zsh has no job
    // control and ^C does nothing to the foreground job.
    var child: Int32 = 0
    precondition(openpty(&parent, &child, nil, nil, &size) == 0)
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var fa: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fa)
    posix_spawn_file_actions_addchdir(&fa, home)
    posix_spawn_file_actions_addopen(&fa, 0, String(cString: ptsname(parent)), O_RDWR, 0)
    posix_spawn_file_actions_adddup2(&fa, 0, 1)
    posix_spawn_file_actions_adddup2(&fa, 0, 2)
    posix_spawn_file_actions_addclose(&fa, parent)
    posix_spawn_file_actions_addclose(&fa, child)
    precondition(posix_spawn(&pid, "/bin/zsh", &fa, &attr, argv, envp) == 0)
    close(child)
} else {
    // forkpty = openpty + fork + login_tty (setsid, TIOCSCTTY, dup2) — a real controlling terminal.
    // The child only calls async-signal-safe chdir/execve on pre-built buffers (SwiftTerm does the same).
    pid = forkpty(&parent, nil, nil, &size)
    if pid == 0 {
        _ = home.withCString { chdir($0) }
        execve("/bin/zsh", argv, envp)
        _exit(127)
    }
    precondition(pid > 0)
}
print("spawned zsh -i pid \(pid) via \(usePosixSpawn ? "posix_spawn" : "forkpty") on \(String(cString: ptsname(parent)))")

// Reader: push-based, one read() per chunk the kernel hands us.
final class Log: @unchecked Sendable {
    let lock = NSLock(); var text = ""; var firstByte: Double?; var marks: [(Double, String)] = []
}
let log = Log()
Thread.detachNewThread {
    var buf = [UInt8](repeating: 0, count: 8192)
    while true {
        let n = read(parent, &buf, buf.count)
        if n <= 0 { break }
        let s = String(decoding: buf[0..<n], as: UTF8.self)
        let t = now()
        log.lock.lock()
        if log.firstByte == nil { log.firstByte = t }
        log.text += s
        // Pull out OSC 133 / OSC 7 marks.
        let re = try! NSRegularExpression(pattern: "\u{1B}\\](133;[A-D](?:;\\d+)?|7;[^\u{07}]*)\u{07}")
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            log.marks.append((t, String(s[Range(m.range(at: 1), in: s)!])))
        }
        log.lock.unlock()
    }
}

func waitFor(_ mark: String, after: Int, timeout: Double = 8000) -> Double? {
    let start = now()
    while now() - start < timeout {
        log.lock.lock(); let hit = log.marks.dropFirst(after).first { $0.1.hasPrefix(mark) }; log.lock.unlock()
        if let hit { return hit.0 }
        usleep(1000)
    }
    return nil
}
func markCount() -> Int { log.lock.lock(); defer { log.lock.unlock() }; return log.marks.count }
func send(_ s: String) { _ = s.withCString { write(parent, $0, strlen($0)) } }

// 1. shell ready = first prompt mark (includes the user's real .zshrc).
guard let ready = waitFor("133;A", after: 0) else { print("no prompt mark — zshrc may override precmd"); exit(1) }
print(String(format: "first byte %.1f ms, prompt ready (zshrc loaded) %.1f ms", (log.firstByte ?? 0) - t0, ready - t0))

// 2. the "$ pwd" command, then a second command in the SAME session.
for cmd in ["ps -o stat=,tpgid=,tty= -p $$; [[ -o monitor ]] && echo JOBCTL_ON || echo JOBCTL_OFF", "pwd", "cd /tmp && ls -d /tmp", "(exit 3)", "echo still in $PWD"] {
    let before = markCount()
    let t = now()
    send(cmd + "\r")
    let done = waitFor("133;D", after: before)
    log.lock.lock(); let status = log.marks.dropFirst(before).first { $0.1.hasPrefix("133;D") }?.1 ?? "?"
    let cwd = log.marks.dropFirst(before).last { $0.1.hasPrefix("7;") }?.1 ?? "?"; log.lock.unlock()
    print(String(format: "%-26@ finished in %6.1f ms  mark=%@  cwd=%@", cmd as NSString, (done ?? .nan) - t, status, cwd))
}

// 3. ^C reaches the foreground job (needs the controlling tty).
let before = markCount()
send("sleep 30\r"); usleep(300_000)
let tInt = now(); send("\u{03}")
let intr = waitFor("133;D", after: before)
print(String(format: "sleep 30 + ^C -> prompt back in %.1f ms (status mark: %@)", (intr ?? .nan) - tInt,
             log.marks.dropFirst(before).first { $0.1.hasPrefix("133;D") }?.1 ?? "none"))

// 4. Handoff data: the shell's live cwd straight from the kernel (no marks needed).
var info = proc_vnodepathinfo()
proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
let kcwd = withUnsafePointer(to: info.pvi_cdir.vip_path) { $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) } }
print("proc_pidinfo cwd = \(kcwd)  -> handoff: kitty @ launch --type=tab --cwd=\(kcwd)")

kill(-pid, SIGHUP)
var st: Int32 = 0; waitpid(pid, &st, 0)
log.lock.lock()
let visible = log.text.replacingOccurrences(of: "\u{1B}\\][^\u{07}]*\u{07}", with: "", options: .regularExpression)
log.lock.unlock()
print("--- raw bytes received: \(log.text.utf8.count); tail with OSC marks stripped (SGR left in) ---")
print(visible.suffix(400).debugDescription); if CommandLine.arguments.contains("--dump") { print(visible) }
