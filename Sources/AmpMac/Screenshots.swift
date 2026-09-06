//  Amp for Mac — MIT licensed. See LICENSE.
//
//  `ampmac screenshots <dir>`: the window on demo devices with fixed meters. No device is opened.

import AppKit
import SwiftUI

enum Screenshots {
    @MainActor
    static func render(to dir: URL, announce: Bool) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular); app.activate(ignoringOtherApps: true)
        if app.applicationIconImage.size.width == 0 || Bundle.main.bundleIdentifier == nil, let icon = NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/AppIcon.icns") { app.applicationIconImage = icon }
        Prefs.defaults = UserDefaults(suiteName: "com.keithadler.ampmac.screenshots")!
        Prefs.defaults.removePersistentDomain(forName: "com.keithadler.ampmac.screenshots")
        Devices.override = Devices.demo
        defer { Prefs.defaults = .standard; Devices.override = nil }
        let model = AmpModel.shared
        model.demo = true
        model.refreshDevices()
        model.inputUID = "demo-solo"; model.outputUID = "demo-solo"; model.inputChannel = 1
        model.userPresets = [Preset(name: "Sam's Basement", params: Presets.builtIn[3].params)]

        var written: [URL] = []
        for (suffix, appearance) in [("", NSAppearance.Name.darkAqua), ("-light", .aqua)] {
            app.appearance = NSAppearance(named: appearance)
            for (name, preset, running, meter) in [
                ("amp", "Rock Room", true, MeterState(inDb: -9, outDb: -4, gateOpen: true, compGr: 5.2, limiterGr: 0.6)),
                ("garage", "Garage", true, MeterState(inDb: -14, outDb: -2, gateOpen: true, compGr: 9.8, limiterGr: 1.4)),
                ("off", "Tight Pop", false, MeterState()),
            ] {
                model.select(named: preset); model.running = running; model.meter = meter; model.problem = nil
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                w.title = "Amp for Mac"
                w.contentView = NSHostingView(rootView: MainView().environmentObject(model).frame(width: 1000, height: 700))
                w.center(); w.makeKeyAndOrderFront(nil)
                settle(); written.append(try capture(w, to: dir.appendingPathComponent("\(name)\(suffix).png"))); w.orderOut(nil)
            }
        }
        // The Ear, mid-song, in Eb with capo 3 chosen.
        let ear = EarModel.shared; ear.demo = true
        History.overrideDir = TestKit.tempDir(); defer { History.overrideDir = nil }
        let eb = Key(root: 3, minor: false)
        let prog: [(Double, Int, Chord.Quality)] = [(0.4, 3, .major), (2.1, 8, .major), (3.9, 10, .major), (5.8, 0, .minor), (7.6, 3, .major), (9.5, 8, .major), (11.3, 10, .major), (13.1, 3, .major)]
        let evs = prog.map { ChordEvent(at: $0.0, chord: Chord(root: $0.1, quality: $0.2)) }
        ear.listens = [Listen(started: Date().addingTimeInterval(-86400 * 2), title: "Sam's song, Tuesday", seconds: 212, key: Key(root: 7, minor: false), events: [ChordEvent(at: 1, chord: Chord(root: 7, quality: .major)), ChordEvent(at: 3, chord: Chord(root: 0, quality: .major)), ChordEvent(at: 5, chord: Chord(root: 2, quality: .major))]),
                       Listen(started: Date().addingTimeInterval(-3600), title: "Radio, this morning", seconds: 95, key: Key(root: 9, minor: true), events: [ChordEvent(at: 1, chord: Chord(root: 9, quality: .minor)), ChordEvent(at: 3, chord: Chord(root: 5, quality: .major)), ChordEvent(at: 5, chord: Chord(root: 0, quality: .major)), ChordEvent(at: 7, chord: Chord(root: 7, quality: .major))])]
        ear.viewing = nil; ear.listening = true; ear.key = eb; ear.capo = 3; ear.events = evs; ear.chord = Chord(root: 10, quality: .major); ear.elapsed = 14
        model.mode = .ear
        for (suffix, appearance) in [("", NSAppearance.Name.darkAqua), ("-light", .aqua)] {
            app.appearance = NSAppearance(named: appearance)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Amp for Mac"
            w.contentView = NSHostingView(rootView: MainView().environmentObject(model).frame(width: 1000, height: 700))
            w.center(); w.makeKeyAndOrderFront(nil)
            settle(); written.append(try capture(w, to: dir.appendingPathComponent("ear\(suffix).png"))); w.orderOut(nil)
        }
        ear.listening = false; ear.demo = false; ear.events = []; ear.key = nil; ear.chord = nil; ear.listens = History.load(); model.mode = .amp
        model.running = false; model.demo = false
        if announce { written += try Promo.render(to: dir, screenshots: dir) }
        return written
    }
    @MainActor static func settle() { let until = Date().addingTimeInterval(0.8); while Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) } }
    @MainActor static func image(of window: NSWindow, retina: Bool = false) throws -> CGImage {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { throw NSError(domain: "shots", code: 1) }
        let fn = unsafeBitCast(sym, to: Fn.self)
        guard let i = fn(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | (retina ? 1 << 3 : 1 << 4))?.takeRetainedValue() else { throw NSError(domain: "shots", code: 2) }
        return i
    }
    @MainActor static func capture(_ window: NSWindow, to url: URL, retina: Bool = false) throws -> URL {
        let img = try image(of: window, retina: retina)
        guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { throw NSError(domain: "shots", code: 3) }
        try png.write(to: url); return url
    }
}
