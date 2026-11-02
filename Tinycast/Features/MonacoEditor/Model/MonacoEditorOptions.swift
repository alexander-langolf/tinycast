import Foundation

struct MonacoEditorOptions: Sendable {
    var text: String
    var language: String
    var isDark: Bool
    var fontFamily: String
    var fontSize: Double
    var project: MonacoSettings.Profile?

    mutating func apply(
        _ profile: MonacoSettings.Profile, fontAvailable: (String) -> Bool
    ) -> MonacoSettings.Failure? {
        project = nil
        guard fontAvailable(profile.settings.fontFamily) else { return .missingFont }
        project = profile
        return nil
    }

    func pageOptions() throws -> [String: Any] {
        var options: [String: Any] = [
            "text": text, "language": language, "theme": isDark ? "vs-dark" : "vs",
            "fontFamily": project?.fontFamily(fallback: fontFamily) ?? fontFamily,
            "fontSize": project?.settings.fontSize ?? fontSize,
            "lineHeight": project?.settings.lineHeight ?? 0.0,
            "minimap": project?.settings.minimap ?? true,
            "wordWrap": project?.settings.wordWrap.rawValue ?? "off"
        ]
        if let theme = project?.theme {
            options["projectTheme"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(theme))
        }
        return options
    }
}
