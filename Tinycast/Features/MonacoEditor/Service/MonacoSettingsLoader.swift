import Foundation

enum MonacoSettingsLoader {
    @concurrent
    static func load(directory: URL) async -> Result<MonacoSettings.Profile, MonacoSettings.Failure> {
        load(directory: directory, read: { try Data(contentsOf: $0) })
    }

    static func load(
        directory: URL, read: (URL) throws -> Data
    ) -> Result<MonacoSettings.Profile, MonacoSettings.Failure> {
        do {
            let settingsURL = directory.appending(path: "editor/monaco.json")
            let settings = try MonacoSettings.parse(read(settingsURL))
            let theme = try MonacoTheme.parse(read(settings.themeURL(relativeTo: settingsURL)))
            return .success(MonacoSettings.Profile(settings: settings, theme: theme))
        } catch let failure as MonacoSettings.Failure {
            return .failure(failure)
        } catch {
            return .failure(.unreadable)
        }
    }
}
