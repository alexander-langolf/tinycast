import Foundation
import os

@MainActor
final class ForkQuickAIRootLog {
    enum Event: String, Codable, Sendable {
        case warmed, claimed, retired, handedOff, fellBack
    }

    enum Engine: String, Codable, Sendable {
        case claude, codex
    }

    enum Reason: String, Codable, Sendable {
        case newChat, mismatch, disabled, handedOff, serverRelaunched, unavailable
    }

    struct Entry: Codable, Sendable {
        let at: Date
        let event: Event
        var root: String?
        var chat: UUID?
        var engine: Engine?
        var terminal: UUID?
        var reason: Reason?
    }

    private let settings: ForkQuickAIRootSettings
    private let files: ForkQuickAIRootLogFiles
    private let queue = DispatchQueue(label: "com.tinycast.quick-ai-root-log", qos: .utility)
    private var timer: Timer?
    nonisolated private static let logger = Logger(
        subsystem: "com.tinycast", category: "QuickAIRootLog")

    init(settings: ForkQuickAIRootSettings, supportDirectory: URL = AppPaths.applicationSupport()) {
        self.settings = settings
        files = ForkQuickAIRootLogFiles(
            directory: supportDirectory.appending(path: "QuickAIRoot", directoryHint: .isDirectory))
    }

    isolated deinit { timer?.invalidate() }

    func start() {
        settingsChanged()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        files.configure(enabled: false, retention: settings.retention.seconds)
    }

    func settingsChanged() {
        files.configure(enabled: settings.isEnabled, retention: settings.retention.seconds)
        guard settings.isEnabled else {
            timer?.invalidate()
            timer = nil
            return
        }
        prune()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.prune() }
        }
        timer?.tolerance = 60
    }

    func append(
        _ event: Event, root: String? = nil, chat: UUID? = nil, engine: Engine? = nil,
        terminal: UUID? = nil, reason: Reason? = nil
    ) {
        guard settings.isEnabled else { return }
        let entry = Entry(
            at: Date(), event: event, root: root, chat: chat, engine: engine,
            terminal: terminal, reason: reason)
        queue.async { [files] in
            do { try files.append(entry) } catch {
                Self.logger.error("Could not append Quick AI log metadata")
            }
        }
    }

    func writeHandoff(chat: UUID, text: String) async throws -> URL {
        try Task.checkCancellation()
        guard settings.isEnabled else { throw CocoaError(.fileWriteNoPermission) }
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        let url: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [files] in
                    do {
                        let url = try cancelled.withLock { cancelled in
                            guard !cancelled else { throw CancellationError() }
                            return try files.writeHandoff(chat: chat, text: text)
                        }
                        continuation.resume(returning: url)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
        try Task.checkCancellation()
        return url
    }

    func pruneFiles(olderThan cutoff: Date) {
        guard settings.isEnabled else { return }
        queue.async { [files] in
            do { try files.pruneFiles(olderThan: cutoff) } catch {
                Self.logger.error("Could not prune Quick AI handoff files")
            }
        }
    }

    private func prune() {
        guard settings.isEnabled else { return }
        queue.async { [files] in
            do { try files.prune() } catch {
                Self.logger.error("Could not prune Quick AI log or handoff files")
            }
        }
    }

    nonisolated static func prune(lines: [String], olderThan cutoff: Date) -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lines.filter { line in
            guard let entry = try? decoder.decode(Entry.self, from: Data(line.utf8)) else {
                return false
            }
            return entry.at >= cutoff
        }
    }
}
