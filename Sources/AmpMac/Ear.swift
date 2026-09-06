//  Amp for Mac — MIT licensed. See LICENSE.
//
//  The Ear: from a stretch of sound to the chord being played, the key of the piece, and where
//  to put a capo so the easy shapes play it. Pure Swift on plain Float arrays; the tests feed it
//  synthesised chords and never open a device.

import Foundation

enum Pitch {
    static let sharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flat = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    /// Keys with flats spell their notes with flats.
    static func name(_ pc: Int, flats: Bool) -> String { (flats ? flat : sharp)[((pc % 12) + 12) % 12] }
    static func usesFlats(root: Int, minor: Bool) -> Bool {
        let majorRoot = minor ? (root + 3) % 12 : root
        return [5, 10, 3, 8, 1].contains(majorRoot)     // F, Bb, Eb, Ab, Db
    }
}

/// Twelve pitch-class energies from one window of samples, by a Goertzel bank over E2 to C7.
struct Chroma: Equatable {
    var bins: [Float]      // 12, C first
    var energy: Float      // total, to tell silence from music
    static let lowestMidi = 40, highestMidi = 96   // E2 ... C7

    static func of(_ x: [Float], sampleRate: Float) -> Chroma {
        let n = x.count
        guard n > 1024 else { return Chroma(bins: [Float](repeating: 0, count: 12), energy: 0) }
        var windowed = [Float](repeating: 0, count: n)
        for i in 0..<n { windowed[i] = x[i] * (0.5 - 0.5 * cosf(2 * Float.pi * Float(i) / Float(n - 1))) }
        var bins = [Float](repeating: 0, count: 12); var energy: Float = 0
        for midi in lowestMidi...highestMidi {
            let f = 440 * powf(2, Float(midi - 69) / 12)
            guard f < sampleRate * 0.45 else { break }
            let w = 2 * Float.pi * f / sampleRate, coeff = 2 * cosf(w)
            var s0: Float = 0, s1: Float = 0, s2: Float = 0
            for i in 0..<n { s0 = windowed[i] + coeff * s1 - s2; s2 = s1; s1 = s0 }
            let power = s1 * s1 + s2 * s2 - coeff * s1 * s2
            let mag = sqrtf(max(power, 0)) / Float(n)
            // Lower octaves carry the bass note, which says root but also fills the chroma with harmonics; weight the middle.
            let octave = (midi - lowestMidi) / 12
            let weight: Float = [0.6, 1.0, 1.0, 0.8, 0.5][min(octave, 4)]
            bins[midi % 12] += mag * weight; energy += mag
        }
        return Chroma(bins: bins, energy: energy)
    }

    var normalized: [Float] { let m = bins.max() ?? 0; return m > 0 ? bins.map { $0 / m } : bins }
}

struct Chord: Equatable, Codable {
    enum Quality: String, Codable, CaseIterable { case major = "", minor = "m", dom7 = "7", maj7 = "maj7", min7 = "m7" }
    var root: Int
    var quality: Quality
    var name: String { name(flats: false) }
    func name(flats: Bool) -> String { Pitch.name(root, flats: flats) + quality.rawValue }
    /// The same chord with a capo on `fret`: what shape your hand makes.
    func shape(capo fret: Int) -> Chord { Chord(root: ((root - fret) % 12 + 12) % 12, quality: quality) }
    static let templates: [(Quality, [Int: Float])] = [
        (.major, [0: 1, 4: 0.8, 7: 0.8]), (.minor, [0: 1, 3: 0.8, 7: 0.8]),
        (.dom7, [0: 1, 4: 0.8, 7: 0.7, 10: 0.6]), (.maj7, [0: 1, 4: 0.8, 7: 0.7, 11: 0.6]), (.min7, [0: 1, 3: 0.8, 7: 0.7, 10: 0.6]),
    ]
    /// The best-fitting chord for a chroma, or nil when nothing fits or it is too quiet.
    static func match(_ c: Chroma, minimumEnergy: Float = 0.0006) -> (chord: Chord, score: Float)? {
        guard c.energy > minimumEnergy else { return nil }
        let v = c.normalized; let vn = sqrtf(v.reduce(0) { $0 + $1 * $1 }); guard vn > 0 else { return nil }
        var best: (Chord, Float)?
        for root in 0..<12 {
            for (q, t) in templates {
                var dot: Float = 0, tn: Float = 0
                for (iv, w) in t { dot += v[(root + iv) % 12] * w; tn += w * w }
                // Penalise energy outside the chord, so a lone note or a 7th does not read as a triad.
                var outside: Float = 0
                for pc in 0..<12 where t[((pc - root) % 12 + 12) % 12] == nil { outside += v[pc] }
                let score = dot / (vn * sqrtf(tn)) - 0.08 * outside
                if best == nil || score > best!.1 { best = (Chord(root: root, quality: q), score) }
            }
        }
        guard let b = best, b.1 > 0.55 else { return nil }
        // Prefer the plain triad unless the seventh is clearly there.
        if b.0.quality != .major && b.0.quality != .minor {
            let triad = Chord(root: b.0.root, quality: b.0.quality == .maj7 || b.0.quality == .dom7 ? .major : .minor)
            let seventh = v[(b.0.root + (b.0.quality == .maj7 ? 11 : 10)) % 12]
            if seventh < 0.45 { return (triad, b.1) }
        }
        return (b.0, b.1)
    }
}

struct Key: Equatable, Codable {
    var root: Int
    var minor: Bool
    var flats: Bool { Pitch.usesFlats(root: root, minor: minor) }
    var name: String { Pitch.name(root, flats: flats) + (minor ? " minor" : " major") }
    static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    /// Krumhansl-Schmuckler: the key whose profile best correlates with the summed chroma.
    static func estimate(_ summed: [Float]) -> Key? {
        guard summed.count == 12, summed.reduce(0, +) > 0 else { return nil }
        func corr(_ a: [Float], _ b: [Float]) -> Float {
            let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
            var num: Float = 0, da: Float = 0, db: Float = 0
            for i in 0..<12 { num += (a[i] - ma) * (b[i] - mb); da += (a[i] - ma) * (a[i] - ma); db += (b[i] - mb) * (b[i] - mb) }
            return da > 0 && db > 0 ? num / sqrtf(da * db) : 0
        }
        var best: (Key, Float)?
        for root in 0..<12 {
            let rotated = (0..<12).map { summed[(root + $0) % 12] }
            for (minor, profile) in [(false, majorProfile), (true, minorProfile)] {
                let c = corr(rotated, profile)
                if best == nil || c > best!.1 { best = (Key(root: root, minor: minor), c) }
            }
        }
        return best?.0
    }
}

/// Where the capo goes so open shapes play the piece.
struct CapoOption: Equatable, Identifiable {
    var fret: Int
    var shapeKey: Key         // the key your hands think in
    var ease: Int             // 0 easiest
    var id: Int { fret }
    var line: String { fret == 0 ? "No capo, play in \(shapeKey.name)." : "Capo \(fret), play in \(shapeKey.name)." }
}
enum Capo {
    static let majorEase: [Int: Int] = [7: 0, 0: 0, 2: 1, 9: 1, 4: 1, 5: 3]          // G C D A E, F is a barre
    static let minorEase: [Int: Int] = [9: 0, 4: 0, 2: 1, 11: 3]                     // Am Em Dm, Bm is a barre
    static func options(for key: Key, maxFret: Int = 7) -> [CapoOption] {
        var out: [CapoOption] = []
        for fret in 0...maxFret {
            let r = ((key.root - fret) % 12 + 12) % 12
            let table = key.minor ? minorEase : majorEase
            guard let e = table[r] else { continue }
            out.append(CapoOption(fret: fret, shapeKey: Key(root: r, minor: key.minor), ease: e))
        }
        return out.sorted { $0.ease != $1.ease ? $0.ease < $1.ease : $0.fret < $1.fret }
    }
}

/// One chord for a stretch of time.
struct ChordEvent: Equatable, Codable, Identifiable {
    var at: Double            // seconds from the start of the listen
    var chord: Chord
    var id: Double { at }
}

/// Runs the Ear over time: smooths chord decisions, sums chroma for the key, keeps the timeline.
final class EarSession {
    private(set) var summed = [Float](repeating: 0, count: 12)
    private(set) var events: [ChordEvent] = []
    private(set) var current: Chord?
    private var candidate: Chord?, candidateCount = 0
    private(set) var key: Key?
    let started: Date
    init(started: Date = Date()) { self.started = started }

    /// Feed one analysed window. Returns the chord if it changed.
    @discardableResult
    func add(_ c: Chroma, at seconds: Double) -> Chord? {
        if c.energy > 0.0006 { for i in 0..<12 { summed[i] += c.normalized[i] } ; key = Key.estimate(summed) }
        let m = Chord.match(c)?.chord
        if m == candidate { candidateCount += 1 } else { candidate = m; candidateCount = 1 }
        // Two windows in a row before a chord counts; a change to nothing needs three.
        let needed = m == nil ? 3 : 2
        guard candidateCount >= needed, candidate != current else { return nil }
        current = candidate
        if let ch = candidate { events.append(ChordEvent(at: seconds, chord: ch)) }
        return candidate
    }

    /// Offline: a whole recording, window by window.
    static func analyse(_ x: [Float], sampleRate: Float, windowSeconds: Float = 0.6, hopSeconds: Float = 0.25) -> EarSession {
        let s = EarSession()
        let n = Int(windowSeconds * sampleRate), hop = Int(hopSeconds * sampleRate)
        guard x.count >= n else { return s }
        var start = 0
        while start + n <= x.count {
            s.add(Chroma.of(Array(x[start..<start + n]), sampleRate: sampleRate), at: Double(start + n / 2) / Double(sampleRate))
            start += hop
        }
        return s
    }
}

/// A saved listen, for the history.
struct Listen: Codable, Identifiable, Equatable {
    var id = UUID()
    var started: Date
    var title: String
    var seconds: Double
    var key: Key?
    var events: [ChordEvent]
    var chordNames: [String] {
        var out: [String] = []
        for e in events { let n = e.chord.name(flats: key?.flats ?? false); if out.last != n { out.append(n) } }
        return out
    }
}

enum History {
    nonisolated(unsafe) static var overrideDir: URL?
    static var dir: URL {
        if let overrideDir { return overrideDir }
        if let h = ProcessInfo.processInfo.environment["AMPMAC_HOME"], !h.isEmpty { return URL(fileURLWithPath: h) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Amp for Mac")
    }
    static var file: URL { dir.appendingPathComponent("listens.json") }
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    static func load() -> [Listen] { (try? decoder.decode([Listen].self, from: Data(contentsOf: file))) ?? [] }
    static func save(_ list: [Listen]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? encoder.encode(Array(list.suffix(200))).write(to: file, options: .atomic)
    }
    static func add(_ l: Listen) { var list = load(); list.append(l); save(list) }
}
