import Foundation

/// Shell marks delimit command output; prompt text stays outside the log.
struct TerminalMarkParser: Sendable {
    enum Event: Equatable, Sendable {
        /// OSC 133;A: at a prompt, reading the next line.
        case promptReady
        /// OSC 133;C: the command line started; its output follows.
        case commandStarted
        /// OSC 133;D: the command ended with this status, 0 when the mark carries none.
        case commandFinished(status: Int32)
        /// OSC 7: the shell's working directory, percent-decoded.
        case workingDirectory(String)
        /// DEC private modes 1049, 1047 and 47: a full-screen program took or left the screen.
        case alternateScreen(Bool)
        /// Text between C and D, CSI kept so the log can colour it.
        case output(String)
    }

    /// Past this an unterminated sequence is noise, not a mark still arriving.
    static let pendingLimit = 4096

    private(set) var isInCommand = false
    private var pending: [UInt8] = []

    private static let escape: UInt8 = 0x1B
    private static let bell: UInt8 = 0x07
    private static let alternateScreenModes: Set<String> = ["?1049", "?1047", "?47"]

    private enum Kind {
        case osc(String)
        case csi(String)
        case other
    }

    private struct Sequence {
        let kind: Kind
        let end: Int
    }

    mutating func feed(_ chunk: some Collection<UInt8>) -> [Event] {
        var data = pending
        data.append(contentsOf: chunk)
        pending = []
        var events: [Event] = []
        var text: [UInt8] = []
        var index = 0
        while index < data.count {
            guard data[index] == Self.escape else {
                if isInCommand { text.append(data[index]) }
                index += 1
                continue
            }
            guard let sequence = Self.sequence(in: data, at: index) else {
                if data.count - index > Self.pendingLimit {
                    index += 1
                    continue
                }
                pending = Array(data[index...])
                break
            }
            switch sequence.kind {
            case .osc(let body):
                Self.flush(&text, into: &events)
                apply(osc: body, into: &events)
            case .csi(let body):
                if let entered = Self.alternateScreen(body) {
                    Self.flush(&text, into: &events)
                    events.append(.alternateScreen(entered))
                } else if isInCommand {
                    text.append(contentsOf: data[index..<sequence.end])
                }
            case .other:
                break
            }
            index = sequence.end
        }
        if pending.isEmpty, !text.isEmpty {
            let whole = Self.wholeScalarLength(text)
            pending = Array(text[whole...])
            text.removeSubrange(whole...)
        }
        Self.flush(&text, into: &events)
        return events
    }

    private mutating func apply(osc body: String, into events: inout [Event]) {
        if body.hasPrefix("133;") {
            let fields = body.split(separator: ";", omittingEmptySubsequences: false)
            switch fields.count > 1 ? fields[1] : "" {
            case "A":
                events.append(.promptReady)
            case "C":
                isInCommand = true
                events.append(.commandStarted)
            case "D":
                isInCommand = false
                let status = fields.count > 2 ? Int32(fields[2]) ?? 0 : 0
                events.append(.commandFinished(status: status))
            default:
                break
            }
        } else if body.hasPrefix("7;"), let path = Self.path(fromFileURL: body.dropFirst(2)) {
            events.append(.workingDirectory(path))
        }
    }

    /// `file://host/path`; the host is ignored because the shell is always local.
    static func path(fromFileURL url: Substring) -> String? {
        guard url.hasPrefix("file://") else { return nil }
        let rest = url.dropFirst("file://".count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let raw = String(rest[slash...])
        return raw.removingPercentEncoding ?? raw
    }

    /// The length of `bytes` up to the last whole UTF-8 scalar.
    static func wholeScalarLength(_ bytes: [UInt8]) -> Int {
        var start = bytes.count - 1
        var continuation = 0
        while start >= 0, bytes[start] & 0xC0 == 0x80, continuation < 3 {
            start -= 1
            continuation += 1
        }
        guard start >= 0 else { return bytes.count }
        let needed: Int
        switch bytes[start] {
        case 0xF0...0xF7: needed = 4
        case 0xE0...0xEF: needed = 3
        case 0xC0...0xDF: needed = 2
        default: return bytes.count
        }
        return continuation + 1 < needed ? start : bytes.count
    }

    private static func flush(_ text: inout [UInt8], into events: inout [Event]) {
        guard !text.isEmpty else { return }
        events.append(.output(String(decoding: text, as: UTF8.self)))
        text.removeAll(keepingCapacity: true)
    }

    private static func alternateScreen(_ body: String) -> Bool? {
        guard let last = body.last, last == "h" || last == "l",
            alternateScreenModes.contains(String(body.dropLast()))
        else { return nil }
        return last == "h"
    }

    private static func decode(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// Nil while the sequence at `start` has not all arrived.
    private static func sequence(in data: [UInt8], at start: Int) -> Sequence? {
        guard start + 1 < data.count else { return nil }
        switch data[start + 1] {
        case UInt8(ascii: "]"):
            var index = start + 2
            while index < data.count {
                if data[index] == bell {
                    return Sequence(kind: .osc(decode(data[(start + 2)..<index])), end: index + 1)
                }
                if data[index] == escape {
                    guard index + 1 < data.count else { return nil }
                    let body = decode(data[(start + 2)..<index])
                    // ESC \ is ST; any other ESC ends the OSC unterminated and starts the next one.
                    return data[index + 1] == UInt8(ascii: "\\")
                        ? Sequence(kind: .osc(body), end: index + 2)
                        : Sequence(kind: .osc(body), end: index)
                }
                index += 1
            }
            return nil
        case UInt8(ascii: "["):
            var index = start + 2
            while index < data.count {
                if (0x40...0x7E).contains(data[index]) {
                    return Sequence(kind: .csi(decode(data[(start + 2)...index])), end: index + 1)
                }
                index += 1
            }
            return nil
        case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"):
            return start + 2 < data.count ? Sequence(kind: .other, end: start + 3) : nil
        default:
            return Sequence(kind: .other, end: start + 2)
        }
    }
}
