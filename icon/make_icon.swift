import AppKit
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let dir = "icon/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1), NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)])!.draw(in: path, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold).applying(.init(paletteColors: [NSColor(red: 0.35, green: 0.85, blue: 0.6, alpha: 1)]))
    if let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let sz = img.size
        img.draw(in: NSRect(x: s*0.28, y: (s - sz.height)/2, width: sz.width, height: sz.height))
    }
    let bar = NSBezierPath(roundedRect: NSRect(x: s*0.5, y: s*0.33, width: s*0.22, height: s*0.06), xRadius: s*0.02, yRadius: s*0.02)
    NSColor(white: 0.9, alpha: 1).setFill(); bar.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
