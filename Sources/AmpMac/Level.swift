//  Amp for Mac — MIT licensed. See LICENSE.
//
//  Level guidance. The raw input peak (before any knob in the amp) says whether the gain knob on
//  the interface is right; the auto level trims the amp's own input gain so hits land near target.

import Foundation

enum Level {
    enum Kind: String { case clipping, hot, good, quiet, silent }
    struct Advice: Equatable { let kind: Kind; let text: String }

    static let target: Float = -14          // where hits should peak after the input gain
    static let window: TimeInterval = 3     // how long a hit counts

    /// What to tell the player, from the loudest raw peak in the last few seconds.
    static func advice(rawPeakDb p: Float, interface: String = "the interface") -> Advice {
        if p >= -0.3 { return Advice(kind: .clipping, text: "Clipping at \(interface). Turn its gain knob down.") }
        if p > -6 { return Advice(kind: .hot, text: "Hot. A touch less gain on \(interface)'s knob.") }
        if p > -22 { return Advice(kind: .good, text: "Level is good.") }
        if p > -45 { return Advice(kind: .quiet, text: "Quiet. Turn the gain knob on \(interface) up.") }
        return Advice(kind: .silent, text: "Play something and the level guide wakes up.")
    }

    /// The next input-gain value: a quarter dB per step toward the target, only when there is a
    /// hit to judge by, never when the interface itself is clipping (no knob here fixes that),
    /// and never more than 12 dB either way: past that the gain belongs on the interface, or
    /// a microphone next to monitors feeds back.
    static func autoStep(gain: Float, rawPeakDb p: Float, target: Float = target) -> Float {
        guard p > -45, p < -0.3 else { return gain }
        let want = target - p
        let diff = want - gain
        guard abs(diff) > 1.5 else { return gain }
        let next = gain + (diff > 0 ? 0.25 : -0.25)
        return min(max(next, -12), 12)
    }

    /// Loudest raw peak over the last few seconds, one value per meter tick.
    struct Recent {
        private var samples: [(Date, Float)] = []
        mutating func add(_ db: Float, at now: Date = Date()) -> Float {
            samples.append((now, db)); samples.removeAll { now.timeIntervalSince($0.0) > Level.window }
            return samples.map(\.1).max() ?? -120
        }
        mutating func clear() { samples = [] }
    }
}
