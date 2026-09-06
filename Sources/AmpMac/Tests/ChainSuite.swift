//  Amp for Mac — MIT licensed. See LICENSE.
//  The whole amp: bypass is honest, silence stays silent, presets change the sound.

import Foundation

enum ChainSuite {
    static var suite: TestSuite { TestSuite(name: "Chain", cases: [
        TestCase(name: "flat chain is a pass-through") { t in
            let c = Chain(sampleRate: 48000, params: .flat)
            let kit = Synth.kit(seconds: 1, sampleRate: 48000)
            let (l, r) = c.render(kit)
            // Nothing in the way but the 5 ms gain glide at the very start.
            let diff = zip(kit.suffix(24000), l.suffix(24000)).map { abs($0 - $1) }.max() ?? 1
            t.check(diff < 0.02, "largest difference \(diff)")
            t.check(l == r, "both sides equal without a room")
        },
        TestCase(name: "silence in, silence out on every preset") { t in
            for p in Presets.builtIn {
                let c = Chain(sampleRate: 48000, params: p.params)
                let (l, r) = c.render([Float](repeating: 0, count: 48000))
                t.check(Measure.peak(l) < 1e-6 && Measure.peak(r) < 1e-6, "\(p.name) makes noise from nothing: \(Measure.peak(l))")
            }
        },
        TestCase(name: "every preset changes the kit and stays under the ceiling") { t in
            let kit = Synth.kit(seconds: 2, sampleRate: 48000)
            var sounds = Set<Int>()
            for p in Presets.builtIn {
                let c = Chain(sampleRate: 48000, params: p.params)
                let (l, r) = c.render(kit)
                let peak = max(Measure.peak(l), Measure.peak(r))
                t.check(peak > 0.05, "\(p.name) is audible")
                t.check(peak <= dbToGain(-0.5) + 1e-5, "\(p.name) peaks at \(peak)")
                let diff = zip(kit, l).map { abs($0 - $1) }.max() ?? 0
                t.check(diff > 0.01, "\(p.name) does something")
                sounds.insert(Int(Measure.rms(l) * 1e5))
            }
            t.check(sounds.count == Presets.builtIn.count, "presets sound different from each other: \(sounds.count) of \(Presets.builtIn.count)")
        },
        TestCase(name: "knobs change without a click") { t in
            var flat = AmpParams.flat
            let same = Chain(sampleRate: 48000, params: flat), changed = Chain(sampleRate: 48000, params: flat)
            let tone = Synth.sine(100, seconds: 1, sampleRate: 48000, level: 0.5)
            _ = same.render(Array(tone[0..<24000])); _ = changed.render(Array(tone[0..<24000]))
            flat.outputGain = -12; changed.apply(flat)
            let a = same.render(Array(tone[24000..<48000])).l, b = changed.render(Array(tone[24000..<48000])).l
            // The first sample after the change is still at the old gain; 50 ms later it is 12 dB down.
            t.check(abs(a[0] - b[0]) < 0.005, "first sample after the change moved by \(abs(a[0] - b[0]))")
            var step: Float = 0
            for i in 0..<200 { let d0 = a[i] - b[i], d1 = a[i + 1] - b[i + 1]; step = max(step, abs(d0 - d1)) }
            t.check(step < 0.005, "gain glides: largest step in the difference \(step)")
            t.check(abs(Measure.peakDb(b.suffix(4800)) - Measure.peakDb(a.suffix(4800)) + 12) < 0.1, "settles 12 dB down: \(Measure.peakDb(b.suffix(4800))) vs \(Measure.peakDb(a.suffix(4800)))")
            t.check(abs(changed.params.outputGain + 12) < 0.01, "params taken")
        },
        TestCase(name: "works at 44.1 and 96 kHz") { t in
            for sr: Float in [44100, 96000] {
                let c = Chain(sampleRate: sr, params: Presets.named("Arena")!.params)
                let kit = Synth.kit(seconds: 1, sampleRate: sr)
                let (l, r) = c.render(kit)
                t.check(l.count == kit.count && r.count == kit.count, "\(sr): sizes")
                t.check(Measure.peak(l) > 0.05 && Measure.peak(l) <= dbToGain(-0.5) + 1e-5, "\(sr): peak \(Measure.peak(l))")
                t.check(!l.contains { $0.isNaN }, "\(sr): no NaN")
            }
        },
        TestCase(name: "block processing matches sample processing") { t in
            let kit = Synth.kit(seconds: 0.5, sampleRate: 48000)
            let a = Chain(sampleRate: 48000, params: Presets.builtIn[1].params), b = Chain(sampleRate: 48000, params: Presets.builtIn[1].params)
            let (whole, _) = a.render(kit)
            var pieces = [Float]()
            for start in stride(from: 0, to: kit.count, by: 128) { pieces += b.render(Array(kit[start..<min(start + 128, kit.count)])).l }
            t.check(whole == pieces, "same output in one block or many")
            t.check(a.inPeak > 0 && a.outPeak > 0, "meters filled")
        },
    ]) }
}
