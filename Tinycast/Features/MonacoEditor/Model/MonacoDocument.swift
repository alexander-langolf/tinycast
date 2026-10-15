import Foundation

/// A file opened in the editor: where it lives and what the disk looked like when it was read.
struct MonacoDocument: Equatable, Sendable {
    enum Failure: Error, Equatable, Sendable {
        case tooLarge(bytes: Int, limit: Int)
        case notText
        case unreadable

        var message: String {
            switch self {
            case .tooLarge(_, let limit): "File is larger than \(limit / 1_048_576) MB"
            case .notText: "File is not UTF-8 text"
            case .unreadable: "File could not be read"
            }
        }
    }

    static let sizeLimit = 2 * 1_048_576

    let path: String
    let modified: Date

    var name: String { (path as NSString).lastPathComponent }
    var language: String { MonacoLanguageMap.language(forFileName: name) }

    /// A file changed under the editor when its modification date moved off the one recorded at load.
    func changedOnDisk(modified current: Date?) -> Bool { current != modified }

    /// Text only: valid UTF-8, no NUL bytes, and within `limit`.
    static func decode(_ data: Data, limit: Int = sizeLimit) -> Result<String, Failure> {
        guard data.count <= limit else { return .failure(.tooLarge(bytes: data.count, limit: limit)) }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            return .failure(.notText)
        }
        return .success(text)
    }
}
