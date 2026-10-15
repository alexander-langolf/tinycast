import Foundation

/// File extensions and well-known file names to the Monaco language ids this bundle ships.
enum MonacoLanguageMap {
    static let plainText = "plaintext"

    private static let byExtension: [String: String] = [
        "swift": "swift", "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
        "ts": "typescript", "mts": "typescript", "cts": "typescript", "tsx": "typescript",
        "json": "json", "jsonc": "json", "md": "markdown", "markdown": "markdown", "mdx": "mdx",
        "html": "html", "htm": "html", "css": "css", "scss": "scss", "less": "less",
        "xml": "xml", "plist": "xml", "svg": "xml", "yaml": "yaml", "yml": "yaml",
        "py": "python", "rb": "ruby", "rs": "rust", "go": "go", "java": "java", "kt": "kotlin",
        "c": "cpp", "h": "cpp", "cc": "cpp", "cpp": "cpp", "hpp": "cpp", "m": "objective-c",
        "mm": "objective-c", "cs": "csharp", "php": "php", "lua": "lua", "pl": "perl",
        "sh": "shell", "zsh": "shell", "bash": "shell", "ps1": "powershell",
        "sql": "sql", "graphql": "graphql", "proto": "protobuf", "ini": "ini", "toml": "ini",
        "dart": "dart", "scala": "scala", "r": "r", "jl": "julia", "ex": "elixir", "exs": "elixir"
    ]

    private static let byName: [String: String] = [
        "dockerfile": "dockerfile", "makefile": "shell", ".zshrc": "shell", ".bashrc": "shell",
        ".zprofile": "shell", ".gitignore": "ini", ".env": "ini"
    ]

    static func language(forFileName name: String) -> String {
        let lowered = name.lowercased()
        if let match = byName[lowered] { return match }
        guard let dot = lowered.lastIndex(of: "."), dot != lowered.startIndex else { return plainText }
        return byExtension[String(lowered[lowered.index(after: dot)...])] ?? plainText
    }
}
