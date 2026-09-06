//  Amp for Mac — MIT licensed. See LICENSE.
//  Promo cards for the announcement, 1600×900 at 2×.

import AppKit
import SwiftUI

enum Promo {
    @MainActor static func render(to dir: URL, screenshots: URL) throws -> [URL] {
        let out = dir.appendingPathComponent("promo"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var written: [URL] = []
        let cards: [(String, String, String, String?)] = [
            ("1-hero", "Your kit through a drum amp.\nOn this Mac.", "Seventeen drum sounds, from Motown to Nevermind, in real time from the input of the interface you already own.", "amp.png"),
            ("2-card", "It hears the key.\nCapo 3, play in C.", "The Ear listens to whatever the Mac is playing, names the chords as they go by, and says where the capo goes so the easy shapes play it. Every listen is kept.", "ear.png"),
            ("3-honest", "It listens to one input.\nIt records nothing.", "Not a plugin, so it will not load in Logic. The delay is your interface's, a few milliseconds. Turn direct monitor off or you hear the kit twice.", "off.png"),
            ("4-free", "Free. Open source. Works on a recording too.", "ampmac render kit.wav kit-room.wav --preset \"Rock Room\"   MIT licensed, no server, no account.", nil),
        ]
        for (name, title, sub, shot) in cards {
            let view = Card(title: title, subtitle: sub, image: shot.flatMap { NSImage(contentsOf: screenshots.appendingPathComponent($0)) })
            let host = NSHostingView(rootView: view); host.frame = NSRect(x: 0, y: 0, width: 1600, height: 900)
            let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false); w.contentView = host; w.orderFront(nil)
            Screenshots.settle()
            written.append(try Screenshots.capture(w, to: out.appendingPathComponent("\(name).png"))); w.orderOut(nil)
        }
        return written
    }
    struct Card: View {
        let title: String, subtitle: String, image: NSImage?
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.07, blue: 0.05), Color(red: 0.58, green: 0.28, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 12) { Image(systemName: "amplifier").font(.system(size: 34)); Text("Amp for Mac").font(.system(size: 30, weight: .semibold)) }.foregroundStyle(.white.opacity(0.85))
                        Text(title).font(.system(size: image == nil ? 60 : 48, weight: .bold, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                        Text(subtitle).font(.system(size: 26)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    }.frame(width: image == nil ? 1300 : 620, alignment: .leading)
                    if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 820).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(radius: 30, y: 12) }
                }.padding(80)
            }.frame(width: 1600, height: 900)
        }
    }
}
