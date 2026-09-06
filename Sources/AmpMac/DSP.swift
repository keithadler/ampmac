//  Amp for Mac — MIT licensed. See LICENSE.
//
//  The drum chain, pure Swift, one sample at a time: gate, attack and sustain shaper, compressor,
//  three-band tone, drive, room and limiter. No CoreAudio in this file, so the tests run on
//  synthesised hits and never open a device.

import Foundation

@inline(__always) func dbToGain(_ db: Float) -> Float { powf(10, db / 20) }
@inline(__always) func gainToDb(_ g: Float) -> Float { 20 * log10f(max(g, 1e-9)) }

/// Every knob on the amp. Codable so presets are plain JSON.
struct AmpParams: Codable, Equatable {
    var inputGain: Float = 0            // dB
    var gateOn = true
    var gateThreshold: Float = -42      // dBFS; opens here, closes 6 dB lower
    var gateRelease: Float = 80         // ms
    var gateRange: Float = -80          // dB when closed
    var shapeOn = true
    var attack: Float = 0               // -100...100 %
    var sustain: Float = 0              // -100...100 %
    var compOn = true
    var compThreshold: Float = -18      // dBFS
    var compRatio: Float = 4
    var compAttack: Float = 5           // ms
    var compRelease: Float = 80         // ms
    var compMakeup: Float = 0           // dB
    var compMix: Float = 100            // % wet; less is parallel compression
    var eqOn = true
    var lowGain: Float = 0              // dB, shelf at 90 Hz
    var midGain: Float = 0              // dB, peak
    var midFreq: Float = 500            // Hz
    var presenceGain: Float = 0         // dB, peak at 3.5 kHz: the crack of the snare
    var highGain: Float = 0             // dB, shelf at 6 kHz
    var driveOn = false
    var drive: Float = 0                // 0...100
    var tone: Float = 50                // 0 dark ... 100 bright
    var roomOn = false
    var roomSize: Float = 40            // 0...100
    var roomMix: Float = 20             // %
    var roomTone: Float = 50            // 0 dark ... 100 bright
    var roomGated = false               // the room cuts with the gate: the 80s sound
    var outputGain: Float = 0           // dB
    var limiterOn = true

    /// Older JSON without a newer knob still loads; the knob takes its default.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func f(_ k: CodingKeys, _ d: Float) -> Float { (try? c.decodeIfPresent(Float.self, forKey: k)) ?? d }
        func b(_ k: CodingKeys, _ d: Bool) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? d }
        inputGain = f(.inputGain, 0); gateOn = b(.gateOn, true); gateThreshold = f(.gateThreshold, -42); gateRelease = f(.gateRelease, 80); gateRange = f(.gateRange, -80)
        shapeOn = b(.shapeOn, true); attack = f(.attack, 0); sustain = f(.sustain, 0)
        compOn = b(.compOn, true); compThreshold = f(.compThreshold, -18); compRatio = f(.compRatio, 4); compAttack = f(.compAttack, 5); compRelease = f(.compRelease, 80); compMakeup = f(.compMakeup, 0); compMix = f(.compMix, 100)
        eqOn = b(.eqOn, true); lowGain = f(.lowGain, 0); midGain = f(.midGain, 0); midFreq = f(.midFreq, 500); presenceGain = f(.presenceGain, 0); highGain = f(.highGain, 0)
        driveOn = b(.driveOn, false); drive = f(.drive, 0); tone = f(.tone, 50)
        roomOn = b(.roomOn, false); roomSize = f(.roomSize, 40); roomMix = f(.roomMix, 20); roomTone = f(.roomTone, 50); roomGated = b(.roomGated, false)
        outputGain = f(.outputGain, 0); limiterOn = b(.limiterOn, true)
    }

    /// Everything off: what goes in comes out, at unity.
    static var flat: AmpParams { var p = AmpParams(); p.gateOn = false; p.shapeOn = false; p.compOn = false; p.eqOn = false; p.driveOn = false; p.roomOn = false; p.limiterOn = false; return p }
}

/// One-pole envelope follower with separate attack and release.
struct Envelope {
    var value: Float = 0
    var attackCoef: Float = 0, releaseCoef: Float = 0
    mutating func set(attackMs: Float, releaseMs: Float, sampleRate: Float) {
        attackCoef = attackMs <= 0 ? 0 : expf(-1 / (attackMs * 0.001 * sampleRate))
        releaseCoef = releaseMs <= 0 ? 0 : expf(-1 / (releaseMs * 0.001 * sampleRate))
    }
    @inline(__always) mutating func track(_ x: Float) -> Float {
        let c = x > value ? attackCoef : releaseCoef
        value = c * value + (1 - c) * x
        return value
    }
}

/// A gain that glides to its target over a few milliseconds, so knob moves never click.
struct Smooth {
    var value: Float = 1, target: Float = 1, coef: Float = 0
    mutating func prepare(ms: Float, sampleRate: Float) { coef = expf(-1 / (ms * 0.001 * sampleRate)) }
    @inline(__always) mutating func next() -> Float { value = coef * value + (1 - coef) * target; return value }
    mutating func jump() { value = target }
}

/// RBJ biquad, transposed direct form II.
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0
    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
    mutating func reset() { z1 = 0; z2 = 0 }
    private static func make(_ b0: Float, _ b1: Float, _ b2: Float, _ a0: Float, _ a1: Float, _ a2: Float) -> Biquad {
        Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
    static func lowShelf(_ f: Float, gainDb: Float, sampleRate: Float) -> Biquad {
        let A = powf(10, gainDb / 40), w = 2 * Float.pi * f / sampleRate, c = cosf(w), s = sinf(w)
        let alpha = s / 2 * sqrtf(2), k = 2 * sqrtf(A) * alpha
        return make(A * ((A + 1) - (A - 1) * c + k), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - k),
                    (A + 1) + (A - 1) * c + k, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - k)
    }
    static func highShelf(_ f: Float, gainDb: Float, sampleRate: Float) -> Biquad {
        let A = powf(10, gainDb / 40), w = 2 * Float.pi * f / sampleRate, c = cosf(w), s = sinf(w)
        let alpha = s / 2 * sqrtf(2), k = 2 * sqrtf(A) * alpha
        return make(A * ((A + 1) + (A - 1) * c + k), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - k),
                    (A + 1) - (A - 1) * c + k, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - k)
    }
    static func peak(_ f: Float, gainDb: Float, q: Float, sampleRate: Float) -> Biquad {
        let A = powf(10, gainDb / 40), w = 2 * Float.pi * f / sampleRate, c = cosf(w), alpha = sinf(w) / (2 * q)
        return make(1 + alpha * A, -2 * c, 1 - alpha * A, 1 + alpha / A, -2 * c, 1 - alpha / A)
    }
    static func highPass(_ f: Float, q: Float, sampleRate: Float) -> Biquad {
        let w = 2 * Float.pi * f / sampleRate, c = cosf(w), alpha = sinf(w) / (2 * q)
        return make((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }
    static func lowPass(_ f: Float, q: Float, sampleRate: Float) -> Biquad {
        let w = 2 * Float.pi * f / sampleRate, c = cosf(w), alpha = sinf(w) / (2 * q)
        return make((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }
}

/// Noise gate with hysteresis and a short hold, so a snare's ring is not chopped.
struct Gate {
    var env = Envelope()
    var gain: Float = 0
    var holdLeft = 0, holdSamples = 0
    var openCoef: Float = 0, closeCoef: Float = 0
    var threshold: Float = 0, closeAt: Float = 0, floorGain: Float = 0
    var isOpen = false
    mutating func prepare(_ p: AmpParams, sampleRate: Float) {
        env.set(attackMs: 0.1, releaseMs: 30, sampleRate: sampleRate)
        openCoef = expf(-1 / (0.2 * 0.001 * sampleRate))
        closeCoef = expf(-1 / (max(p.gateRelease, 1) * 0.001 * sampleRate))
        holdSamples = Int(0.03 * sampleRate)
        threshold = dbToGain(p.gateThreshold); closeAt = dbToGain(p.gateThreshold - 6); floorGain = dbToGain(p.gateRange)
    }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        let e = env.track(abs(x))
        if e > threshold { isOpen = true; holdLeft = holdSamples }
        else if e < closeAt { if holdLeft > 0 { holdLeft -= 1 } else { isOpen = false } }
        let target: Float = isOpen ? 1 : floorGain
        let c = isOpen ? openCoef : closeCoef
        gain = c * gain + (1 - c) * target
        return x * gain
    }
}

/// Transient shaper. Attack compares a fast and a slow follower on the way up; sustain compares a
/// short and a long release on the way down. Each adds or removes up to 12 dB.
struct Shaper {
    var attackFast = Envelope(), attackSlow = Envelope(), sustainFast = Envelope(), sustainSlow = Envelope()
    var attackAmt: Float = 0, sustainAmt: Float = 0
    var lastGainDb: Float = 0
    mutating func prepare(_ p: AmpParams, sampleRate: Float) {
        attackFast.set(attackMs: 0.2, releaseMs: 30, sampleRate: sampleRate)
        attackSlow.set(attackMs: 20, releaseMs: 30, sampleRate: sampleRate)
        sustainFast.set(attackMs: 1, releaseMs: 40, sampleRate: sampleRate)
        sustainSlow.set(attackMs: 1, releaseMs: 400, sampleRate: sampleRate)
        attackAmt = p.attack / 100; sustainAmt = p.sustain / 100
    }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        let a = abs(x)
        let af = gainToDb(attackFast.track(a)), asl = gainToDb(attackSlow.track(a))
        let sf = gainToDb(sustainFast.track(a)), ssl = gainToDb(sustainSlow.track(a))
        let g = attackAmt * min(max(af - asl, 0), 12) + sustainAmt * min(max(ssl - sf, 0), 12)
        lastGainDb = g
        return g == 0 ? x : x * dbToGain(g)
    }
}

/// Feed-forward compressor with a 6 dB soft knee and a mix knob for parallel squash.
struct Compressor {
    var env = Envelope()
    var thresholdDb: Float = -18, ratio: Float = 4, makeup: Float = 1, mix: Float = 1
    let kneeDb: Float = 6
    var grDb: Float = 0
    mutating func prepare(_ p: AmpParams, sampleRate: Float) {
        env.set(attackMs: p.compAttack, releaseMs: p.compRelease, sampleRate: sampleRate)
        thresholdDb = p.compThreshold; ratio = max(p.compRatio, 1); makeup = dbToGain(p.compMakeup); mix = min(max(p.compMix / 100, 0), 1)
    }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        let level = gainToDb(env.track(abs(x)))
        let over = level - thresholdDb
        var gr: Float = 0
        if over > kneeDb / 2 { gr = over * (1 - 1 / ratio) }
        else if over > -kneeDb / 2 { let t = over + kneeDb / 2; gr = (1 - 1 / ratio) * t * t / (2 * kneeDb) }
        grDb = gr
        let wet = x * dbToGain(-gr) * makeup
        return x * (1 - mix) + wet * mix
    }
}

/// Soft saturation with a tone control after it. Drive 0 is a light touch; the section's own
/// switch is the true bypass.
struct Drive {
    var pre: Float = 1, post: Float = 1
    var lp = Biquad()
    mutating func prepare(_ p: AmpParams, sampleRate: Float) {
        let amount = min(max(p.drive / 100, 0), 1)
        pre = dbToGain(-6 + amount * 42)
        post = pre > 1 ? powf(pre, 0.55) : 1
        let f = 2000 * powf(2, min(max(p.tone / 100, 0), 1) * 3.3)
        lp = Biquad.lowPass(min(f, sampleRate * 0.45), q: 0.7071, sampleRate: sampleRate)
    }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        lp.process(tanhf(x * pre) / pre * post)
    }
}

/// Freeverb-shaped room: eight combs and four allpasses per side, offset for width.
struct Room {
    struct Comb {
        var buf: [Float]; var idx = 0; var store: Float = 0
        var feedback: Float = 0.8, damp1: Float = 0.5, damp2: Float = 0.5
        init(_ n: Int) { buf = [Float](repeating: 0, count: max(n, 1)) }
        @inline(__always) mutating func process(_ x: Float) -> Float {
            let out = buf[idx]
            store = out * damp2 + store * damp1
            buf[idx] = x + store * feedback
            idx += 1; if idx == buf.count { idx = 0 }
            return out
        }
    }
    struct AllPass {
        var buf: [Float]; var idx = 0
        init(_ n: Int) { buf = [Float](repeating: 0, count: max(n, 1)) }
        @inline(__always) mutating func process(_ x: Float) -> Float {
            let b = buf[idx]
            buf[idx] = x + b * 0.5
            idx += 1; if idx == buf.count { idx = 0 }
            return b - x
        }
    }
    var combsL: [Comb] = [], combsR: [Comb] = [], apL: [AllPass] = [], apR: [AllPass] = []
    var predelay: [Float] = [], pdIdx = 0
    var mix: Float = 0
    static let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    static let allpassTunings = [556, 441, 341, 225]
    mutating func prepare(_ p: AmpParams, sampleRate: Float) {
        let scale = sampleRate / 44100
        if combsL.isEmpty {
            combsL = Room.combTunings.map { Comb(Int(Float($0) * scale)) }
            combsR = Room.combTunings.map { Comb(Int(Float($0 + 23) * scale)) }
            apL = Room.allpassTunings.map { AllPass(Int(Float($0) * scale)) }
            apR = Room.allpassTunings.map { AllPass(Int(Float($0 + 23) * scale)) }
            predelay = [Float](repeating: 0, count: Int(0.008 * sampleRate))
        }
        let size = min(max(p.roomSize / 100, 0), 1)
        let fb: Float = 0.70 + size * 0.28, damp: Float = 0.85 - min(max(p.roomTone / 100, 0), 1) * 0.75
        for i in combsL.indices { combsL[i].feedback = fb; combsL[i].damp1 = damp; combsL[i].damp2 = 1 - damp }
        for i in combsR.indices { combsR[i].feedback = fb; combsR[i].damp1 = damp; combsR[i].damp2 = 1 - damp }
        mix = min(max(p.roomMix / 100, 0), 1)
    }
    mutating func reset() {
        for i in combsL.indices { combsL[i].buf = [Float](repeating: 0, count: combsL[i].buf.count); combsL[i].store = 0 }
        for i in combsR.indices { combsR[i].buf = [Float](repeating: 0, count: combsR[i].buf.count); combsR[i].store = 0 }
        for i in apL.indices { apL[i].buf = [Float](repeating: 0, count: apL[i].buf.count) }
        for i in apR.indices { apR[i].buf = [Float](repeating: 0, count: apR[i].buf.count) }
        predelay = [Float](repeating: 0, count: predelay.count)
    }
    /// Dry in, stereo out. With mix 0 the dry signal passes untouched on both sides.
    @inline(__always) mutating func process(_ x: Float) -> (Float, Float) {
        let (l, r) = wet(x); return (x + l, x + r)
    }
    /// The room alone, already scaled by the mix, so the chain can gate it.
    @inline(__always) mutating func wet(_ x: Float) -> (Float, Float) {
        guard mix > 0, !predelay.isEmpty else { return (0, 0) }
        let delayed = predelay[pdIdx]; predelay[pdIdx] = x; pdIdx += 1; if pdIdx == predelay.count { pdIdx = 0 }
        let input = delayed * 0.015
        var l: Float = 0, r: Float = 0
        for i in combsL.indices { l += combsL[i].process(input); r += combsR[i].process(input) }
        for i in apL.indices { l = apL[i].process(l); r = apR[i].process(r) }
        let wet = mix * 3
        return (l * wet, r * wet)
    }
}

/// Peak limiter: instant attack on the current sample, then a hard ceiling as the guarantee.
struct Limiter {
    var ceiling: Float = dbToGain(-0.5)
    var gain: Float = 1, releaseCoef: Float = 0
    var grDb: Float = 0
    mutating func prepare(sampleRate: Float) { releaseCoef = expf(-1 / (0.06 * sampleRate)) }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        let a = abs(x)
        let need: Float = a > ceiling ? ceiling / a : 1
        if need < gain { gain = need } else { gain = releaseCoef * gain + (1 - releaseCoef) }
        grDb = -gainToDb(gain)
        return max(-ceiling, min(ceiling, x * gain))
    }
}

/// The whole amp. Mono in, stereo out. Prepared for one sample rate; `apply` changes the knobs
/// without clearing the delay lines, so presets switch while you play.
final class Chain {
    private(set) var params = AmpParams()
    private(set) var sampleRate: Float = 48000
    private var inGain = Smooth(), outGain = Smooth()
    private var hpf = Biquad()
    private var gate = Gate(), shaper = Shaper(), comp = Compressor()
    private var low = Biquad(), mid = Biquad(), presence = Biquad(), high = Biquad()
    private var drive = Drive(), room = Room(), limiter = Limiter()
    // Meters, written per block by the audio thread.
    private(set) var inPeak: Float = 0, outPeak: Float = 0, gateOpen = false, compGr: Float = 0, limiterGr: Float = 0

    init(sampleRate: Float = 48000, params: AmpParams = AmpParams()) { prepare(sampleRate: sampleRate); apply(params); inGain.jump(); outGain.jump() }

    func prepare(sampleRate sr: Float) {
        sampleRate = sr
        inGain.prepare(ms: 5, sampleRate: sr); outGain.prepare(ms: 5, sampleRate: sr)
        hpf = Biquad.highPass(30, q: 0.7071, sampleRate: sr)
        limiter.prepare(sampleRate: sr)
        room = Room()
        apply(params)
        reset()
    }

    func apply(_ p: AmpParams) {
        params = p
        inGain.target = dbToGain(p.inputGain); outGain.target = dbToGain(p.outputGain)
        gate.prepare(p, sampleRate: sampleRate)
        shaper.prepare(p, sampleRate: sampleRate)
        comp.prepare(p, sampleRate: sampleRate)
        let (l1, l2, h1, h2) = (low.z1, low.z2, high.z1, high.z2); let (m1, m2, p1, p2) = (mid.z1, mid.z2, presence.z1, presence.z2)
        low = Biquad.lowShelf(90, gainDb: p.lowGain, sampleRate: sampleRate); low.z1 = l1; low.z2 = l2
        mid = Biquad.peak(min(max(p.midFreq, 40), sampleRate * 0.45), gainDb: p.midGain, q: 1.0, sampleRate: sampleRate); mid.z1 = m1; mid.z2 = m2
        presence = Biquad.peak(3500, gainDb: p.presenceGain, q: 1.2, sampleRate: sampleRate); presence.z1 = p1; presence.z2 = p2
        high = Biquad.highShelf(6000, gainDb: p.highGain, sampleRate: sampleRate); high.z1 = h1; high.z2 = h2
        drive.prepare(p, sampleRate: sampleRate)
        room.prepare(p, sampleRate: sampleRate)
    }

    func reset() {
        hpf.reset(); low.reset(); mid.reset(); presence.reset(); high.reset(); drive.lp.reset()
        gate = Gate(); gate.prepare(params, sampleRate: sampleRate)
        shaper = Shaper(); shaper.prepare(params, sampleRate: sampleRate)
        comp = Compressor(); comp.prepare(params, sampleRate: sampleRate)
        room.reset(); limiter = Limiter(); limiter.prepare(sampleRate: sampleRate)
        inPeak = 0; outPeak = 0; gateOpen = false; compGr = 0; limiterGr = 0
    }

    @inline(__always) func processSample(_ input: Float) -> (Float, Float) {
        var x = input * inGain.next()
        let p = params
        if p.gateOn { x = gate.process(x) }
        if p.shapeOn { x = shaper.process(x) }
        if p.compOn { x = comp.process(x) }
        if p.eqOn { x = high.process(presence.process(mid.process(low.process(hpf.process(x))))) }
        if p.driveOn { x = drive.process(x) }
        var l = x, r = x
        if p.roomOn {
            let (wl, wr) = room.wet(x)
            let g: Float = p.roomGated && p.gateOn ? gate.gain : 1
            l += wl * g; r += wr * g
        }
        let g = outGain.next(); l *= g; r *= g
        if p.limiterOn { l = limiter.process(l); r = limiter.process(r) }
        return (l, r)
    }

    /// One block. Input and outputs may not alias.
    func process(input: UnsafePointer<Float>, outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>, frames: Int) {
        var ip: Float = 0, op: Float = 0
        for i in 0..<frames {
            let x = input[i]; ip = max(ip, abs(x))
            let (l, r) = processSample(x)
            outL[i] = l; outR[i] = r
            op = max(op, max(abs(l), abs(r)))
        }
        inPeak = ip; outPeak = op; gateOpen = gate.isOpen; compGr = comp.grDb; limiterGr = limiter.grDb
    }

    /// Whole-buffer convenience for tests and the offline render.
    func render(_ mono: [Float]) -> (l: [Float], r: [Float]) {
        var l = [Float](repeating: 0, count: mono.count), r = l
        mono.withUnsafeBufferPointer { ip in
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                if let i = ip.baseAddress, let lb = lp.baseAddress, let rb = rp.baseAddress { process(input: i, outL: lb, outR: rb, frames: mono.count) }
            } }
        }
        return (l, r)
    }
}
