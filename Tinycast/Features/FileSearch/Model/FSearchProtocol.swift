import Foundation

struct FSearchHit: Sendable, Equatable {
    let path: String
    let isDirectory: Bool
}

/// One line of the `fsearch stdio` conversation; ids pair a reply with the request that asked.
enum FSearchProtocol {
    enum Response: Sendable, Equatable {
        case hits(id: Int, [FSearchHit])
        case failure(id: Int?, message: String)
    }

    static func requestLine(id: Int, query: String, limit: Int) -> Data? {
        struct Request: Encodable {
            let id: Int
            let q: String
            let limit: Int
        }
        guard var data = try? JSONEncoder().encode(Request(id: id, q: query, limit: limit)) else {
            return nil
        }
        data.append(0x0A)
        return data
    }

    /// A line that is not a reply is `nil`, so one bad line fails nothing but itself.
    static func decode(_ line: Data) -> Response? {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: line) else { return nil }
        guard reply.ok else { return .failure(id: reply.id, message: reply.error ?? "rejected") }
        guard let id = reply.id else { return nil }
        let hits = (reply.hits ?? []).map { FSearchHit(path: $0.path, isDirectory: $0.kind == "dir") }
        return .hits(id: id, hits)
    }
}

private struct Reply: Decodable {
    struct Hit: Decodable {
        let path: String
        let kind: String
    }
    let id: Int?
    let ok: Bool
    let error: String?
    let hits: [Hit]?
}
