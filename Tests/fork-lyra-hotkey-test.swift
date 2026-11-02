import Carbon.HIToolbox
import Foundation

@main
struct ForkLyraHotKeyTest {
    static let actionKey = "hotkey.command:lyra-rewrite"

    static func main() throws {
        for includesShift in [false, true] {
            try seedsUnboundAction(includesShift: includesShift)
            try preservesExistingBinding(includesShift: includesShift)
            try preservesUnboundChoice(includesShift: includesShift)
            try preservesRebinding(includesShift: includesShift)
            try refusesOccupiedChord(includesShift: includesShift)
        }
        print("Lyra hotkey seeding passed")
    }

    static func isolated(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "com.tinycast.tests.lyra-hotkey.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    static func expectedBinding(includesShift: Bool) -> HotKeyBinding {
        .combo(KeyShortcut(carbonKeyCode: kVK_ANSI_R,
                           carbonModifiers: controlKey | optionKey | cmdKey | (includesShift ? shiftKey : 0)))
    }

    static func store(_ binding: HotKeyBinding, key: String, defaults: UserDefaults) throws {
        let json = String(decoding: try JSONEncoder().encode(binding), as: UTF8.self)
        defaults.set(json, forKey: key)
    }

    static func binding(_ defaults: UserDefaults, key: String = actionKey) throws -> HotKeyBinding? {
        guard let json = defaults.string(forKey: key) else { return nil }
        return try JSONDecoder().decode(HotKeyBinding.self, from: Data(json.utf8))
    }

    static func seed(_ defaults: UserDefaults, includesShift: Bool) {
        ForkLyraHotKey.seed(defaults: defaults, actionKey: actionKey, includesShift: includesShift)
    }

    static func seedsUnboundAction(includesShift: Bool) throws {
        try isolated { defaults in
            seed(defaults, includesShift: includesShift)
            let actual = try binding(defaults)
            precondition(actual == expectedBinding(includesShift: includesShift))
            precondition(defaults.bool(forKey: ForkLyraHotKey.seedKey))
        }
    }

    static func preservesExistingBinding(includesShift: Bool) throws {
        for existing in [HotKeyBinding.doubleTap(.command), .combo(KeyShortcut(
            carbonKeyCode: kVK_ANSI_L, carbonModifiers: controlKey | optionKey))] {
            try isolated { defaults in
                try store(existing, key: actionKey, defaults: defaults)
                let original = defaults.string(forKey: actionKey)
                seed(defaults, includesShift: includesShift)
                precondition(defaults.string(forKey: actionKey) == original)
                let actual = try binding(defaults)
                precondition(actual == existing)
                precondition(defaults.bool(forKey: ForkLyraHotKey.seedKey))
                defaults.removeObject(forKey: actionKey)
                seed(defaults, includesShift: includesShift)
                precondition(defaults.object(forKey: actionKey) == nil)
            }
        }
        isolated { defaults in
            defaults.set("unreadable binding", forKey: actionKey)
            seed(defaults, includesShift: includesShift)
            precondition(defaults.string(forKey: actionKey) == "unreadable binding")
        }
    }

    static func preservesUnboundChoice(includesShift: Bool) throws {
        isolated { defaults in
            defaults.set(true, forKey: ForkLyraHotKey.seedKey)
            seed(defaults, includesShift: includesShift)
            precondition(defaults.object(forKey: actionKey) == nil)
        }
        isolated { defaults in
            seed(defaults, includesShift: includesShift)
            defaults.removeObject(forKey: actionKey)
            seed(defaults, includesShift: includesShift)
            seed(defaults, includesShift: !includesShift)
            precondition(defaults.object(forKey: actionKey) == nil)
        }
    }

    static func preservesRebinding(includesShift: Bool) throws {
        try isolated { defaults in
            seed(defaults, includesShift: includesShift)
            let replacement = HotKeyBinding.doubleTap(.option)
            try store(replacement, key: actionKey, defaults: defaults)
            seed(defaults, includesShift: !includesShift)
            let actual = try binding(defaults)
            precondition(actual == replacement)
        }
    }

    static func refusesOccupiedChord(includesShift: Bool) throws {
        for ownerKey in ["hotkey.command:clipboard-history", "hotkey.app.test-app",
                         "hotkey.quicklink.test-id", "hotkey.extensionCommand.test-entry"] {
            try isolated { defaults in
                let occupied = expectedBinding(includesShift: includesShift)
                try store(occupied, key: ownerKey, defaults: defaults)
                let original = defaults.string(forKey: ownerKey)
                seed(defaults, includesShift: includesShift)
                precondition(defaults.object(forKey: actionKey) == nil)
                precondition(defaults.string(forKey: ownerKey) == original)
                precondition(defaults.bool(forKey: ForkLyraHotKey.seedKey))
                defaults.removeObject(forKey: ownerKey)
                seed(defaults, includesShift: includesShift)
                precondition(defaults.object(forKey: actionKey) == nil,
                             "A skipped seed must not claim the chord on a later launch")
            }
        }
        try isolated { defaults in
            try store(expectedBinding(includesShift: !includesShift),
                      key: "hotkey.command:clipboard-history", defaults: defaults)
            seed(defaults, includesShift: includesShift)
            let actual = try binding(defaults)
            precondition(actual == expectedBinding(includesShift: includesShift),
                         "Only the user's selected Hyper chord blocks seeding")
        }
    }
}
