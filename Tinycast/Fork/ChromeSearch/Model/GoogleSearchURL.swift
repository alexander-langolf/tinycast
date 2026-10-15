import Foundation

enum GoogleSearchURL {
    /// `URLQueryItem` leaves `+` bare, which the server reads as a space.
    static func queryItem(_ name: String, _ value: String) -> URLQueryItem {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: allowed))
    }

    static func resultsPage(for query: String, language: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.percentEncodedQueryItems = [
            queryItem("q", query), queryItem("hl", language), queryItem("num", "10")
        ]
        return components?.url
    }
}
