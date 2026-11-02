import Foundation

enum ForkWorkflowRoute {
    static func validName(_ name: String) -> Bool {
        guard (1...64).contains(name.utf8.count), let first = name.utf8.first,
            (97...122).contains(first) else { return false }
        return name.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }

    static func action(_ url: URL, scheme: String?) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let suppliedScheme = parts.scheme, suppliedScheme == "tinycast" || suppliedScheme == scheme,
            parts.host == "run", parts.user == nil, parts.password == nil, parts.port == nil,
            parts.query == nil, parts.fragment == nil, parts.percentEncodedPath == parts.path,
            parts.path.hasPrefix("/") else { return nil }
        let name = String(parts.path.dropFirst())
        return validName(name) ? name : nil
    }

    static func permits(_ name: String, catalog: JSONValue) -> Bool {
        validName(name) && catalog.objectValue?["actions"]?.arrayValue?.contains {
            $0.objectValue?["name"]?.stringValue == name && $0.objectValue?["linkSafe"]?.boolValue == true
        } == true
    }
}
