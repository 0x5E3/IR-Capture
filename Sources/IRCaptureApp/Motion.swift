#if os(macOS)
import SwiftUI

// Motion.swift: how the gear moves, after the desktop bench's (views/motion.js, rack.js; handoff 2026-11-09, 1.7 and D).
// Each part moves as the real part does, and nothing animates while nothing changes:
//   power clock     one moment everything powered warms from: the first time the interface plays or records in this
//                   session (a level check or a capture). The magic eyes, the nixies and the VU lamps warm over 6 s
//                   from it. A display lit later strikes at once.
//   VU needle       a damped spring, omega 16.5 rad/s, zeta 0.78: about 300 ms to 99 % of a step, 1.5 % overshoot
//                   (the VU standard's ballistics). SwiftUI's interpolating spring is the same equation and keeps the
//                   needle's speed when a new reading arrives mid-swing.
//   magic eye       the two sprite frames round the exact closure laid over each other (summed, not stacked), eased
//                   with a 25 ms attack and a 70 ms release.
//   jewel lamps     a filament: on in 90 ms, off in 240 ms with a tail. LEDs change at once.
//   nixies          a digit changes at once (a neon glow goes out in microseconds).
//   reels           at the display's own rate (ProMotion: 120 Hz); the speed model is in TapeDeck.swift.

enum SwellMotion {
    /// The power-on warm-up, seconds (the bench's SwellMotion.power END).
    static let warmup: Double = 6
    /// The VU needle's spring: omega 16.5 rad/s, zeta 0.78 (unit mass: stiffness omega^2, damping 2 zeta omega).
    static let vuSpring = Animation.interpolatingSpring(mass: 1, stiffness: 16.5 * 16.5, damping: 2 * 0.78 * 16.5)
    /// A filament lamp: heats in 90 ms, cools in 240 ms with a tail.
    static func filament(_ on: Bool) -> Animation { on ? .easeIn(duration: 0.09) : .easeOut(duration: 0.24) }
    /// The unlit picture under a lit one: it goes only once the lit one is fully up (so their shadows never double),
    /// and comes back at once when the lamp goes out (the lit picture then dies away over it).
    static func underLayer(_ on: Bool) -> Animation? { on ? .linear(duration: 0.001).delay(0.09) : nil }
    /// The magic eye's shadow wedge: attack (closing) 25 ms, release 70 ms.
    static func eye(closing: Bool) -> Animation { .easeOut(duration: closing ? 0.025 : 0.07) }

    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t)
    }
}

/// The power clock (one for the app). `onAt` is set once, when audio first runs; `warming` is true for the 6 s after,
/// so the powered views run their timelines only then.
final class PowerClock: ObservableObject {
    static let shared = PowerClock()
    @Published private(set) var onAt: Date?
    @Published private(set) var warming = false

    func powerOn() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.powerOn() }; return }
        guard onAt == nil else { return }
        onAt = Date(); warming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + SwellMotion.warmup + 0.15) { [weak self] in self?.warming = false }
    }

    /// Seconds since power-on; nil before it (the gear preview and the screenshots: everything already warm).
    func age(at date: Date) -> Double? { onAt.map { date.timeIntervalSince($0) } }

    /// The magic eye's glow, 0 … 1: nothing until 1.75 s, full at 6 s (the EM84's warm-up on the bench).
    func eyeGlow(at date: Date) -> Double {
        guard let a = age(at: date) else { return 1 }
        return SwellMotion.smooth(1.75, SwellMotion.warmup, a)
    }

    /// A nixie tube's glow, 0 … 1, over the warm-up; each tube a little uneven (`tube` picks its pace).
    func nixieGlow(at date: Date, tube: Int) -> Double {
        guard let a = age(at: date) else { return 1 }
        let pace: [Double] = [1.0, 0.84, 1.08, 0.93]
        return SwellMotion.smooth(0.25, SwellMotion.warmup * pace[((tube % 4) + 4) % 4], a)
    }

    /// A pilot lamp's filament behind a meter face: up in about 1.5 s, the last of it over the warm-up.
    func lampGlow(at date: Date) -> Double {
        guard let a = age(at: date) else { return 1 }
        return min(1, 0.82 * SwellMotion.smooth(0.05, 1.5, a) + 0.18 * SwellMotion.smooth(1.5, SwellMotion.warmup, a))
    }
}
#endif
