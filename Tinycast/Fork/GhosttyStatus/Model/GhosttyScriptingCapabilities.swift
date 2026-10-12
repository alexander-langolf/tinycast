import Foundation

struct GhosttyScriptingCapabilities: Equatable, Sendable {
    let inventory: Bool
    let agents: Bool

    static func inspect(_ data: Data) -> Self {
        let reader = DictionaryReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else { return Self(inventory: false, agents: false) }
        let required: Set<String> = [
            "application:capp:window", "window:Gwnd:tab", "tab:Gtab:terminal",
            "window:Gwnd:id:ID  ", "tab:Gtab:id:ID  ", "tab:Gtab:name:pnam",
            "tab:Gtab:focused terminal:GTfT", "terminal:Gtrm:id:ID  ",
            "terminal:Gtrm:working directory:Gwdr", "select tab:GhstSlTb",
            "activate window:GhstAcWn"
        ]
        let inventory = required.isSubset(of: reader.entries)
        return Self(
            inventory: inventory,
            agents: inventory
                && reader.entries.contains("terminal:Gtrm:pid:Gpid")
                && reader.entries.contains("terminal:Gtrm:tty:Gtty"))
    }
}

private final class DictionaryReader: NSObject, XMLParserDelegate {
    var entries = Set<String>()
    private var currentClass: String?

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        switch elementName {
        case "class":
            if let name = attributes["name"], let code = attributes["code"] {
                currentClass = "\(name):\(code)"
            }
        case "property":
            if let currentClass, let name = attributes["name"], let code = attributes["code"] {
                entries.insert("\(currentClass):\(name):\(code)")
            }
        case "element":
            if let currentClass, let type = attributes["type"] {
                entries.insert("\(currentClass):\(type)")
            }
        case "command":
            if let name = attributes["name"], let code = attributes["code"] {
                entries.insert("\(name):\(code)")
            }
        default: break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?
    ) {
        if elementName == "class" { currentClass = nil }
    }
}
