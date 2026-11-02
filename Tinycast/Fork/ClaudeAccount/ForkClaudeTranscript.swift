import CryptoKit
import Foundation
import Synchronization

final class ForkClaudeTranscript: Sendable {
    private let efforts: Mutex<[String: String]>

    init() {
        efforts = Mutex(UserDefaults.standard.dictionary(forKey: "fork.claudeAccount.assistantEfforts") as? [String: String] ?? [:])
    }

    func effort(for message: AIMessage, conversation: UUID?) -> String? {
        let key = Self.key(message, conversation: conversation)
        return efforts.withLock { $0[key] }
    }

    func record(_ message: AIMessage, conversation: UUID?, effort: String) {
        let key = Self.key(message, conversation: conversation)
        efforts.withLock { values in
            values[key] = effort
            UserDefaults.standard.set(values, forKey: "fork.claudeAccount.assistantEfforts")
        }
    }

    private static func key(_ message: AIMessage, conversation: UUID?) -> String {
        var data = Data((conversation?.uuidString ?? "").utf8)
        for part in [message.text] + message.toolCalls.map(\.id) {
            data.append(Data("\(part.utf8.count):\(part)".utf8))
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
