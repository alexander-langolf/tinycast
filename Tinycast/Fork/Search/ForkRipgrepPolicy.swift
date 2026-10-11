import Foundation

enum ForkRipgrepPolicy {
    nonisolated static func arguments(
        patterns: [String], home: String, subtree: Bool, depthLimit: Int? = nil,
        directory: String? = nil
    ) -> [String] {
        var arguments = ["--files", "--hidden", "--no-messages", "--null", "--glob", "!.git/"]
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
        } || ["Library", ".Trash"].contains {
            path == home + "/" + $0 || path.hasPrefix(home + "/" + $0 + "/")
        } || ignore.excludes(path: path)
    }
}
