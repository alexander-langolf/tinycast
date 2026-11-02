import Foundation

struct ClaudeUsageSnapshot: Decodable, Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let kind: String
        let percent: Double
        let resetsAt: Date
        let modelName: String?
    }

    let windows: [Window]

    var session: Window? { windows.first { $0.kind == "session" } }
    var weekly: Window? { windows.first { $0.kind == "weekly_all" } }

    private enum CodingKeys: String, CodingKey {
        case limits
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded: [Window]
        if container.contains(.limits) {
            decoded = try container.decode([Limit].self, forKey: .limits).map(\.window)
        } else {
            var fallback: [Window] = []
            for (key, kind) in [(CodingKeys.fiveHour, "session"), (.sevenDay, "weekly_all")] {
                if let value = try container.decodeIfPresent(LegacyLimit.self, forKey: key) {
                    fallback.append(Window(kind: kind, percent: value.utilization,
                        resetsAt: value.resetsAt, modelName: nil))
                }
            }
            guard !fallback.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "No usage windows were provided"))
            }
            decoded = fallback
        }
        windows = decoded.enumerated().sorted { lhs, rhs in
            let left = Self.order(lhs.element.kind)
            let right = Self.order(rhs.element.kind)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    private static func order(_ kind: String) -> Int {
        switch kind {
        case "session": 0
        case "weekly_all": 1
        case "weekly_scoped": 2
        default: 3
        }
    }

    private static func resetDate(_ text: String, decoder: any Decoder) throws -> Date {
        let hasOffset = text.range(of: #"(?:Z|[+-]\d{2}:\d{2})$"#,
            options: .regularExpression) != nil
        guard hasOffset,
            let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
                ?? (try? Date.ISO8601FormatStyle().parse(text))
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid usage reset timestamp"))
        }
        return date
    }

    private static func validate(_ percent: Double, decoder: any Decoder) throws {
        guard percent.isFinite, (0...100).contains(percent) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Usage percentage must be between 0 and 100"))
        }
    }

    private struct Limit: Decodable {
        let window: Window

        private enum CodingKeys: String, CodingKey {
            case kind, percent, scope
            case resetsAt = "resets_at"
        }

        private struct Scope: Decodable {
            struct Model: Decodable {
                let displayName: String

                enum CodingKeys: String, CodingKey {
                    case displayName = "display_name"
                }
            }

            let model: Model?
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            guard !kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container,
                    debugDescription: "Usage window kind is empty")
            }
            let percent = try container.decode(Double.self, forKey: .percent)
            try ClaudeUsageSnapshot.validate(percent, decoder: decoder)
            let reset = try container.decode(String.self, forKey: .resetsAt)
            let scope = try container.decodeIfPresent(Scope.self, forKey: .scope)
            window = Window(kind: kind, percent: percent,
                resetsAt: try ClaudeUsageSnapshot.resetDate(reset, decoder: decoder),
                modelName: scope?.model?.displayName)
        }
    }

    private struct LegacyLimit: Decodable {
        let utilization: Double
        let resetsAt: Date

        private enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            utilization = try container.decode(Double.self, forKey: .utilization)
            try ClaudeUsageSnapshot.validate(utilization, decoder: decoder)
            resetsAt = try ClaudeUsageSnapshot.resetDate(
                container.decode(String.self, forKey: .resetsAt), decoder: decoder)
        }
    }
}
