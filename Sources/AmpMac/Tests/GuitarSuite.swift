//  Amp for Mac — MIT licensed. See LICENSE.
//
//  The guitar side, tested on synthesised playing rather than on a real guitar: what the speaker takes
//  away, what the gain adds, and whether the app can tell which guitar is plugged in.

import Foundation

enum GuitarSuite {
    static let sr: Float = 48000

    private static func amp(_ change: (inout AmpParams) -> Void) -> Chain {
        var p = AmpParams(); p.instrument = .guitar; p.gateOn = false; p.compOn = false; p.limiterOn = false
        change(&p)
        return Chain(sampleRate: sr, params: p)
    }
    private static func mono(_ c: Chain, _ x: [Float]) -> [Float] {
        let (l, r) = c.render(x); return zip(l, r).map { ($0 + $1) / 2 }
    }

    static var suite: TestSuite { TestSuite(name: "Guitar", cases: [
        TestCase(name: "the speaker takes the top off, which is what makes it an amp") { t in
            // Noise, because a chord only tells you about the frequencies the chord happens to have.
            let x = Synth.noise(seconds: 2, sampleRate: sr)
            let withCab = mono(amp { $0.gain = 75; $0.cab = .fourByTwelve }, x)
            let without = mono(amp { $0.gain = 75; $0.cab = .direct }, x)
            let cabTop = Measure.aboveDb(withCab, 6000, sampleRate: sr)
            let rawTop = Measure.aboveDb(without, 6000, sampleRate: sr)
            t.check(cabTop < rawTop - 8, "a cabinet is at least 8 dB quieter above 6 kHz: \(cabTop) against \(rawTop)")
            t.check(Measure.aboveDb(withCab, 60, sampleRate: sr) < 0, "and it has no bottom octave")
        },
        TestCase(name: "every speaker sounds different, and no speaker is silent") { t in
            let x = Synth.electric(sampleRate: sr)
            var outs: [(Cab, [Float])] = []
            for cab in Cab.allCases {
                let y = mono(amp { $0.gain = 60; $0.cab = cab }, x)
                t.check(Measure.rms(y) > 0.001, "\(cab.title) makes a sound")
                t.check(y.allSatisfy { $0.isFinite }, "\(cab.title) stays a number")
                outs.append((cab, y))
            }
            for i in 0..<outs.count { for j in (i + 1)..<outs.count {
                let diff = zip(outs[i].1, outs[j].1).map { abs($0 - $1) }.max() ?? 0
                t.check(diff > 0.01, "\(outs[i].0.title) and \(outs[j].0.title) are not the same speaker")
            } }
        },
        TestCase(name: "gain adds harmonics that were not played") { t in
            let x = Synth.sine(220, seconds: 1, sampleRate: sr, level: 0.3)
            let clean = mono(amp { $0.gain = 5; $0.cab = .direct }, x)
            let dirty = mono(amp { $0.gain = 90; $0.cab = .direct }, x)
            // Everything above the fundamental, as a share of the whole.
            // Measured from the third harmonic up: a filter at the second still passes enough of a
            // 220 Hz fundamental to drown what is being measured.
            let cleanHarmonics = Measure.aboveDb(clean, 550, sampleRate: sr)
            let dirtyHarmonics = Measure.aboveDb(dirty, 550, sampleRate: sr)
            t.check(dirtyHarmonics > cleanHarmonics + 8, "dirt makes harmonics: \(dirtyHarmonics) against \(cleanHarmonics)")
        },
        TestCase(name: "the tone stack moves the ends and the middle") { t in
            let x = Synth.noise(seconds: 2, sampleRate: sr)
            func band(_ change: @escaping (inout AmpParams) -> Void, above f: Float) -> Float {
                Measure.aboveDb(mono(amp { p in p.gain = 20; p.cab = .direct; change(&p) }, x), f, sampleRate: sr)
            }
            t.check(band({ $0.treble = 100 }, above: 3000) > band({ $0.treble = 0 }, above: 3000) + 8, "treble moves the top")
            func bottom(_ change: @escaping (inout AmpParams) -> Void) -> Float {
                Measure.belowDb(mono(amp { p in p.gain = 20; p.cab = .direct; change(&p) }, x), 200, sampleRate: sr)
            }
            t.check(bottom({ $0.bass = 100 }) > bottom({ $0.bass = 0 }) + 5, "bass moves the bottom: \(bottom({ $0.bass = 100 })) against \(bottom({ $0.bass = 0 }))")
            let scooped = mono(amp { $0.gain = 20; $0.cab = .direct; $0.middle = 0 }, x)
            let full = mono(amp { $0.gain = 20; $0.cab = .direct; $0.middle = 100 }, x)
            t.check(Measure.rms(scooped) != Measure.rms(full), "the middle does something")
        },
        TestCase(name: "it can tell an acoustic from an electric") { t in
            for (signal, expected) in [(Synth.electric(sampleRate: sr), InputKind.electric),
                                       (Synth.acoustic(sampleRate: sr), InputKind.acoustic)] {
                let chain = amp { $0.gain = 40; $0.input = .auto }
                _ = chain.render(signal)
                t.equal(chain.hearing, expected, "\(expected.title) heard as \(chain.hearing.title), ratio \(chain.senseRatio)")
            }
        },
        TestCase(name: "silence never changes its mind") { t in
            let chain = amp { $0.gain = 40; $0.input = .auto }
            _ = chain.render(Synth.acoustic(sampleRate: sr))
            let heardWhilePlaying = chain.hearing
            _ = chain.render([Float](repeating: 0, count: Int(sr * 3)))
            t.equal(chain.hearing, heardWhilePlaying, "it keeps what it heard through three seconds of nothing")
        },
        TestCase(name: "an acoustic is made to look like a pickup before the amp sees it") { t in
            // Measured nearly clean and with no speaker, because distortion makes its own top end
            // back: past a certain gain both paths are bright again, which is the reason a cabinet
            // exists at all. What this proves is what reaches the amp, not what leaves it.
            let x = Synth.acoustic(sampleRate: sr)
            let asAcoustic = mono(amp { $0.gain = 8; $0.input = .acoustic; $0.cab = .direct }, x)
            let asElectric = mono(amp { $0.gain = 8; $0.input = .electric; $0.cab = .direct }, x)
            let air = (Measure.aboveDb(asAcoustic, 6000, sampleRate: sr), Measure.aboveDb(asElectric, 6000, sampleRate: sr))
            t.check(air.0 < air.1 - 6, "the air a coil cannot make is gone: \(air.0) against \(air.1)")
            let boom = (Measure.belowDb(asAcoustic, 150, sampleRate: sr), Measure.belowDb(asElectric, 150, sampleRate: sr))
            t.check(boom.0 < boom.1 - 1, "and so is the boom from the body: \(boom.0) against \(boom.1)")
            t.check(asAcoustic.allSatisfy { $0.isFinite }, "and it is still a number")
        },
        TestCase(name: "every guitar preset plays, differs, and stays under the ceiling") { t in
            let x = Synth.electric(sampleRate: sr)
            var outs: [(String, [Float])] = []
            for p in Presets.guitarPresets {
                let (l, r) = Chain(sampleRate: sr, params: p.params).render(x)
                t.check(l.allSatisfy { $0.isFinite } && r.allSatisfy { $0.isFinite }, "\(p.name) stays a number")
                t.check(Measure.peak(l) <= 1.0 && Measure.peak(r) <= 1.0, "\(p.name) stays under full scale")
                t.check(Measure.rms(l) > 0.0005, "\(p.name) makes a sound")
                outs.append((p.name, l))
            }
            for i in 0..<outs.count { for j in (i + 1)..<outs.count {
                let diff = zip(outs[i].1, outs[j].1).map { abs($0 - $1) }.max() ?? 0
                t.check(diff > 0.005, "\(outs[i].0) and \(outs[j].0) sound the same")
            } }
        },
        TestCase(name: "an old preset with no guitar in it still loads as drums") { t in
            let old = #"{"inputGain":0,"gateOn":true,"lowGain":3}"#
            let p = Presets.params(fromJSON: Data(old.utf8))
            t.equal(p?.instrument, .drums, "no instrument means drums")
            t.equal(p?.cab, .fourByTwelve, "and the guitar knobs take their defaults")
            t.equal(p?.input, .auto, "including the input")
        },
    ]) }
}
