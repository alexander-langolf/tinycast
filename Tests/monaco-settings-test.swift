import Foundation
import JavaScriptCore

@main
struct MonacoSettingsTest {
    nonisolated(unsafe) static var failures = 0
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static func check(_ description: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL")  \(description)")
        if !condition { failures += 1 }
    }

    static func main() {
        do {
            let profile = try shippedSettings()
            try fallbackAndReload(profile)
            try pageMapping(profile)
        } catch {
            check("harness setup: \(error)", false)
        }
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func shippedSettings() throws -> MonacoSettings.Profile {
        let directory = root.appending(path: "server")
        var reads: [URL] = []
        let profile = try MonacoSettingsLoader.load(directory: directory) { url in
            reads.append(url)
            return try Data(contentsOf: url)
        }.get()
        let settings = profile.settings
        check("shipped font", settings.fontFamily == "Geist Mono" && settings.fontSize == 16)
        check("shipped line height multiplier", settings.lineHeight == 1.7)
        check("shipped minimap and wrap", !settings.minimap && settings.wordWrap == .on)
        check("theme path resolves relative to settings", reads == [
            directory.appending(path: "editor/monaco.json"),
            directory.appending(path: "editor/themes/monokai-pro-filter-spectrum.json")
        ])
        check("shipped theme decoded", profile.theme.type == .dark && !profile.theme.tokenColors.isEmpty)
        return profile
    }

    static func fallbackAndReload(_ profile: MonacoSettings.Profile) throws {
        let directory = URL(filePath: "/injected/server")
        let themeData = try JSONEncoder().encode(profile.theme)
        let original = try JSONEncoder().encode(profile.settings)
        func load(_ settings: Data, theme: Data? = nil) -> Result<MonacoSettings.Profile, MonacoSettings.Failure> {
            MonacoSettingsLoader.load(directory: directory) { url in
                url.lastPathComponent == "monaco.json" ? settings : theme ?? themeData
            }
        }
        let missing = MonacoSettingsLoader.load(directory: directory) { _ in
            throw CocoaError(.fileReadNoSuchFile)
        }
        if case .failure(.unreadable) = missing { check("missing file falls back", true) }
        else { check("missing file falls back", false) }
        if case .failure(.invalidJSON) = load(Data("{".utf8)) { check("malformed file falls back", true) }
        else { check("malformed file falls back", false) }
        if case .failure(.invalidJSON) = load(original, theme: Data("[]".utf8)) {
            check("malformed theme falls back", true)
        } else { check("malformed theme falls back", false) }
        let missingTheme = MonacoSettingsLoader.load(directory: directory) { url in
            guard url.lastPathComponent == "monaco.json" else { throw CocoaError(.fileReadNoSuchFile) }
            return original
        }
        if case .failure(.unreadable) = missingTheme { check("missing theme falls back", true) }
        else { check("missing theme falls back", false) }
        var edited = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        edited["fontSize"] = -1
        if case .failure(.invalidValue) = load(try JSONSerialization.data(withJSONObject: edited)) {
            check("invalid font size falls back", true)
        } else { check("invalid font size falls back", false) }
        edited["fontSize"] = 19
        edited["wordWrap"] = "bounded"
        var content = original
        var reads = 0
        func reopen() throws -> MonacoSettings.Profile {
            try MonacoSettingsLoader.load(directory: directory) { url in
                reads += 1
                return url.lastPathComponent == "monaco.json" ? content : themeData
            }.get()
        }
        let first = try reopen()
        content = try JSONSerialization.data(withJSONObject: edited)
        let second = try reopen()
        check("reopen reads changed settings and theme", reads == 4 && first.settings.fontSize == 16
            && second.settings.fontSize == 19 && second.settings.wordWrap == .bounded)
        var options = MonacoEditorOptions(
            text: "buffer", language: "plaintext", isDark: false, fontFamily: "Tinycast Mono", fontSize: 13)
        let failure = options.apply(profile, fontAvailable: { _ in false })
        if case .missingFont? = failure { check("missing font rejected", true) }
        else { check("missing font rejected", false) }
        let fallback = try options.pageOptions()
        check("fallback uses app light theme and Tinycast font", fallback["theme"] as? String == "vs"
            && fallback["fontFamily"] as? String == "Tinycast Mono" && fallback["fontSize"] as? Double == 13
            && fallback["projectTheme"] == nil)
        check("fallback keeps editor defaults", fallback["minimap"] as? Bool == true
            && fallback["wordWrap"] as? String == "off" && fallback["lineHeight"] as? Double == 0)
        options.isDark = true
        check("fallback uses app dark theme", try options.pageOptions()["theme"] as? String == "vs-dark")
    }

    static func pageMapping(_ profile: MonacoSettings.Profile) throws {
        var options = MonacoEditorOptions(
            text: "buffer", language: "swift", isDark: false, fontFamily: "Tinycast Mono", fontSize: 13)
        check("available font accepted", options.apply(profile, fontAvailable: { $0 == "Geist Mono" }) == nil)
        let mapped = try options.pageOptions()
        check("mapper applies font and size", mapped["fontFamily"] as? String == "\"Geist Mono\", Tinycast Mono"
            && mapped["fontSize"] as? Double == 16)
        check("mapper applies layout options", mapped["lineHeight"] as? Double == 1.7
            && mapped["minimap"] as? Bool == false && mapped["wordWrap"] as? String == "on")
        guard let context = JSContext() else { check("JavaScriptCore available", false); return }
        context.evaluateScript("""
            var selectedTheme, definedTheme, createdOptions;
            var window = { webkit: { messageHandlers: { tinycast: { postMessage() {} } } } };
            var document = { getElementById() { return {}; } };
            function createTokenizationSupport() { return {}; }
            var monaco = {
              languages: { register() {}, setTokensProvider() {} }, KeyCode: { Escape: 9 },
              editor: {
                defineTheme(name, theme) { definedTheme = theme; },
                setTheme(theme) { selectedTheme = theme; },
                create(element, options) {
                  createdOptions = options;
                  return {
                    getModel() { return { getAlternativeVersionId() { return 1; } }; },
                    onDidChangeModelContent() {}, addCommand() {}, focus() {}, dispose() {}, updateOptions() {}
                  };
                }
              }
            };
            """)
        let source = try String(contentsOf: root.appending(path: "Scripts/monaco-bundle/src/main.js"), encoding: .utf8)
        let page = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("import ") }.joined(separator: "\n")
        context.evaluateScript(page)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: mapped), as: UTF8.self)
        context.evaluateScript("window.tinycastEditor.open(\(json)); window.tinycastEditor.setTheme('vs');")
        check("page executes without exception", context.exception == nil)
        check("custom theme survives appearance change", context.evaluateScript(
            "selectedTheme === 'tinycast-project' && createdOptions.theme === 'tinycast-project'")?.toBool() == true)
        check("page passes layout options to Monaco", context.evaluateScript(
            "createdOptions.minimap.enabled === false && createdOptions.wordWrap === 'on' && createdOptions.lineHeight === 1.7")?.toBool() == true)
        context.evaluateScript("""
            var converted = convertTheme({
              type: 'light', colors: { 'editor.background': '#12345678', 'editor.foreground': '#abcdef' },
              tokenColors: [
                { scope: ['comment', 'keyword, string'], settings: { foreground: '#aabbcc80', fontStyle: 'italic bold' } },
                { scope: 'markup.bold', settings: { fontStyle: '' } },
                { settings: { foreground: '#112233' } }
              ]
            });
            """)
        check("light type maps to vs", context.evaluateScript("converted.base === 'vs' && converted.inherit")?.toBool() == true)
        check("dark type maps to vs-dark", context.evaluateScript("definedTheme.base === 'vs-dark'")?.toBool() == true)
        check("editor colors retain hash and alpha", context.evaluateScript(
            "converted.colors['editor.background'] === '#12345678' && converted.colors['editor.foreground'] === '#abcdef'")?.toBool() == true)
        check("scope arrays and comma lists produce individual rules", context.evaluateScript(
            "converted.rules.map(r => r.token).join('|') === 'comment|keyword|string|markup.bold|'")?.toBool() == true)
        check("token colors drop hash and retain alpha and fontStyle", context.evaluateScript(
            "converted.rules.slice(0, 3).every(r => r.foreground === 'aabbcc80' && r.fontStyle === 'italic bold')")?.toBool() == true)
        check("style-only rules preserve explicit reset", context.evaluateScript(
            "converted.rules[3].fontStyle === '' && !('foreground' in converted.rules[3])")?.toBool() == true)
        context.evaluateScript("window.tinycastEditor.open({text:'', language:'plaintext', theme:'vs', minimap:true, wordWrap:'off'}); window.tinycastEditor.setTheme('vs-dark');")
        check("fallback clears previous custom theme", context.evaluateScript(
            "createdOptions.theme === 'vs' && selectedTheme === 'vs-dark'")?.toBool() == true)
        check("page checks finish without exception", context.exception == nil)
    }
}
