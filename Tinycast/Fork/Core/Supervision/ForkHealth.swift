import Carbon.HIToolbox
import Foundation

enum ForkHealth {
    static let resource = AutomationOperation(
        kind: .resource, name: "tinycast://health", title: "Health",
        summary: "Companion app supervision, Secure Event Input, and Accessibility permission.",
        scope: .contextRead, linkHost: nil, needsApproval: false, inputSchema: nil,
        mimeType: "application/json")
    static let repair = AutomationOperation(
        kind: .tool, name: "health_repair", title: "Repair companion app supervision",
        summary: "Reset the companion app relaunch limit and check readiness.",
        scope: .contextRead, linkHost: nil, needsApproval: false,
        inputSchema: .object([
            "type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)
        ]), mimeType: "application/json")
    static let operations = [resource, repair]

    @MainActor
    static func json(
        apps: [ForkAppSupervisor.Snapshot], processes: [ForkProcessSupervisor.Snapshot] = [],
        secureInputOwner: Int?, accessibility: Bool, workflowActionCount: Int? = nil
    ) -> JSONValue {
        .object([
            "apps": .array(apps.map { app in
                .object([
                    "bundleID": .string(app.bundleID), "displayName": .string(app.displayName),
                    "state": .string(app.state.rawValue),
                    "lastLaunchTime": app.lastLaunchTime.map { .string($0.formatted(.iso8601)) } ?? .null,
                    "relaunchCount": .number(Double(app.relaunchCount))
                ])
            }),
            "processes": .array(processes.map { process in
                .object(["displayName": .string(process.name), "state": .string(process.state.rawValue),
                         "ownership": .string(process.ownership.rawValue),
                         "actionCount": process.name == "workflow-server"
                            ? workflowActionCount.map { .number(Double($0)) } ?? .null : .null,
                         "pid": process.pid.map { .number(Double($0)) } ?? .null])
            }),
            "secureEventInput": .object([
                "enabled": .bool(IsSecureEventInputEnabled()),
                "ownerPID": secureInputOwner.map { .number(Double($0)) } ?? .null
            ]),
            "accessibility": .bool(accessibility)
        ])
    }

    @concurrent
    static func secureInputOwner() async -> Int? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/ioreg")
        process.arguments = ["-l", "-w", "0", "-d", "1"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard let exit = try? process.runObservingExit() else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        exit.wait()
        guard process.terminationStatus == 0,
            let text = String(data: data, encoding: .utf8),
            let regex = try? NSRegularExpression(pattern: "\"kCGSSessionSecureInputPID\"\\s*=\\s*(\\d+)"),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text), let pid = Int(text[range]), pid > 0
        else { return nil }
        return pid
    }
}
