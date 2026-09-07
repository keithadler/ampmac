//  Amp for Mac — MIT licensed. See LICENSE.
//
//  A synthesised kit: kick, snare and hat at 120 bpm. The tests hit the chain with it and the
//  `tone` command writes it to a file, so nothing needs a microphone to try the amp.

import Foundation

enum Synth {
    /// Deterministic noise so two runs give the same file.
    struct Noise { var s: UInt32 = 0x9E3779B9; mutating func next() -> Float { s = s &* 1664525 &+ 1013904223; return Float(Int32(bitPattern: s)) / Float(Int32.max) } }

    static func kick(_ sr: Float) -> [Float] {
        let n = Int(0.35 * sr); var out = [Float](repeating: 0, count: n); var ph: Float = 0
        for i in 0..<n {
            let t = Float(i) / sr
            let f = 50 + 120 * expf(-t * 35)
            ph += 2 * Float.pi * f / sr
            out[i] = sinf(ph) * expf(-t * 9) * 0.9 + (i < 60 ? 0.4 * expf(-Float(i) / 12) : 0)
        }
        return out
    }
    static func snare(_ sr: Float) -> [Float] {
        let n = Int(0.25 * sr); var out = [Float](repeating: 0, count: n); var noise = Noise(s: 7); var ph: Float = 0
        for i in 0..<n {
            let t = Float(i) / sr
            ph += 2 * Float.pi * 190 / sr
            out[i] = noise.next() * expf(-t * 22) * 0.55 + sinf(ph) * expf(-t * 30) * 0.5
        }
        return out
    }
    static func hat(_ sr: Float) -> [Float] {
        let n = Int(0.08 * sr); var out = [Float](repeating: 0, count: n); var noise = Noise(s: 3); var hp: Float = 0
        for i in 0..<n {
            let t = Float(i) / sr
            let x = noise.next(); let y = x - hp; hp = x   // crude high-pass
            out[i] = y * expf(-t * 60) * 0.25
        }
        return out
    }

    /// `seconds` of a rock beat. Mono, peaks near -3 dBFS.
    static func kit(seconds: Float, sampleRate sr: Float = 48000, level: Float = 0.7) -> [Float] {
        let total = Int(seconds * sr); var out = [Float](repeating: 0, count: total)
        let beat = Int(0.5 * sr)   // 120 bpm
        let k = kick(sr), s = snare(sr), h = hat(sr)
        func add(_ hit: [Float], at: Int, gain: Float) { for i in 0..<hit.count where at + i < total { out[at + i] += hit[i] * gain } }
        var bar = 0
        while bar * 4 * beat < total {
            let b0 = bar * 4 * beat
            add(k, at: b0, gain: 1); add(k, at: b0 + beat * 2, gain: 1); add(k, at: b0 + beat * 2 + beat / 2, gain: 0.7)
            add(s, at: b0 + beat, gain: 1); add(s, at: b0 + beat * 3, gain: 1)
            for e in 0..<8 { add(h, at: b0 + e * beat / 2, gain: e % 2 == 0 ? 1 : 0.6) }
            bar += 1
        }
        let peak = out.map(abs).max() ?? 1
        return out.map { $0 / max(peak, 1e-6) * level }
    }

    /// Four strummed chords, C G Am F, a bar each, for trying the Ear.
    static func chords(sampleRate sr: Float = 48000, barSeconds: Float = 1.5) -> [Float] {
        func strum(_ midis: [Int]) -> [Float] {
            let n = Int(barSeconds * sr); var out = [Float](repeating: 0, count: n)
            for m in midis {
                let f = 440 * powf(2, Float(m - 69) / 12)
                for (h, g) in [(1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15)] as [(Int, Float)] {
                    let w = 2 * Float.pi * f * Float(h) / sr
                    for i in 0..<n { out[i] += sinf(w * Float(i)) * g * expf(-Float(i) / (sr * 2)) }
                }
            }
            let peak = out.map(abs).max() ?? 1
            return out.map { $0 / peak * 0.5 }
        }
        return strum([48, 52, 55, 60]) + strum([43, 47, 50, 55]) + strum([45, 48, 52, 57]) + strum([41, 45, 48, 53])
    }

    /// A guitar chord as a magnetic pickup hears it: harmonics that fade out by the fifth, nothing
    /// worth speaking of above five kilohertz, and a soft attack. This is what an electric looks like
    /// to the detector.
    static func electric(sampleRate sr: Float = 48000, seconds: Float = 3) -> [Float] {
        let n = Int(seconds * sr); var out = [Float](repeating: 0, count: n)
        for m in [40, 47, 52, 56, 59, 64] {                       // an open E chord
            let f = 440 * powf(2, Float(m - 69) / 12)
            for h in 1...6 {
                let hf = f * Float(h)
                guard hf < 5000 else { break }
                let g = 1 / powf(Float(h), 1.6)                    // a coil rolls the harmonics off fast
                let w = 2 * Float.pi * hf / sr
                for i in 0..<n { out[i] += sinf(w * Float(i)) * g * expf(-Float(i) / (sr * 1.6)) }
            }
        }
        // The attack of a picked string, which swells rather than clicks.
        for i in 0..<min(n, Int(sr * 0.02)) { out[i] *= Float(i) / (sr * 0.02) }
        let peak = out.map(abs).max() ?? 1
        return out.map { $0 / peak * 0.4 }
    }

    /// The same chord through a piezo under the saddle: a boom from the body, the hard quack around
    /// three and a half kilohertz, air all the way up, and a pick attack that is a spike.
    static func acoustic(sampleRate sr: Float = 48000, seconds: Float = 3) -> [Float] {
        let n = Int(seconds * sr); var out = [Float](repeating: 0, count: n)
        for m in [40, 47, 52, 56, 59, 64] {
            let f = 440 * powf(2, Float(m - 69) / 12)
            for h in 1...160 {
                let hf = f * Float(h)
                guard hf < sr * 0.45 else { break }
                // Far more of the top survives, and there is a lift where the quack lives.
                var g = 1 / powf(Float(h), 0.85)
                if hf > 2800 && hf < 4200 { g *= 2.2 }
                let w = 2 * Float.pi * hf / sr
                for i in 0..<n { out[i] += sinf(w * Float(i)) * g * expf(-Float(i) / (sr * 1.4)) }
            }
        }
        var noise = Noise(s: 0x51ED2701)
        let body = 2 * Float.pi * 100 / sr
        for i in 0..<n {
            out[i] += sinf(body * Float(i)) * 0.5 * expf(-Float(i) / (sr * 0.5))   // the box resonating
            if i < Int(sr * 0.004) { out[i] += noise.next() * 1.2 }                // the pick, as a spike
        }
        let peak = out.map(abs).max() ?? 1
        return out.map { $0 / peak * 0.4 }
    }

    /// Flat noise, for measuring what a filter does rather than what a chord happens to contain.
    static func noise(seconds: Float, sampleRate sr: Float = 48000, level: Float = 0.25) -> [Float] {
        var n = Noise(s: 0x2545F491)
        return (0..<Int(seconds * sr)).map { _ in n.next() * level }
    }

    /// A single hit surrounded by silence, for transient tests.
    static func oneHit(_ hit: [Float], pad: Int) -> [Float] { [Float](repeating: 0, count: pad) + hit + [Float](repeating: 0, count: pad) }

    static func sine(_ f: Float, seconds: Float, sampleRate sr: Float = 48000, level: Float = 0.5) -> [Float] {
        (0..<Int(seconds * sr)).map { sinf(2 * Float.pi * f * Float($0) / sr) * level }
    }
}

enum Measure {
    static func peak(_ x: ArraySlice<Float>) -> Float { x.reduce(0) { max($0, abs($1)) } }
    static func peak(_ x: [Float]) -> Float { peak(x[...]) }
    static func rms(_ x: ArraySlice<Float>) -> Float { x.isEmpty ? 0 : sqrtf(x.reduce(0) { $0 + $1 * $1 } / Float(x.count)) }
    static func rms(_ x: [Float]) -> Float { rms(x[...]) }
    static func peakDb(_ x: ArraySlice<Float>) -> Float { gainToDb(peak(x)) }
    /// How loud a signal is below a frequency, against the whole.
    static func belowDb(_ x: [Float], _ f: Float, sampleRate: Float = 48000) -> Float {
        var lp = Biquad.lowPass(f, q: 0.7071, sampleRate: sampleRate)
        var lp2 = Biquad.lowPass(f, q: 0.7071, sampleRate: sampleRate)
        let bottom = x.map { lp2.process(lp.process($0)) }
        return gainToDb(rms(bottom) / max(rms(x), 1e-9))
    }

    /// How loud a signal is above a frequency, in dB relative to the whole. Enough to say "the speaker
    /// took the top off" without an FFT in the test suite.
    static func aboveDb(_ x: [Float], _ f: Float, sampleRate: Float = 48000) -> Float {
        var hp = Biquad.highPass(f, q: 0.7071, sampleRate: sampleRate)
        var hp2 = Biquad.highPass(f, q: 0.7071, sampleRate: sampleRate)
        let top = x.map { hp2.process(hp.process($0)) }
        return gainToDb(rms(top) / max(rms(x), 1e-9))
    }
}
