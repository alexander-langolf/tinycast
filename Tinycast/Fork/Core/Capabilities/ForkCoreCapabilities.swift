import AppKit

@MainActor
enum ForkCoreCapabilities {
    static func perform(_ call: AutomationCall, core: AppCore) async -> AutomationOutcome {
        do {
            let arguments = call.operation.name == ForkSelectionOperations.quickActionRun.name
                ? try ForkQuickActionArguments(arguments: call.arguments) : nil
            let target = try target(core: core)
            if let arguments {
                guard core.settings.quickActionsEnabled else {
                    return .toolError("Quick Actions are disabled.")
                }
                let language = core.quickActionSettings.settings.targetLanguage
                let service = ForkQuickActionService(
                    sink: ForkTextInjectorSink(injector: core.textInjector),
                    read: { try await read(from: $0, core: core) },
                    provider: { try core.quickActionProvider(for: $0) },
                    instruction: { core.quickActionSettings.settings.instructionOverride(for: $0) },
                    targetLanguage: language.isEmpty ? Locale.current.language : Locale.Language(identifier: language))
                let result = try await service.run(
                    action: .builtIn(arguments.action), target: target, apply: arguments.apply,
                    instructionOverride: arguments.instruction)
                return .value(.object([
                    "text": .string(result.text), "source": .string(result.source.rawValue),
                    "applied": .bool(result.applied)
                ]))
            }
            let result = try await read(from: target, core: core)
            return .value(.object([
                "text": .string(result.text), "source": .string(result.source.rawValue),
                "bundleID": .string(target.bundleIdentifier ?? "")
            ]))
        } catch is CancellationError {
            return .toolError("Cancelled.")
        } catch let error as ForkQuickActionArguments.Failure {
            return .toolError(error.description)
        } catch let error as QuickActionFailure {
            return .toolError(error.localizedDescription)
        } catch {
            return .toolError("The Quick Action could not be completed.")
        }
    }

    private static func target(core: AppCore) throws -> NSRunningApplication {
        let current = NSRunningApplication.current
        let frontmost = NSWorkspace.shared.frontmostApplication
        let target = frontmost?.processIdentifier == current.processIdentifier
            ? core.paletteCoordinator.targetApp : frontmost
        guard let target, !target.isTerminated, target.processIdentifier != current.processIdentifier,
            target.bundleIdentifier != Bundle.main.bundleIdentifier
        else { throw QuickActionFailure.noTarget }
        return target
    }

    private static func read(from target: NSRunningApplication, core: AppCore) async throws -> ForkSelection {
        try Task.checkCancellation()
        guard Permissions.ensureAccessibility() else { throw QuickActionFailure.needsAccessibility }
        let result = await ForkSelectionAdapters.read(from: target) { app in
            if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette() }
            return await core.textInjector.copySelection(from: app)
        }
        try Task.checkCancellation()
        guard let selection = result.selection else {
            throw result.accessibilityWasEmpty
                ? QuickActionFailure.noSelection : .unreadableApp(target.localizedName)
        }
        return selection
    }
}
