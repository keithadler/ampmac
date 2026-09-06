//  Amp for Mac — MIT licensed. See LICENSE.
//
//  Thirty-nine presets built for a drum kit, twelve genres, and the user's own saved beside them.
//  Each carries an output trim so all of them land at about the same loudness (see `ampmac loudness`)., and the user's own saved beside them.

import Foundation

struct Preset: Codable, Equatable, Identifiable {
    var name: String
    var params: AmpParams
    var builtIn = false
    var genre = "Mine"
    var id: String { name }
}

enum Presets {
    static let genres = ["Rock", "Pop", "Hip Hop", "Jazz", "Metal", "Soul & Funk", "Country & Folk", "Punk & Garage", "Blues", "Reggae", "Electronic", "Studio"]

    /// One line per preset. The output trim at the end keeps every preset at the loudness of what went in
    /// (`ampmac loudness` prints the table; a test holds it within 1.5 dB).
    private static func make(_ name: String, _ genre: String, gate: (Float, Float), shape: (Float, Float), comp: (Float, Float, Float, Float, Float, Float),
                             eq: (Float, Float, Float, Float, Float), drive: (Float, Float)?, room: (Float, Float, Float, Bool)?, trim: Float = 0) -> Preset {
        var p = AmpParams()
        p.gateThreshold = gate.0; p.gateRelease = gate.1
        p.attack = shape.0; p.sustain = shape.1
        p.compThreshold = comp.0; p.compRatio = comp.1; p.compAttack = comp.2; p.compRelease = comp.3; p.compMakeup = comp.4; p.compMix = comp.5
        p.lowGain = eq.0; p.midGain = eq.1; p.midFreq = eq.2; p.presenceGain = eq.3; p.highGain = eq.4
        if let d = drive { p.driveOn = true; p.drive = d.0; p.tone = d.1 }
        if let r = room { p.roomOn = true; p.roomSize = r.0; p.roomMix = r.1; p.roomTone = r.2; p.roomGated = r.3 }
        p.outputGain = trim
        return Preset(name: name, params: p, builtIn: true, genre: genre)
    }

    static let builtIn: [Preset] = [
        // Rock
        make("Rock Room", "Rock", gate: (-42, 80), shape: (25, 10), comp: (-20, 4, 15, 120, 5, 70), eq: (4, -3, 350, 2, 2), drive: (25, 60), room: (45, 25, 55, false), trim: -5),
        make("Arena", "Rock", gate: (-40, 100), shape: (40, 20), comp: (-18, 3, 20, 200, 4, 60), eq: (5, -4, 500, 3, 4), drive: (15, 65), room: (85, 35, 60, false), trim: -6),
        make("Seattle '91", "Rock", gate: (-40, 90), shape: (45, 25), comp: (-20, 6, 2, 100, 7, 70), eq: (4, 3, 220, 5, 3), drive: (15, 70), room: (65, 35, 70, false), trim: -4.5),
        make("Stairwell '71", "Rock", gate: (-55, 250), shape: (15, 45), comp: (-22, 4, 30, 250, 6, 70), eq: (5, -3, 300, 0, 0), drive: (30, 40), room: (90, 45, 35, false), trim: -9.5),
        make("Big Console", "Rock", gate: (-42, 80), shape: (30, 5), comp: (-18, 4, 10, 100, 5, 80), eq: (3, -2, 400, 4, 2), drive: (20, 60), room: (35, 20, 55, false), trim: -4),
        make("Mono '63", "Rock", gate: (-50, 200), shape: (5, 30), comp: (-24, 6, 5, 200, 8, 100), eq: (4, 2, 300, -2, -4), drive: (40, 30), room: (70, 40, 25, false), trim: -6.5),
        make("Grunge", "Rock", gate: (-45, 120), shape: (20, 25), comp: (-22, 6, 5, 120, 7, 90), eq: (4, -2, 500, 1, -1), drive: (45, 40), room: (55, 30, 40, false), trim: -7),
        // Pop
        make("Tight Pop", "Pop", gate: (-40, 60), shape: (35, -20), comp: (-18, 4, 10, 80, 4, 80), eq: (3, -2, 400, 3, 3), drive: (10, 70), room: (20, 12, 60, false), trim: -2),
        make("Gated '81", "Pop", gate: (-36, 30), shape: (30, 0), comp: (-18, 4, 5, 60, 5, 100), eq: (2, 2, 2000, 3, 4), drive: (10, 80), room: (75, 60, 70, true), trim: -5),
        make("Disco", "Pop", gate: (-38, 40), shape: (40, -30), comp: (-18, 6, 5, 60, 6, 100), eq: (4, -3, 350, 4, 5), drive: (15, 85), room: (30, 25, 70, true), trim: -3),
        make("Radio Pop", "Pop", gate: (-38, 50), shape: (40, -30), comp: (-16, 6, 3, 60, 6, 100), eq: (3, -3, 400, 5, 5), drive: (8, 85), room: (25, 15, 80, false), trim: -2.5),
        make("Dry 2020s", "Pop", gate: (-34, 30), shape: (60, -70), comp: (-14, 8, 1, 40, 6, 100), eq: (5, -4, 450, 4, 3), drive: (10, 80), room: nil, trim: -2),
        // Hip Hop
        make("Boom Bap", "Hip Hop", gate: (-40, 60), shape: (20, -50), comp: (-28, 10, 1, 50, 12, 100), eq: (6, 2, 1500, -2, -8), drive: (90, 20), room: (10, 8, 30, false), trim: -2.5),
        make("Lo-fi", "Hip Hop", gate: (-45, 80), shape: (0, 0), comp: (-30, 10, 1, 40, 10, 100), eq: (-2, 4, 900, -3, -6), drive: (80, 25), room: (30, 20, 25, false), trim: -3.5),
        make("Trap Knock", "Hip Hop", gate: (-34, 40), shape: (50, -60), comp: (-16, 8, 1, 40, 6, 100), eq: (8, -6, 500, 3, 2), drive: (20, 60), room: nil, trim: -4),
        make("Neo Soul", "Hip Hop", gate: (-48, 150), shape: (-10, 25), comp: (-22, 3, 20, 150, 3, 60), eq: (3, 1, 250, -1, -3), drive: (25, 35), room: (30, 18, 40, false), trim: -3),
        // Jazz
        make("Jazz Club", "Jazz", gate: (-55, 200), shape: (-10, 20), comp: (-22, 2, 20, 200, 2, 50), eq: (1, 0, 500, 1, 1), drive: (15, 50), room: (35, 20, 55, false)),
        make("Brushes", "Jazz", gate: (-60, 300), shape: (-20, 30), comp: (-24, 2, 30, 300, 2, 40), eq: (0, 0, 500, 2, 2), drive: nil, room: (40, 22, 60, false)),
        make("Big Band", "Jazz", gate: (-48, 150), shape: (30, 10), comp: (-20, 3, 10, 150, 4, 70), eq: (2, 1, 800, 4, 4), drive: (15, 70), room: (60, 30, 65, false), trim: -2),
        // Metal
        make("Tight Metal", "Metal", gate: (-34, 30), shape: (70, -60), comp: (-14, 8, 2, 40, 6, 100), eq: (6, -8, 400, 6, 6), drive: (25, 90), room: nil, trim: -5),
        make("Thrash", "Metal", gate: (-34, 30), shape: (60, -50), comp: (-16, 6, 2, 50, 6, 100), eq: (5, -6, 450, 5, 5), drive: (30, 85), room: (20, 10, 70, false), trim: -5),
        make("Doom", "Metal", gate: (-48, 200), shape: (10, 40), comp: (-22, 6, 10, 250, 8, 90), eq: (8, -3, 350, 0, -2), drive: (55, 30), room: (80, 35, 25, false), trim: -9.5),
        // Soul & Funk
        make("Detroit '65", "Soul & Funk", gate: (-45, 100), shape: (10, -30), comp: (-20, 6, 3, 80, 6, 100), eq: (2, 3, 800, 2, -3), drive: (45, 30), room: (15, 10, 40, false), trim: -4),
        make("Funk Dry", "Soul & Funk", gate: (-40, 50), shape: (45, -40), comp: (-18, 5, 3, 60, 5, 100), eq: (3, 2, 1000, 4, 1), drive: (20, 60), room: nil, trim: -1),
        make("Memphis Soul", "Soul & Funk", gate: (-45, 100), shape: (5, -20), comp: (-22, 5, 5, 100, 6, 100), eq: (3, 2, 600, 0, -5), drive: (40, 25), room: (15, 10, 30, false), trim: -3.5),
        // Country & Folk
        make("Nashville", "Country & Folk", gate: (-45, 100), shape: (20, 0), comp: (-20, 3, 10, 120, 3, 70), eq: (2, -1, 400, 3, 4), drive: (5, 80), room: (30, 18, 65, false), trim: -1),
        make("Americana", "Country & Folk", gate: (-48, 150), shape: (5, 15), comp: (-22, 3, 15, 150, 4, 70), eq: (3, 1, 300, 0, -2), drive: (30, 35), room: (45, 25, 35, false), trim: -4.5),
        // Punk & Garage
        make("Garage", "Punk & Garage", gate: (-50, 150), shape: (10, 30), comp: (-24, 8, 1, 60, 8, 100), eq: (2, 3, 1200, 0, -2), drive: (60, 35), room: (35, 30, 40, false), trim: -7),
        make("Bowery '76", "Punk & Garage", gate: (-40, 60), shape: (30, -20), comp: (-20, 6, 2, 60, 6, 100), eq: (2, 4, 1000, 3, 0), drive: (50, 50), room: (15, 10, 50, false), trim: -5),
        // Blues
        make("Juke Joint", "Blues", gate: (-45, 100), shape: (10, 0), comp: (-22, 5, 5, 100, 6, 100), eq: (3, 3, 700, -1, -6), drive: (55, 25), room: (20, 12, 30, false), trim: -5.5),
        make("Chicago", "Blues", gate: (-45, 100), shape: (15, 5), comp: (-20, 4, 8, 100, 5, 90), eq: (2, 2, 600, 2, -2), drive: (35, 40), room: (30, 18, 45, false), trim: -4.5),
        // Reggae
        make("One Drop", "Reggae", gate: (-40, 80), shape: (20, -20), comp: (-18, 4, 5, 80, 5, 100), eq: (8, -2, 400, -2, -5), drive: (25, 30), room: nil, trim: -5.5),
        make("Dub", "Reggae", gate: (-45, 150), shape: (0, 40), comp: (-22, 4, 10, 200, 6, 80), eq: (6, -2, 400, -2, -4), drive: (30, 30), room: (90, 45, 35, false), trim: -9),
        // Electronic
        make("Dance", "Electronic", gate: (-36, 30), shape: (50, -40), comp: (-16, 6, 2, 50, 6, 100), eq: (6, -4, 400, 4, 6), drive: (15, 85), room: (40, 30, 75, true), trim: -4.5),
        make("Industrial", "Electronic", gate: (-40, 60), shape: (30, 0), comp: (-24, 10, 1, 50, 10, 100), eq: (4, 0, 900, 2, 0), drive: (85, 45), room: (45, 30, 30, true), trim: -4.5),
        // Studio
        make("Clean Kit", "Studio", gate: (-48, 120), shape: (0, 0), comp: (-20, 2, 10, 100, 2, 60), eq: (0, 0, 500, 0, 0), drive: nil, room: nil, trim: 0.5),
        make("Dry Punch", "Studio", gate: (-38, 40), shape: (60, -40), comp: (-16, 6, 3, 50, 6, 90), eq: (3, -2, 600, 2, 2), drive: (20, 60), room: nil, trim: -3),
        make("London '69", "Studio", gate: (-50, 150), shape: (0, 15), comp: (-24, 8, 1, 150, 9, 100), eq: (3, 1, 600, 0, -1), drive: (35, 45), room: (25, 18, 45, false), trim: -3),
        make("Dead 70s", "Studio", gate: (-45, 100), shape: (0, -60), comp: (-20, 4, 10, 100, 4, 90), eq: (3, 2, 500, -2, -5), drive: (30, 30), room: nil, trim: -1.5),
    ]

    static func inGenre(_ g: String) -> [Preset] { builtIn.filter { $0.genre == g } }

    /// Built-in first, then the user's, by name. A user preset with a built-in name is not allowed.
    static func all(user: [Preset] = Prefs.userPresets) -> [Preset] { builtIn + user.filter { u in !builtIn.contains { $0.name == u.name } }.map { var p = $0; p.builtIn = false; p.genre = "Mine"; return p } }

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
    static var autoLevel: Bool { get { defaults.object(forKey: "autoLevel") as? Bool ?? false } set { defaults.set(newValue, forKey: "autoLevel") } }
    static var wasRunning: Bool { get { defaults.bool(forKey: "wasRunning") } set { defaults.set(newValue, forKey: "wasRunning") } }
}
