import Observation
import Synchronization

/// The live tokens for any isolation, observed by hand: `InterfaceMetrics` reads them off-main.
nonisolated final class ForkThemeState: Observable, Sendable {
    static let shared = ForkThemeState()

    private let registrar = ObservationRegistrar()
    private let storage = Mutex(ForkTheme())

    private init() {}

    var theme: ForkTheme {
        get {
            registrar.access(self, keyPath: \.theme)
            return storage.withLock { $0 }
        }
        set {
            registrar.withMutation(of: self, keyPath: \.theme) {
                storage.withLock { $0 = newValue }
            }
        }
    }
}
