import Foundation

@MainActor
final class ForkTargetHandleStore<Target> {
    private struct Entry {
        let target: Target
        let owner: UUID
        let expires: Date
    }

    private let now: () -> Date
    private var entries: [String: Entry] = [:]

    init(now: @escaping () -> Date = { Date() }) { self.now = now }

    func insert(_ target: Target, owner: UUID) -> String {
        entries = entries.filter { $0.value.expires > now() }
        if entries.count >= 128, let oldest = entries.min(by: { $0.value.expires < $1.value.expires }) {
            entries[oldest.key] = nil
        }
        let id = UUID().uuidString
        entries[id] = Entry(target: target, owner: owner, expires: now().addingTimeInterval(120))
        return id
    }

    func resolve(_ id: String, owner: UUID, isCurrent: (Target) -> Bool) -> Target? {
        guard let entry = entries[id], entry.owner == owner, entry.expires > now(),
            isCurrent(entry.target) else { return nil }
        return entry.target
    }

    func remove(_ id: String) { entries[id] = nil }
    func removeAll() { entries.removeAll() }
}
