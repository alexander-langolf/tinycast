#if TINYCAST_DIAGNOSTICS_CLI
import Foundation

enum ForkDiagnosticsCLI {
    struct Options {
        var channel = Channel(rawValue: ProcessInfo.processInfo.environment["TINYCAST_CHANNEL"] ?? "")
            ?? Channel.defaultChannel
        var client = ProcessInfo.processInfo.environment["TINYCAST_CLIENT"]
        var follow = false
        var json = false
        var repair = false
        var filter = ForkLogFilter()
    }

    static func run(arguments: [String]) async -> Bool {
        guard let command = arguments.first, command == "health" || command == "logs" else { return false }
        let options = parse(Array(arguments.dropFirst()), command: command)
        do {
            if command == "logs" {
                try await logs(options)
            } else {
                let token = Credentials.token(
                    service: "\(options.channel.bundleIdentifier).automation-clients", client: options.client)
                let bridge = Bridge(port: options.channel.port, token: token, appName: options.channel.appName)
                let data = try await bridge.diagnostics(repair: options.repair)
                if options.json { print(String(decoding: data, as: UTF8.self)) }
                else { try table(data) }
            }
        } catch { fail(error.localizedDescription) }
        return true
    }

    private static func parse(_ arguments: [String], command: String) -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()
        func value(_ argument: String) -> String {
            guard let value = iterator.next() else { fail("\(argument) needs a value") }
            return value
        }
        while let argument = iterator.next() {
            switch argument {
            case "--channel":
                guard let channel = Channel(rawValue: value(argument)) else {
                    fail("--channel must be dev, stable or beta")
                }
                options.channel = channel
            case "--client" where command == "health": options.client = value(argument)
            case "--json" where command == "health": options.json = true
            case "--repair" where command == "health": options.repair = true
            case "--follow" where command == "logs": options.follow = true
            case "--id" where command == "logs":
                guard let id = UUID(uuidString: value(argument)) else { fail("--id needs a correlation UUID") }
                options.filter.correlationID = id
            case "--op" where command == "logs":
                guard let operation = ForkEvent.Operation(rawValue: value(argument)) else {
                    fail("--op needs a known operation name")
                }
                options.filter.operation = operation
            case "--level" where command == "logs":
                guard let level = ForkEvent.Level(rawValue: value(argument)) else {
                    fail("--level must be debug, info, warning or error")
                }
                options.filter.level = level
            case "--since" where command == "logs":
                guard let minutes = Double(value(argument)), minutes.isFinite, minutes >= 0,
                    minutes <= 5_256_000
                else { fail("--since needs a non-negative number of minutes (at most ten years)") }
                options.filter.since = Date().addingTimeInterval(-minutes * 60)
            default: fail("unknown \(command) option \(argument)")
            }
        }
        return options
    }

    private static func logs(_ options: Options) async throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: options.channel.bundleIdentifier).appending(path: "Diagnostics")
        var reader = ForkLogReader(directory: directory, filter: options.filter)
        repeat {
            for line in try reader.read() { print(line) }
            guard options.follow else { return }
            try await Task.sleep(for: .milliseconds(250))
        } while !Task.isCancelled
    }

    static func health(endpoint: URL, token: String, session: URLSession, repair: Bool) async throws -> Data {
        let params: [String: Any] = repair
            ? ["name": "health_repair", "arguments": [String: String]()]
            : ["uri": "tinycast://health"]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2025-03-26", forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1,
            "method": repair ? "tools/call" : "resources/read", "params": params
        ])
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw URLError(.badServerResponse) }
        if let error = object["error"] as? [String: Any] {
            throw NSError(domain: "TinycastHealth", code: error["code"] as? Int ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: error["message"] as? String ?? "Health request failed."])
        }
        guard let result = object["result"] as? [String: Any], result["isError"] as? Bool != true,
            let contents = result[repair ? "content" : "contents"] as? [[String: Any]],
            let text = contents.first?["text"] as? String, let payload = text.data(using: .utf8),
            (try JSONSerialization.jsonObject(with: payload)) is [String: Any]
        else { throw URLError(.cannotParseResponse) }
        return payload
    }

    private static func table(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        print("APP\tSTATE\tRELAUNCHES\tLAST LAUNCH")
        for app in object["apps"] as? [[String: Any]] ?? [] {
            let columns = [
                app["displayName"] as? String ?? "?", app["state"] as? String ?? "?",
                String(app["relaunchCount"] as? Int ?? 0), app["lastLaunchTime"] as? String ?? "—"
            ]
            print(columns.joined(separator: "\t"))
        }
        print("PROCESS\tSTATE\tOWNERSHIP\tPID")
        for process in object["processes"] as? [[String: Any]] ?? [] {
            print([process["displayName"] as? String ?? "?", process["state"] as? String ?? "?",
                   process["ownership"] as? String ?? "?", (process["pid"] as? Int).map(String.init) ?? "—"].joined(separator: "\t"))
        }
        let secure = object["secureEventInput"] as? [String: Any] ?? [:]
        let enabled = secure["enabled"] as? Bool == true
        let owner = (secure["ownerPID"] as? Int).map(String.init) ?? "unknown"
        print("Secure Event Input: \(enabled ? "on" : "off"); owner PID: \(owner)")
        print("Accessibility: \(object["accessibility"] as? Bool == true ? "granted" : "not granted")")
    }
}
#endif
