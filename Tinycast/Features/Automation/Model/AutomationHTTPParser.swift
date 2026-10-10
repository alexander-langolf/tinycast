import Foundation

/// Strict, bounded HTTP/1.1 request framing: only what a local JSON-RPC client needs.
enum AutomationHTTPParser {
    static let maximumHeadBytes = 16 * 1024
    static let maximumBodyBytes = 256 * 1024
    static let maximumHeaderCount = 64

    enum HeadResult: Equatable {
        case incomplete
        case head(AutomationHTTPHead)
    }

    static func parseHead(_ buffer: Data) -> Result<HeadResult, AutomationHTTPRejection> {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = buffer.range(of: terminator) else {
            if buffer.count > maximumHeadBytes {
                return .failure(.init(status: 431, reason: "Header section too large"))
            }
            return .success(.incomplete)
        }
        guard end.lowerBound <= maximumHeadBytes else {
            return .failure(.init(status: 431, reason: "Header section too large"))
        }
        guard let text = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8)
        else { return .failure(.init(status: 400, reason: "Headers are not UTF-8")) }
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2] == "HTTP/1.1", !requestLine[0].isEmpty,
            requestLine[1].hasPrefix("/")
        else { return .failure(.init(status: 400, reason: "Malformed request line")) }
        guard lines.count <= maximumHeaderCount else {
            return .failure(.init(status: 431, reason: "Too many headers"))
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                !line.hasPrefix(" "), !line.hasPrefix("\t")
            else { return .failure(.init(status: 400, reason: "Malformed header")) }
            let name = line[..<colon].lowercased()
            guard !name.contains(" "), !name.contains("\t") else {
                return .failure(.init(status: 400, reason: "Malformed header name"))
            }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard headers[name] == nil else {
                return .failure(.init(status: 400, reason: "Repeated header \(name)"))
            }
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil else {
            return .failure(.init(status: 501, reason: "Transfer-Encoding is not supported"))
        }
        var length = 0
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0, raw.allSatisfy(\.isASCII) else {
                return .failure(.init(status: 400, reason: "Invalid Content-Length"))
            }
            guard parsed <= maximumBodyBytes else {
                return .failure(.init(status: 413, reason: "Body too large"))
            }
            length = parsed
        }
        let head = AutomationHTTPHead(
            method: String(requestLine[0]), target: String(requestLine[1]), headers: headers,
            contentLength: length, bodyStart: end.upperBound - buffer.startIndex)
        return .success(.head(head))
    }
}
