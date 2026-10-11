import AppKit

enum FileNavigatorActionsAdapter {
    @concurrent
    static func validate(_ targets: [FileSearchResult], folder: String) async throws -> Set<String> {
        let manager = FileManager.default
        var missing: Set<String> = []
        for target in targets {
            try Task.checkCancellation()
            if !manager.fileExists(atPath: target.id) { missing.insert(target.id) }
        }
        try Task.checkCancellation()
        var directory: ObjCBool = false
        if !manager.fileExists(atPath: folder, isDirectory: &directory) || !directory.boolValue {
            missing.insert(folder)
        }
        return missing
    }

    @MainActor
    static func open(_ targets: [FileSearchResult], core: AppCore) async throws {
        if targets.count == 1, let target = targets.first {
            core.fileSearchCoordinator.open(target)
            return
        }
        var lastApplication: NSRunningApplication?
        for target in targets {
            try Task.checkCancellation()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            lastApplication = try await NSWorkspace.shared.open(target.url, configuration: configuration)
        }
        try Task.checkCancellation()
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        lastApplication?.activate()
    }

    @MainActor
    static func reveal(_ targets: [FileSearchResult], core: AppCore) {
        if targets.count == 1, let target = targets.first {
            core.fileSearchCoordinator.showInFinder(target)
        } else {
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
        }
    }

    @MainActor
    static func copyPaths(_ targets: [FileSearchResult], core: AppCore) {
        if targets.count == 1, let target = targets.first {
            core.fileSearchCoordinator.copyPath(target)
        } else {
            Paster.copyPlainText(targets.map(\.id).joined(separator: "\n"))
            core.showMessage("Copied paths")
        }
    }

    nonisolated static func editorCommand(
        _ files: [FileSearchResult], folder: String, override: String
    ) -> String {
        let editor = override.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = editor.isEmpty ? "${EDITOR:-fresh}" : editor
        let arguments = files.map { file in
            let relative = FileNavigatorPath.relative(file.id, to: folder)
            return FileNavigatorPath.quote(relative.hasPrefix("-") ? "./" + relative : relative)
        }
        return executable + " " + arguments.joined(separator: " ")
    }
}
