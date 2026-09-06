//  Amp for Mac — MIT licensed. See LICENSE.
//
//  The Ear: what is playing, in what key, with which capo, and everything it heard before.

import SwiftUI
import AppKit

@MainActor
final class EarModel: ObservableObject {
    static let shared = EarModel()
    let capture = Capture()
    @Published var listening = false
    @Published var source: Capture.Source = Capture.macSoundAvailable ? .mac : .device("") { didSet { if let d = try? Presets.encoder.encode(source) { Prefs.defaults.set(d, forKey: "earSource") }; if listening { stop(); start() } } }
    @Published var chord: Chord?
    @Published var key: Key?
    @Published var capo: Int? { didSet { Prefs.defaults.set(capo ?? -1, forKey: "capo") } }
    @Published var events: [ChordEvent] = []
    @Published var elapsed: Double = 0
    @Published var problem: String?
    @Published var listens: [Listen] = History.load()
    @Published var viewing: Listen?
    /// Screenshots: fixed state, no capture.
    var demo = false
    private var session = EarSession()
    private var timer: DispatchSourceTimer?
    private var busy = false

    init() {
        if let d = Prefs.defaults.data(forKey: "earSource"), let s = try? JSONDecoder().decode(Capture.Source.self, from: d) { source = s }
        let c = Prefs.defaults.integer(forKey: "capo"); capo = c >= 0 && Prefs.defaults.object(forKey: "capo") != nil ? c : nil
    }

    var capoOptions: [CapoOption] { key.map { Capo.options(for: $0) } ?? [] }
    var flats: Bool { key?.flats ?? false }
    func shown(_ c: Chord) -> String { capo.map { c.shape(capo: $0).name(flats: flats) } ?? c.name(flats: flats) }
    var statusLine: String {
        if let problem { return problem }
        if listening { return "Listening to \(source.label). \(Int(elapsed)) s." }
        return "Off. Press the button and play something on the Mac, or through the input."
    }

    func toggle() { listening ? stop() : start() }
    func start() {
        problem = nil; viewing = nil
        session = EarSession(); events = []; chord = nil; key = nil; elapsed = 0
        do { try capture.start(source) } catch { problem = error.localizedDescription; return }
        listening = true
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        t.schedule(deadline: .now() + 0.6, repeating: 0.25)
        t.setEventHandler { [weak self] in self?.analyse() }
        t.resume(); timer = t
    }
    nonisolated private func analyse() {
        let (samples, rate, started) = MainActor.assumeIsolatedIfPossible { (self.capture.latest(seconds: 0.6), self.capture.sampleRate, self.session.started) }
        guard samples.count > 1024 else { return }
        let chroma = Chroma.of(samples, sampleRate: Float(rate))
        let at = Date().timeIntervalSince(started)
        Task { @MainActor in
            guard self.listening else { return }
            self.session.add(chroma, at: at)
            self.elapsed = at
            if self.chord != self.session.current { self.chord = self.session.current }
            if self.key != self.session.key { self.key = self.session.key; if let k = self.key, self.capo == nil, let best = Capo.options(for: k).first, best.fret != 0 { /* suggest, do not set */ _ = best } }
            if self.events.count != self.session.events.count { self.events = self.session.events }
        }
    }
    func stop() {
        timer?.cancel(); timer = nil
        capture.stop(); listening = false
        if !session.events.isEmpty {
            let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
            let l = Listen(started: session.started, title: "Listen at \(f.string(from: session.started))", seconds: elapsed, key: session.key, events: session.events)
            History.add(l); listens = History.load(); viewing = l
        }
    }
    func rename(_ l: Listen, to title: String) {
        guard let i = listens.firstIndex(where: { $0.id == l.id }) else { return }
        listens[i].title = title; History.save(listens); if viewing?.id == l.id { viewing = listens[i] }
    }
    func delete(_ l: Listen) { listens.removeAll { $0.id == l.id }; History.save(listens); if viewing?.id == l.id { viewing = nil } }
    func show(_ l: Listen) { viewing = l; key = l.key; events = l.events; chord = nil }
}

extension MainActor {
    /// The capture buffer is locked on its own; this only reads two values the model owns.
    nonisolated static func assumeIsolatedIfPossible<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
}

struct EarPanel: View {
    @EnvironmentObject var ear: EarModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let v = ear.viewing { ListenCard(listen: v) } else { liveCard }
                capoCard
                timelineCard
                Text("The Ear hears chords and keys the way a tuner hears pitch: well on a clear mix, less well on a wall of distortion. It records nothing.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.navigationTitle("Amp for Mac")
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Button { ear.toggle() } label: {
                Image(systemName: "ear").font(.system(size: 28, weight: .bold)).frame(width: 66, height: 66)
                    .background(ear.listening ? Color.teal : Color.secondary.opacity(0.18), in: Circle())
                    .foregroundStyle(ear.listening ? .white : .secondary)
                    .shadow(color: ear.listening ? .teal.opacity(0.6) : .clear, radius: 12)
            }.buttonStyle(.plain).help(ear.listening ? "Stop listening (⌘E)" : "Listen (⌘E)").accessibilityLabel(ear.listening ? "Stop listening" : "Listen")
            VStack(alignment: .leading, spacing: 6) {
                Text(ear.viewing?.title ?? "Ear").font(.title.bold())
                Text(ear.statusLine).foregroundStyle(ear.problem == nil ? Color.secondary : Color.orange).fixedSize(horizontal: false, vertical: true)
                if ear.problem?.contains("Privacy") == true { Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!) }.buttonStyle(.link).font(.callout) }
            }
            Spacer(minLength: 12)
            Picker("Source", selection: $ear.source) {
                if Capture.macSoundAvailable { Text("The Mac's own sound").tag(Capture.Source.mac) }
                ForEach(Devices.inputs()) { d in Text(d.name).tag(Capture.Source.device(d.uid)) }
            }.frame(width: 260).labelsHidden().controlSize(.small)
        }
    }
    private var liveCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Now").font(.caption).foregroundStyle(.secondary)
                Text(ear.chord.map { ear.shown($0) } ?? "–").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                if let c = ear.chord, ear.capo != nil { Text("sounds as \(c.name(flats: ear.flats))").font(.callout).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Key").font(.caption).foregroundStyle(.secondary)
                Text(ear.key?.name ?? "–").font(.system(size: 34, weight: .semibold, design: .rounded))
            }
            Spacer()
        }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
    private var capoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capo").font(.headline)
            if ear.capoOptions.isEmpty { Text("The key shows up after a few chords, and the capo choices with it.").font(.callout).foregroundStyle(.secondary) }
            else {
                Picker("Capo", selection: $ear.capo) {
                    Text("Show the real chords").tag(Int?.none)
                    ForEach(ear.capoOptions) { o in Text(o.line + (o.ease == 0 ? "  (easiest)" : "")).tag(Int?.some(o.fret)) }
                }.pickerStyle(.radioGroup).labelsHidden()
                Text("With a capo chosen, every chord below is the shape your hand makes.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chords, in order").font(.headline)
            if ear.events.isEmpty { Text("Nothing yet.").font(.callout).foregroundStyle(.secondary) }
            else {
                ChordFlow(names: merged(ear.events))
            }
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
    private func merged(_ events: [ChordEvent]) -> [(String, String)] {
        var out: [(String, String)] = []
        for e in events { let n = ear.shown(e.chord); if out.last?.0 != n { out.append((n, String(format: "%d:%02d", Int(e.at) / 60, Int(e.at) % 60))) } }
        return out
    }
}

/// Chips that wrap.
struct ChordFlow: View {
    let names: [(String, String)]
    var body: some View {
        var width: CGFloat = 0, height: CGFloat = 0
        return GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                    VStack(spacing: 2) { Text(n.0).font(.title3.bold()); Text(n.1).font(.caption2).foregroundStyle(.secondary) }
                        .padding(.horizontal, 10).padding(.vertical, 6).background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        .alignmentGuide(.leading) { d in
                            if abs(width - d.width) > g.size.width { width = 0; height -= d.height + 8 }
                            let r = width; if i == names.count - 1 { width = 0 } else { width -= d.width + 8 }; return r
                        }
                        .alignmentGuide(.top) { _ in let r = height; if i == names.count - 1 { height = 0 }; return r }
                }
            }
        }.frame(minHeight: CGFloat(max(1, (names.count + 7) / 8)) * 56)
    }
}

struct ListenCard: View {
    @EnvironmentObject var ear: EarModel
    let listen: Listen
    @State private var title = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: $title).textFieldStyle(.roundedBorder).font(.title3).frame(maxWidth: 360)
                    .onAppear { title = listen.title }.onSubmit { ear.rename(listen, to: title) }
                Spacer()
                Button("Back to live") { ear.viewing = nil; ear.events = []; ear.key = nil }
                Button(role: .destructive) { ear.delete(listen) } label: { Image(systemName: "trash") }
            }
            Text("\(listen.started.formatted(date: .abbreviated, time: .shortened)), \(Int(listen.seconds)) s, \(listen.key?.name ?? "key unknown")").font(.callout).foregroundStyle(.secondary)
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HistorySidebar: View {
    @EnvironmentObject var ear: EarModel
    var body: some View {
        List(selection: Binding(get: { ear.viewing?.id }, set: { id in if let l = ear.listens.first(where: { $0.id == id }) { ear.show(l) } })) {
            Section("Heard before") {
                if ear.listens.isEmpty { Text("Nothing yet. Every listen lands here.").foregroundStyle(.secondary) }
                ForEach(ear.listens.reversed()) { l in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.title).lineLimit(1)
                        Text((l.key?.name ?? "") + (l.chordNames.isEmpty ? "" : " · " + l.chordNames.prefix(4).joined(separator: " "))).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.tag(l.id)
                }
            }
        }.navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
    }
}
