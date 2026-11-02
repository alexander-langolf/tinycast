import Foundation

enum ForkCallCLI {
    struct Options: Sendable {
        let tool: String
        let arguments: Data
        let channel: String
        let client: String?
    }

    enum Failure: Error, LocalizedError {
        case message(String)

        var errorDescription: String? {
            if case .message(let text) = self { return text }
            return nil
        }
    }

    static func parse(
        _ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultChannel: String
    ) throws -> Options {
        guard arguments.first == "call", arguments.count >= 2,
            !arguments[1].isEmpty, !arguments[1].hasPrefix("--")
        else { throw Failure.message("usage: tinycast call <tool> [--args <json>] [--channel dev|stable|beta] [--client <id>]") }
        var channel = environment["TINYCAST_CHANNEL"].flatMap { ["dev", "stable", "beta"].contains($0) ? $0 : nil }
            ?? defaultChannel
        var client = environment["TINYCAST_CLIENT"]
        var data = Data("{}".utf8)
        var seen = Set<String>()
        var iterator = arguments.dropFirst(2).makeIterator()
        while let option = iterator.next() {
            guard ["--args", "--channel", "--client"].contains(option) else {
                throw Failure.message("Unknown call option.")
            }
            guard seen.insert(option).inserted else { throw Failure.message("Duplicate call option.") }
            guard let value = iterator.next(), !value.isEmpty else {
                throw Failure.message("\(option) needs a value.")
            }
            switch option {
            case "--args":
                data = Data(value.utf8)
                guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                    throw Failure.message("--args must be a JSON object.")
                }
            case "--channel":
                guard ["dev", "stable", "beta"].contains(value) else {
                    throw Failure.message("--channel must be dev, stable or beta.")
                }
                channel = value
            default:
                guard !value.hasPrefix("--") else { throw Failure.message("--client needs a value.") }
                client = value
            }
        }
        return Options(tool: arguments[1], arguments: data, channel: channel, client: client)
    }

    #if TINYCAST_DIAGNOSTICS_CLI
    static func run(arguments: [String]) async -> Bool {
        guard arguments.first == "call" else { return false }
        do {
            let options = try parse(arguments, defaultChannel: Channel.defaultChannel.rawValue)
            guard let channel = Channel(rawValue: options.channel) else { fail("Invalid channel.") }
            let token = Credentials.token(service: "\(channel.bundleIdentifier).automation-clients", client: options.client)
            let bridge = Bridge(port: channel.port, token: token, appName: channel.appName)
            let data = try await bridge.call(tool: options.tool, arguments: options.arguments)
            print(String(decoding: data, as: UTF8.self))
        } catch { fail(error.localizedDescription) }
        return true
    }

    static func call(
        endpoint: URL, token: String, session: URLSession, tool: String, arguments: Data
    ) async throws -> Data {
        let values = try JSONSerialization.jsonObject(with: arguments)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2025-03-26", forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": values]
        ])
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw URLError(.badServerResponse) }
        if let error = object["error"] as? [String: Any] {
            throw Failure.message(error["message"] as? String ?? "The call failed.")
        }
        guard response.statusCode == 200, let result = object["result"] as? [String: Any] else {
            throw Failure.message("Tinycast answered HTTP \(response.statusCode).")
        }
        let contents = result["content"] as? [[String: Any]]
        if result["isError"] as? Bool == true {
            throw Failure.message(contents?.first?["text"] as? String ?? "The tool failed.")
        }
        if let text = contents?.first?["text"] as? String, let payload = text.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed])) != nil
        { return payload }
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }
    #endif
}
