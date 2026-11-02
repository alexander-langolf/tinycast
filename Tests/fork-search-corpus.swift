// Deterministic synthetic clipboard texts for the fork-search parity harness.
import Foundation

enum ForkSearchCorpus {
    static let queries = [
        "c", "co", "con", "config", "tinycast", "swift ui", "xyzq", "https github", "'exact", "^pre",
        "fix$", "!skip word", "strasse", "café", "日本", "phr", "gufT", "👍",
    ]

    /// SplitMix64: a fixed sequence per seed, so parity runs see the same corpus on every machine.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let asciiTokens = [
        "config", "tinycast", "swift", "ui", "prefix", "fix", "exact", "skip", "let", "var", "func",
        "return", "struct", "import Foundation", "https://github.com/multiverse-io/tinycast/pull/42",
        "https://example.com/docs/config", "git push origin main", "func match(_ query: String)",
        "if let value {", "}", "// TODO: fix the prefix", "const x = 42;", "sudo make install",
        "~/.config/tinycast/settings.json", "console.log(\"ok\")", "Connection: keep-alive",
        "lorem ipsum dolor", "the quick brown fox", "word", "c", "co", "con", "fix$", "^pre", "'exact",
        "!skip", "docs", "$HOME/.config", "{\"name\":\"tinycast\"}",
    ]

    /// camelCase identifiers: the hump bonuses that folding a clipboard text can lose.
    private static let camelTokens = [
        "parseHTTPResponseHeader", "myViewController.swift", "getUserIDFromToken", "fooBarBaz",
        "XMLHttpRequest", "item2Count", "setUpTheView()", "onDidFinishLaunching",
    ]

    private static let unicodeTokens = [
        "👨‍👩‍👧", "🇩🇪", "🎉", "café crème", "Straße", "日本語のテキスト", "e\u{301}", "naïve résumé",
        "\r\n", "Ünïcödé", "👍🏽", "東京", "ﬁle", "ß", "Ω≈ç√", "🧑‍💻 dev", "https://café.example/ß",
        "👋🏿", "❤️", "☺︎", "great 👍🏽 work",
    ]

    private static let separators = [" ", " ", " ", "\n", "\t", ", ", "; ", "  ", "/", "_", "-"]

    static func items(count: Int, seed: UInt64) -> [String] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in
            let unicode = rng.next() % 100 < 10
            let camel = !unicode && rng.next() % 100 < 5
            let roll = rng.next() % 100
            let length = roll < 50 ? 20 : roll < 85 ? 200 : roll < 98 ? 2_000 : 15_000
            return text(unicode: unicode, camel: camel, length: length, rng: &rng)
        }
    }

    /// Joins tokens until the length is reached, then cuts to it (grapheme counts drift slightly).
    private static func text(unicode: Bool, camel: Bool, length: Int, rng: inout SplitMix64) -> String {
        var out = ""
        var count = 0
        while count < length {
            var piece: String
            if unicode, rng.next() % 3 == 0 {
                piece = unicodeTokens[Int(rng.next() % UInt64(unicodeTokens.count))]
            } else if camel {
                piece = camelTokens[Int(rng.next() % UInt64(camelTokens.count))]
            } else {
                piece = asciiTokens[Int(rng.next() % UInt64(asciiTokens.count))]
            }
            piece += separators[Int(rng.next() % UInt64(separators.count))]
            out += piece
            count += piece.count
        }
        return String(out.prefix(length))
    }
}
