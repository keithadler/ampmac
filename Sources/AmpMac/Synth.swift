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
}
