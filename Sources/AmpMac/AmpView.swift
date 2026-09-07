//  Amp for Mac — MIT licensed. See LICENSE.
//
//  The window: presets down the side, the amp on the right. One ScrollView with the header inside,
//  so the split view sizes and captures properly.

import SwiftUI
import AppKit

enum Mode: String, CaseIterable { case amp = "Amp", ear = "Ear" }

struct MainView: View {
    @EnvironmentObject var model: AmpModel
    @ObservedObject var ear = EarModel.shared
    var body: some View {
        NavigationSplitView {
            if model.mode == .amp { PresetSidebar() } else { HistorySidebar().environmentObject(ear) }
        } detail: {
            if model.mode == .amp { AmpPanel() } else { EarPanel().environmentObject(ear) }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $model.mode) { ForEach(Mode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) } }.pickerStyle(.segmented).frame(width: 160)
            }
        }
    }
}

struct PresetSidebar: View {
    @EnvironmentObject var model: AmpModel
    @State private var saving = false
    @State private var newName = ""
    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { model.presetName }, set: { if let n = $0 { model.select(named: n) } })) {
                ForEach(Presets.genres(for: model.params.instrument), id: \.self) { g in
                    Section(g) { ForEach(Presets.inGenre(g, instrument: model.params.instrument)) { p in Label(p.name, systemImage: icon(g)).tag(p.name) } }
                }
                if !model.userPresets.isEmpty {
                    Section("Mine") { ForEach(model.userPresets) { p in Label(p.name, systemImage: "person").tag(p.name) } }
                }
            }
            Divider()
            HStack {
                Button { newName = model.edited ? "" : model.presetName; saving = true } label: { Label("Save…", systemImage: "square.and.arrow.down") }
                Spacer()
                if model.edited { Button("Revert") { model.revert() } }
                Button(role: .destructive) { model.delete(named: model.presetName) } label: { Image(systemName: "trash") }
                    .disabled(Presets.builtIn.contains { $0.name == model.presetName }).help("Delete this preset of yours")
            }.buttonStyle(.borderless).padding(10)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        .sheet(isPresented: $saving) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save these knobs as").font(.headline)
                TextField("Name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 300).onSubmit(save)
                if Presets.builtIn.contains(where: { $0.name == newName.trimmingCharacters(in: .whitespaces) }) { Text("That is a built-in name. Pick another.").font(.caption).foregroundStyle(.red) }
                HStack { Spacer(); Button("Cancel") { saving = false }.keyboardShortcut(.cancelAction); Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }.padding(20)
        }
    }
    private func save() { model.save(as: newName); saving = false }
    private func icon(_ genre: String) -> String {
        switch genre {
        case "Rock": return "guitars"; case "Pop": return "sparkles"; case "Hip Hop": return "waveform"; case "Jazz": return "moon.stars"; case "Metal": return "bolt.horizontal"
        case "Soul & Funk": return "record.circle"; case "Country & Folk": return "leaf"; case "Punk & Garage": return "car"; case "Blues": return "music.quarternote.3"
        case "Reggae": return "sun.max"; case "Electronic": return "cpu"; case "Studio": return "circle"
        case "Clean": return "drop"; case "Crunch": return "flame"; case "Lead": return "star"; case "Country": return "leaf"; case "Indie": return "guitars"
        default: return "person"
        }
    }
}

struct AmpPanel: View {
    @EnvironmentObject var model: AmpModel
    private let columns = [GridItem(.adaptive(minimum: 360), spacing: 14, alignment: .top)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                MetersRow(meter: model.meter, running: model.running)
                LazyVGrid(columns: columns, spacing: 14) {
                    if model.params.instrument == .guitar { guitarCards } else { drumCards }
                }
                Text(model.params.instrument == .guitar
                     ? "Turn the interface's direct-monitor knob or switch off, or you hear the dry guitar and the amp together."
                     : "Turn the interface's direct-monitor knob or switch off, or you hear the dry kit and the amp together.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.meter.dropouts > 0 { Text("\(model.meter.dropouts) dropouts since start. A bigger buffer in Settings fixes that.").font(.callout).foregroundStyle(.orange) }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Amp for Mac")
    }

    @ViewBuilder private var drumCards: some View {
        Group {
                    SectionCard("Gate", on: $model.params.gateOn) {
                        Knob("Threshold", value: $model.params.gateThreshold, range: -80...0, unit: "dB")
                        Knob("Release", value: $model.params.gateRelease, range: 10...500, unit: "ms")
                    }
                    SectionCard("Attack & Sustain", on: $model.params.shapeOn) {
                        Knob("Attack", value: $model.params.attack, range: -100...100, unit: "%")
                        Knob("Sustain", value: $model.params.sustain, range: -100...100, unit: "%")
                    }
                    SectionCard("Compressor", on: $model.params.compOn) {
                        Knob("Threshold", value: $model.params.compThreshold, range: -40...0, unit: "dB")
                        Knob("Ratio", value: $model.params.compRatio, range: 1...20, unit: ":1")
                        Knob("Attack", value: $model.params.compAttack, range: 0.1...50, unit: "ms", digits: 1)
                        Knob("Release", value: $model.params.compRelease, range: 10...500, unit: "ms")
                        Knob("Makeup", value: $model.params.compMakeup, range: 0...18, unit: "dB")
                        Knob("Mix", value: $model.params.compMix, range: 0...100, unit: "%")
                    }
                    SectionCard("Tone", on: $model.params.eqOn) {
                        Knob("Low", value: $model.params.lowGain, range: -12...12, unit: "dB")
                        Knob("Mid", value: $model.params.midGain, range: -12...12, unit: "dB")
                        Knob("Mid at", value: $model.params.midFreq, range: 200...5000, unit: "Hz")
                        Knob("Crack", value: $model.params.presenceGain, range: -12...12, unit: "dB")
                        Knob("High", value: $model.params.highGain, range: -12...12, unit: "dB")
                    }
                    SectionCard("Drive", on: $model.params.driveOn) {
                        Knob("Drive", value: $model.params.drive, range: 0...100, unit: "%")
                        Knob("Tone", value: $model.params.tone, range: 0...100, unit: "%")
                    }
                    SectionCard("Room", on: $model.params.roomOn) {
                        Knob("Size", value: $model.params.roomSize, range: 0...100, unit: "%")
                        Knob("Mix", value: $model.params.roomMix, range: 0...100, unit: "%")
                        Knob("Tone", value: $model.params.roomTone, range: 0...100, unit: "%")
                        Toggle("Cut the room with the gate (the 80s sound)", isOn: $model.params.roomGated).font(.callout)
                    }
                    SectionCard("Levels", on: nil) {
                        Knob("Input", value: $model.params.inputGain, range: -24...24, unit: "dB")
                        Toggle("Auto level: keep hits near \(Int(Level.target)) dB", isOn: $model.autoLevel).font(.callout)
                        Knob("Output", value: $model.params.outputGain, range: -24...24, unit: "dB")
                        Toggle("Limiter, ceiling half a dB under full", isOn: $model.params.limiterOn).font(.callout)
                    }
        }
    }

    @ViewBuilder private var guitarCards: some View {
        Group {
            SectionCard("Guitar", on: nil) {
                Picker("Plugged in", selection: $model.params.input) {
                    ForEach(InputKind.allCases) { k in Text(k.title).tag(k) }
                }.pickerStyle(.segmented)
                if model.params.input == .auto {
                    HStack(spacing: 6) {
                        Image(systemName: model.meter.hearing == .acoustic ? "guitars" : "guitars.fill")
                        Text(model.running ? "Hearing \(model.meter.hearing.title.lowercased())" : "It listens once you start playing")
                    }.font(.callout).foregroundStyle(.secondary)
                }
                if model.hearingAcoustic {
                    Knob("Pickup", value: $model.params.pickup, range: 0...100, unit: "")
                    Text("An acoustic is made to look like a magnetic pickup before the amp sees it: the body boom, the piezo quack and the air above five kilohertz come off, and a coil's own resonance goes on. 0 is a neck pickup, 100 a bridge.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            SectionCard("Amp", on: nil) {
                Knob("Gain", value: $model.params.gain, range: 0...100, unit: "")
                Knob("Bass", value: $model.params.bass, range: 0...100, unit: "")
                Knob("Middle", value: $model.params.middle, range: 0...100, unit: "")
                Knob("Treble", value: $model.params.treble, range: 0...100, unit: "")
                Knob("Presence", value: $model.params.guitarPresence, range: 0...100, unit: "")
                Knob("Master", value: $model.params.master, range: 0...100, unit: "")
                Knob("Sag", value: $model.params.sag, range: 0...100, unit: "")
                Toggle("Bright: sparkle at low gain, out of the way when you turn up", isOn: $model.params.bright).font(.callout)
            }
            SectionCard("Speaker", on: nil) {
                Picker("Cabinet", selection: $model.params.cab) {
                    ForEach(Cab.allCases) { c in Text(c.title).tag(c) }
                }.pickerStyle(.radioGroup)
                Text("The speaker is most of what makes an amp an amp. With none, you hear the electronics on their own, which is what a direct box sounds like.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SectionCard("Gate", on: $model.params.gateOn) {
                Knob("Threshold", value: $model.params.gateThreshold, range: -80...0, unit: "dB")
                Knob("Release", value: $model.params.gateRelease, range: 10...500, unit: "ms")
            }
            SectionCard("Room", on: $model.params.roomOn) {
                Knob("Size", value: $model.params.roomSize, range: 0...100, unit: "%")
                Knob("Mix", value: $model.params.roomMix, range: 0...100, unit: "%")
                Knob("Tone", value: $model.params.roomTone, range: 0...100, unit: "%")
            }
            SectionCard("Levels", on: nil) {
                Knob("Input", value: $model.params.inputGain, range: -24...24, unit: "dB")
                Knob("Output", value: $model.params.outputGain, range: -24...24, unit: "dB")
                Toggle("Limiter, ceiling half a dB under full", isOn: $model.params.limiterOn).font(.callout)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Button { model.toggle() } label: {
                Image(systemName: "power").font(.system(size: 28, weight: .bold))
                    .frame(width: 66, height: 66)
                    .background(model.running ? Color.orange : Color.secondary.opacity(0.18), in: Circle())
                    .foregroundStyle(model.running ? .white : .secondary)
                    .shadow(color: model.running ? .orange.opacity(0.6) : .clear, radius: 12)
            }.buttonStyle(.plain).help(model.running ? "Stop listening (⌘L)" : "Start listening (⌘L)").accessibilityLabel(model.running ? "Stop listening" : "Start listening")
            VStack(alignment: .leading, spacing: 6) {
                Picker("Instrument", selection: Binding(get: { model.params.instrument }, set: { model.switchTo($0) })) {
                    ForEach(Instrument.allCases) { i in Text(i.title).tag(i) }
                }.pickerStyle(.segmented).frame(width: 190).labelsHidden()
                HStack(spacing: 8) {
                    Text(model.presetName).font(.title.bold())
                    if model.edited { Text("edited").font(.caption).padding(.horizontal, 7).padding(.vertical, 2).background(.orange.opacity(0.2), in: Capsule()) }
                }
                Text(model.statusLine).foregroundStyle(model.problem == nil ? Color.secondary : Color.orange).fixedSize(horizontal: false, vertical: true)
                if model.running, let a = model.advice {
                    HStack(spacing: 6) {
                        Circle().fill(adviceColor(a.kind)).frame(width: 9, height: 9)
                        Text(a.text).font(.callout).foregroundStyle(a.kind == .good ? Color.secondary : Color.primary)
                    }.transition(.opacity)
                }
                if model.micDenied { Button("Open Microphone settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }.buttonStyle(.link).font(.callout) }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Picker("Input", selection: $model.inputUID) { ForEach(model.devices.filter { $0.inputs > 0 }) { d in Text(d.name).tag(d.uid as String?) } }
                if let d = model.inputDevice, d.inputs > 1 {
                    Picker("Channel", selection: $model.inputChannel) { ForEach(0..<d.inputs, id: \.self) { i in Text(d.channelLabel(i)).tag(i) } }
                }
                Picker("Output", selection: $model.outputUID) { ForEach(model.devices.filter { $0.outputs > 0 }) { d in Text(d.name).tag(d.uid as String?) } }
            }.frame(width: 340).labelsHidden().controlSize(.small)
        }
    }
}

private func adviceColor(_ k: Level.Kind) -> Color {
    switch k { case .clipping: return .red; case .hot: return .orange; case .good: return .green; case .quiet: return .yellow; case .silent: return .secondary }
}

struct MetersRow: View {
    let meter: MeterState, running: Bool
    var body: some View {
        HStack(spacing: 18) {
            LevelMeter(label: "In", db: running ? meter.inDb : -80)
            LevelMeter(label: "Out", db: running ? meter.outDb : -80)
            HStack(spacing: 6) {
                Circle().fill(running && meter.gateOpen ? Color.green : Color.secondary.opacity(0.25)).frame(width: 12, height: 12)
                Text("Gate").font(.caption).foregroundStyle(.secondary)
            }.frame(width: 60)
            ReductionMeter(label: "Squash", db: running ? meter.compGr : 0)
            ReductionMeter(label: "Limit", db: running ? meter.limiterGr : 0)
        }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LevelMeter: View {
    let label: String, db: Float
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3).fill(db > -3 ? Color.red : db > -12 ? Color.yellow : Color.green)
                        .frame(width: g.size.width * CGFloat(min(max((db + 60) / 60, 0), 1)))
                }
            }.frame(height: 12)
            Text(db <= -79 ? "–" : String(format: "%.0f", db)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
    }
}

struct ReductionMeter: View {
    let label: String, db: Float
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize()
            GeometryReader { g in
                ZStack(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3).fill(Color.orange).frame(width: g.size.width * CGFloat(min(max(db / 20, 0), 1)))
                }
            }.frame(width: 90, height: 12)
            Text(String(format: "%.0f", -db)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let on: Binding<Bool>?
    @ViewBuilder let content: Content
    init(_ title: String, on: Binding<Bool>?, @ViewBuilder content: () -> Content) { self.title = title; self.on = on; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let on { Toggle("", isOn: on).toggleStyle(.switch).controlSize(.small).labelsHidden().accessibilityLabel("\(title) on") }
            }
            content.disabled(on?.wrappedValue == false).opacity(on?.wrappedValue == false ? 0.45 : 1)
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Knob: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let unit: String
    var digits = 0
    init(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, unit: String, digits: Int = 0) { self.label = label; _value = value; self.range = range; self.unit = unit; self.digits = digits }
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.callout).frame(width: 72, alignment: .trailing)
            Slider(value: $value, in: range).controlSize(.small)
            Text(String(format: "%.\(digits)f %@", value, unit)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
        }.accessibilityElement(children: .combine).accessibilityLabel(label)
    }
}
