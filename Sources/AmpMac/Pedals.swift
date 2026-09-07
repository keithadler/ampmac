//  Amp for Mac — MIT licensed. See LICENSE.
//
//  A two-slot pedal board. Slot 1 sits in front of the amp, where a drive or a compressor goes;
//  slot 2 after it, where a chorus, an echo or a tremolo goes. Any pedal fits either slot; the
//  slot decides where in the chain it is heard. Every preset ships with the two pedals a player of
//  that sound would most likely have on the floor, switched the way they would most likely leave them.

import Foundation

enum PedalKind: String, Codable, CaseIterable, Identifiable {
    case none, screamer, fuzz, squeeze, chorus, echo, tremolo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Empty"
        case .screamer: return "Screamer"
        case .fuzz: return "Fuzz"
        case .squeeze: return "Squeeze"
        case .chorus: return "Chorus"
        case .echo: return "Echo"
        case .tremolo: return "Tremolo"
        }
    }
    var blurb: String {
        switch self {
        case .none: return "Nothing in this slot."
        case .screamer: return "The green overdrive: a mid hump and soft clipping. Low drive and high level is the classic tight boost into a hot amp."
        case .fuzz: return "Hard clipping and a lot of it. On a drum kit it is a crush."
        case .squeeze: return "A compressor for sustain and even picking. Country and clean players leave it on."
        case .chorus: return "A second, slightly out-of-tune copy of the sound, for width."
        case .echo: return "A tape-style echo that darkens with every repeat. Around 110 ms with one repeat is a slapback."
        case .tremolo: return "The volume rises and falls. The amp-in-a-surf-record sound."
        }
    }
    /// Knob names, ranges and units, three per pedal.
    var knobs: [(String, ClosedRange<Float>, String)] {
        switch self {
        case .none: return []
        case .screamer: return [("Drive", 0...100, ""), ("Tone", 0...100, ""), ("Level", 0...100, "")]
        case .fuzz: return [("Fuzz", 0...100, ""), ("Tone", 0...100, ""), ("Level", 0...100, "")]
        case .squeeze: return [("Sustain", 0...100, ""), ("Attack", 0...100, ""), ("Level", 0...100, "")]
        case .chorus: return [("Rate", 0...100, ""), ("Depth", 0...100, ""), ("Mix", 0...100, "%")]
        case .echo: return [("Time", 40...1200, "ms"), ("Repeats", 0...90, "%"), ("Mix", 0...100, "%")]
        case .tremolo: return [("Rate", 0...100, ""), ("Depth", 0...100, "%"), ("Level", 0...100, "")]
        }
    }
    /// Where a fresh pedal of this kind starts.
    var defaults: (Float, Float, Float) {
        switch self {
        case .none: return (50, 50, 50)
        case .screamer: return (30, 55, 55)
        case .fuzz: return (50, 50, 50)
        case .squeeze: return (45, 50, 50)
        case .chorus: return (30, 40, 40)
        case .echo: return (380, 30, 20)
        case .tremolo: return (35, 50, 50)
        }
    }
}

struct PedalSlot: Codable, Equatable {
    var kind: PedalKind = .none
    var on = false
    var a: Float = 50, b: Float = 50, c: Float = 50
    init() {}
    init(_ kind: PedalKind, on: Bool, _ a: Float, _ b: Float, _ c: Float) { self.kind = kind; self.on = on; self.a = a; self.b = b; self.c = c }
    /// A fresh pedal of a kind, at its defaults, off.
    static func fresh(_ kind: PedalKind) -> PedalSlot { let d = kind.defaults; return PedalSlot(kind, on: false, d.0, d.1, d.2) }
    var title: String { kind.title }
}

/// One pedal's DSP. Mono in, mono out. `prepare` sets the knobs without clearing the delay lines,
/// so stomping and turning while playing does not click.
struct PedalBox {
    private(set) var slot = PedalSlot()
    private var sr: Float = 48000
    // drives
    private var pre: Float = 1, post: Float = 1, level: Float = 1
    private var hump = Biquad(), tone = Biquad(), dc = Biquad()
    // squeeze
    private var env = Envelope(), thresholdDb: Float = -25, ratio: Float = 4, makeup: Float = 1
    // chorus and echo
    private var buf: [Float] = [], idx = 0
    private var phase: Float = 0, inc: Float = 0
    private var base: Float = 0, depth: Float = 0, feedback: Float = 0, mix: Float = 0
    private var fbTone = Biquad()
    private var maxDelay = 0

    mutating func prepare(_ s: PedalSlot, sampleRate: Float) {
        if sr != sampleRate || buf.isEmpty {
            sr = sampleRate
            maxDelay = Int(1.25 * sr)
            buf = [Float](repeating: 0, count: maxDelay + 1)
            idx = 0
        }
        slot = s
        let a = s.a, b = s.b, c = s.c
        switch s.kind {
        case .none: break
        case .screamer:
            // Drive 0 is a clean boost, 100 is about 34 dB in; the level knob is ±12 dB around unity.
            pre = dbToGain(a / 100 * 34)
            post = pre > 1 ? 1 / powf(pre, 0.72) : 1
            level = dbToGain((c - 50) / 50 * 12)
            hump = Biquad.peak(720, gainDb: 3 + a / 100 * 6, q: 0.7, sampleRate: sr)
            tone = Biquad.lowPass(min(1200 * powf(2, b / 100 * 3), sr * 0.45), q: 0.7071, sampleRate: sr)
            dc = Biquad.highPass(40, q: 0.7071, sampleRate: sr)
        case .fuzz:
            pre = dbToGain(10 + a / 100 * 30)
            post = 1 / powf(pre, 0.85)
            level = dbToGain((c - 50) / 50 * 12)
            hump = Biquad.peak(1200, gainDb: 2, q: 0.6, sampleRate: sr)
            tone = Biquad.lowPass(min(900 * powf(2, b / 100 * 3.2), sr * 0.45), q: 0.7071, sampleRate: sr)
            dc = Biquad.highPass(60, q: 0.7071, sampleRate: sr)
        case .squeeze:
            thresholdDb = -12 - a / 100 * 26
            ratio = 3 + a / 100 * 3
            env.set(attackMs: 0.5 + b / 100 * 30, releaseMs: 160, sampleRate: sr)
            // Makeup puts a chord that was at about -18 dBFS back where it was.
            let restore = max(0, -18 - thresholdDb) * (1 - 1 / ratio)
            makeup = dbToGain(restore)
            level = dbToGain((c - 50) / 50 * 12)
        case .chorus:
            inc = (0.2 + a / 100 * 4.8) / sr
            base = 0.007 * sr
            depth = (0.0005 + b / 100 * 0.0035) * sr
            mix = min(max(c / 100, 0), 1)
        case .echo:
            base = min(max(a, 40), 1200) / 1000 * sr
            feedback = min(max(b / 100, 0), 0.9)
            mix = min(max(c / 100, 0), 1)
            fbTone = Biquad.lowPass(3500, q: 0.7071, sampleRate: sr)
        case .tremolo:
            inc = (0.5 + a / 100 * 11.5) / sr
            depth = min(max(b / 100, 0), 1)
            level = dbToGain((c - 50) / 50 * 12)
        }
    }

    mutating func reset() {
        for i in buf.indices { buf[i] = 0 }
        idx = 0; phase = 0
        hump.reset(); tone.reset(); dc.reset(); fbTone.reset()
        env = Envelope(); if slot.kind == .squeeze { prepare(slot, sampleRate: sr) }
    }

    @inline(__always) private func read(_ delay: Float) -> Float {
        // Linear interpolation from a circular buffer, `delay` samples behind the write head.
        let d = min(max(delay, 1), Float(maxDelay - 2))
        let whole = Int(d), frac = d - Float(whole)
        var i0 = idx - whole; if i0 < 0 { i0 += buf.count }
        var i1 = i0 - 1; if i1 < 0 { i1 += buf.count }
        return buf[i0] * (1 - frac) + buf[i1] * frac
    }
    @inline(__always) private mutating func write(_ x: Float) {
        buf[idx] = x; idx += 1; if idx == buf.count { idx = 0 }
    }

    @inline(__always) mutating func process(_ x: Float) -> Float {
        switch slot.kind {
        case .none: return x
        case .screamer:
            let y = tanhf(hump.process(x) * pre) * post
            return tone.process(dc.process(y)) * level
        case .fuzz:
            let z = hump.process(x) * pre
            let y = max(-1, min(1, z * 1.5 - z * z * z * 0.5)) * post
            return tone.process(dc.process(y)) * level
        case .squeeze:
            let lvl = gainToDb(env.track(abs(x)))
            let over = lvl - thresholdDb
            let gr: Float = over > 3 ? over * (1 - 1 / ratio) : over > -3 ? (1 - 1 / ratio) * (over + 3) * (over + 3) / 12 : 0
            return x * dbToGain(-gr) * makeup * level
        case .chorus:
            phase += inc; if phase >= 1 { phase -= 1 }
            let lfo = sinf(2 * Float.pi * phase)
            write(x)
            let wet = read(base + depth * (1 + lfo))
            return x * (1 - 0.35 * mix) + wet * 0.7 * mix
        case .echo:
            let d = read(base)
            write(x + fbTone.process(d) * feedback)
            return x + d * mix
        case .tremolo:
            phase += inc; if phase >= 1 { phase -= 1 }
            let g = 1 - depth * (0.5 - 0.5 * sinf(2 * Float.pi * phase))
            return x * g * level
        }
    }
}

extension Presets {
    /// The two pedals a player of this sound would most likely have on the floor, switched the way
    /// they would most likely leave them. Slot 1 is in front of the amp, slot 2 after it.
    static func defaultPedals(genre: String, instrument: Instrument, name: String = "") -> (PedalSlot, PedalSlot) {
        // A gentle sound in a crushed genre keeps the compressor, not the crush.
        if name == "Neo Soul" { return (PedalSlot(.squeeze, on: true, 40, 60, 58), PedalSlot(.echo, on: false, 140, 15, 18)) }
        if instrument == .guitar {
            switch genre {
            case "Clean": return (PedalSlot(.squeeze, on: true, 40, 50, 50), PedalSlot(.chorus, on: false, 30, 40, 40))
            case "Crunch": return (PedalSlot(.screamer, on: false, 35, 55, 60), PedalSlot(.echo, on: false, 380, 30, 20))
            case "Lead": return (PedalSlot(.screamer, on: true, 25, 55, 58), PedalSlot(.echo, on: true, 400, 35, 22))
            case "Metal": return (PedalSlot(.screamer, on: true, 10, 60, 65), PedalSlot(.echo, on: false, 350, 25, 15))
            case "Blues": return (PedalSlot(.screamer, on: true, 30, 45, 55), PedalSlot(.tremolo, on: false, 35, 50, 50))
            case "Country": return (PedalSlot(.squeeze, on: true, 55, 40, 50), PedalSlot(.echo, on: true, 110, 15, 30))
            case "Indie": return (PedalSlot(.fuzz, on: false, 50, 50, 50), PedalSlot(.chorus, on: true, 25, 45, 35))
            default: return (PedalSlot.fresh(.screamer), PedalSlot.fresh(.echo))
            }
        }
        switch genre {
        case "Hip Hop": return (PedalSlot(.fuzz, on: true, 35, 40, 60), PedalSlot(.echo, on: false, 90, 10, 15))
        case "Punk & Garage": return (PedalSlot(.fuzz, on: true, 45, 45, 56), PedalSlot(.echo, on: false, 120, 10, 15))
        case "Electronic": return (PedalSlot(.fuzz, on: true, 30, 55, 56), PedalSlot(.echo, on: true, 250, 40, 18))
        case "Reggae": return (PedalSlot(.squeeze, on: false, 40, 60, 50), PedalSlot(.echo, on: true, 375, 55, 28))
        case "Soul & Funk": return (PedalSlot(.squeeze, on: true, 45, 60, 56), PedalSlot(.tremolo, on: false, 40, 40, 50))
        case "Country & Folk": return (PedalSlot(.squeeze, on: false, 40, 60, 50), PedalSlot(.echo, on: true, 110, 12, 20))
        case "Blues", "Jazz": return (PedalSlot(.squeeze, on: false, 40, 60, 50), PedalSlot(.echo, on: false, 140, 15, 18))
        case "Metal": return (PedalSlot(.fuzz, on: false, 40, 45, 50), PedalSlot(.echo, on: false, 120, 10, 15))
        default: return (PedalSlot(.squeeze, on: false, 40, 60, 50), PedalSlot(.echo, on: false, 120, 10, 15))
        }
    }
}
