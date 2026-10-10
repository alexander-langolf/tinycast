import Foundation
import Observation
import os

/// The folder the installed agents start in, apart from the private folder that holds their files.
@MainActor @Observable
final class ForkAIWorkingDirectory {
    private(set) static var current: ForkAIWorkingDirectory?
    nonisolated private static let logger = Logger(
        subsystem: "com.tinycast", category: "AIWorkingDirectory")
    private let defaults: UserDefaults
    /// Run after a change, so a process whose directory is fixed at launch can start again.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var reportedMissing: String?

    /// Absolute or `~/`-relative; nil keeps upstream's private folder as the directory too.
    var path: String? {
        didSet {
            guard path != oldValue else { return }
            if let path {
                defaults.set(path, forKey: "aiWorkingDirectory")
            } else {
                defaults.removeObject(forKey: "aiWorkingDirectory")
            }
            reportedMissing = nil
            onChange?()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        path = defaults.string(forKey: "aiWorkingDirectory")
    }

    func start() {
        precondition(Self.current == nil)
        Self.current = self
    }

    /// Nil when unset or not a folder now, so the caller falls back to its private one.
    var url: URL? {
        guard let path, AppPaths.isFolderPath(path) else { return nil }
        let url = URL(
            filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            if reportedMissing != path {
                reportedMissing = path
                Self.logger.error(
                    "AI working directory \(path, privacy: .public) is not a folder; using default")
            }
            return nil
        }
        return url
    }

    var isMissing: Bool { path != nil && url == nil }

    /// How a chosen folder is stored: `~`-relative where it can be.
    static func setting(for url: URL) -> String {
        (url.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath
    }
}
