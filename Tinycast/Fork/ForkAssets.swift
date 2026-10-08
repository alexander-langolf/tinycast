import SwiftUI
import Synchronization

nonisolated struct ForkAssets {
    private static let overrides = Mutex<[String: String]>([:])

    var names: [String: String] = [:]

    func publish() {
        Self.overrides.withLock { $0 = names }
    }

    nonisolated static func name(_ name: String) -> String {
        let candidate = overrides.withLock { $0[name] } ?? "Fork/\(name)"
        return NSImage(named: candidate) == nil ? name : candidate
    }

    nonisolated static func image(named name: String) -> NSImage? {
        NSImage(named: Self.name(name))
    }
}
