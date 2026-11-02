import Foundation
import Synchronization
import os

enum ForkLog {
    private static let mirror = Mutex<ForkJSONLMirror?>(nil)

    static func install(_ value: ForkJSONLMirror?) { mirror.withLock { $0 = value } }

    static func record(_ event: ForkEvent) {
        guard let data = try? event.line() else { return }
        let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
        let logger = Logger(subsystem: "com.tinycast", category: event.category.rawValue)
        switch event.level {
        case .debug: logger.debug("\(line, privacy: .public)")
        case .info: logger.info("\(line, privacy: .public)")
        case .warning: logger.warning("\(line, privacy: .public)")
        case .error: logger.error("\(line, privacy: .public)")
        }
        mirror.withLock { $0 }?.append(event)
    }
}
