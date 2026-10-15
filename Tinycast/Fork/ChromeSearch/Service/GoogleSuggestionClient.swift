import Foundation

/// Cacheless, never `URLSession.shared`: a keystroke sent to Google leaves nothing on disk.
struct GoogleSuggestionClient: GoogleSuggesting {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 3
        return URLSession(configuration: config)
    }()

    static var language: String {
        Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
            ?? "en"
    }

    func suggestions(for query: String) async -> [GoogleSuggestion] {
        guard let url = GoogleSuggestions.url(for: query, language: Self.language),
            let (data, response) = try? await Self.session.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return [] }
        return GoogleSuggestions.parse(data, charset: response.textEncodingName, typed: query)
    }
}
