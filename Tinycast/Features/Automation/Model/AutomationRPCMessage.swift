import Foundation

enum AutomationRPCMessage {
    static func result(id: AutomationRPCID, _ result: JSONValue) -> Data {
        encode(["jsonrpc": .string("2.0"), "id": id.json, "result": result])
    }

    static func error(id: AutomationRPCID?, _ error: AutomationRPCError) -> Data {
        var body: [String: JSONValue] = [
            "code": .number(Double(error.code)), "message": .string(error.message)
        ]
        if let data = error.data { body["data"] = data }
        var message: [String: JSONValue] = ["jsonrpc": .string("2.0"), "error": .object(body)]
        if let id { message["id"] = id.json }
        return encode(message)
    }

    static func notification(method: String, params: JSONValue) -> Data {
        encode(["jsonrpc": .string("2.0"), "method": .string(method), "params": params])
    }

    static func encode(_ object: [String: JSONValue]) -> Data {
        let value = JSONValue.object(object).jsonObject
        return (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()
    }
}
