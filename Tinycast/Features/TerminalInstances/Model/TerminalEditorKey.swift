import Foundation

enum TerminalEditorKey {
    nonisolated static func controlLetter(_ letter: String, shift: Bool) -> String? {
        if shift { return letter == "z" ? "y" : nil }
        return ["s", "z", "x", "c", "v", "a", "f"].contains(letter) ? letter : nil
    }
}
