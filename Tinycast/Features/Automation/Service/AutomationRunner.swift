import AppKit

/// The effects themselves. The router has already decided the call may happen.
@MainActor
final class AutomationRunner {
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
    }

    /// Validates what the call will do and writes the exact words an approval will show.
    func prepare(_ call: AutomationCall) -> Result<AutomationRouter.Prepared, PrepareFailure> {
        var prepared = AutomationRouter.Prepared()
        switch call.operation.name {
        case AutomationOperationCatalog.terminalRun.name:
            guard let command = call.arguments["command"]?.stringValue,
                !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return .failure(PrepareFailure("The command is empty.")) }
            switch resolveDirectory(call.arguments["cwd"]?.stringValue) {
            case .failure(let failure): return .failure(failure)
            case .success(let directory):
                prepared.command = command
                prepared.directory = directory
                prepared.approvalTitle = "Run a command?"
                prepared.approvalDetails = [
                    .init(label: "Requested by", value: call.caller.label),
                    .init(label: "Command", value: command),
                    .init(label: "Folder", value: directory)
                ]
            }
        default:
            break
        }
        return .success(prepared)
    }

    struct PrepareFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    func perform(_ call: AutomationCall, prepared: AutomationRouter.Prepared) async -> AutomationOutcome {
        let arguments = call.arguments
        switch call.operation.name {
        case AutomationOperationCatalog.hudShow.name:
            showMessage(from: call.caller.label, text: arguments["text"]?.stringValue ?? "")
            return .value(.object(["shown": .bool(true)]))
        case AutomationOperationCatalog.paletteShow.name:
            showPalette(query: arguments["query"]?.stringValue ?? "")
            return .value(.object(["shown": .bool(true)]))
        case AutomationOperationCatalog.terminalRun.name:
            guard let command = prepared.command, let directory = prepared.directory,
                let instance = core.terminalInstances.open(command: command, directory: directory)
            else { return .toolError("Could not start the terminal.") }
            return .value(.object(["terminalId": .string(instance.id.uuidString)]))
        default:
            return .rpcError(.internalError("Operation is not implemented"))
        }
    }

    func showMessage(from label: String, text: String) {
        let text = AutomationText.displaySafe(text, limit: 120)
        let label = AutomationText.displaySafe(label, limit: 40)
        core.showMessage("\(label): \(text)", tone: .neutral)
    }

    /// Seeds the search field and never activates a row: the user still has to press return.
    func showPalette(query: String) {
        let query = AutomationText.displaySafe(query, limit: 200)
        core.paletteCoordinator.showPalette(
            mode: .launcher, restoreAnyMode: false, seeding: query.isEmpty ? nil : query)
    }

    private func resolveDirectory(_ requested: String?) -> Result<String, PrepareFailure> {
        guard let requested, !requested.isEmpty else {
            return .success(FileManager.default.homeDirectoryForCurrentUser.path)
        }
        let path = (requested as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return .failure(PrepareFailure("The folder does not exist: \(requested)")) }
        return .success(URL(filePath: path).standardizedFileURL.path)
    }
}
