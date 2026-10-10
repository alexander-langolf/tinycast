import Foundation

/// The small subset of JSON Schema the registry uses: enough to refuse a malformed call before it
/// reaches the runner. Returns a message for the first problem, or nil.
enum AutomationSchemaValidator {
    static func validate(arguments: [String: JSONValue], against schema: JSONValue?) -> String? {
        guard let schema = schema?.objectValue else { return nil }
        let properties = schema["properties"]?.objectValue ?? [:]
        let required = (schema["required"]?.arrayValue ?? []).compactMap(\.stringValue)
        for key in required where arguments[key] == nil { return "Missing argument “\(key)”" }
        for (key, value) in arguments.sorted(by: { $0.key < $1.key }) {
            guard let rule = properties[key] else {
                if schema["additionalProperties"]?.boolValue == false {
                    return "Unknown argument “\(key)”"
                }
                continue
            }
            if let problem = check(value, key: key, rule: rule) { return problem }
        }
        return nil
    }

    private static func check(_ value: JSONValue, key: String, rule: JSONValue) -> String? {
        guard let rule = rule.objectValue, let type = rule["type"]?.stringValue else { return nil }
        switch (type, value) {
        case ("string", .string(let text)):
            if let max = rule["maxLength"]?.intValue, text.count > max {
                return "“\(key)” is longer than \(max) characters"
            }
        case ("integer", .number(let number)):
            guard number == number.rounded() else { return "“\(key)” must be an integer" }
            if let minimum = rule["minimum"]?.intValue, Int(number) < minimum {
                return "“\(key)” must be at least \(minimum)"
            }
            if let maximum = rule["maximum"]?.intValue, Int(number) > maximum {
                return "“\(key)” must be at most \(maximum)"
            }
        case ("array", .array(let items)):
            if let minimum = rule["minItems"]?.intValue, items.count < minimum {
                return "“\(key)” needs at least \(minimum) item(s)"
            }
            if let maximum = rule["maxItems"]?.intValue, items.count > maximum {
                return "“\(key)” takes at most \(maximum) items"
            }
            if let item = rule["items"] {
                for element in items {
                    if let problem = check(element, key: key, rule: item) { return problem }
                }
            }
        case ("boolean", .bool):
            break
        default:
            return "“\(key)” must be a \(type)"
        }
        return nil
    }
}
