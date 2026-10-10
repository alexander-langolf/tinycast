import Foundation

enum ForkQuickAIHandoff {
    struct Handoff: Sendable {
        let text: String
        let overflow: String?
        let firstMessage: String

        nonisolated func text(handoffPath: String) -> String {
            firstMessage + "\n\nThe rest of the Quick AI conversation is in \(handoffPath); read it first."
                + "\n\n" + ForkQuickAIHandoff.closingLine
        }
    }

    nonisolated static let closingLine =
        "This conversation started in Tinycast Quick AI, which could only answer in text. "
        + "Continue it here as a work session, with your normal tools and approval rules, "
        + "starting from the latest request."

    nonisolated static func prompt(
        messages: [ChatMessage], pending: ChatMessage?, limit: Int = 32 * 1_024
    ) -> Handoff {
        let messages = messages + (pending.map { [$0] } ?? [])
        guard let firstIndex = messages.firstIndex(where: { $0.role == .user }) else {
            return Handoff(text: closingLine, overflow: nil, firstMessage: "")
        }
        let first = messages[firstIndex]
        var turns: [String] = []
        let firstAttachments = placeholders(for: first)
        if !firstAttachments.isEmpty { turns.append("Sasha:\n" + firstAttachments) }
        turns += messages.dropFirst(firstIndex + 1).map { message in
            let speaker = message.role == .user ? "Sasha:" : "Quick AI:"
            let attachments = placeholders(for: message)
            let content = [message.text, attachments].filter { !$0.isEmpty }.joined(separator: "\n")
            return speaker + "\n" + content
        }
        let exchange = turns.joined(separator: "\n\n")
        let text = first.text + (exchange.isEmpty ? "" : "\n\n---\n\n" + exchange)
            + "\n\n" + closingLine
        return Handoff(
            text: text, overflow: text.utf8.count > limit ? exchange : nil,
            firstMessage: first.text)
    }

    nonisolated private static func placeholders(for message: ChatMessage) -> String {
        (message.images.map { _ in "[image attached in Quick AI]" }
            + message.documents.map { "[document: \(AIAttachmentPolicy.sanitized(name: $0.name))]" })
            .joined(separator: "\n")
    }

    nonisolated static func command(executable: String, prompt: String) -> String {
        [executable, "--", prompt].map(quote).joined(separator: " ")
    }

    nonisolated static func quote(_ argument: String) -> String {
        var result = "$'"
        for scalar in argument.unicodeScalars {
            switch scalar.value {
            case 0x5C: result += "\\\\"
            case 0x27: result += "\\'"
            case 0x0A: result += "\\n"
            case 0x09: result += "\\t"
            case 0x0D: result += "\\r"
            default:
                if CharacterSet.controlCharacters.contains(scalar)
                    || CharacterSet.newlines.contains(scalar)
                {
                    result += String(format: "\\U%08X", scalar.value)
                } else {
                    result += String(scalar)
                }
            }
        }
        return result + "'"
    }
}
