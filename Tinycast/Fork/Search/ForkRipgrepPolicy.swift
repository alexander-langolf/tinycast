import Foundation

enum ForkRipgrepPolicy {
    nonisolated static func arguments(
        patterns: [String], home: String, subtree: Bool, depthLimit: Int? = nil
    ) -> [String] {
        var arguments = ["--files", "--no-messages", "--null"]
        if let depthLimit { arguments += ["--max-depth", String(depthLimit)] }
        if !subtree { arguments += ["--glob", "!/Library/", "--glob", "!/.Trash/"] }
        for pattern in FileSearchIgnoreList.defaults + patterns {
            let pattern = pattern.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty, !pattern.contains("\0"),
                !pattern.contains(where: { "{}\\!".contains($0) })
            else { continue }
            if !pattern.contains("/") {
                arguments += ["--iglob", "!" + pattern, "--iglob", "!" + pattern + "/**"]
            } else if pattern.hasPrefix(home + "/") {
                let relative = String(pattern.dropFirst(home.count + 1))
                arguments += ["--iglob", "!/" + relative, "--iglob", "!/" + relative + "/**"]
            }
        }
        if !subtree { arguments += ["--iglob", "!*.app/**", "--iglob", "!*.pkg/**"] }
        return arguments
    }

    nonisolated static func excludes(
        _ path: String, ignore: FileSearchIgnoreList, packages: Bool = true
    ) -> Bool {
        path.split(separator: "/").contains {
            $0.hasPrefix(".")
                || (packages
                    && ($0.lowercased().hasSuffix(".app")
                        || $0.lowercased().hasSuffix(".pkg")))
        } || ignore.excludes(path: path)
    }
}
