import Darwin
import Foundation
import Synchronization

/// A persistent interactive `zsh -il` on its own pseudo-terminal, with job control.
final class TerminalProcess: @unchecked Sendable {
    enum Event: Sendable {
        case marks([TerminalMarkParser.Event])
        case exited
    }

    let processID: pid_t
    let events: AsyncStream<Event>

    private struct DescriptorState: Sendable {
        var descriptor: Int32
        var sources = 2
        var terminated = false
        var reaped = false
    }

    private let descriptorState: Mutex<DescriptorState>
    private let parentEnd: Int32
    private let continuation: AsyncStream<Event>.Continuation
    /// Source and buffer state below is touched on this queue alone.
    private let queue: DispatchQueue
    private var parser = TerminalMarkParser()
    private var readBuffer = [UInt8](repeating: 0, count: TerminalProcess.readSize)
    private var batch: [TerminalMarkParser.Event] = []
    private var flushScheduled = false
    private var readSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?
    private var writeSource: DispatchSourceWrite?
    private var writeResumed = false
    private var pendingInput: [UInt8] = []
    private var inputOffset = 0
    private var hasExited = false

    private static let shell = "/bin/zsh"
    private static let readSize = 64 * 1024
    private static let rows: UInt16 = 40
    /// Output-only reads coalesce for this long, so a flood is not a redraw per read.
    private static let flushDelay: DispatchTimeInterval = .milliseconds(30)
    private static let hangupGrace: DispatchTimeInterval = .seconds(2)

    private init(parentEnd: Int32, processID: pid_t) {
        self.parentEnd = parentEnd
        descriptorState = Mutex(DescriptorState(descriptor: parentEnd))
        self.processID = processID
        queue = DispatchQueue(label: "com.tinycast.terminal-instance", qos: .userInitiated)
        let stream = AsyncStream.makeStream(of: Event.self)
        events = stream.stream
        continuation = stream.continuation
    }

    /// Forks briefly and writes the shim, so callers run it off the main actor.
    static func spawn(
        directory: String, columns: Int, shimRoot: URL = FileManager.default.temporaryDirectory
    ) -> TerminalProcess? {
        guard let shim = TerminalShellShim.install(in: shimRoot) else { return nil }
        let environment = TerminalShellShim.environment(
            base: ProcessInfo.processInfo.environment, shim: shim)
        let argv = TerminalCStrings([shell, "-il"])
        let envp = TerminalCStrings(environment.map { "\($0.key)=\($0.value)" })
        let paths = TerminalCStrings([shell, directory])
        defer { withExtendedLifetime((argv, envp, paths)) {} }
        guard let executable = paths.pointers[0], let workingDirectory = paths.pointers[1] else {
            return nil
        }
        let argvPointers = argv.pointers
        let envpPointers = envp.pointers
        let descriptorLimit = getdtablesize()
        var size = winsize(ws_row: rows, ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        var parentEnd: Int32 = -1
        let processID = forkpty(&parentEnd, nil, nil, &size)
        if processID == 0 {
            // Async-signal-safe calls only, on memory built before the fork.
            var unblocked = sigset_t()
            _ = sigprocmask(SIG_SETMASK, &unblocked, nil)
            _ = Darwin.signal(SIGPIPE, SIG_DFL)
            _ = Darwin.signal(SIGINT, SIG_DFL)
            _ = Darwin.signal(SIGQUIT, SIG_DFL)
            _ = Darwin.signal(SIGTSTP, SIG_DFL)
            _ = Darwin.signal(SIGTTIN, SIG_DFL)
            _ = Darwin.signal(SIGTTOU, SIG_DFL)
            _ = Darwin.signal(SIGCHLD, SIG_DFL)
            var descriptor: Int32 = 3
            while descriptor < descriptorLimit {
                _ = Darwin.close(descriptor)
                descriptor += 1
            }
            _ = chdir(workingDirectory)
            _ = execve(executable, argvPointers, envpPointers)
            _exit(127)
        }
        guard processID > 0 else { return nil }
        _ = fcntl(parentEnd, F_SETFL, fcntl(parentEnd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(parentEnd, F_SETFD, FD_CLOEXEC)
        let process = TerminalProcess(parentEnd: parentEnd, processID: processID)
        process.begin()
        return process
    }

    /// Bytes for the shell's line editor: a command plus `\r`, or `\u{03}` for ⌃C.
    func send(_ text: String) {
        let bytes = Array(text.utf8)
        queue.async { [self] in
            guard readSource != nil else { return }
            pendingInput.append(contentsOf: bytes)
            flushInput()
        }
    }

    /// ⌃C goes ahead of any unsent input: a command still being written is dropped, since a ⌃C queued
    /// behind it would only flush the terminal's input and leave the shell mid-line. `TerminalSession`
    /// follows up when the shell was still reading the line and no prompt comes back.
    func interrupt() {
        queue.async { [self] in
            guard readSource != nil else { return }
            pendingInput.removeAll(keepingCapacity: true)
            inputOffset = 0
            pendingInput.append(3)
            flushInput()
        }
    }

    /// Hangs up captured job groups immediately, then kills both after grace even if zsh exited.
    func terminate() {
        let groups = descriptorState.withLock { state -> [pid_t] in
            guard !state.terminated, !state.reaped else { return [] }
            state.terminated = true
            let foreground = state.descriptor >= 0 ? tcgetpgrp(state.descriptor) : -1
            let shellGroup = getpgid(processID)
            let groups = Array(Set([foreground, shellGroup].filter { $0 > 0 }))
            for group in groups { killpg(group, SIGHUP) }
            return groups
        }
        queue.async { [self] in stopReading() }
        guard !groups.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.hangupGrace) {
            for group in groups { killpg(group, SIGKILL) }
        }
    }

    private func flushInput() {
        guard let writeSource else { return }
        while inputOffset < pendingInput.count {
            let written = pendingInput.withUnsafeBytes { bytes in
                Darwin.write(
                    parentEnd, bytes.baseAddress?.advanced(by: inputOffset), bytes.count - inputOffset)
            }
            if written > 0 {
                inputOffset += written
            } else if written < 0, errno == EINTR {
                continue
            } else if written < 0, errno == EAGAIN {
                break
            } else {
                pendingInput.removeAll(keepingCapacity: true)
                inputOffset = 0
                break
            }
        }
        if inputOffset == pendingInput.count {
            pendingInput.removeAll(keepingCapacity: true)
            inputOffset = 0
        }
        if pendingInput.isEmpty, writeResumed {
            writeSource.suspend()
            writeResumed = false
        } else if !pendingInput.isEmpty, !writeResumed {
            writeSource.resume()
            writeResumed = true
        }
    }

    private func releaseDescriptor() {
        descriptorState.withLock { state in
            state.sources -= 1
            guard state.sources == 0 else { return }
            _ = Darwin.close(state.descriptor)
            state.descriptor = -1
        }
    }

    private func begin() {
        let read = DispatchSource.makeReadSource(fileDescriptor: parentEnd, queue: queue)
        read.setEventHandler { [self] in drain() }
        read.setCancelHandler { [self] in releaseDescriptor() }
        let write = DispatchSource.makeWriteSource(fileDescriptor: parentEnd, queue: queue)
        write.setEventHandler { [self] in flushInput() }
        write.setCancelHandler { [self] in releaseDescriptor() }
        writeSource = write
        readSource = read
        let exit = DispatchSource.makeProcessSource(identifier: processID, eventMask: .exit, queue: queue)
        exit.setEventHandler { [self] in
            if collectExit() { finish() }
        }
        exitSource = exit
        read.resume()
        exit.resume()
        // A shell that died before the source existed would never be reported.
        queue.async { [self] in
            if collectExit() { finish() }
        }
    }

    private func drain() {
        let count = readBuffer.withUnsafeMutableBytes { Darwin.read(parentEnd, $0.baseAddress, $0.count) }
        if count > 0 {
            enqueue(parser.feed(readBuffer[0..<count]))
        } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
            // EIO once every holder of the child end is gone; the exit source still reaps.
            stopReading()
        }
    }

    private func enqueue(_ events: [TerminalMarkParser.Event]) {
        for event in events {
            if case .output(let text) = event, case .output(let previous)? = batch.last {
                batch[batch.count - 1] = .output(previous + text)
            } else {
                batch.append(event)
            }
        }
        let hasMark = batch.contains { event in
            if case .output = event { return false }
            return true
        }
        if hasMark { return flush() }
        guard !flushScheduled, !batch.isEmpty else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + Self.flushDelay) { [self] in
            flushScheduled = false
            flush()
        }
    }

    private func flush() {
        guard !batch.isEmpty else { return }
        continuation.yield(.marks(batch))
        batch.removeAll()
    }

    private func collectExit() -> Bool {
        guard !hasExited else { return false }
        var status: Int32 = 0
        let reaped = descriptorState.withLock { state in
            guard waitpid(processID, &status, WNOHANG) == processID else { return false }
            state.reaped = true
            return true
        }
        guard reaped else { return false }
        hasExited = true
        return true
    }

    private func finish() {
        if readSource != nil {
            while true {
                let count = readBuffer.withUnsafeMutableBytes {
                    Darwin.read(parentEnd, $0.baseAddress, $0.count)
                }
                guard count > 0 else { break }
                enqueue(parser.feed(readBuffer[0..<count]))
            }
        }
        flush()
        stopReading()
        exitSource?.cancel()
        exitSource = nil
        continuation.yield(.exited)
        continuation.finish()
    }

    private func stopReading() {
        if let writeSource {
            if !writeResumed { writeSource.resume() }
            writeSource.cancel()
            self.writeSource = nil
            writeResumed = false
        }
        pendingInput.removeAll()
        inputOffset = 0
        readSource?.cancel()
        readSource = nil
    }
}

/// argv and envp built before the fork, so the child touches nothing but these pointers.
private final class TerminalCStrings {
    let pointers: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    private let count: Int

    init(_ values: [String]) {
        count = values.count
        pointers = .allocate(capacity: count + 1)
        for (index, value) in values.enumerated() { pointers[index] = strdup(value) }
        pointers[count] = nil
    }

    deinit {
        for index in 0..<count { free(pointers[index]) }
        pointers.deallocate()
    }
}
