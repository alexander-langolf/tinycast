import Foundation

struct ForkEvent: Codable, Sendable {
    enum Level: String, Codable, Sendable, CaseIterable {
        case debug, info, warning, error
    }

    enum Category: String, Codable, Sendable {
        case workflows, quickActions, selection, betterTouchTool, supervision, automation, claudeAccount, lyra
    }

    enum Operation: String, Codable, Sendable {
        case quickAction, selectedText, copySelection, bttSelection, appSupervision, health, claudeRequest
        case automation, lyra, workflow
    }

    enum AutomationOperation: String, Sendable {
        case paletteShow = "palette_show", hudShow = "hud_show", questionAsk = "question_ask"
        case questionAcknowledge = "question_ack", terminalFocus = "terminal_focus", terminalRun = "terminal_run"
        case agents = "tinycast://agents", terminals = "tinycast://terminals", questions = "tinycast://questions"
        case context = "tinycast://context", health = "tinycast://health", healthRepair = "health_repair"
        case selectionRead = "selection_read", quickActionRun = "quick_action_run", lyraRewrite = "lyra_rewrite", modelComplete = "model_complete", textReplace = "text_replace"
        case uiPreview = "ui_preview", uiMarker = "ui_marker", uiResult = "ui_result", unknown
    }

    enum Step: String, Codable, Sendable {
        case fallback, start, end, error, accessibility, selectionRead, copySelection, copyGates, copyPoll
        case bttRead, readiness, launch, termination, gaveUp, modelRequest, requestHeaders, response
        case trigger, firstToken, insertion, paste, dismissal, marker, offer, policyReload
    }

    enum Outcome: String, Codable, Sendable {
        case started, success, empty, unavailable, skipped, timeout, cancelled, failed, gaveUp
    }

    enum PolicyFailure: String, Sendable {
        case invalidJSON, unknownKey, invalidValue, unreadable, invalidPrompt, changedDuringRead
    }

    struct Fields: Sendable {
        var length: Int?
        var byteCount: Int?
        var count: Int?
        var bundleID: String?
        var clientID: UUID?
        var errorCode: Int?
        var statusCode: Int?
        var headerCount: Int?
        var allowed: Bool?
        var automationOperation: AutomationOperation?
        var policyVersion: String?
        var policyFile: String?
        var policyFailure: PolicyFailure?
        var caretKnown: Bool?

        var values: [String: String] {
            var result: [String: String] = [:]
            func number(_ key: String, _ value: Int?) {
                if let value { result[key] = String(value) }
            }
            number("length", length)
            number("bytes", byteCount)
            number("count", count)
            number("errorCode", errorCode)
            number("statusCode", statusCode)
            number("headerCount", headerCount)
            if let clientID { result["clientID"] = clientID.uuidString }
            if let allowed { result["allowed"] = String(allowed) }
            if let automationOperation { result["operation"] = automationOperation.rawValue }
            if let bundleID, bundleID.count <= 256, bundleID.contains("."),
                bundleID.utf8.allSatisfy({
                    (65...90).contains($0) || (97...122).contains($0)
                        || (48...57).contains($0) || $0 == 45 || $0 == 46
                })
            { result["bundleID"] = bundleID }
            if let policyVersion, policyVersion.utf8.count == 12,
                policyVersion.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            { result["policyVersion"] = policyVersion }
            if let policyFile, policyFile.utf8.count <= 68,
                policyFile == "lyra.json" || policyFile.hasSuffix(".txt") && !policyFile.dropLast(4).isEmpty
                    && policyFile.dropLast(4).utf8.allSatisfy({
                        (65...90).contains($0) || (97...122).contains($0)
                            || (48...57).contains($0) || $0 == 45 || $0 == 95
                    })
            { result["policyFile"] = policyFile }
            if let policyFailure { result["policyFailure"] = policyFailure.rawValue }
            if let caretKnown { result["caretKnown"] = String(caretKnown) }
            return result
        }
    }

    let time: Date
    let level: Level
    let category: Category
    let operation: Operation
    let correlationID: UUID
    let step: Step
    let durationMS: Double
    let outcome: Outcome
    let fields: [String: String]

    init(
        time: Date = Date(), level: Level = .info, category: Category, operation: Operation,
        correlationID: UUID, step: Step, durationMS: Double = 0, outcome: Outcome,
        fields: Fields = Fields()
    ) {
        self.time = time
        self.level = level
        self.category = category
        self.operation = operation
        self.correlationID = correlationID
        self.step = step
        self.durationMS = durationMS.isFinite ? max(0, durationMS) : 0
        self.outcome = outcome
        self.fields = fields.values
    }

    func line() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(10)
        return data
    }
}
