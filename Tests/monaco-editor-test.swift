// Pins the Monaco editor's pure rules: language map, kind fallback, text limits and page messages.
import Foundation

@main
struct MonacoEditorTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)  \(detail())"); failures += 1
        }
    }

    static func main() {
        languages()
        kind()
        document()
        messages()
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func languages() {
        check("swift extension", MonacoLanguageMap.language(forFileName: "main.swift") == "swift")
        check(
            "extension is case-insensitive", MonacoLanguageMap.language(forFileName: "A.TSX") == "typescript")
        check("last extension wins", MonacoLanguageMap.language(forFileName: "a.test.json") == "json")
        check("well-known name", MonacoLanguageMap.language(forFileName: "Dockerfile") == "dockerfile")
        check("dotfile with a name entry", MonacoLanguageMap.language(forFileName: ".zshrc") == "shell")
        check("unknown dotfile is plain", MonacoLanguageMap.language(forFileName: ".unknown") == "plaintext")
        check("no extension is plain", MonacoLanguageMap.language(forFileName: "LICENSE") == "plaintext")
        check("unknown extension is plain", MonacoLanguageMap.language(forFileName: "a.zzz") == "plaintext")
    }

    static func kind() {
        check("terminal raw value", FileNavigatorEditorKind(rawValue: "terminal") == .terminal)
        check("monaco raw value", FileNavigatorEditorKind(rawValue: "monaco") == .monaco)
        check("unknown raw value is rejected", FileNavigatorEditorKind(rawValue: "vim") == nil)
        check(
            "absent value falls back to terminal",
            (FileNavigatorEditorKind(rawValue: "") ?? .terminal) == .terminal)
    }

    static func document() {
        check("utf-8 text decodes", decoded("héllo\n") == "héllo\n")
        check("empty file decodes", decoded("") == "")
        check("nul byte is not text", Self.failure(Data([0x61, 0x00, 0x62])) == .notText)
        check("invalid utf-8 is not text", Self.failure(Data([0xFF, 0xFE, 0x41])) == .notText)
        let big = Data(repeating: 0x61, count: 11)
        check(
            "over the limit is refused", Self.failure(big, limit: 10) == .tooLarge(bytes: 11, limit: 10))
        check(
            "at the limit is accepted",
            {
                if case .success = MonacoDocument.decode(Data(repeating: 0x61, count: 10), limit: 10) {
                    true
                } else {
                    false
                }
            }())
        let date = Date(timeIntervalSince1970: 100)
        let document = MonacoDocument(path: "/tmp/a/main.swift", modified: date)
        check("name and language", document.name == "main.swift" && document.language == "swift")
        check("unchanged date is not an external change", !document.changedOnDisk(modified: date))
        check("moved date is an external change", document.changedOnDisk(modified: date + 1))
        check("missing file is an external change", document.changedOnDisk(modified: nil))
    }

    static func messages() {
        check("ready", MonacoBridgeMessage(body: ["type": "ready"]) == .ready)
        check("save", MonacoBridgeMessage(body: ["type": "save"]) == .save)
        check("close", MonacoBridgeMessage(body: ["type": "close"]) == .close)
        check("dirty true", MonacoBridgeMessage(body: ["type": "dirty", "dirty": true]) == .dirty(true))
        check("dirty without flag is dropped", MonacoBridgeMessage(body: ["type": "dirty"]) == nil)
        check(
            "dirty with wrong type is dropped",
            MonacoBridgeMessage(body: ["type": "dirty", "dirty": "yes"]) == nil)
        check("unknown type is dropped", MonacoBridgeMessage(body: ["type": "eval"]) == nil)
        check("non-object is dropped", MonacoBridgeMessage(body: "save") == nil)
        check("missing type is dropped", MonacoBridgeMessage(body: ["dirty": true]) == nil)
    }

    static func decoded(_ text: String) -> String? {
        if case .success(let value) = MonacoDocument.decode(Data(text.utf8)) { value } else { nil }
    }

    static func failure(_ data: Data, limit: Int = MonacoDocument.sizeLimit) -> MonacoDocument.Failure? {
        if case .failure(let failure) = MonacoDocument.decode(data, limit: limit) { failure } else { nil }
    }
}
