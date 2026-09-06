//  Amp for Mac — MIT licensed. See LICENSE.

import Foundation

enum LevelSuite {
    static var suite: TestSuite { TestSuite(name: "Level", cases: [
        TestCase(name: "advice names the knob and the direction") { t in
            t.equal(Level.advice(rawPeakDb: 0).kind, .clipping, "0 dB clips")
            t.check(Level.advice(rawPeakDb: -0.1, interface: "Scarlett Solo USB").text.contains("Scarlett Solo USB") && Level.advice(rawPeakDb: -0.1).text.contains("down"), "clipping says down")
            t.equal(Level.advice(rawPeakDb: -3).kind, .hot, "-3 is hot")
            t.equal(Level.advice(rawPeakDb: -12).kind, .good, "-12 is good")
            t.check(Level.advice(rawPeakDb: -30).text.contains("up"), "quiet says up")
            t.equal(Level.advice(rawPeakDb: -60).kind, .silent, "nothing played")
        },
        TestCase(name: "auto level walks toward the target and stops there") { t in
            var g: Float = 0
            for _ in 0..<200 { g = Level.autoStep(gain: g, rawPeakDb: -30) }
            t.check(abs(g - 12) < 0.01, "quiet input raised by at most 12 dB: \(g)")
            g = 0
            for _ in 0..<200 { g = Level.autoStep(gain: g, rawPeakDb: -4) }
            t.check(g < -8 && g >= -10, "hot input pulled down to within the dead band of -10 dB: \(g)")
            t.equal(Level.autoStep(gain: 3, rawPeakDb: -16), 3, "within 1.5 dB it holds still")
            t.equal(Level.autoStep(gain: 3, rawPeakDb: -70), 3, "silence changes nothing")
            t.equal(Level.autoStep(gain: 3, rawPeakDb: 0), 3, "clipping changes nothing; that is the knob's job")
            t.equal(Level.autoStep(gain: 0.1, rawPeakDb: -14), 0.1, "steps are a quarter dB")
            t.check(Level.autoStep(gain: 12, rawPeakDb: -40) <= 12, "capped at 12")
        },
        TestCase(name: "recent peak holds for the window then lets go") { t in
            var r = Level.Recent(); let now = Date()
            _ = r.add(-8, at: now)
            t.equal(r.add(-40, at: now.addingTimeInterval(1)), -8, "the hit still counts a second later")
            t.equal(r.add(-40, at: now.addingTimeInterval(4)), -40, "four seconds on it is gone")
        },
    ]) }
}
