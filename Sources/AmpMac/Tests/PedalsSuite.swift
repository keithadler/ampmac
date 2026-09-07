//  Amp for Mac — MIT licensed. See LICENSE.

import Foundation

enum PedalsSuite {
    static func run(_ slot: PedalSlot, _ x: [Float], sr: Float = 48000) -> [Float] {
        var box = PedalBox(); box.prepare(slot, sampleRate: sr)
        return x.map { box.process($0) }
    }
    /// Share of the energy above `hz`, as a plain ratio.
    static func highShare(_ x: [Float], sr: Float, above hz: Float) -> Float {
        var hp = Biquad.highPass(hz, q: 0.7071, sampleRate: sr)
        let top = x.map { hp.process($0) }
        let all = Measure.rms(x); return all > 0 ? Measure.rms(top) / all : 0
    }
    static func peakAround(_ x: [Float], _ at: Int, _ span: Int) -> Float {
        var m: Float = 0
        for i in max(0, at - span)...min(x.count - 1, at + span) { m = max(m, abs(x[i])) }
        return m
    }
    static var suite: TestSuite { TestSuite(name: "Pedals", cases: [
        TestCase(name: "an empty slot and an off pedal pass the signal untouched") { t in
            let x = Synth.sine(220, seconds: 0.5, sampleRate: 48000, level: 0.3)
            t.check(run(PedalSlot(), x) == x, "empty is identity")
            var p = AmpParams.flat; p.pedal1 = PedalSlot(.fuzz, on: false, 80, 50, 50); p.pedal2 = PedalSlot(.echo, on: false, 300, 50, 50)
            let (l, _) = Chain(sampleRate: 48000, params: p).render(x)
            let (l0, _) = Chain(sampleRate: 48000, params: AmpParams.flat).render(x)
            t.check(l == l0, "off pedals are out of the chain")
        },
        TestCase(name: "the drives stay near unity at their defaults and darken with the tone knob") { t in
            let chords = Synth.chords(sampleRate: 48000)
            for kind in [PedalKind.screamer, .fuzz] {
                let y = run(PedalSlot.fresh(kind), chords)
                let g = gainToDb(Measure.rms(y) / Measure.rms(chords))
                t.check(abs(g) < 6, "\(kind.title) at defaults sits within 6 dB of unity, got \(g)")
                let dark = run(PedalSlot(kind, on: true, 60, 0, 50), chords), bright = run(PedalSlot(kind, on: true, 60, 100, 50), chords)
                let hd = highShare(dark, sr: 48000, above: 3000), hb = highShare(bright, sr: 48000, above: 3000)
                t.check(hb > hd, "\(kind.title) tone knob opens the top: \(hd) vs \(hb)")
            }
        },
        TestCase(name: "squeeze evens out loud and quiet") { t in
            let loud = Synth.sine(220, seconds: 0.5, sampleRate: 48000, level: 0.5), quiet = Synth.sine(220, seconds: 0.5, sampleRate: 48000, level: 0.05)
            let slot = PedalSlot(.squeeze, on: true, 60, 30, 50)
            let ratioIn = Measure.rms(loud) / Measure.rms(quiet)
            let ratioOut = Measure.rms(Array(run(slot, loud).suffix(12000))) / Measure.rms(Array(run(slot, quiet).suffix(12000)))
            t.check(ratioOut < ratioIn * 0.6, "the gap shrinks: \(ratioIn) in, \(ratioOut) out")
        },
        TestCase(name: "echo repeats at the set time, tremolo pumps at the set rate, chorus keeps the level") { t in
            let sr: Float = 48000
            var click = [Float](repeating: 0, count: Int(sr)); click[100] = 1
            let echo = run(PedalSlot(.echo, on: true, 250, 60, 100), click, sr: sr)
            let quarter = Int(0.25 * sr)
            let peak = peakAround(echo, quarter + 100, 5)
            t.check(peak > 0.5, "a repeat a quarter second later: \(peak)")
            let second = peakAround(echo, 2 * quarter + 100, 5)
            t.check(second > 0.1 && second < peak, "and a softer one after that: \(second)")
            let tone = Synth.sine(440, seconds: 2, sampleRate: sr, level: 0.3)
            let trem = run(PedalSlot(.tremolo, on: true, 100, 100, 50), tone, sr: sr)   // 12 Hz, full depth
            var env: [Float] = []; let win = Int(sr / 440 * 2)
            var i = 0
            while i + win <= trem.count { env.append(peakAround(trem, i + win / 2, win / 2)); i += win }
            var dips = 0
            if env.count > 2 { for k in 1..<(env.count - 1) where env[k] < env[k - 1] && env[k] <= env[k + 1] && env[k] < 0.15 { dips += 1 } }
            t.check(dips >= 20 && dips <= 28, "about 24 dips in two seconds at 12 Hz, got \(dips)")
            let chorus = run(PedalSlot.fresh(.chorus).with(on: true), tone, sr: sr)
            let g = gainToDb(Measure.rms(chorus) / Measure.rms(tone))
            t.check(abs(g) < 3, "chorus keeps the level within 3 dB, got \(g)")
        },
        TestCase(name: "every built-in preset has two pedals that fit its genre, and old JSON still loads") { t in
            for p in Presets.builtIn {
                t.check(p.params.pedal1.kind != .none && p.params.pedal2.kind != .none, "\(p.name) has both slots filled")
                let front: Set<PedalKind> = [.screamer, .fuzz, .squeeze], rear: Set<PedalKind> = [.chorus, .echo, .tremolo]
                t.check(front.contains(p.params.pedal1.kind) && rear.contains(p.params.pedal2.kind), "\(p.name): a drive or squeeze in front, a time effect behind")
            }
            let old = Presets.params(fromJSON: Data("{\"instrument\":\"guitar\",\"gain\":40}".utf8))
            t.check(old?.pedal1.kind == PedalKind.none && old?.pedal2.on == false, "JSON without pedals gets empty slots")
            let lead = Presets.named("Singing", user: [])!.params
            t.check(lead.pedal1.on && lead.pedal2.on, "a lead sound has its boost and echo on")
            let clean = Presets.named("Glass", user: [])!.params
            t.check(clean.pedal1.on && !clean.pedal2.on, "a clean sound has the compressor on and the chorus ready")
        },
    ]) }
}

extension PedalSlot {
    func with(on: Bool) -> PedalSlot { var s = self; s.on = on; return s }
}
