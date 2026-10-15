import Foundation

/// One autocomplete entry; a website's `text` is its bare host and `detail` Google's description.
struct GoogleSuggestion: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case query
        case website(URL)
    }

    let text: String
    let kind: Kind
    var detail = ""
}

/// Google's autocomplete endpoint: the request it takes and the `client=chrome` array it answers with.
enum GoogleSuggestions {
    static let limit = 8

    static func url(for query: String, language: String) -> URL? {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        components?.percentEncodedQueryItems = [
            GoogleSearchURL.queryItem("client", "chrome"), GoogleSearchURL.queryItem("hl", language),
            GoogleSearchURL.queryItem("q", query)
        ]
        return components?.url
    }

    /// The body as text: the response's charset, else ISO-8859-1, which Google sends for this client.
    static func decode(_ data: Data, charset: String?) -> String {
        var encoding = String.Encoding.isoLatin1
        if let charset {
            let converted = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if converted != kCFStringEncodingInvalidId {
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(converted))
            }
        }
        return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
    }

    /// Google's order, minus blanks, `typed` and repeats. A type other than QUERY or NAVIGATION drops.
    static func parse(_ data: Data, charset: String?, typed: String) -> [GoogleSuggestion] {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(decode(data, charset: charset).utf8))
                as? [Any],
            root.count > 1, let raw = root[1] as? [Any]
        else { return [] }
        let descriptions = root.count > 2 ? root[2] as? [Any] : nil
        let types = (root.count > 4 ? root[4] as? [String: Any] : nil)?["google:suggesttype"] as? [Any]
        var seen: Set<String> = [fold(typed)]
        var result: [GoogleSuggestion] = []
        for (index, element) in raw.enumerated() {
            guard let text = (element as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { continue }
            let type = types.flatMap { index < $0.count ? $0[index] as? String : nil } ?? "QUERY"
            let detail = (descriptions.flatMap { index < $0.count ? $0[index] as? String : nil } ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suggestion: GoogleSuggestion
            switch type {
            case "QUERY":
                suggestion = GoogleSuggestion(text: text, kind: .query)
            case "NAVIGATION":
                guard let site = website(text, detail: detail) else { continue }
                suggestion = site
            default:
                continue
            }
            guard seen.insert(key(suggestion)).inserted else { continue }
            result.append(suggestion)
            if result.count == limit { break }
        }
        return result
    }

    private static func website(_ raw: String, detail: String) -> GoogleSuggestion? {
        let absolute = raw.contains("://") ? raw : "https://" + raw
        guard let url = URL(string: absolute), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = url.host(), !host.isEmpty
        else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return GoogleSuggestion(text: bare, kind: .website(url), detail: detail)
    }

    private static func key(_ suggestion: GoogleSuggestion) -> String {
        if case .website(let url) = suggestion.kind { return url.absoluteString }
        return fold(suggestion.text)
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
