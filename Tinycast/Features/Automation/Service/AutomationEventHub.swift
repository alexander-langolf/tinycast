import Foundation

/// Fan-out for resource-updated notifications. A subscription belongs to one client and names the
/// resources it wants; nothing here knows what a resource contains.
@MainActor
final class AutomationEventHub {
    struct Subscription {
        let id: UUID
        let updates: AsyncStream<String>
    }

    private struct Entry {
        let client: UUID
        let uris: Set<String>
        let continuation: AsyncStream<String>.Continuation
    }

    static let maximumPerClient = 4
    private var entries: [UUID: Entry] = [:]

    var hasSubscribers: Bool { !entries.isEmpty }

    func count(for client: UUID) -> Int { entries.values.filter { $0.client == client }.count }

    func subscribe(client: UUID, uris: Set<String>) -> Subscription? {
        guard count(for: client) < Self.maximumPerClient else { return nil }
        let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(32))
        let id = UUID()
        entries[id] = Entry(client: client, uris: uris, continuation: continuation)
        return Subscription(id: id, updates: stream)
    }

    func unsubscribe(_ id: UUID) {
        entries.removeValue(forKey: id)?.continuation.finish()
    }

    /// `client` limits delivery to that client's own subscriptions (its private resources).
    func publish(uri: String, client: UUID? = nil) {
        for entry in entries.values where entry.uris.contains(uri) {
            if let client, entry.client != client { continue }
            entry.continuation.yield(uri)
        }
    }

    /// A revoked client's streams end gracefully.
    func end(client: UUID) {
        for (id, entry) in entries where entry.client == client { unsubscribe(id) }
    }

    func endAll() {
        for id in Array(entries.keys) { unsubscribe(id) }
    }
}
