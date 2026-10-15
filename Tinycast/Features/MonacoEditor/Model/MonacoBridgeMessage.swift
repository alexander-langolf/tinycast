import Foundation

/// The closed set of messages the editor page may send; anything else is dropped.
enum MonacoBridgeMessage: Equatable, Sendable {
    case ready
    case dirty(Bool)
    case save
    case close

    /// `body` is the untyped object WebKit hands over; only the documented shapes decode.
    init?(body: Any) {
        guard let object = body as? [String: Any], let type = object["type"] as? String else { return nil }
        switch type {
        case "ready": self = .ready
        case "save": self = .save
        case "close": self = .close
        case "dirty":
            guard let dirty = object["dirty"] as? Bool else { return nil }
            self = .dirty(dirty)
        default: return nil
        }
    }
}
