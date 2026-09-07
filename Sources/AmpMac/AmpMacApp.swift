//  Amp for Mac — MIT licensed. See LICENSE.
//
//  A drum amp for the input of your audio interface. It listens to one input and plays to one
//  output. Nothing is recorded, nothing leaves the Mac.

import SwiftUI
import AppKit
import ServiceManagement
import AVFoundation

@main
struct AmpMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AmpModel.shared
    init() { CLI.runIfRequested() }
    var body: some Scene {
        WindowGroup("Amp for Mac") {
            MainView().environmentObject(model).frame(minWidth: 900, idealWidth: 1000, minHeight: 620, idealHeight: 700)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button(model.running ? "Stop the Amp" : "Start the Amp") { model.toggle() }.keyboardShortcut("l", modifiers: .command)
                Button(EarModel.shared.listening ? "Stop the Ear" : "Start the Ear") { model.mode = .ear; EarModel.shared.toggle() }.keyboardShortcut("e", modifiers: .command)
                Divider()
                ForEach(Array(Presets.builtIn.prefix(9).enumerated()), id: \.offset) { i, p in
                    Button(p.name) { model.select(named: p.name) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
            CommandGroup(replacing: .help) {
                Button("Amp for Mac Help") { Help.open() }
                Button("Check for Updates…") { Updates.checkAndPresent() }
                Button("Report a Problem…") { NSWorkspace.shared.open(URL(string: "https://github.com/keithadler/ampmac/issues")!) }
                Divider()
                Button("More from the Same Maker…") { NSWorkspace.shared.open(URL(string: "https://keithadler.github.io")!) }
            }
        }
        Settings { SettingsView().environmentObject(model) }
        MenuBarExtra(isInserted: .constant(Prefs.menuBar)) {
            Button(model.running ? "Stop the Amp" : "Start the Amp") { model.toggle() }
            Menu("Preset") { ForEach(Presets.all(user: model.userPresets)) { p in Button(p.name) { model.select(named: p.name) } } }
            Divider()
            Button("Open Amp for Mac") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.title == "Amp for Mac" }?.makeKeyAndOrderFront(nil) }
            Button("Quit") { NSApp.terminate(nil) }
        } label: { Image(systemName: model.running ? "amplifier" : "amplifier").symbolRenderingMode(.hierarchical) }
    }
}

struct MeterState: Equatable {
    var inDb: Float = -80, outDb: Float = -80, gateOpen = false, compGr: Float = 0, limiterGr: Float = 0, dropouts: UInt32 = 0
    var hearing: InputKind = .electric
}

@MainActor
final class AmpModel: ObservableObject {
    static let shared = AmpModel()
    let engine = Engine.shared
    @Published var params: AmpParams { didSet { guard !loading else { return }; engine.params.set(params); Prefs.params = params; edited = differs(params, base) } }
    @Published var mode: Mode = Mode(rawValue: Prefs.defaults.string(forKey: "mode") ?? "") ?? .amp { didSet { Prefs.defaults.set(mode.rawValue, forKey: "mode") } }
    @Published var autoLevel = Prefs.autoLevel { didSet { Prefs.autoLevel = autoLevel } }
    @Published var advice: Level.Advice?
    private var recent = Level.Recent()
    /// With auto level on, the input gain is the amp's business, not an edit.
    private func differs(_ a: AmpParams, _ b: AmpParams) -> Bool { var x = a, y = b; if autoLevel { x.inputGain = 0; y.inputGain = 0 }; return x != y }
    @Published var presetName: String { didSet { Prefs.presetName = presetName } }
    @Published var edited = false
    @Published var devices: [AudioDevice] = []
    @Published var inputUID: String? { didSet { guard !loading else { return }; Prefs.inputUID = inputUID; if let d = inputDevice { inputChannel = d.uid == oldValue ? min(inputChannel, d.inputs - 1) : d.defaultInputChannel }; restartIfRunning() } }
    @Published var outputUID: String? { didSet { guard !loading else { return }; Prefs.outputUID = outputUID; restartIfRunning() } }
    @Published var inputChannel = 0 { didSet { guard !loading else { return }; Prefs.inputChannel = inputChannel; restartIfRunning() } }
    @Published var running = false
    @Published var problem: String?
    @Published var meter = MeterState()
    @Published var userPresets = Prefs.userPresets
    @Published var micDenied = false
    /// Screenshots: fixed meters, no engine.
    var demo = false
    private var base = AmpParams()
    private var loading = false
    private var timer: Timer?

    init() {
        loading = true
        let name = Prefs.presetName ?? "Rock Room"
        let preset = Presets.named(name) ?? Presets.builtIn[2]
        presetName = preset.name; base = preset.params
        params = Prefs.params ?? preset.params
        edited = differs(params, base)
        inputUID = Prefs.inputUID; outputUID = Prefs.outputUID; inputChannel = Prefs.inputChannel ?? 0
        loading = false
        refreshDevices()
        engine.params.set(params)
    }

    /// Whether the acoustic knobs are worth showing: either it was told, or it heard one.
    var hearingAcoustic: Bool {
        params.instrument == .guitar && (params.input == .acoustic || (params.input == .auto && meter.hearing == .acoustic))
    }
    var inputDevice: AudioDevice? { devices.first { $0.uid == inputUID } }
    var outputDevice: AudioDevice? { devices.first { $0.uid == outputUID } }
    var latencyMs: Double {
        if running, !demo { return engine.roundTripMs }
        guard let i = inputDevice, let o = outputDevice else { return 0 }
        return Devices.roundTripMs(input: i, output: o, bufferFrames: Prefs.bufferFrames)
    }
    var statusLine: String {
        if let problem { return problem }
        guard let i = inputDevice, let o = outputDevice else { return "No audio interface found. Plug it in, or pick the Mac's own input and output." }
        let route = i.uid == o.uid ? "\(i.name), \(i.channelLabel(inputChannel))" : "\(i.name), \(i.channelLabel(inputChannel)) → \(o.name)"
        if running { return String(format: "Listening on %@. About %.1f ms round trip.", route, latencyMs) }
        return "Off. Ready on \(route)."
    }

    func refreshDevices() {
        let list = Devices.all()
        let wasLoading = loading; loading = true
        devices = list
        if inputUID == nil || !list.contains(where: { $0.uid == inputUID }), let d = Devices.defaultChoice(list) { inputUID = d.input.uid; inputChannel = Prefs.inputChannel ?? d.input.defaultInputChannel }
        if outputUID == nil || !list.contains(where: { $0.uid == outputUID }), let d = Devices.defaultChoice(list) { outputUID = d.output.uid }
        if let d = inputDevice, inputChannel >= d.inputs { inputChannel = d.defaultInputChannel }
        loading = wasLoading
        if running, !demo, inputDevice == nil || outputDevice == nil { stop(); problem = "The interface went away." }
    }

    func toggle() { running ? stop() : start() }

    func start() {
        problem = nil
        guard let i = inputDevice, let o = outputDevice else { problem = "Pick an input and an output first."; return }
        switch Engine.microphoneAllowed() {
        case .authorized: begin(i, o)
        case .notDetermined:
            Task { @MainActor [weak self] in
                let ok = await Engine.requestMicrophone()
                guard let self else { return }
                if ok { self.begin(i, o) } else { self.micDenied = true; self.problem = "Microphone permission was not given, so the amp cannot hear the interface." }
            }
        default: micDenied = true; problem = "Microphone permission is off for Amp for Mac. Turn it on in System Settings › Privacy & Security › Microphone."
        }
    }
    private func begin(_ i: AudioDevice, _ o: AudioDevice) {
        do {
            try engine.start(input: i, output: o, inputChannel: inputChannel, bufferFrames: Prefs.bufferFrames, params: params)
            running = true; Prefs.wasRunning = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        } catch { problem = error.localizedDescription; running = false }
    }
    func stop() {
        engine.stop(); running = false; Prefs.wasRunning = false
        timer?.invalidate(); timer = nil
        meter = MeterState(); advice = nil; recent.clear()
    }
    private func restartIfRunning() { if running, !demo { stop(); start() } }
    private func tick() {
        let m = engine.meters
        var s = meter
        let inDb = gainToDb(m.inPeak), outDb = gainToDb(m.outPeak)
        s.inDb = max(inDb, s.inDb - 1.5); s.outDb = max(outDb, s.outDb - 1.5)
        s.gateOpen = m.gateOpen; s.compGr = max(m.compGr, s.compGr - 0.8); s.limiterGr = max(m.limiterGr, s.limiterGr - 0.8); s.dropouts = m.dropouts
        s.hearing = m.hearing
        meter = s
        let raw = recent.add(inDb)
        let a = Level.advice(rawPeakDb: raw, interface: inputDevice?.name ?? "the interface")
        if a != advice { advice = a }
        if autoLevel {
            let g = Level.autoStep(gain: params.inputGain, rawPeakDb: raw)
            if g != params.inputGain { params.inputGain = g }
        }
    }

    /// Changing instrument is changing amp: the knobs mean different things, so it loads that bank's
    /// first preset rather than trying to carry drum settings across.
    func switchTo(_ instrument: Instrument) {
        guard params.instrument != instrument else { return }
        let wanted = instrument == .drums ? "Rock Room" : "Soho '66"
        let bank = instrument == .drums ? Presets.drumPresets : Presets.guitarPresets
        select(named: (bank.first { $0.name == wanted } ?? bank[0]).name)
    }

    // MARK: Presets
    func select(named name: String) {
        guard let p = Presets.named(name, user: userPresets) else { return }
        presetName = p.name; base = p.params; params = p.params; edited = false
    }
    func save(as name: String) {
        let n = name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty, !Presets.builtIn.contains(where: { $0.name == n }) else { return }
        var list = userPresets.filter { $0.name != n }; list.append(Preset(name: n, params: params)); list.sort { $0.name < $1.name }
        userPresets = list; Prefs.userPresets = list
        presetName = n; base = params; edited = false
    }
    func delete(named name: String) {
        userPresets.removeAll { $0.name == name }; Prefs.userPresets = userPresets
        if presetName == name { select(named: "Rock Room") }
    }
    func revert() { params = base; edited = false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["AMPMAC_HOME"] == nil, !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered"); try? SMAppService.mainApp.register()
        }
        Updates.scheduleBackgroundChecks()
        Devices.onChange = { Task { @MainActor in AmpModel.shared.refreshDevices() } }
        Devices.listen()
        if Prefs.resumeOnOpen, Prefs.wasRunning { AmpModel.shared.start() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !Prefs.menuBar && !AmpModel.shared.running }
    func applicationWillTerminate(_ notification: Notification) { Engine.shared.stop(); EarModel.shared.capture.stop() }
}

enum Help {
    static var pageName: String { (Locale.preferredLanguages.first ?? "en").hasPrefix("es") ? "Help.es" : "Help" }
    static var bundledPage: URL? {
        if let url = Bundle.main.url(forResource: pageName, withExtension: "html") { return url }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" { if url.pathExtension == "app", let u = Bundle(url: url)?.url(forResource: pageName, withExtension: "html") { return u }; url = url.deletingLastPathComponent() }
        return nil
    }
    @MainActor static func open() { NSWorkspace.shared.open(bundledPage ?? URL(string: "https://github.com/keithadler/ampmac#readme")!) }
}

struct SettingsView: View {
    @EnvironmentObject var model: AmpModel
    @State private var resume = Prefs.resumeOnOpen
    @State private var menuBar = Prefs.menuBar
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var updates = Updates.enabled
    @State private var buffer = Prefs.bufferFrames
    var body: some View {
        Form {
            Section("Audio") {
                Picker("Buffer size", selection: $buffer) {
                    ForEach([32, 64, 128, 256, 512], id: \.self) { n in Text("\(n) frames").tag(n) }
                }.onChange(of: buffer) { _, v in Prefs.bufferFrames = v; if model.running { model.stop(); model.start() } }
                Text("Smaller is quicker to the ear and harder on the Mac. 128 is a safe start; try 64 on Apple Silicon.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Microphone permission: \(AVAuthorizationStatusLike(Engine.microphoneAllowed()).word)")
                    Spacer()
                    Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
                }
                Text("macOS treats an interface input as a microphone. Amp for Mac needs that permission to hear the drums. It records nothing.").font(.caption).foregroundStyle(.secondary)
            }
            Section("App") {
                Toggle("Start listening again when the app opens", isOn: $resume).onChange(of: resume) { _, v in Prefs.resumeOnOpen = v }
                Toggle("Open at login", isOn: $login).onChange(of: login) { _, v in if v { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() } }
                Toggle("Show in the menu bar", isOn: $menuBar).onChange(of: menuBar) { _, v in Prefs.menuBar = v }
                Toggle("Check for updates daily", isOn: $updates).onChange(of: updates) { _, v in Updates.enabled = v }
            }
        }.formStyle(.grouped).frame(width: 520).padding(.bottom, 8)
    }
}
