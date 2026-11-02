import Foundation

enum ForkClaudeCLIVersion {
    static func read(commandPath: String) async -> String {
        guard let executable = await ForkAIExecutableResolver.resolve(kind: .claude, commandPath: commandPath)
        else { return "2.1.280" }
        let task = Task.detached { () -> String in
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = ["--version"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            return await withTaskCancellationHandler {
                if Task.isCancelled { return "2.1.280" }
                do {
                    let exit = try process.runObservingExit()
                    let timeout = Task.detached {
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                        if process.isRunning { process.terminate() }
                    }
                    defer { timeout.cancel() }
                    if Task.isCancelled, process.isRunning { process.terminate() }
                    let data = try output.fileHandleForReading.readToEnd() ?? Data()
                    exit.wait()
                    guard process.terminationStatus == 0,
                        let text = String(data: data, encoding: .utf8),
                        let first = text.split(whereSeparator: \.isWhitespace).first,
                        first.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil
                    else { return "2.1.280" }
                    return String(first)
                } catch { return "2.1.280" }
            } onCancel: {
                if process.isRunning { process.terminate() }
            }
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
    }
}
