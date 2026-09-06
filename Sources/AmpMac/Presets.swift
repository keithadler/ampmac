//  Amp for Mac — MIT licensed. See LICENSE.
//
//  Seventeen presets built for a drum kit: seven rooms and ten sounds people know by ear, and the user's own saved beside them.

import Foundation

struct Preset: Codable, Equatable, Identifiable {
    var name: String
    var params: AmpParams
    var builtIn = false
    var id: String { name }
}

enum Presets {
    static let builtIn: [Preset] = {
        func make(_ name: String, _ edit: (inout AmpParams) -> Void) -> Preset { var p = AmpParams(); edit(&p); return Preset(name: name, params: p, builtIn: true) }
        return [
            make("Clean Kit") { p in
                p.gateThreshold = -48; p.gateRelease = 120
                p.attack = 0; p.sustain = 0
                p.compThreshold = -20; p.compRatio = 2; p.compAttack = 10; p.compRelease = 100; p.compMakeup = 2; p.compMix = 60
                p.roomOn = false
            },
            make("Tight Pop") { p in
                p.gateThreshold = -40; p.gateRelease = 60
                p.attack = 35; p.sustain = -20
                p.compThreshold = -18; p.compRatio = 4; p.compAttack = 10; p.compRelease = 80; p.compMakeup = 4; p.compMix = 80
                p.lowGain = 3; p.midGain = -2; p.midFreq = 400; p.highGain = 3
                p.driveOn = true; p.drive = 10; p.tone = 70
                p.roomOn = true; p.roomSize = 20; p.roomMix = 12
            },
            make("Rock Room") { p in
                p.gateThreshold = -42; p.gateRelease = 80
                p.attack = 25; p.sustain = 10
                p.compThreshold = -20; p.compRatio = 4; p.compAttack = 15; p.compRelease = 120; p.compMakeup = 5; p.compMix = 70
                p.lowGain = 4; p.midGain = -3; p.midFreq = 350; p.highGain = 2
                p.driveOn = true; p.drive = 25; p.tone = 60
                p.roomOn = true; p.roomSize = 45; p.roomMix = 25
            },
            make("Garage") { p in
                p.gateThreshold = -50; p.gateRelease = 150
                p.attack = 10; p.sustain = 30
                p.compThreshold = -24; p.compRatio = 8; p.compAttack = 1; p.compRelease = 60; p.compMakeup = 8; p.compMix = 100
                p.lowGain = 2; p.midGain = 3; p.midFreq = 1200; p.highGain = -2
                p.driveOn = true; p.drive = 60; p.tone = 35
                p.roomOn = true; p.roomSize = 35; p.roomMix = 30
            },
            make("Arena") { p in
                p.gateThreshold = -40; p.gateRelease = 100
                p.attack = 40; p.sustain = 20
                p.compThreshold = -18; p.compRatio = 3; p.compAttack = 20; p.compRelease = 200; p.compMakeup = 4; p.compMix = 60
                p.lowGain = 5; p.midGain = -4; p.midFreq = 500; p.highGain = 4
                p.driveOn = true; p.drive = 15; p.tone = 65
                p.roomOn = true; p.roomSize = 85; p.roomMix = 35
            },
            make("Dry Punch") { p in
                p.gateThreshold = -38; p.gateRelease = 40
                p.attack = 60; p.sustain = -40
                p.compThreshold = -16; p.compRatio = 6; p.compAttack = 3; p.compRelease = 50; p.compMakeup = 6; p.compMix = 90
                p.lowGain = 3; p.midGain = -2; p.midFreq = 600; p.highGain = 2
                p.driveOn = true; p.drive = 20; p.tone = 60
                p.roomOn = false
            },
            make("Lo-fi") { p in
                p.gateThreshold = -45; p.gateRelease = 80
                p.attack = 0; p.sustain = 0
                p.compThreshold = -30; p.compRatio = 10; p.compAttack = 1; p.compRelease = 40; p.compMakeup = 10; p.compMix = 100
                p.lowGain = -2; p.midGain = 4; p.midFreq = 900; p.highGain = -6
                p.driveOn = true; p.drive = 80; p.tone = 25
                p.roomOn = true; p.roomSize = 30; p.roomMix = 20
            },
            make("Levee Stairwell") { p in
                p.gateThreshold = -55; p.gateRelease = 250
                p.attack = 15; p.sustain = 45
                p.compThreshold = -22; p.compRatio = 4; p.compAttack = 30; p.compRelease = 250; p.compMakeup = 6; p.compMix = 70
                p.lowGain = 5; p.midGain = -3; p.midFreq = 300; p.highGain = 0
                p.driveOn = true; p.drive = 30; p.tone = 40
                p.roomOn = true; p.roomSize = 90; p.roomMix = 45
            },
            make("In the Air") { p in
                p.gateThreshold = -36; p.gateRelease = 30
                p.attack = 30; p.sustain = 0
                p.compThreshold = -18; p.compRatio = 4; p.compAttack = 5; p.compRelease = 60; p.compMakeup = 5; p.compMix = 100
                p.lowGain = 2; p.midGain = 2; p.midFreq = 2000; p.highGain = 4
                p.driveOn = true; p.drive = 10; p.tone = 80
                p.roomOn = true; p.roomSize = 75; p.roomMix = 60; p.roomGated = true
            },
            make("Motown") { p in
                p.gateThreshold = -45; p.gateRelease = 100
                p.attack = 10; p.sustain = -30
                p.compThreshold = -20; p.compRatio = 6; p.compAttack = 3; p.compRelease = 80; p.compMakeup = 6; p.compMix = 100
                p.lowGain = 2; p.midGain = 3; p.midFreq = 800; p.highGain = -3
                p.driveOn = true; p.drive = 45; p.tone = 30
                p.roomOn = true; p.roomSize = 15; p.roomMix = 10
            },
            make("Abbey Road") { p in
                p.gateThreshold = -50; p.gateRelease = 150
                p.attack = 0; p.sustain = 15
                p.compThreshold = -24; p.compRatio = 8; p.compAttack = 1; p.compRelease = 150; p.compMakeup = 9; p.compMix = 100
                p.lowGain = 3; p.midGain = 1; p.midFreq = 600; p.highGain = -1
                p.driveOn = true; p.drive = 35; p.tone = 45
                p.roomOn = true; p.roomSize = 25; p.roomMix = 18
            },
            make("Nevermind") { p in
                p.gateThreshold = -42; p.gateRelease = 90
                p.attack = 35; p.sustain = 10
                p.compThreshold = -18; p.compRatio = 4; p.compAttack = 15; p.compRelease = 120; p.compMakeup = 5; p.compMix = 65
                p.lowGain = 5; p.midGain = -4; p.midFreq = 450; p.highGain = 4
                p.driveOn = true; p.drive = 20; p.tone = 65
                p.roomOn = true; p.roomSize = 55; p.roomMix = 28
            },
            make("Boom Bap") { p in
                p.gateThreshold = -40; p.gateRelease = 60
                p.attack = 20; p.sustain = -50
                p.compThreshold = -28; p.compRatio = 10; p.compAttack = 1; p.compRelease = 50; p.compMakeup = 12; p.compMix = 100
                p.lowGain = 6; p.midGain = 2; p.midFreq = 1500; p.highGain = -8
                p.driveOn = true; p.drive = 90; p.tone = 20
                p.roomOn = true; p.roomSize = 10; p.roomMix = 8
            },
            make("Blue Note") { p in
                p.gateThreshold = -55; p.gateRelease = 200
                p.attack = -10; p.sustain = 20
                p.compThreshold = -22; p.compRatio = 2; p.compAttack = 20; p.compRelease = 200; p.compMakeup = 2; p.compMix = 50
                p.lowGain = 1; p.midGain = 0; p.midFreq = 500; p.highGain = 1
                p.driveOn = true; p.drive = 15; p.tone = 50
                p.roomOn = true; p.roomSize = 35; p.roomMix = 20
            },
            make("Tight Metal") { p in
                p.gateThreshold = -34; p.gateRelease = 30
                p.attack = 70; p.sustain = -60
                p.compThreshold = -14; p.compRatio = 8; p.compAttack = 2; p.compRelease = 40; p.compMakeup = 6; p.compMix = 100
                p.lowGain = 6; p.midGain = -8; p.midFreq = 400; p.highGain = 6
                p.driveOn = true; p.drive = 25; p.tone = 90
                p.roomOn = false
            },
            make("Dead 70s") { p in
                p.gateThreshold = -45; p.gateRelease = 100
                p.attack = 0; p.sustain = -60
                p.compThreshold = -20; p.compRatio = 4; p.compAttack = 10; p.compRelease = 100; p.compMakeup = 4; p.compMix = 90
                p.lowGain = 3; p.midGain = 2; p.midFreq = 500; p.highGain = -5
                p.driveOn = true; p.drive = 30; p.tone = 30
                p.roomOn = false
            },
            make("Disco") { p in
                p.gateThreshold = -38; p.gateRelease = 40
                p.attack = 40; p.sustain = -30
                p.compThreshold = -18; p.compRatio = 6; p.compAttack = 5; p.compRelease = 60; p.compMakeup = 6; p.compMix = 100
                p.lowGain = 4; p.midGain = -3; p.midFreq = 350; p.highGain = 5
                p.driveOn = true; p.drive = 15; p.tone = 85
                p.roomOn = true; p.roomSize = 30; p.roomMix = 25; p.roomGated = true
            },
        ]
    }()

    /// Built-in first, then the user's, by name. A user preset with a built-in name is not allowed.
    static func all(user: [Preset] = Prefs.userPresets) -> [Preset] { builtIn + user.filter { u in !builtIn.contains { $0.name == u.name } }.map { var p = $0; p.builtIn = false; return p } }

    /// Exact name first, then case-insensitive, then a unique prefix or substring.
    static func named(_ s: String, user: [Preset] = Prefs.userPresets) -> Preset? {
        let list = all(user: user)
        if let p = list.first(where: { $0.name == s }) { return p }
        if let p = list.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return p }
        let pre = list.filter { $0.name.lowercased().hasPrefix(s.lowercased()) }
        if pre.count == 1 { return pre[0] }
        let sub = list.filter { $0.name.localizedCaseInsensitiveContains(s) }
        return sub.count == 1 ? sub[0] : nil
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    static func json(_ p: AmpParams) -> String { String(decoding: (try? encoder.encode(p)) ?? Data(), as: UTF8.self) }
    static func params(fromJSON d: Data) -> AmpParams? { try? JSONDecoder().decode(AmpParams.self, from: d) }
}

/// Settings. Named Prefs because a `Settings` enum collides with SwiftUI's Settings scene.
enum Prefs {
    nonisolated(unsafe) static var defaults = UserDefaults.standard
    static var inputUID: String? { get { defaults.string(forKey: "inputUID") } set { defaults.set(newValue, forKey: "inputUID") } }
    static var outputUID: String? { get { defaults.string(forKey: "outputUID") } set { defaults.set(newValue, forKey: "outputUID") } }
    /// Zero-based input channel on the chosen device; nil means "pick for me".
    static var inputChannel: Int? { get { defaults.object(forKey: "inputChannel") as? Int } set { defaults.set(newValue, forKey: "inputChannel") } }
    static var bufferFrames: Int { get { let v = defaults.integer(forKey: "bufferFrames"); return v == 0 ? 128 : v } set { defaults.set(newValue, forKey: "bufferFrames") } }
    static var params: AmpParams? {
        get { defaults.data(forKey: "params").flatMap(Presets.params(fromJSON:)) }
        set { defaults.set(newValue.flatMap { try? Presets.encoder.encode($0) }, forKey: "params") }
    }
    static var presetName: String? { get { defaults.string(forKey: "presetName") } set { defaults.set(newValue, forKey: "presetName") } }
    static var userPresets: [Preset] {
        get { defaults.data(forKey: "userPresets").flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? [] }
        set { defaults.set(try? Presets.encoder.encode(newValue), forKey: "userPresets") }
    }
    static var menuBar: Bool { get { defaults.object(forKey: "menuBar") as? Bool ?? true } set { defaults.set(newValue, forKey: "menuBar") } }
    static var resumeOnOpen: Bool { get { defaults.object(forKey: "resumeOnOpen") as? Bool ?? false } set { defaults.set(newValue, forKey: "resumeOnOpen") } }
    static var autoLevel: Bool { get { defaults.object(forKey: "autoLevel") as? Bool ?? true } set { defaults.set(newValue, forKey: "autoLevel") } }
    static var wasRunning: Bool { get { defaults.bool(forKey: "wasRunning") } set { defaults.set(newValue, forKey: "wasRunning") } }
}
