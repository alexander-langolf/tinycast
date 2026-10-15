import Foundation

/// Where Edit opens a file: the configured terminal command, or the embedded Monaco editor.
enum FileNavigatorEditorKind: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case monaco

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .monaco: "Monaco"
        }
    }
}
