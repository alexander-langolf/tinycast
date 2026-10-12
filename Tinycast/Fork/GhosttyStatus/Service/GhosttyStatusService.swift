import AppKit
import Carbon
import OSLog
import Synchronization

struct GhosttyApplicationTarget: Sendable {
    let identity: GhosttyApplicationIdentity
    let bundleURL: URL
}

enum GhosttyStatusService {
    private static let bundleID = "com.mitchellh.ghostty"
    private static let preferredApplication = URL(filePath: "/Applications/Ghostty.app")

    @MainActor static func currentTarget() -> GhosttyApplicationTarget? {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
        guard
            let running = applications.first(where: { $0.isActive })
                ?? applications.first(where: { $0.bundleURL == preferredApplication }) ?? applications.first,
            let bundleURL = running.bundleURL,
            let started = GhosttyProcessReader.startedAt(running.processIdentifier)
        else { return nil }
        return .init(
            identity: .init(processID: running.processIdentifier, launchedAt: started), bundleURL: bundleURL)
    }

    static func read(_ target: GhosttyApplicationTarget) async -> GhosttyStatusState {
        await perform(target, fallback: .unavailable) { session in
            do {
                let capabilities = try session.capabilities()
                guard capabilities.inventory else {
                    GhosttyStatusDiagnostics.report("dictionary.inventory", code: 0)
                    return .unavailable
                }
                guard session.hasPermission(ask: false) else { return .permissionRequired }
                let readAt = Date()
                session.phase = "inventory.tabs"
                let tabs = try session.tabs(agents: capabilities.agents)
                session.phase = "process.scan"
                let observations = capabilities.agents ? GhosttyProcessReader.collect(tabs: tabs) : []
                session.phase = "inventory.revalidate"
                if capabilities.agents { try session.revalidate(terminals: tabs) }
                try session.checkValidity()
                let associations = GhosttyAgentDetection.associations(
                    tabs: tabs, processes: observations, readAt: readAt)
                let inventory = GhosttyTabInventory(
                    application: target.identity, tabs: tabs, readAt: readAt,
                    capability: capabilities.agents ? .verifiedProcesses : .tabsOnly,
                    associations: associations)
                return tabs.isEmpty ? .empty : .loaded(inventory)
            } catch GhosttyEventFailure.permission {
                return .permissionRequired
            } catch {
                session.report(error)
                return .unavailable
            }
        }
    }

    static func select(_ identity: GhosttyTabIdentity, target: GhosttyApplicationTarget) async -> Bool {
        guard target.identity == identity.application else { return false }
        return await perform(target, fallback: false) { session in
            do {
                guard try session.capabilities().inventory, session.hasPermission(ask: false) else {
                    return false
                }
                let window = try session.object("Gwnd", id: identity.windowID, container: .null())
                let tab = try session.object("Gtab", id: identity.tabID, container: window)
                guard try session.string("ID  ", of: window) == identity.windowID,
                    try session.string("ID  ", of: tab) == identity.tabID
                else { return false }
                _ = try session.send(eventClass: "Ghst", eventID: "SlTb", direct: tab)
                _ = try session.send(eventClass: "Ghst", eventID: "AcWn", direct: window)
                return true
            } catch { return false }
        }
    }

    static func requestPermission(_ target: GhosttyApplicationTarget) async -> Bool {
        await perform(target, fallback: false) { $0.hasPermission(ask: true) }
    }

    private static func perform<Value: Sendable>(
        _ target: GhosttyApplicationTarget, fallback: Value,
        operation: @escaping @Sendable (GhosttyEventSession) -> Value
    ) async -> Value {
        await GhosttySerializedRequest.run(on: TerminalGhosttyLauncher.scriptQueue, fallback: fallback) {
            cancelled in
            let session = GhosttyEventSession(target: target, cancelled: cancelled)
            do { try session.checkValidity() } catch {
                session.report(error)
                return fallback
            }
            return operation(session)
        }
    }
}

private enum GhosttyEventFailure: Error {
    case unavailable
    case permission
}

final class GhosttyEventSession {
    let target: GhosttyApplicationTarget
    let cancelled: GhosttyRequestCancellation
    private let deadline = ProcessInfo.processInfo.systemUptime + 2
    var phase = "target.validity"

    init(target: GhosttyApplicationTarget, cancelled: GhosttyRequestCancellation) {
        self.target = target
        self.cancelled = cancelled
    }

    func checkValidity() throws {
        guard !cancelled.isCancelled else { throw GhosttyEventFailure.unavailable }
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            GhosttyStatusDiagnostics.report("deadline.\(phase)", code: 0)
            throw GhosttyEventFailure.unavailable
        }
        guard GhosttyProcessReader.startedAt(target.identity.processID) == target.identity.launchedAt else {
            GhosttyStatusDiagnostics.report("target.changed", code: 0)
            throw GhosttyEventFailure.unavailable
        }
    }

    func capabilities() throws -> GhosttyScriptingCapabilities {
        phase = "dictionary.read"
        try checkValidity()
        guard let bundle = Bundle(url: target.bundleURL),
            let name = bundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String,
            let resources = bundle.resourceURL
        else { throw GhosttyEventFailure.unavailable }
        return GhosttyScriptingCapabilities.inspect(try Data(contentsOf: resources.appending(path: name)))
    }

    func hasPermission(ask: Bool) -> Bool {
        phase = "automation.permission"
        guard (try? checkValidity()) != nil else { return false }
        let address = NSAppleEventDescriptor(processIdentifier: target.identity.processID)
        let status = AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, ask)
        if status != noErr { GhosttyStatusDiagnostics.report(phase, code: status) }
        return status == noErr
    }

    func tabs(agents: Bool) throws -> [GhosttyTabSnapshot] {
        var tabs: [GhosttyTabSnapshot] = []
        for window in try all("Gwnd", of: .null()) {
            let windowID = try string("ID  ", of: window)
            for tab in try all("Gtab", of: window) {
                let tabID = try string("ID  ", of: tab)
                var terminals: [GhosttyTerminalSnapshot] = []
                for terminal in try all("Gtrm", of: tab) {
                    terminals.append(
                        .init(
                            id: try string("ID  ", of: terminal),
                            workingDirectory: try? string("Gwdr", of: terminal),
                            foregroundProcessGroup: agents ? try value("Gpid", of: terminal).int32Value : nil,
                            ttyDevice: agents
                                ? GhosttyProcessReader.ttyDevice(try? string("Gtty", of: terminal)) : nil))
                }
                let focused = try? value("GTfT", of: tab)
                tabs.append(
                    .init(
                        id: .init(application: target.identity, windowID: windowID, tabID: tabID),
                        title: try? string("pnam", of: tab), terminals: terminals,
                        focusedTerminalID: focused.flatMap { try? string("ID  ", of: $0) }))
            }
        }
        return tabs
    }

    func revalidate(terminals tabs: [GhosttyTabSnapshot]) throws {
        for tab in tabs {
            let window = try object("Gwnd", id: tab.id.windowID, container: .null())
            let tabObject = try object("Gtab", id: tab.id.tabID, container: window)
            for terminal in tab.terminals {
                let object = try object("Gtrm", id: terminal.id, container: tabObject)
                guard try value("Gpid", of: object).int32Value == terminal.foregroundProcessGroup,
                    GhosttyProcessReader.ttyDevice(try string("Gtty", of: object)) == terminal.ttyDevice
                else { throw GhosttyEventFailure.unavailable }
            }
        }
    }

    func object(
        _ type: String, id: String, container: NSAppleEventDescriptor
    ) throws -> NSAppleEventDescriptor {
        try specifier(
            type: fourCC(type), form: OSType(formUniqueID), data: NSAppleEventDescriptor(string: id),
            container: container)
    }

    private func all(_ type: String, of container: NSAppleEventDescriptor) throws -> [NSAppleEventDescriptor]
    {
        phase = "event.list.\(type)"
        let object = try allSpecifier(type, of: container)
        let result = try send(eventClass: "core", eventID: "getd", direct: object)
        guard result.descriptorType == typeAEList else { throw GhosttyEventFailure.unavailable }
        return (1..<(result.numberOfItems + 1)).compactMap { result.atIndex($0) }
    }

    func allSpecifier(_ type: String, of container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let data = NSAppleEventDescriptor(enumCode: OSType(kAEAll)).data
        guard let ordinal = NSAppleEventDescriptor(descriptorType: DescType(typeAbsoluteOrdinal), data: data)
        else {
            throw GhosttyEventFailure.unavailable
        }
        return try specifier(
            type: fourCC(type), form: OSType(formAbsolutePosition),
            data: ordinal, container: container)
    }

    func string(_ property: String, of object: NSAppleEventDescriptor) throws -> String {
        guard let string = try value(property, of: object).stringValue else {
            throw GhosttyEventFailure.unavailable
        }
        return string
    }

    private func value(_ property: String, of object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor
    {
        phase = "event.property.\(property)"
        let reference = try specifier(
            type: fourCC("prop"), form: OSType(formPropertyID),
            data: NSAppleEventDescriptor(typeCode: fourCC(property)), container: object)
        return try send(eventClass: "core", eventID: "getd", direct: reference)
    }

    func send(
        eventClass: String, eventID: String, direct: NSAppleEventDescriptor
    ) throws -> NSAppleEventDescriptor {
        try checkValidity()
        let event = NSAppleEventDescriptor(
            eventClass: fourCC(eventClass), eventID: fourCC(eventID),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: target.identity.processID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(direct, forKeyword: AEKeyword(keyDirectObject))
        phase = eventClass == "core" ? phase : "event.command.\(eventID)"
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(
                options: [.waitForReply, .neverInteract],
                timeout: max(0.01, deadline - ProcessInfo.processInfo.systemUptime))
        } catch {
            report(error)
            throw error
        }
        let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0
        if error == -1743 { throw GhosttyEventFailure.permission }
        guard error == 0 else {
            GhosttyStatusDiagnostics.report(phase, code: error)
            throw GhosttyEventFailure.unavailable
        }
        try checkValidity()
        return reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) ?? .null()
    }

    private func specifier(
        type: OSType, form: OSType, data: NSAppleEventDescriptor,
        container: NSAppleEventDescriptor
    ) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: type), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        guard let object = record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else {
            throw GhosttyEventFailure.unavailable
        }
        return object
    }

    private func fourCC(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }

    func report(_ error: Error) {
        guard !cancelled.isCancelled else { return }
        let code = (error as NSError).code
        GhosttyStatusDiagnostics.report(phase, code: code)
    }
}

private enum GhosttyStatusDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tinycast.app", category: "GhosttyStatus")
    private static let recent = Mutex<[String: TimeInterval]>([:])

    static func report(_ phase: String, code: Int32) {
        report(phase, code: Int(code))
    }

    static func report(_ phase: String, code: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        let key = "\(phase):\(code)"
        let shouldLog = recent.withLock { history in
            guard now - (history[key] ?? -.infinity) >= 30 else { return false }
            history[key] = now
            return true
        }
        if shouldLog { logger.error("phase=\(phase, privacy: .public) code=\(code, privacy: .public)") }
    }
}
