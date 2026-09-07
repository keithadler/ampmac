//  Amp for Mac — MIT licensed. See LICENSE.
//
//  The guitar side. A drum channel and a guitar amp share most of their parts, which is why this file
//  is short: the gate, compressor, room and limiter are the ones already in DSP.swift. What a guitar
//  needs on top is the order they run in and three things a drum channel never has — gain stages that
//  clip one after another, a tone stack that interacts the way a passive one does, and a speaker.
//
//  The speaker is the whole difference. A distorted guitar with no cabinet is a wasp in a tin: all the
//  energy above 5 kHz that a real 12-inch driver simply cannot reproduce. Nothing here is a recording
//  of a cabinet; it is filters shaped like one, which is why the app still ships with no assets.

import Foundation

enum Instrument: String, Codable, CaseIterable, Identifiable {
    case drums, guitar
    var id: String { rawValue }
    var title: String { self == .drums ? "Drums" : "Guitar" }
}

/// Which speaker is in front of you. Sizes and cabinets, not anybody's brand.
enum Cab: String, Codable, CaseIterable, Identifiable {
    case fourByTwelve, twoByTwelve, oneByTwelve, oneByEight, direct
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fourByTwelve: return "4×12 stack"
        case .twoByTwelve: return "2×12 combo"
        case .oneByTwelve: return "1×12 combo"
        case .oneByEight: return "1×8 practice"
        case .direct: return "No speaker"
        }
    }
    /// low cut, the thump resonance, the cone dip, the presence peak, and where the driver gives up.
    var shape: (cut: Float, res: (Float, Float), dip: (Float, Float), air: (Float, Float), top: Float) {
        switch self {
        case .fourByTwelve: return (80,  (110, 4.5), (800, -4.5), (2600, 4.0), 4800)
        case .twoByTwelve:  return (90,  (130, 3.5), (700, -3.0), (3000, 3.5), 5200)
        case .oneByTwelve:  return (100, (150, 2.5), (900, -2.5), (3200, 3.0), 5600)
        case .oneByEight:   return (170, (230, 3.0), (1000, -5.0), (3000, 2.0), 4200)
        case .direct:       return (20,  (100, 0),   (800, 0),     (3000, 0),   20000)
        }
    }
}

/// Clipping at twice the sample rate. Distortion makes harmonics above half the sample rate, and those
/// fold back down the spectrum as tones that were never played: the metallic edge on cheap amp plugins.
/// Running the clipper at 2× and filtering on the way in and out puts most of that where it belongs.
struct Oversampled2x {
    var up1 = Biquad(), up2 = Biquad(), down1 = Biquad(), down2 = Biquad()
    mutating func prepare(sampleRate: Float) {
        let corner = min(sampleRate * 0.45, 20000)
        up1 = Biquad.lowPass(corner, q: 0.7071, sampleRate: sampleRate * 2)
        up2 = Biquad.lowPass(corner, q: 0.7071, sampleRate: sampleRate * 2)
        down1 = Biquad.lowPass(corner, q: 0.7071, sampleRate: sampleRate * 2)
        down2 = Biquad.lowPass(corner, q: 0.7071, sampleRate: sampleRate * 2)
    }
    mutating func reset() { up1.reset(); up2.reset(); down1.reset(); down2.reset() }
    /// One sample in, one out, with `shape` run twice in between.
    @inline(__always) mutating func process(_ x: Float, _ shape: (Float) -> Float) -> Float {
        // Zero stuffing doubles the rate; the filters remove the image it creates, and the 2 puts back
        // the level that stuffing a zero takes away.
        let a = up2.process(up1.process(x * 2))
        let b = up2.process(up1.process(0))
        let ya = down2.process(down1.process(shape(a)))
        _ = down2.process(down1.process(shape(b)))
        return ya
    }
}

/// Valve-shaped clipping: it squashes the top harder than the bottom, which is what puts even
/// harmonics in and is most of why one amp sounds warm and another sounds like a fuzz box.
@inline(__always) func softClip(_ x: Float, asymmetry: Float = 0.25) -> Float {
    let bias = asymmetry * 0.35
    let y = tanhf(x + bias) - tanhf(bias)
    return y * (1 / (1 - tanhf(bias) * tanhf(bias)))
}

/// Two gain stages with the tone controls' worth of filtering between them, the way a real preamp is
/// laid out. Cutting bass before the distortion rather than after is what keeps a high gain sound
/// tight instead of muddy: the low strings otherwise use up all the headroom.
struct Preamp {
    var tight = Biquad(), bright = Biquad(), interstage = Biquad(), fizz = Biquad()
    var stage1 = Oversampled2x(), stage2 = Oversampled2x()
    var driveA: Float = 1, driveB: Float = 1, makeup: Float = 1, stages = 2

    mutating func prepare(_ p: AmpParams, sampleRate: Float) {
        let g = min(max(p.gain / 100, 0), 1)
        // Two stages, sharing the work, so the second is always fed something already shaped.
        driveA = dbToGain(-3 + g * 30)
        driveB = dbToGain(-6 + g * 26)
        stages = g > 0.45 ? 2 : 1
        // The bass cut moves up as the gain goes up: clean amps keep their bottom end.
        tight = Biquad.highPass(70 + g * 90, q: 0.7071, sampleRate: sampleRate)
        // A bright cap: sparkle at low gain that gets out of the way when you turn up.
        bright = Biquad.highShelf(2000, gainDb: p.bright ? (1 - g) * 8 : 0, sampleRate: sampleRate)
        interstage = Biquad.highPass(120, q: 0.7071, sampleRate: sampleRate)
        fizz = Biquad.lowPass(min(9000, sampleRate * 0.45), q: 0.7071, sampleRate: sampleRate)
        stage1.prepare(sampleRate: sampleRate); stage2.prepare(sampleRate: sampleRate)
        // Loud presets should not also be the loudest: the gain knob buys dirt, not volume.
        makeup = dbToGain(-(g * 16))
    }
    mutating func reset() { tight.reset(); bright.reset(); interstage.reset(); fizz.reset(); stage1.reset(); stage2.reset() }

    @inline(__always) mutating func process(_ input: Float) -> Float {
        var x = bright.process(tight.process(input))
        x = stage1.process(x * driveA) { softClip($0, asymmetry: 0.3) }
        if stages > 1 {
            x = interstage.process(x)
            x = stage2.process(x * driveB) { softClip($0, asymmetry: 0.15) }
        }
        return fizz.process(x) * makeup
    }
}

/// Bass, middle and treble, the way a passive stack behaves: the controls pull against each other, and
/// scooping the middle takes the whole signal down with it, which is why a scooped amp always needs
/// turning up. The level that costs is put back so the knobs change the tone and not the volume.
struct ToneStack {
    var low = Biquad(), mid = Biquad(), high = Biquad(), tilt = Biquad()
    var makeup: Float = 1

    mutating func prepare(_ p: AmpParams, sampleRate: Float) {
        let b = min(max(p.bass / 100, 0), 1), m = min(max(p.middle / 100, 0), 1), t = min(max(p.treble / 100, 0), 1)
        low = Biquad.lowShelf(120, gainDb: (b - 0.5) * 20, sampleRate: sampleRate)
        // The mid is where the stack's character lives, and it is not symmetrical: cutting goes deeper
        // than boosting, because that is what the network does.
        let midDb = m < 0.5 ? (m - 0.5) * 26 : (m - 0.5) * 14
        mid = Biquad.peak(560, gainDb: midDb, q: 0.75, sampleRate: sampleRate)
        high = Biquad.highShelf(2200, gainDb: (t - 0.5) * 20, sampleRate: sampleRate)
        // Bass and treble at once lift the ends together, the interaction a real stack has.
        tilt = Biquad.peak(1000, gainDb: -((b + t) / 2 - 0.5) * 4, q: 0.6, sampleRate: sampleRate)
        makeup = dbToGain(-(midDb < 0 ? midDb * 0.45 : midDb * 0.25) - (b - 0.5) * 3)
    }
    mutating func reset() { low.reset(); mid.reset(); high.reset(); tilt.reset() }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        tilt.process(high.process(mid.process(low.process(x)))) * makeup
    }
}

/// The power amp: softer clipping than the preamp, and sag. A valve rectifier cannot supply a big
/// chord instantly, so the amp ducks and swells back over a few tens of milliseconds. It is the part
/// people mean when they say an amp feels alive rather than sounds different.
struct PowerAmp {
    var env = Envelope()
    var sagAmount: Float = 0, drive: Float = 1
    var clip = Oversampled2x()
    var presence = Biquad()

    mutating func prepare(_ p: AmpParams, sampleRate: Float) {
        env.set(attackMs: 12, releaseMs: 140, sampleRate: sampleRate)
        sagAmount = min(max(p.sag / 100, 0), 1)
        drive = dbToGain(min(max(p.master / 100, 0), 1) * 14 - 2)
        clip.prepare(sampleRate: sampleRate)
        presence = Biquad.peak(4200, gainDb: (min(max(p.guitarPresence / 100, 0), 1) - 0.5) * 12, q: 0.9, sampleRate: sampleRate)
    }
    mutating func reset() { env.value = 0; clip.reset(); presence.reset() }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        let level = env.track(abs(x))
        let sag = 1 - sagAmount * min(0.45, level * 0.9)
        return clip.process(presence.process(x) * drive * sag) { softClip($0, asymmetry: 0.08) } * (1 / max(drive * 0.5, 0.5))
    }
}

/// The speaker. Four filters and a steep top: a low cut because a guitar cabinet has no bottom octave,
/// a resonance where the cone and the box argue, the dip that gives a 12-inch its voice, a presence
/// peak, and then the fall off a driver has above about 5 kHz. That last one is the whole trick.
struct Cabinet {
    var cut = Biquad(), res = Biquad(), dip = Biquad(), air = Biquad(), top1 = Biquad(), top2 = Biquad()
    var bypass = false

    mutating func prepare(_ cab: Cab, sampleRate: Float) {
        bypass = cab == .direct
        let s = cab.shape
        cut = Biquad.highPass(s.cut, q: 0.8, sampleRate: sampleRate)
        res = Biquad.peak(s.res.0, gainDb: s.res.1, q: 1.4, sampleRate: sampleRate)
        dip = Biquad.peak(s.dip.0, gainDb: s.dip.1, q: 1.1, sampleRate: sampleRate)
        air = Biquad.peak(s.air.0, gainDb: s.air.1, q: 1.3, sampleRate: sampleRate)
        let top = min(s.top, sampleRate * 0.45)
        top1 = Biquad.lowPass(top, q: 0.9, sampleRate: sampleRate)      // two in series, so the fall is
        top2 = Biquad.lowPass(top * 1.15, q: 0.6, sampleRate: sampleRate) // as steep as a real driver's
    }
    mutating func reset() { cut.reset(); res.reset(); dip.reset(); air.reset(); top1.reset(); top2.reset() }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        guard !bypass else { return x }
        return top2.process(top1.process(air.process(dip.process(res.process(cut.process(x))))))
    }
}

// MARK: Which guitar is plugged in

enum InputKind: String, Codable, CaseIterable, Identifiable {
    case auto, electric, acoustic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Work it out"
        case .electric: return "Electric"
        case .acoustic: return "Acoustic"
        }
    }
}

/// Telling an acoustic from an electric, by listening.
///
/// A magnetic pickup is a coil, and a coil is an inductor: it cannot produce much above about five
/// kilohertz, and it resonates somewhere between two and three. A piezo under a saddle, or a mic in
/// front of a soundhole, has real energy at eight and twelve kilohertz and a hard pick transient with
/// it. So the two are told apart on how much of the signal lives above five kilohertz, which is a
/// difference of ten decibels or more between them and does not depend on what is being played.
///
/// It only counts while something is actually being played, and it changes its mind slowly, because a
/// guitar sound that switches character mid-bar is worse than one that is wrong for two seconds.
struct InputSense {
    var high = Biquad(), low = Biquad()
    var highEnv = Envelope(), lowEnv = Envelope(), level = Envelope()
    /// The running answer, 0 fully electric, 1 fully acoustic.
    private(set) var acousticness: Float = 0
    private(set) var heard: InputKind = .electric
    /// The last share of energy measured in the top, kept for calibration and for the window.
    private(set) var ratio: Float = 0
    var sampleRate: Float = 48000

    /// Above this share of energy in the top, it is not coming out of a magnetic pickup. Measured
    /// rather than guessed: a synthesised electric chord sits at 0.006 and an acoustic at 0.22, so
    /// these sit an easy distance from both, with a gap between them so the answer cannot flutter.
    static let acousticAbove: Float = 0.09
    static let electricBelow: Float = 0.05
    /// Quieter than this and there is nothing to judge.
    static let floor: Float = 0.002

    mutating func prepare(sampleRate sr: Float) {
        sampleRate = sr
        high = Biquad.highPass(5500, q: 0.7071, sampleRate: sr)
        low = Biquad.lowPass(5500, q: 0.7071, sampleRate: sr)
        highEnv.set(attackMs: 30, releaseMs: 400, sampleRate: sr)
        lowEnv.set(attackMs: 30, releaseMs: 400, sampleRate: sr)
        level.set(attackMs: 10, releaseMs: 600, sampleRate: sr)
    }
    mutating func reset() {
        high.reset(); low.reset(); highEnv.value = 0; lowEnv.value = 0; level.value = 0
        acousticness = 0; heard = .electric
    }

    @inline(__always) mutating func observe(_ x: Float) {
        let l = level.track(abs(x))
        let h = highEnv.track(abs(high.process(x)))
        let lo = lowEnv.track(abs(low.process(x)))
        guard l > InputSense.floor else { return }
        // The top against the whole, which is a ratio and so does not care how hard you play.
        ratio = h / max(h + lo, 1e-9)
        // Two seconds to change its mind, at the rate this is called.
        let step = 1 / (sampleRate * 2)
        let target: Float = ratio > InputSense.acousticAbove ? 1 : (ratio < InputSense.electricBelow ? 0 : acousticness)
        acousticness += (target - acousticness) * step * 4
        acousticness = min(1, max(0, acousticness))
        if acousticness > 0.65 { heard = .acoustic } else if acousticness < 0.35 { heard = .electric }
    }

    /// What the chain should use, given the setting and what has been heard.
    func resolve(_ setting: InputKind) -> InputKind { setting == .auto ? heard : setting }
}

/// Making an acoustic behave like an electric.
///
/// The problem is not that an acoustic is too bright. It is that a piezo has three faults a magnetic
/// pickup does not: a boom under a hundred hertz from the body, a narrow hard "quack" around three and
/// a half kilohertz that turns to broken glass the moment you distort it, and an octave of air above
/// six kilohertz that a guitar amp has never once been asked to reproduce. Take those three away and
/// put a coil's own resonance in their place, and the amp downstream behaves as though a Stratocaster
/// were plugged into it. Everything after this stage is then the ordinary amp.
struct PickupSim {
    var body = Biquad(), quack = Biquad(), resonance = Biquad(), top1 = Biquad(), top2 = Biquad()
    var comp = Envelope()
    var makeup: Float = 1

    mutating func prepare(_ p: AmpParams, sampleRate: Float) {
        // Where along the string the coil is: neck is round and low, bridge is thin and bright.
        let position = min(max(p.pickup / 100, 0), 1)
        let resFreq = 2000 + position * 1400
        body = Biquad.highPass(95 + position * 45, q: 0.7071, sampleRate: sampleRate)
        quack = Biquad.peak(3400, gainDb: -7, q: 2.8, sampleRate: sampleRate)
        resonance = Biquad.peak(resFreq, gainDb: 5, q: 0.9, sampleRate: sampleRate)
        let top = min(5200, sampleRate * 0.45)
        top1 = Biquad.lowPass(top, q: 0.85, sampleRate: sampleRate)
        top2 = Biquad.lowPass(top * 1.2, q: 0.6, sampleRate: sampleRate)
        comp.set(attackMs: 4, releaseMs: 120, sampleRate: sampleRate)
        makeup = dbToGain(2)
    }
    mutating func reset() { body.reset(); quack.reset(); resonance.reset(); top1.reset(); top2.reset(); comp.value = 0 }

    @inline(__always) mutating func process(_ x: Float) -> Float {
        var y = body.process(x)
        y = quack.process(y)
        y = resonance.process(y)
        y = top2.process(top1.process(y))
        // A piezo's attack is a spike where a pickup's is a swell. Taking the top off the transient is
        // what stops every chord arriving as a click.
        let env = comp.track(abs(y))
        let over = max(0, env - 0.25)
        return y * (1 / (1 + over * 2.5)) * makeup
    }
}
