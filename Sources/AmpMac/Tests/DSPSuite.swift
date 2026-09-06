//  Amp for Mac — MIT licensed. See LICENSE.
//  Each stage on its own, on synthesised signals.

import Foundation

enum DSPSuite {
    static let sr: Float = 48000
    static var suite: TestSuite { TestSuite(name: "DSP", cases: [
        TestCase(name: "gate mutes what is under the threshold") { t in
            var p = AmpParams(); p.gateThreshold = -30; p.gateRange = -80
            var g = Gate(); g.prepare(p, sampleRate: sr)
            let quiet = Synth.sine(200, seconds: 0.5, sampleRate: sr, level: dbToGain(-50))
            let out = quiet.map { g.process($0) }
            t.check(Measure.peakDb(out.suffix(4000)) < -100, "closed gate leaves \(Measure.peakDb(out.suffix(4000))) dB, expected under -100")
            let loud = Synth.sine(200, seconds: 0.2, sampleRate: sr, level: dbToGain(-10))
            let open = loud.map { g.process($0) }
            t.check(abs(Measure.peakDb(open.suffix(2000)) - (-10)) < 0.5, "open gate passes at \(Measure.peakDb(open.suffix(2000))) dB, expected -10")
            t.check(g.isOpen, "gate reports open")
        },
        TestCase(name: "gate holds through a snare's ring") { t in
            var p = AmpParams(); p.gateThreshold = -30; p.gateRelease = 80
            var g = Gate(); g.prepare(p, sampleRate: sr)
            let hit = Synth.oneHit(Synth.snare(sr), pad: Int(0.2 * sr))
            let out = hit.map { g.process($0) }
            // 40 ms into the hit the snare is well under -30 dB but the hold and release keep it audible.
            let i = Int(0.2 * sr) + Int(0.04 * sr)
            let inLevel = Measure.peakDb(hit[i..<i + 480]), outLevel = Measure.peakDb(out[i..<i + 480])
            t.check(outLevel > inLevel - 3, "ring kept: in \(inLevel) dB, out \(outLevel) dB")
        },
        TestCase(name: "compressor squashes by the ratio") { t in
            var p = AmpParams(); p.compThreshold = -18; p.compRatio = 4; p.compAttack = 5; p.compRelease = 80; p.compMakeup = 0; p.compMix = 100
            var c = Compressor(); c.prepare(p, sampleRate: sr)
            let x = Synth.sine(1000, seconds: 1, sampleRate: sr, level: dbToGain(-6))
            let out = x.map { c.process($0) }
            let level = Measure.peakDb(out.suffix(4800))
            // -6 dB in, 12 over the threshold at 4:1 leaves 3 over: about -15 dB, allowing for the follower.
            t.check(level > -17 && level < -13.5, "output \(level) dB, expected near -15")
            t.check(c.grDb > 6 && c.grDb < 11, "gain reduction \(c.grDb) dB")
        },
        TestCase(name: "compressor leaves quiet signals alone and mix 0 is dry") { t in
            var p = AmpParams(); p.compThreshold = -18; p.compRatio = 4; p.compMix = 100
            var c = Compressor(); c.prepare(p, sampleRate: sr)
            let x = Synth.sine(1000, seconds: 0.5, sampleRate: sr, level: dbToGain(-30))
            let out = x.map { c.process($0) }
            t.check(abs(Measure.peakDb(out.suffix(2400)) - (-30)) < 0.2, "under the threshold: \(Measure.peakDb(out.suffix(2400))) dB")
            p.compMix = 0; var d = Compressor(); d.prepare(p, sampleRate: sr)
            let loud = Synth.sine(1000, seconds: 0.2, sampleRate: sr, level: 0.9)
            let dry = loud.map { d.process($0) }
            t.check(zip(loud, dry).allSatisfy { abs($0 - $1) < 1e-6 }, "mix 0 passes the input unchanged")
        },
        TestCase(name: "shaper adds attack and takes sustain") { t in
            let hit = Synth.oneHit(Synth.kick(sr), pad: Int(0.3 * sr)); let start = Int(0.3 * sr)
            func run(attack: Float, sustain: Float) -> [Float] { var p = AmpParams(); p.attack = attack; p.sustain = sustain; var s = Shaper(); s.prepare(p, sampleRate: sr); return hit.map { s.process($0) } }
            let flat = run(attack: 0, sustain: 0), punchy = run(attack: 100, sustain: 0), dead = run(attack: 0, sustain: -100), long = run(attack: 0, sustain: 100)
            t.check(zip(hit, flat).allSatisfy { abs($0 - $1) < 1e-6 }, "0/0 is a pass-through")
            let onset = start..<start + Int(0.005 * sr), tail = start + Int(0.15 * sr)..<start + Int(0.25 * sr)
            t.check(Measure.peakDb(punchy[onset]) > Measure.peakDb(hit[onset]) + 3, "attack up: \(Measure.peakDb(punchy[onset])) vs \(Measure.peakDb(hit[onset]))")
            t.check(Measure.rms(dead[tail]) < Measure.rms(hit[tail]) * 0.6, "sustain down: \(Measure.rms(dead[tail])) vs \(Measure.rms(hit[tail]))")
            t.check(Measure.rms(long[tail]) > Measure.rms(hit[tail]) * 1.4, "sustain up: \(Measure.rms(long[tail])) vs \(Measure.rms(hit[tail]))")
        },
        TestCase(name: "tone shelves and peak move the right bands") { t in
            func level(_ b: Biquad, at f: Float) -> Float { var q = b; let out = Synth.sine(f, seconds: 0.5, sampleRate: sr, level: 0.5).map { q.process($0) }; return Measure.peakDb(out.suffix(4800)) - gainToDb(0.5) }
            let low = Biquad.lowShelf(90, gainDb: 6, sampleRate: sr)
            t.check(abs(level(low, at: 40) - 6) < 0.7, "low shelf at 40 Hz: \(level(low, at: 40))")
            t.check(abs(level(low, at: 3000)) < 0.3, "low shelf leaves 3 kHz: \(level(low, at: 3000))")
            let mid = Biquad.peak(1000, gainDb: 6, q: 1, sampleRate: sr)
            t.check(abs(level(mid, at: 1000) - 6) < 0.3, "peak at 1 kHz: \(level(mid, at: 1000))")
            t.check(abs(level(mid, at: 100)) < 0.3, "peak leaves 100 Hz: \(level(mid, at: 100))")
            let high = Biquad.highShelf(6000, gainDb: -6, sampleRate: sr)
            t.check(abs(level(high, at: 15000) + 6) < 0.7, "high shelf at 15 kHz: \(level(high, at: 15000))")
            t.check(abs(level(high, at: 200)) < 0.3, "high shelf leaves 200 Hz: \(level(high, at: 200))")
        },
        TestCase(name: "drive rounds the peaks and keeps them under full") { t in
            var p = AmpParams(); p.drive = 100; p.tone = 100
            var d = Drive(); d.prepare(p, sampleRate: sr)
            let x = Synth.sine(200, seconds: 0.3, sampleRate: sr, level: 0.9)
            let out = x.map { d.process($0) }
            let crest = Measure.rms(out.suffix(4800)) / Measure.peak(out.suffix(4800))
            t.check(crest > 0.8, "square-ish at full drive: rms/peak \(crest), a sine is 0.707")
            t.check(Measure.peak(out) < 1.2, "peak \(Measure.peak(out)) stays sane")
            p.drive = 0; var soft = Drive(); soft.prepare(p, sampleRate: sr)
            let gentle = Synth.sine(200, seconds: 0.3, sampleRate: sr, level: 0.3).map { soft.process($0) }
            t.check(abs(Measure.peakDb(gentle.suffix(4800)) - gainToDb(0.3)) < 1, "drive 0 is close to clean: \(Measure.peakDb(gentle.suffix(4800))) vs \(gainToDb(0.3))")
        },
        TestCase(name: "room rings after a hit and fades, and mix 0 is dry") { t in
            var p = AmpParams(); p.roomSize = 60; p.roomMix = 50
            var r = Room(); r.prepare(p, sampleRate: sr)
            var impulse = [Float](repeating: 0, count: Int(3 * sr)); impulse[0] = 1
            var l = [Float](), rr = [Float]()
            for x in impulse { let (a, b) = r.process(x); l.append(a); rr.append(b) }
            let s = Int(sr)
            let early = Measure.rms(l[Int(0.05 * sr)..<Int(0.15 * sr)]), mid = Measure.rms(l[s..<s + 4800]), late = Measure.rms(l[Int(2.8 * sr)..<Int(2.9 * sr)])
            t.check(early > 0.001, "tail exists: \(early)")
            t.check(mid < early && late < mid, "tail fades: \(early) > \(mid) > \(late)")
            t.check(late < 0.02, "tail is quiet by 2.8 s: \(late)")
            t.check(zip(l, rr).contains { abs($0 - $1) > 1e-4 }, "left and right differ")
            p.roomMix = 0; var dry = Room(); dry.prepare(p, sampleRate: sr)
            let kit = Synth.kit(seconds: 0.5, sampleRate: sr)
            t.check(kit.allSatisfy { let (a, b) = dry.process($0); return a == $0 && b == $0 }, "mix 0 passes both sides untouched")
        },
        TestCase(name: "gated room cuts off where the open room rings on") { t in
            let hit = Synth.oneHit(Synth.snare(sr), pad: Int(0.6 * sr)); let start = Int(0.6 * sr)
            func run(gated: Bool) -> [Float] {
                var p = AmpParams.flat; p.gateOn = true; p.gateThreshold = -30; p.gateRelease = 30; p.roomOn = true; p.roomSize = 80; p.roomMix = 60; p.roomGated = gated
                return Chain(sampleRate: sr, params: p).render(hit).l
            }
            let open = run(gated: false), gated = run(gated: true)
            let late = start + Int(0.35 * sr)..<start + Int(0.45 * sr)
            t.check(Measure.rms(open[late]) > 0.003, "open room still rings at 350 ms: \(Measure.rms(open[late]))")
            t.check(Measure.rms(gated[late]) < Measure.rms(open[late]) * 0.05, "gated room is cut: \(Measure.rms(gated[late])) vs \(Measure.rms(open[late]))")
        },
        TestCase(name: "limiter never lets a sample over the ceiling") { t in
            var lim = Limiter(); lim.prepare(sampleRate: sr)
            let hot = Synth.kit(seconds: 2, sampleRate: sr, level: 4)
            let out = hot.map { lim.process($0) }
            t.check(Measure.peak(out) <= lim.ceiling + 1e-6, "peak \(Measure.peak(out)) vs ceiling \(lim.ceiling)")
            t.check(Measure.peak(out) > lim.ceiling * 0.9, "it still reaches the ceiling")
        },
    ]) }
}
