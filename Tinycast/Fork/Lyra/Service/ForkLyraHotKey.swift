import Carbon.HIToolbox
import Foundation

enum ForkLyraHotKey {
    static let seedKey = "fork.lyra.panelHotKeySeeded"

    static func seed(defaults: UserDefaults, actionKey: String, includesShift: Bool) {
        guard !defaults.bool(forKey: seedKey) else { return }
        defaults.set(true, forKey: seedKey)
        guard defaults.object(forKey: actionKey) == nil else { return }

        let chord = KeyShortcut.hyperChord(includesShift: includesShift)
        let binding = HotKeyBinding.combo(KeyShortcut(
            carbonKeyCode: kVK_ANSI_R, carbonModifiers: KeyShortcut.carbonModifiers(from: chord)))
        let decoder = JSONDecoder()
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("hotkey.") {
            guard key != actionKey, let json = value as? String,
                let other = try? decoder.decode(HotKeyBinding.self, from: Data(json.utf8)) else { continue }
            if binding.conflicts(with: other) { return }
        }
        guard let data = try? JSONEncoder().encode(binding) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: actionKey)
    }
}
