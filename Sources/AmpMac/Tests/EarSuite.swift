//  Amp for Mac — MIT licensed. See LICENSE.

import Foundation

enum EarSuite {
    static let sr: Float = 48000
    /// A strummed chord: the notes with a few harmonics each, slightly detuned so it is not a pure tone.
    static func chord(_ midis: [Int], seconds: Float, level: Float = 0.3) -> [Float] {
        let n = Int(seconds * sr); var out = [Float](repeating: 0, count: n)
        for m in midis {
            let f = 440 * powf(2, Float(m - 69) / 12)
            for (h, g) in [(1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15)] as [(Int, Float)] {
                let w = 2 * Float.pi * f * Float(h) / sr
                for i in 0..<n { out[i] += sinf(w * Float(i)) * g * expf(-Float(i) / (sr * 2)) }
            }
        }
        let peak = out.map(abs).max() ?? 1
        return out.map { $0 / peak * level }
    }
    static var suite: TestSuite { TestSuite(name: "Ear", cases: [
        TestCase(name: "hears a C major and an A minor") { t in
            let c = Chroma.of(chord([48, 52, 55, 60, 64], seconds: 0.6), sampleRate: sr)   // C E G C E
            t.equal(Chord.match(c)?.chord, Chord(root: 0, quality: .major), "C major: \(c.normalized.map { String(format: "%.2f", $0) })")
            let a = Chroma.of(chord([45, 52, 57, 60, 64], seconds: 0.6), sampleRate: sr)   // A E A C E
            t.equal(Chord.match(a)?.chord, Chord(root: 9, quality: .minor), "A minor")
            let g7 = Chroma.of(chord([43, 47, 50, 53, 59], seconds: 0.6), sampleRate: sr)  // G B D F B
            t.equal(Chord.match(g7)?.chord, Chord(root: 7, quality: .dom7), "G7 keeps its seventh")
            t.check(Chord.match(Chroma.of([Float](repeating: 0, count: 30000), sampleRate: sr)) == nil, "silence is no chord")
        },
        TestCase(name: "a progression comes out in order with its key") { t in
            let x = chord([48, 52, 55, 60], seconds: 1.2) + chord([43, 47, 50, 55], seconds: 1.2) + chord([45, 48, 52, 57], seconds: 1.2) + chord([41, 45, 48, 53], seconds: 1.2)
            let s = EarSession.analyse(x, sampleRate: sr)
            let names = s.events.map(\.chord.name)
            var merged: [String] = []; for n in names where merged.last != n { merged.append(n) }
            t.equal(merged, ["C", "G", "Am", "F"], "C G Am F: \(names)")
            t.equal(s.key, Key(root: 0, minor: false), "in C major: \(s.key?.name ?? "none")")
            t.check(s.events.first.map { $0.at < 0.8 } ?? false, "first chord lands early: \(s.events.first?.at ?? -1)")
        },
        TestCase(name: "names spell with flats in flat keys") { t in
            t.equal(Key(root: 3, minor: false).name, "Eb major", "Eb")
            t.equal(Key(root: 10, minor: true).name, "Bb minor", "Bbm")
            t.equal(Key(root: 4, minor: false).name, "E major", "E")
            t.equal(Chord(root: 3, quality: .major).name(flats: true), "Eb", "Eb chord")
            t.equal(Chord(root: 3, quality: .major).name(flats: false), "D#", "D# without flats")
        },
        TestCase(name: "capo options make the easy shapes") { t in
            let eb = Capo.options(for: Key(root: 3, minor: false))
            t.equal(eb.first?.fret, 3, "Eb: capo 3 plays C shapes")
            t.equal(eb.first?.shapeKey.name, "C major", "shape key")
            t.check(eb.contains { $0.fret == 1 && $0.shapeKey.root == 2 }, "or capo 1 in D")
            t.check(!eb.contains { $0.fret == 0 }, "no capo in Eb is not on the easy list")
            let g = Capo.options(for: Key(root: 7, minor: false))
            t.equal(g.first?.fret, 0, "G needs no capo")
            let fm = Capo.options(for: Key(root: 5, minor: true))
            t.equal(fm.first?.fret, 1, "F minor: capo 1, Em shapes")
            t.equal(fm.first?.shapeKey.name, "E minor", "Em")
            t.equal(Chord(root: 3, quality: .major).shape(capo: 3).name, "C", "Eb with capo 3 is a C shape")
            t.equal(Chord(root: 8, quality: .minor).shape(capo: 3).name, "Fm", "Abm with capo 3 is an Fm shape")
        },
        TestCase(name: "history saves and loads in its own folder") { t in
            History.overrideDir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: History.overrideDir!); History.overrideDir = nil }
            let l = Listen(started: Date(), title: "Tuesday", seconds: 42, key: Key(root: 3, minor: false), events: [ChordEvent(at: 0.5, chord: Chord(root: 3, quality: .major)), ChordEvent(at: 2, chord: Chord(root: 3, quality: .major)), ChordEvent(at: 4, chord: Chord(root: 8, quality: .major))])
            History.add(l)
            let back = History.load()
            t.equal(back.count, 1, "one listen"); t.equal(back.first?.title, "Tuesday", "title kept")
            t.equal(back.first?.chordNames ?? [], ["Eb", "Ab"], "chords merged and spelt with flats")
            t.equal(back.first?.key?.name, "Eb major", "key kept")
        },
    ]) }
}
