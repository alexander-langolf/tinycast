import Foundation

enum ForkRipgrepPolicy {
    nonisolated static func executable(
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> URL? {
        let candidates =
            ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"]
            + path.split(separator: ":", omittingEmptySubsequences: false).map {
                URL(filePath: $0.isEmpty ? "." : String($0)).appending(path: "rg").path
            }
        return candidates.first { candidate in
            var directory: ObjCBool = false
            return FileManager.default.isExecutableFile(atPath: candidate)
                && FileManager.default.fileExists(atPath: candidate, isDirectory: &directory)
                && !directory.boolValue
        }.map { URL(filePath: $0) }
    }

    nonisolated static func arguments(
        patterns: [String], home: String, subtree: Bool, depthLimit: Int? = nil,
        directory: String? = nil, hidden: Bool = true
    ) -> [String] {
        var arguments = ["--files", "--no-messages", "--null", "--glob", "!.git/"]
        if hidden { arguments.insert("--hidden", at: 1) }
        if let depthLimit { arguments += ["--max-depth", String(depthLimit)] }
        let directory = directory ?? home
        let prefix = directory == "/" ? "/" : directory + "/"
        for name in ["Library", ".Trash"] {
            let path = home + "/" + name
            if path.hasPrefix(prefix) {
                arguments += ["--glob", "!/" + path.dropFirst(prefix.count) + "/"]
            }
        }
        for pattern in FileSearchIgnoreList.defaults + patterns {
            let pattern = pattern.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty, !pattern.contains("\0"),
                !pattern.contains(where: { "{}\\!".contains($0) })
            else { continue }
            if !pattern.contains("/") {
                arguments += ["--iglob", "!" + pattern, "--iglob", "!" + pattern + "/**"]
            } else if pattern.hasPrefix(prefix) {
                let relative = String(pattern.dropFirst(prefix.count))
                arguments += ["--iglob", "!/" + relative, "--iglob", "!/" + relative + "/**"]
            }
        }
        if !subtree { arguments += ["--iglob", "!*.app/**", "--iglob", "!*.pkg/**"] }
        return arguments
    }

    nonisolated static func excludes(
        _ path: String, ignore: FileSearchIgnoreList, home: String, packages: Bool = true
    ) -> Bool {
        path.split(separator: "/").contains {
            $0 == ".git"
                || (packages
                    && ($0.lowercased().hasSuffix(".app")
                        || $0.lowercased().hasSuffix(".pkg")))
        }
            || ["Library", ".Trash"].contains {
                path == home + "/" + $0 || path.hasPrefix(home + "/" + $0 + "/")
            } || ignore.excludes(path: path)
    }
}
