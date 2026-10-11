import AppKit

/// The effects themselves. The router has already decided the call may happen.
@MainActor
final class AutomationRunner {
    struct PrepareFailure: Error, CustomStringConvertible, Sendable {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private unowned let core: AppCore
    private let questions: AutomationQuestionStore
    /// Which client started each terminal; `terminal_focus` reaches only a client's own.
    private var startedBy: [UUID: UUID] = [:]

    init(core: AppCore, questions: AutomationQuestionStore) {
        self.core = core
        self.questions = questions
    }

    /// Validates what the call will do and writes the exact words an approval will show.
    func prepare(_ call: AutomationCall) async -> Result<AutomationRouter.Prepared, PrepareFailure> {
        var prepared = AutomationRouter.Prepared()
        let arguments = call.arguments
        switch call.operation.name {
        case AutomationOperationCatalog.terminalRun.name:
            guard let command = arguments["command"]?.stringValue,
                !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return .failure(PrepareFailure("The command is empty.")) }
            let directory = await Task.detached {
                Self.resolveDirectory(arguments["cwd"]?.stringValue)
            }.value
            switch directory {
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
            let open = Set(core.terminalInstances.instances.map(\.id))
            startedBy = startedBy.filter { open.contains($0.key) }
            if let client = call.caller.clientID { startedBy[instance.id] = client }
            return .value(.object(["terminalId": .string(instance.id.uuidString)]))
        case AutomationOperationCatalog.terminalFocus.name:
            guard let id = arguments["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
                let client = call.caller.clientID, startedBy[id] == client,
                core.terminalInstancesPresenter.focus(id)
            else { return .toolError("No open terminal you started has that id.") }
            return .value(.object(["focused": .bool(true)]))
        case AutomationOperationCatalog.questionAsk.name:
            return ask(call)
        case AutomationOperationCatalog.questionAcknowledge.name:
            guard let client = call.caller.clientID,
                let id = arguments["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
                questions.acknowledge(id, by: client)
            else { return .toolError("No answered or expired question of yours has that id.") }
            return .value(.object(["acknowledged": .bool(true)]))
        default:
            return await read(call)
        }
    }

    private func read(_ call: AutomationCall) async -> AutomationOutcome {
        switch call.operation.name {
        case AutomationOperationCatalog.agents.name:
            await core.agentRuns.refreshOnce()
            return .value(.object(["runs": .array(core.agentRuns.runs.map(Self.json))]))
        case AutomationOperationCatalog.terminals.name:
            let client = call.caller.clientID
            return .value(
                .object([
                    "terminals": .array(
                        core.terminalInstances.instances.map { instance in
                            json(instance, startedByCaller: client != nil && startedBy[instance.id] == client)
                        })
                ]))
        case AutomationOperationCatalog.questions.name:
            guard let client = call.caller.clientID else { return .toolError("Not available.") }
            return .value(
                .object(["questions": .array(questions.visible(to: client).map(\.json))]))
        case AutomationOperationCatalog.context.name:
            let app = NSWorkspace.shared.frontmostApplication
            return .value(
                .object([
                    "frontmostApp": .object([
                        "name": .string(app?.localizedName ?? ""),
                        "bundleId": .string(app?.bundleIdentifier ?? "")
                    ])
                ]))
        default:
            return .rpcError(.internalError("Operation is not implemented"))
        }
    }

    private static func json(_ run: AgentRun) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(run.id), "agent": .string(run.agent.rawValue), "name": .string(run.name),
            "cwd": .string(run.cwd), "state": .string(run.state),
            "startedAt": .number(Double(run.startedAt)),
            "attachable": .bool(!(run.attach ?? "").isEmpty)
        ]
        if let last = run.last { object["last"] = .string(last) }
        return .object(object)
    }

    private func json(_ instance: TerminalInstance, startedByCaller: Bool) -> JSONValue {
        let phase: String
        switch instance.session.phase {
        case .starting: phase = "starting"
        case .idle: phase = "idle"
        case .running: phase = "running"
        case .ended: phase = "ended"
        }
        return .object([
            "id": .string(instance.id.uuidString), "directory": .string(instance.session.directory),
            "phase": .string(phase), "pinned": .bool(instance.isPinned),
            "startedByYou": .bool(startedByCaller)
        ])
    }

    private func ask(_ call: AutomationCall) -> AutomationOutcome {
        let text = AutomationText.displaySafe(
            call.arguments["question"]?.stringValue ?? "", limit: 500)
        var choices: [String] = []
        for item in call.arguments["choices"]?.arrayValue ?? [] {
            let choice = AutomationText.displaySafe(item.stringValue ?? "", limit: 60)
            if !choice.isEmpty, !choices.contains(choice) { choices.append(choice) }
        }
        guard !text.isEmpty, !choices.isEmpty else {
            return .toolError("A question needs text and at least one non-empty choice.")
        }
        let lifetime = call.arguments["ttl_seconds"]?.intValue.map(TimeInterval.init)
        guard
            let question = questions.ask(
                client: call.caller, text: text, choices: choices,
                lifetime: lifetime ?? AutomationQuestionStore.defaultLifetime)
        else { return .toolError("Too many open questions; wait for some to be answered.") }
        return .value(
            .object([
                "id": .string(question.id.uuidString),
                "expiresAt": .string(question.expiresAt.formatted(.iso8601))
            ]))
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

    private nonisolated static func resolveDirectory(_ requested: String?) -> Result<String, PrepareFailure> {
        guard let requested, !requested.isEmpty else {
            return .success(FileManager.default.homeDirectoryForCurrentUser.path)
        }
        let path = (requested as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"),
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return .failure(PrepareFailure("The folder does not exist: \(requested)")) }
        return .success(URL(filePath: path).standardizedFileURL.path)
    }
}
