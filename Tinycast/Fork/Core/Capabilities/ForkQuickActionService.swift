import AppKit

@MainActor
struct ForkQuickActionService {
    struct Result: Sendable {
        let text: String
        let source: ForkSelection.Kind
        let applied: Bool
    }

    let sink: any ForkTextSink
    let read: @MainActor (NSRunningApplication) async throws -> ForkSelection
    let provider: @MainActor (QuickAction) throws -> any AIProvider
    let instruction: @MainActor (QuickAction) -> String?
    let targetLanguage: Locale.Language

    func run(
        action: QuickAction, target: NSRunningApplication, apply: Bool,
        instructionOverride: String? = nil
    ) async throws -> Result {
        try Task.checkCancellation()
        guard !target.isTerminated else { throw QuickActionFailure.noTarget }
        let selection = try await read(target)
        try Task.checkCancellation()
        let accepted = try QuickActionRunner.accepted(selection.text)
        let output: String
        if action.usesTranslationFramework {
            output = try await ForkTrace.step(.modelRequest, category: .quickActions) {
                try await TextTranslator.translate(accepted, to: targetLanguage)
            }
        } else {
            output = try await QuickActionRunner.run(
                action, selection: accepted, using: try provider(action),
                instructionOverride: instructionOverride ?? instruction(action))
        }
        try Task.checkCancellation()
        guard !target.isTerminated else { throw QuickActionFailure.noTarget }
        let applied = apply ? await sink.replaceSelection(in: target, with: output) : false
        try Task.checkCancellation()
        return Result(text: output, source: selection.source, applied: applied)
    }
}
