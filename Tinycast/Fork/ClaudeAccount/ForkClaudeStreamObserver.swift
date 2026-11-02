import Foundation

struct ForkClaudeStreamObserver {
    private var parser = SSEParser()
    private var blocks: [Int: [String: JSONValue]] = [:]
    private var pending: [JSONValue] = []
    private(set) var thinkingByCall: [String: [JSONValue]] = [:]

    mutating func feed(_ data: Data) { consume(parser.feed(data)) }
    mutating func finish() { consume(parser.finish()) }

    private mutating func consume(_ payloads: [String]) {
        for payload in payloads {
            guard let data = payload.data(using: .utf8),
                let event = JSONValue(data: data)?.objectValue,
                case .string(let type) = event["type"]
            else { continue }
            let index: Int
            if case .number(let number) = event["index"] { index = Int(number) } else { index = 0 }
            switch type {
            case "content_block_start":
                guard case .object(let block) = event["content_block"],
                    case .string(let kind) = block["type"]
                else { continue }
                if kind == "thinking" || kind == "redacted_thinking" {
                    blocks[index] = block
                } else if kind == "tool_use", case .string(let id) = block["id"] {
                    thinkingByCall[id] = pending
                    pending = []
                }
            case "content_block_delta":
                guard case .object(let delta) = event["delta"], blocks[index] != nil else { continue }
                for key in ["thinking", "signature"] {
                    if case .string(let addition) = delta[key] {
                        let previous: String
                        if case .string(let text) = blocks[index]?[key] { previous = text } else { previous = "" }
                        blocks[index]?[key] = .string(previous + addition)
                    }
                }
            case "content_block_stop":
                if let block = blocks.removeValue(forKey: index) { pending.append(.object(block)) }
            default: break
            }
        }
    }
}
