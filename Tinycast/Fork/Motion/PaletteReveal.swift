import SwiftUI

/// Plays one block's entrance: hidden, a stagger, then a fade and a slide home.
struct PaletteReveal: ViewModifier {
    let reveal: PaletteMotion.Reveal
    let trigger: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let offset = reduceMotion ? .zero : reveal.offset
        let delay = reduceMotion ? 0 : reveal.delay
        let duration = reduceMotion ? PaletteMotion.fadeDuration : PaletteMotion.revealDuration
        // Rests at 1, so a view that never replays renders exactly as it would without this.
        return content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, progress in
            view
                .opacity(progress)
                .offset(x: offset.width * (1 - progress), y: offset.height * (1 - progress))
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.0)
                LinearKeyframe(0.0, duration: delay)
                LinearKeyframe(1.0, duration: duration, timingCurve: PaletteMotion.revealCurve)
            }
        }
    }
}

/// Replays when its view is inserted, for a block that comes and goes with a branch.
private struct PaletteRevealOnAppear: ViewModifier {
    let reveal: PaletteMotion.Reveal
    @State private var appearances = 0

    func body(content: Content) -> some View {
        content
            .modifier(PaletteReveal(reveal: reveal, trigger: appearances))
            .onAppear { appearances += 1 }
    }
}

extension View {
    /// Enters with `reveal` each time the view is inserted.
    func paletteReveal(_ reveal: PaletteMotion.Reveal) -> some View {
        modifier(PaletteRevealOnAppear(reveal: reveal))
    }

    /// Enters with `reveal` each time `key` changes; a view that stays put and changes content.
    func paletteReveal(_ reveal: PaletteMotion.Reveal, on key: some Hashable) -> some View {
        modifier(PaletteReveal(reveal: reveal, trigger: key))
    }
}
