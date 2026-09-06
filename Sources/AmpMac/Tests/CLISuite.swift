//  Amp for Mac — MIT licensed. See LICENSE.

import Foundation

enum CLISuite {
    static func run(_ cmd: String, _ args: [String] = []) -> (code: Int32, out: String) {
        CLI.sink = []; defer { CLI.sink = nil }
        let code = CLI.run(cmd, args)
        return (code, (CLI.sink ?? []).joined(separator: "\n"))
    }
    static var suite: TestSuite { TestSuite(name: "CLI", cases: [
        TestCase(name: "help, version, usage error") { t in
            t.equal(run("help").code, 0, "help"); t.check(run("version").out.hasPrefix("ampmac "), "version")
            t.equal(run("nonsense").code, 64, "unknown command")
            t.equal(run("render").code, 64, "render without files")
        },
        TestCase(name: "presets list and show") { t in
            let (c, o) = run("presets", ["--json"])
            t.equal(c, 0, "exit"); t.check(o.contains("\"Rock Room\""), "lists Rock Room")
            let (c2, o2) = run("presets", ["Garage"])
            t.equal(c2, 0, "exit"); t.check(o2.contains("\"drive\" : 60"), "shows the knobs")
            t.equal(run("presets", ["nope"]).code, 1, "unknown preset exits 1")
        },
        TestCase(name: "status and devices on demo hardware") { t in
            Devices.override = Devices.demo; defer { Devices.override = nil }
            let (c, o) = run("devices", ["--json"])
            t.equal(c, 0, "exit"); t.check(o.contains("Scarlett Solo USB"), "names the interface")
            let (c2, o2) = run("status", ["--json"])
            t.check(c2 == 0 || c2 == 1, "status exits 0 or 1 (microphone permission decides)")
            t.check(o2.contains("\"inputChannel\" : 2"), "picks input 2 on a Solo: \(o2)")
            t.check(o2.contains("\"roundTripMs\" : 7.1"), "latency estimate: \(o2)")
            let (c3, o3) = run("status", ["--in", "Microphone", "--out", "Speakers", "--channel", "1"])
            t.check(c3 == 1, "no interface exits 1")
            t.check(o3.contains("MacBook Pro Microphone"), "named input wins: \(o3)")
        },
        TestCase(name: "tone then render through a preset") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let kit = dir.appendingPathComponent("kit.wav").path, out = dir.appendingPathComponent("out.wav").path
            t.equal(run("tone", [kit, "--seconds", "2"]).code, 0, "tone")
            let (c, o) = run("render", [kit, out, "--preset", "Rock Room"])
            t.equal(c, 0, "render: \(o)")
            let (samples, sr) = (try? Wave.read(URL(fileURLWithPath: out))) ?? ([], 0)
            t.equal(sr, 48000, "sample rate kept")
            t.check(samples.count >= 96000 - 2, "two seconds written: \(samples.count)")
            t.check(Measure.peak(samples) > 0.1 && Measure.peak(samples) <= 1, "audible and under full: \(Measure.peak(samples))")
            t.equal(run("render", [kit, out, "--preset", "nope"]).code, 1, "unknown preset")
            let knobs = dir.appendingPathComponent("knobs.json")
            try Presets.json(.flat).write(to: knobs, atomically: true, encoding: .utf8)
            t.equal(run("render", [kit, out, "--params", knobs.path]).code, 0, "params file")
        },
        TestCase(name: "chords on a recording finds the key and the capo") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let f = dir.appendingPathComponent("chords.wav").path
            t.equal(run("tone", [f, "--chords"]).code, 0, "tone --chords")
            let (c, o) = run("chords", [f])
            t.equal(c, 0, "exit"); t.check(o.contains("Key: C major"), "key: \(o)"); t.check(o.contains("No capo, play in C major"), "capo: \(o)")
            t.check(o.contains("C (0:0") && o.contains("Am ("), "chords in order: \(o)")
            let (c2, o2) = run("chords", [f, "--capo", "3", "--json"])
            t.equal(c2, 0, "exit"); t.check(o2.contains("\"chord\" : \"A\""), "capo 3 shows C as an A shape: \(o2)")
        },
    ]) }
}
