import AppKit
// Amp for Mac icon: a drum head seen from above on a warm amp-tolex tile, with a power dot.
func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s)); img.lockFocus()
    let inset = s * 0.06
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.10, alpha: 1), NSColor(calibratedRed: 0.14, green: 0.08, blue: 0.05, alpha: 1)])!.draw(in: tile, angle: -70)
    // grille lines, faint
    NSColor.white.withAlphaComponent(0.07).setStroke()
    var y = inset + s * 0.08
    while y < s - inset { let l = NSBezierPath(); l.move(to: NSPoint(x: inset + s * 0.05, y: y)); l.line(to: NSPoint(x: s - inset - s * 0.05, y: y)); l.lineWidth = s * 0.012; l.stroke(); y += s * 0.05 }
    // hoop
    let hoop = NSBezierPath(ovalIn: NSRect(x: s * 0.17, y: s * 0.17, width: s * 0.66, height: s * 0.66))
    NSColor(calibratedRed: 0.85, green: 0.80, blue: 0.72, alpha: 1).setFill(); hoop.fill()
    // head
    let head = NSBezierPath(ovalIn: NSRect(x: s * 0.22, y: s * 0.22, width: s * 0.56, height: s * 0.56))
    NSGradient(colors: [NSColor(calibratedWhite: 0.99, alpha: 1), NSColor(calibratedWhite: 0.86, alpha: 1)])!.draw(in: head, angle: -60)
    // lugs
    NSColor(calibratedRed: 0.30, green: 0.22, blue: 0.16, alpha: 1).setFill()
    for i in 0..<8 {
        let a = CGFloat(i) / 8 * 2 * .pi + .pi / 8
        let cx = s * 0.5 + cos(a) * s * 0.315, cy = s * 0.5 + sin(a) * s * 0.315
        NSBezierPath(ovalIn: NSRect(x: cx - s * 0.028, y: cy - s * 0.028, width: s * 0.056, height: s * 0.056)).fill()
    }
    // the power dot
    NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.70, y: s * 0.70, width: s * 0.11, height: s * 0.11)).fill()
    img.unlockFocus(); return img
}
let out = "icon/AmpMac.iconset"
try? FileManager.default.removeItem(atPath: out); try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px)); NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("iconset written")
