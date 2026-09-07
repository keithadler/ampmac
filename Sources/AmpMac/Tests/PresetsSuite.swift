//  Amp for Mac — MIT licensed. See LICENSE.

import Foundation

enum PresetsSuite {
    static var suite: TestSuite { TestSuite(name: "Presets", cases: [
        TestCase(name: "built in by genre, unique names, JSON round trip") { t in
            t.check(Presets.builtIn.count >= 36, "count: \(Presets.builtIn.count)")
            t.equal(Set(Presets.builtIn.map(\.name)).count, Presets.builtIn.count, "unique names")
            t.check(Presets.builtIn.allSatisfy { Presets.genres(for: $0.params.instrument).contains($0.genre) }, "every preset has a listed genre")
            for i in Instrument.allCases {
                t.check(Presets.genres(for: i).allSatisfy { !Presets.inGenre($0, instrument: i).isEmpty }, "every \(i.rawValue) genre has a preset")
            }
            t.check(Presets.guitarPresets.allSatisfy { $0.params.instrument == .guitar }, "the guitar bank is guitars")
            t.check(Presets.drumPresets.allSatisfy { $0.params.instrument == .drums }, "the drum bank is drums")
            for p in Presets.builtIn {
                let back = Presets.params(fromJSON: Presets.json(p.params).data(using: .utf8)!)
                t.check(back == p.params, "\(p.name) survives JSON")
            }
        },
        TestCase(name: "named finds exact, case-insensitive, prefix") { t in
            t.equal(Presets.named("Rock Room", user: [])?.name, "Rock Room", "exact")
            t.equal(Presets.named("rock room", user: [])?.name, "Rock Room", "case")
            t.equal(Presets.named("gar", user: [])?.name, "Garage", "prefix")
            t.equal(Presets.named("punch", user: [])?.name, "Dry Punch", "substring")
            t.check(Presets.named("xyz", user: []) == nil, "unknown is nil")
        },
        TestCase(name: "user presets live in Prefs and cannot shadow a built-in") { t in
            var p = AmpParams(); p.drive = 77
            Prefs.userPresets = [Preset(name: "Sam's Basement", params: p), Preset(name: "Garage", params: p)]
            let all = Presets.all()
            t.equal(all.count, Presets.builtIn.count + 1, "one user preset joins the built in; the Garage copy is dropped")
            t.equal(Presets.named("Sam", user: Prefs.userPresets)?.params.drive, 77, "found by prefix")
            t.check(Presets.named("Garage")?.builtIn == true, "the built-in Garage wins")
        },
        TestCase(name: "old JSON without a newer knob still loads") { t in
            let old = "{\"drive\" : 33, \"roomOn\" : true}".data(using: .utf8)!
            let p = Presets.params(fromJSON: old)
            t.equal(p?.drive, 33, "drive read"); t.equal(p?.roomOn, true, "roomOn read"); t.equal(p?.roomGated, false, "missing knob takes its default"); t.equal(p?.presenceGain, 0, "presence defaults"); t.equal(p?.roomTone, 50, "room tone defaults")
            t.equal(p?.compRatio, 4, "missing knob takes its default")
        },
        TestCase(name: "saved knobs come back") { t in
            var p = AmpParams(); p.roomMix = 33; p.compRatio = 7
            Prefs.params = p
            t.check(Prefs.params == p, "params round trip through defaults")
            Prefs.presetName = "Arena"; t.equal(Prefs.presetName, "Arena", "preset name")
            Prefs.inputChannel = 1; t.equal(Prefs.inputChannel, 1, "channel")
            t.equal(Prefs.bufferFrames, 128, "default buffer")
        },
    ]) }
}
