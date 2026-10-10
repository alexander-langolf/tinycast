import SwiftUI

/// A block that enters with a reveal and leaves with a fade, holding its last content until then.
struct PaletteRevealSlot<Content: View>: View {
    private let reveal: PaletteMotion.Reveal
    private let isPresented: Bool
    private let key: AnyHashable
    private let fills: Bool
    private let content: () -> Content
    @State private var memory = Memory()
    @State private var fading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `key` replays the entrance while presented; `fills` keeps the space when there is nothing.
    init(
        _ reveal: PaletteMotion.Reveal, isPresented: Bool, key: AnyHashable = 0, fills: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.reveal = reveal
        self.isPresented = isPresented
        self.key = key
        self.fills = fills
        self.content = content
    }

    /// Written during `body` so the leaving frame and the replay trigger never lag a render.
    @MainActor private final class Memory {
        var last: Content?
        var wasPresented = false
        var entries = 0
        var key: AnyHashable = 0
        var exit = 0
    }

    private struct Trigger: Hashable {
        var key: AnyHashable
        var entries: Int
    }

    var body: some View {
        let shown = resolve()
        return ZStack(alignment: .top) {
            if let shown {
                shown
                    .paletteReveal(reveal, on: Trigger(key: memory.key, entries: memory.entries))
                    .opacity(fading ? 0 : 1)
                    .allowsHitTesting(isPresented)
                    .accessibilityHidden(!isPresented)
            } else if fills {
                Color.clear
            }
        }
        .onChange(of: isPresented) { _, presented in
            presented ? cancelExit() : beginExit()
        }
    }

    private func resolve() -> Content? {
        if isPresented {
            if !memory.wasPresented { memory.entries += 1 }
            if memory.key != key, memory.wasPresented { memory.entries += 1 }
            memory.key = key
            memory.wasPresented = true
            let live = content()
            memory.last = live
            return live
        }
        memory.wasPresented = false
        if reduceMotion { memory.last = nil }
        return memory.last
    }

    private func beginExit() {
        guard memory.last != nil else { return }
        memory.exit += 1
        let exit = memory.exit
        withAnimation(PaletteMotion.exit) {
            fading = true
        } completion: {
            guard memory.exit == exit, !memory.wasPresented else { return }
            memory.last = nil
            fading = false
        }
    }

    private func cancelExit() {
        memory.exit += 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { fading = false }
    }
}
