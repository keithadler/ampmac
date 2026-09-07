//  Amp for Mac — MIT licensed. See LICENSE.
//
//  The command-line face. Exit codes: 0 fine, 1 something to look at, 2 problem, 64 usage.

import Foundation
import AppKit
import AVFoundation

enum CLI {
    static let usage = """
    ampmac — a drum amp for the input of your audio interface (command-line face)

    USAGE
      ampmac status [--json]                          devices chosen, latency, microphone permission
      ampmac devices [--json]                         every audio device, inputs and outputs
      ampmac presets [--json] [<name>]                the presets; with a name, that preset's knobs as JSON
      ampmac run [--in <device>] [--out <device>] [--channel N] [--preset <name>] [--seconds N]
                                                      play the amp from the terminal, meters once a second
      ampmac render <in.wav> <out.wav> [--preset <name>] [--params <file.json>]
                                                      run a recording through the amp, offline
      ampmac tone <out.wav> [--seconds N]             write a synthesised kit to try the amp with
      ampmac tone <out.wav> --chords ["C G Am F"] [--bpm N] [--loops N]
                                                      write a strummed progression from chordmap's synth
      ampmac chords <file> [--capo N] [--json] [--bpm hint] [--genre band|hiphop|dance]
                                                      the Ear on a recording: key, tempo, capo, the chord sheet
      ampmac ear [--source mac|<device>] [--seconds N] [--json]
                                                      the Ear live, on the Mac's own sound or an input
      ampmac screenshots <dir> [--announce]           render windows and promo cards from demo data
      ampmac selftest [--filter S] [--list] [--json]
      ampmac help | version

    Device names match on any part: --in Scarlett. Channels count from 1 (a Scarlett Solo's
    instrument jack is 2). Set AMPMAC_HOME to isolate settings, as the tests do.
    """

    static var version: String {
        if Bundle.main.bundleIdentifier == "com.keithadler.ampmac", let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let b = Bundle(url: url), b.bundleIdentifier == "com.keithadler.ampmac", let v = b.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
            url = url.deletingLastPathComponent()
        }
        return "dev"
    }

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let h = env["AMPMAC_HOME"], !h.isEmpty {
            Prefs.defaults = UserDefaults(suiteName: "com.keithadler.ampmac.test")!
            Prefs.defaults.removePersistentDomain(forName: "com.keithadler.ampmac.test")
        }
        if env["AMPMAC_DEMO_DEVICES"] == "1" { Devices.override = Devices.demo }
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first, !cmd.hasPrefix("-psn") else { return }
        exit(run(cmd, Array(args.dropFirst())))
    }

    static func flag(_ n: String, _ a: [String]) -> Bool { a.contains(n) }
    static func value(_ n: String, _ a: [String]) -> String? { guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }; return a[i + 1] }
    static let valued = ["--filter", "--in", "--out", "--channel", "--preset", "--seconds", "--params", "--buffer", "--capo", "--source", "--bpm", "--genre", "--loops"]
    static func positional(_ a: [String]) -> [String] {
        var out: [String] = []; var skip = false
        for x in a { if skip { skip = false; continue }; if valued.contains(x) { skip = true; continue }; if x.hasPrefix("--") { continue }; out.append(x) }
        return out
    }
    nonisolated(unsafe) static var quiet = false
    /// When set, output is collected here instead of printed (tests).
    nonisolated(unsafe) static var sink: [String]?
    static func out(_ s: String) { if sink != nil { sink?.append(s) } else if !quiet { print(s) } }
    static func err(_ s: String) { if sink != nil { sink?.append(s) } else if !quiet { fputs(s + "\n", stderr) } }
    static func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }
    static func dict(_ d: AudioDevice) -> [String: Any] {
        ["name": d.name, "uid": d.uid, "manufacturer": d.manufacturer, "inputs": d.inputs, "outputs": d.outputs, "sampleRate": d.sampleRate, "bufferFrames": d.bufferFrames, "inputLatencyFrames": d.inLatency, "outputLatencyFrames": d.outLatency, "interface": d.isInterface]
    }
    static func micWord(_ s: AVAuthorizationStatusLike) -> String { s.word }

    /// The devices a command should use: named on the command line, else saved, else the best guess.
    static func choose(_ args: [String]) -> (AudioDevice, AudioDevice, Int)? {
        let list = Devices.all()
        var input = value("--in", args).flatMap { n in list.first { $0.inputs > 0 && $0.name.localizedCaseInsensitiveContains(n) } } ?? Devices.find(uid: Prefs.inputUID)
        var output = value("--out", args).flatMap { n in list.first { $0.outputs > 0 && $0.name.localizedCaseInsensitiveContains(n) } } ?? Devices.find(uid: Prefs.outputUID)
        if input == nil || output == nil, let d = Devices.defaultChoice(list) { input = input ?? d.input; output = output ?? d.output }
        guard let i = input, let o = output else { return nil }
        let ch = (value("--channel", args).flatMap(Int.init).map { $0 - 1 }) ?? Prefs.inputChannel ?? i.defaultInputChannel
        return (i, o, min(max(ch, 0), max(i.inputs - 1, 0)))
    }

    static func run(_ cmd: String, _ args: [String]) -> Int32 {
        let js = flag("--json", args)
        let pos = positional(args)
        switch cmd {
        case "help", "--help", "-h": out(usage); return 0
        case "version", "--version": out("ampmac \(version)"); return 0
        case "status":
            let mic = Engine.microphoneAllowed()
            guard let (i, o, ch) = choose(args) else { err("No audio device with an input and one with an output. Plug the interface in."); return 1 }
            let ms = Devices.roundTripMs(input: i, output: o, bufferFrames: Prefs.bufferFrames)
            let preset = Prefs.presetName ?? "Rock Room"
            if js {
                out(json(["input": dict(i), "output": dict(o), "inputChannel": ch + 1, "channelLabel": i.channelLabel(ch), "bufferFrames": Prefs.bufferFrames, "roundTripMs": NSDecimalNumber(string: String(format: "%.1f", ms)),
                          "microphone": AVAuthorizationStatusLike(mic).word, "preset": preset, "interfaceFound": i.isInterface, "version": version, "chordmap": Chordmap.version]))
            } else {
                out("Input: \(i.name), \(i.channelLabel(ch))")
                out("Output: \(o.name)")
                out(String(format: "Round trip: about %.1f ms at %d frames, %.0f Hz", ms, Prefs.bufferFrames, i.sampleRate))
                out("Microphone permission: \(AVAuthorizationStatusLike(mic).word)")
                out("Preset: \(preset)")
                out("Ear: chordmap \(Chordmap.version)")
                if !i.isInterface { out("No audio interface found; using the Mac's own input and output.") }
            }
            return i.isInterface && mic != .denied ? 0 : 1
        case "devices":
            let list = Devices.all()
            if js { out(json(list.map(dict))) } else {
                if list.isEmpty { out("No audio devices."); return 1 }
                for d in list { out(String(format: "%-34@ in %d  out %d  %.0f Hz%@", d.name, d.inputs, d.outputs, d.sampleRate, d.isInterface ? "  (interface)" : "")) }
            }
            return 0
        case "presets":
            if let name = pos.first {
                guard let p = Presets.named(name) else { err("No preset called \(name)."); return 1 }
                out(Presets.json(p.params)); return 0
            }
            let all = Presets.all()
            if js { out(json(all.map { ["name": $0.name, "builtIn": $0.builtIn] })) } else { for p in all { out(p.name + (p.builtIn ? "" : "  (mine)")) } }
            return 0
        case "render":
            guard pos.count >= 2 else { err("ampmac render <in.wav> <out.wav> [--preset <name>]"); return 64 }
            guard let params = paramsFrom(args) else { return 1 }
            do {
                let (samples, sr) = try Wave.read(URL(fileURLWithPath: pos[0]))
                let chain = Chain(sampleRate: Float(sr), params: params)
                let (l, r) = chain.render(samples)
                try Wave.write(URL(fileURLWithPath: pos[1]), left: l, right: r, sampleRate: sr)
                out(String(format: "%@: %d samples at %.0f Hz, peak in %.1f dB, out %.1f dB", pos[1], samples.count, sr, gainToDb(Measure.peak(samples)), gainToDb(max(Measure.peak(l), Measure.peak(r)))))
                return 0
            } catch { err("render failed: \(error.localizedDescription)"); return 2 }
        case "tone":
            guard let path = pos.first else { err("ampmac tone <out.wav> [--seconds N]"); return 64 }
            let secs = Float(value("--seconds", args) ?? "") ?? 8
            if flag("--chords", args) {
                let prog = pos.count > 1 ? pos[1] : "C G Am F"
                let bpm = Float(value("--bpm", args) ?? "") ?? 100, loops = Int(value("--loops", args) ?? "") ?? 2
                let (x, sr) = Chordmap.synth(prog, bpm: bpm, loops: loops)
                guard !x.isEmpty else { err("chordmap could not read the progression \"\(prog)\". Try: \"C G Am F\""); return 64 }
                do { try Wave.write(URL(fileURLWithPath: path), left: x, right: x, sampleRate: sr); out(String(format: "%@: %@ at %.0f bpm, %d loops, %.1f s", path, prog, bpm, loops, Double(x.count) / sr)); return 0 }
                catch { err("tone failed: \(error.localizedDescription)"); return 2 }
            }
            let kit = Synth.kit(seconds: secs, sampleRate: 48000)
            do { try Wave.write(URL(fileURLWithPath: path), left: kit, right: kit, sampleRate: 48000); out("\(path): \(kit.count) samples, 120 bpm"); return 0 }
            catch { err("tone failed: \(error.localizedDescription)"); return 2 }
        case "run":
            guard let (i, o, ch) = choose(args) else { err("No audio device with an input and one with an output."); return 1 }
            guard let params = paramsFrom(args) else { return 1 }
            let secs = Double(value("--seconds", args) ?? "") ?? 0
            let buffer = Int(value("--buffer", args) ?? "") ?? Prefs.bufferFrames
            if Engine.microphoneAllowed() != .authorized {
                let sem = DispatchSemaphore(value: 0); let box = FlagBox()
                Task { box.value = await Engine.requestMicrophone(); sem.signal() }
                sem.wait()
                guard box.value else { err("Microphone permission was not given. System Settings › Privacy & Security › Microphone."); return 1 }
            }
            let engine = Engine.shared
            do { try engine.start(input: i, output: o, inputChannel: ch, bufferFrames: buffer, params: params) } catch { err(error.localizedDescription); return 2 }
            out(String(format: "Listening: %@, %@ → %@. %.1f ms round trip at %d frames. Ctrl-C stops.", i.name, i.channelLabel(ch), o.name, engine.roundTripMs, engine.bufferFrames))
            signal(SIGINT) { _ in Engine.shared.stop(); print(""); exit(0) }
            let until = secs > 0 ? Date().addingTimeInterval(secs) : Date.distantFuture
            var lastFrames: UInt64 = 0
            var recent = Level.Recent()
            while Date() < until {
                RunLoop.main.run(until: Date().addingTimeInterval(1))
                let m = engine.meters
                let bar = String(repeating: "|", count: Int(max(0, min(30, (gainToDb(m.inPeak) + 60) / 2))))
                let advice = Level.advice(rawPeakDb: recent.add(gainToDb(m.inPeak)), interface: i.name)
                out(String(format: "in %6.1f dB  out %6.1f dB  gate %@  squash %4.1f dB  %@%@  %@", gainToDb(m.inPeak), gainToDb(m.outPeak), m.gateOpen ? "open  " : "closed", m.compGr, bar, m.frames == lastFrames ? "  (no audio)" : "", advice.text))
                lastFrames = m.frames
            }
            engine.stop()
            return engine.meters.dropouts > 0 ? 1 : 0
        case "chords":
            guard let path = pos.first else { err("ampmac chords <file> [--capo N] [--json]"); return 64 }
            do {
                let (samples, sr) = try Wave.read(URL(fileURLWithPath: path))
                let a = try Chordmap.analyze(samples, sampleRate: sr, bpmHint: Float(value("--bpm", args) ?? ""), genre: value("--genre", args))
                return report(a, capo: Int(value("--capo", args) ?? ""), json: js)
            } catch { err("chords failed: \(error.localizedDescription)"); return 2 }
        case "ear":
            let src: Capture.Source
            if let n = value("--source", args), n != "mac" {
                guard let d = Devices.inputs().first(where: { $0.name.localizedCaseInsensitiveContains(n) }) else { err("No input called \(n)."); return 1 }
                src = .device(d.uid)
            } else { src = .mac }
            let capture = Capture()
            do { try capture.start(src) } catch { err(error.localizedDescription); return 2 }
            let secs = Double(value("--seconds", args) ?? "") ?? 0
            let began = Date()
            out("Listening to \(src.label). Ctrl-C stops.")
            signal(SIGINT) { _ in exit(0) }
            let until = secs > 0 ? began.addingTimeInterval(secs) : Date.distantFuture
            var last: String?
            var nextHear = began.addingTimeInterval(4.2)
            while Date() < until {
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                guard Date() >= nextHear else { continue }
                nextHear = Date().addingTimeInterval(EarModel.everySeconds)
                let x = capture.latest(seconds: EarModel.windowSeconds); guard x.count >= Int(4 * capture.sampleRate) else { continue }
                guard let a = try? Chordmap.analyze(x, sampleRate: capture.sampleRate) else { continue }
                let now = a.chord(at: a.duration - 0.5)?.label
                if now != last, let now, !js { out(String(format: "%6.1f s  %@   (%@, %.0f bpm)", capture.seconds, now, a.key.name, a.tempo.bpm)) }
                last = now
            }
            capture.stop()
            let all = capture.all()
            guard all.count >= Int(4 * capture.sampleRate) else { err("Too short to chart: chordmap needs four seconds."); return 1 }
            do {
                let a = try Chordmap.analyze(all, sampleRate: capture.sampleRate)
                let f = DateFormatter(); f.timeStyle = .short
                History.add(Listen(started: began, title: "Listen at \(f.string(from: began))", seconds: capture.seconds, analysis: a))
                return report(a, capo: nil, json: js)
            } catch { err(error.localizedDescription); return 2 }
        case "loudness":
            // Each preset's average gain on the synthesised kit; presets are trimmed so this sits near 0 dB.
            // A drum preset is measured on a kit and a guitar preset on chords: an amp told how loud
            // it is on a snare has been told nothing.
            let kit = Synth.kit(seconds: 4, sampleRate: 48000)
            let chords = Synth.chords(sampleRate: 48000)
            for p in Presets.builtIn {
                let source = p.params.instrument == .guitar ? chords : kit
                let (l, r) = Chain(sampleRate: 48000, params: p.params).render(source)
                let g = gainToDb((Measure.rms(l) + Measure.rms(r)) / 2 / Measure.rms(source))
                out(String(format: "%-16@ %+5.1f dB  (output knob %+.0f)", p.name, g, p.params.outputGain))
            }
            return 0
        case "screenshots":
            guard let dir = pos.first else { err("ampmac screenshots <dir>"); return 64 }
            do { let files = try MainActor.assumeIsolated { try Screenshots.render(to: URL(fileURLWithPath: dir), announce: flag("--announce", args)) }; for f in files { out(f.path) }; return 0 }
            catch { err("screenshots failed: \(error)"); return 2 }
        case "selftest":
            if flag("--list", args) { TestKit.list(); return 0 }
            let results = MainActor.assumeIsolated { TestKit.run(filter: value("--filter", args)) }
            return TestKit.report(results, json: js)
        default:
            err(usage); return 64
        }
    }

    static func report(_ a: Analysis, capo: Int?, json js: Bool) -> Int32 {
        if js {
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
            out(String(decoding: (try? e.encode(a)) ?? Data(), as: UTF8.self)); return 0
        }
        let flats = Pitch.usesFlats(a.key)
        out("Key: \(a.key.name)" + (a.key.confidence < 0.1 ? " (or \(a.key.alternative))" : ""))
        out(String(format: "Tempo: %.0f bpm, %@", a.tempo.bpm, a.meter))
        let pick = a.guitar.capo
        out(pick == 0 ? "Capo: none, every shape open" : "Capo \(pick): " + a.guitar.shapes.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value)" }.joined(separator: ", "))
        for o in a.capoOptionsByEase.prefix(3) where o.capo != pick { out(String(format: "  or capo %d, %.0f s of barre chords", o.capo, o.hardSeconds)) }
        for w in a.warnings { out("Note: \(w)") }
        if let capo, capo != 0 {
            out("Shapes with capo \(capo):")
            var names: [String] = []
            for c in a.chords where c.label != "N" { let n = Pitch.shape(c.label, capo: capo, flats: flats); if names.last != n { names.append(n) } }
            out(names.joined(separator: "  "))
        } else {
            out(""); out(Chordmap.chordSheet(a))
        }
        return a.chords.isEmpty ? 1 : 0
    }

    /// --params file wins, then --preset, then the saved knobs, then Rock Room.
    static func paramsFrom(_ args: [String]) -> AmpParams? {
        if let f = value("--params", args) {
            guard let d = FileManager.default.contents(atPath: f), let p = Presets.params(fromJSON: d) else { err("Could not read knobs from \(f)."); return nil }
            return p
        }
        if let n = value("--preset", args) {
            guard let p = Presets.named(n) else { err("No preset called \(n). Try: ampmac presets"); return nil }
            return p.params
        }
        return Prefs.params ?? Presets.named("Rock Room")!.params
    }
}

/// A word for each microphone permission state.
struct AVAuthorizationStatusLike {
    let word: String
    init(_ s: AVAuthorizationStatus) {
        switch s { case .authorized: word = "allowed"; case .denied: word = "denied"; case .restricted: word = "restricted"; case .notDetermined: word = "not asked yet"; @unknown default: word = "unknown" }
    }
}

final class FlagBox: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    var value: Bool { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}
