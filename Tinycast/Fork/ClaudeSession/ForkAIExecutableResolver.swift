import Foundation

enum ForkAIExecutableResolver {
    static func resolve(kind: InstalledAIKind, commandPath: String) async -> URL? {
        switch InstalledAILaunch(commandPath: commandPath).command() {
        case .executable(let url): return url
        case .missing: return nil
        case .automatic:
            return await ExecutableLocator.locate(
                kind.command, extraHomePaths: kind.extraExecutablePaths)
        }
    }
}
