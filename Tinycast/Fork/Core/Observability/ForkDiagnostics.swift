import Foundation

@MainActor
final class ForkDiagnostics {
    private var mirror: ForkJSONLMirror?

    func start() {
        let mirror = ForkJSONLMirror(directory: AppPaths.applicationSupport().appending(path: "Diagnostics"))
        self.mirror = mirror
        ForkLog.install(mirror)
    }

    func stop() {
        ForkLog.install(nil)
        mirror = nil
    }
}
