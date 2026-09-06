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
      ampmac tone <out.wav> [--seconds N | --chords]  write a synthesised kit (or C G Am F) to try things with
      ampmac chords <file> [--capo N] [--json]        the Ear on a recording: key, capo choices, chords in order
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
    static let valued = ["--filter", "--in", "--out", "--channel", "--preset", "--seconds", "--params", "--buffer", "--capo", "--source"]
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
                          "microphone": AVAuthorizationStatusLike(mic).word, "preset": preset, "interfaceFound": i.isInterface, "version": version]))
            } else {
                out("Input: \(i.name), \(i.channelLabel(ch))")
                out("Output: \(o.name)")
                out(String(format: "Round trip: about %.1f ms at %d frames, %.0f Hz", ms, Prefs.bufferFrames, i.sampleRate))
                out("Microphone permission: \(AVAuthorizationStatusLike(mic).word)")
                out("Preset: \(preset)")
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
            let kit = flag("--chords", args) ? Synth.chords() : Synth.kit(seconds: secs, sampleRate: 48000)
            do { try Wave.write(URL(fileURLWithPath: path), left: kit, right: kit, sampleRate: 48000); out("\(path): \(kit.count) samples, \(flag("--chords", args) ? "C G Am F" : "120 bpm")"); return 0 }
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
            guard let path = pos.first else { err("ampmac chords <file> [--capo N]"); return 64 }
            do {
                let (samples, sr) = try Wave.read(URL(fileURLWithPath: path))
                let s = EarSession.analyse(samples, sampleRate: Float(sr))
                return report(session: s, capo: Int(value("--capo", args) ?? ""), json: js)
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
            let session = EarSession()
            out("Listening to \(src.label). Ctrl-C stops.")
            signal(SIGINT) { _ in exit(0) }
            let until = secs > 0 ? Date().addingTimeInterval(secs) : Date.distantFuture
            var last: Chord?
            while Date() < until {
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                let x = capture.latest(seconds: 0.6); guard x.count > 1024 else { continue }
                let chroma = Chroma.of(x, sampleRate: Float(capture.sampleRate))
                if flag("--debug", args) { out(String(format: "%5.1f s  rate %.0f  peak %.4f  energy %.4f  %@  %@", Date().timeIntervalSince(session.started), capture.sampleRate, Measure.peak(x), chroma.energy, chroma.normalized.map { String(format: "%.2f", $0) }.joined(separator: " "), Chord.match(chroma).map { "\($0.chord.name) \(String(format: "%.2f", $0.score))" } ?? "-")) }
                session.add(chroma, at: Date().timeIntervalSince(session.started))
                if session.current != last, let c = session.current, !js { out(String(format: "%6.1f s  %@", Date().timeIntervalSince(session.started), c.name(flats: session.key?.flats ?? false))); last = c }
                else if session.current != last { last = session.current }
            }
            capture.stop()
            if !session.events.isEmpty {
                let f = DateFormatter(); f.timeStyle = .short
                History.add(Listen(started: session.started, title: "Listen at \(f.string(from: session.started))", seconds: Date().timeIntervalSince(session.started), key: session.key, events: session.events))
            }
            return report(session: session, capo: nil, json: js)
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

    static func report(session s: EarSession, capo: Int?, json js: Bool) -> Int32 {
        let flats = s.key?.flats ?? false
        var names: [(Double, String)] = []
        for e in s.events { let n = capo.map { e.chord.shape(capo: $0).name(flats: flats) } ?? e.chord.name(flats: flats); if names.last?.1 != n { names.append((e.at, n)) } }
        let options = s.key.map { Capo.options(for: $0) } ?? []
        if js {
            out(json(["key": s.key?.name ?? "", "capo": options.map { ["fret": $0.fret, "playIn": $0.shapeKey.name, "ease": $0.ease] }, "chords": names.map { ["at": ($0.0 * 10).rounded() / 10, "chord": $0.1] }]))
        } else {
            guard !names.isEmpty else { out("No chords heard."); return 1 }
            out("Key: \(s.key?.name ?? "unknown")")
            for o in options.prefix(3) { out((o.ease == 0 ? "  " : "  ") + o.line + (o.ease == 0 ? "  (easiest)" : "")) }
            if let capo { out("Shapes with capo \(capo):") }
            out(names.map { String(format: "%@ (%d:%02d)", $0.1, Int($0.0) / 60, Int($0.0) % 60) }.joined(separator: "  "))
        }
        return names.isEmpty ? 1 : 0
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
