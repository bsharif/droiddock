// Draws simple sample "photos" for README screenshots (no real photos).
// Run: swift packaging/demo/make_demo_images.swift <out_dir>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

struct Scene { let sky: (NSColor, NSColor); let sun: NSColor; let hills: [NSColor] }
func c(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

let scenes: [Scene] = [
    Scene(sky: (c(0.98, 0.62, 0.36), c(0.55, 0.30, 0.55)), sun: c(1, 0.9, 0.6), hills: [c(0.35, 0.22, 0.40), c(0.22, 0.14, 0.28)]),
    Scene(sky: (c(0.55, 0.80, 0.98), c(0.25, 0.50, 0.85)), sun: c(1, 0.98, 0.85), hills: [c(0.35, 0.62, 0.38), c(0.20, 0.45, 0.28)]),
    Scene(sky: (c(0.10, 0.12, 0.30), c(0.30, 0.20, 0.50)), sun: c(0.95, 0.95, 0.85), hills: [c(0.12, 0.18, 0.30), c(0.06, 0.08, 0.16)]),
    Scene(sky: (c(0.98, 0.85, 0.55), c(0.95, 0.55, 0.35)), sun: c(1, 1, 0.9), hills: [c(0.80, 0.55, 0.35), c(0.60, 0.38, 0.25)]),
    Scene(sky: (c(0.70, 0.90, 0.95), c(0.40, 0.75, 0.85)), sun: c(1, 1, 1), hills: [c(0.25, 0.55, 0.60), c(0.10, 0.35, 0.45)]),
    Scene(sky: (c(0.85, 0.75, 0.95), c(0.55, 0.45, 0.80)), sun: c(1, 0.85, 0.95), hills: [c(0.45, 0.35, 0.60), c(0.30, 0.22, 0.45)]),
]

for (i, s) in scenes.enumerated() {
    let w = 800, h = 600
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: w, height: h)
    NSGradient(starting: s.sky.0, ending: s.sky.1)!.draw(in: rect, angle: -90)
    s.sun.setFill()
    NSBezierPath(ovalIn: NSRect(x: 480 - i * 40, y: 330, width: 140, height: 140)).fill()
    for (j, color) in s.hills.enumerated() {
        color.setFill()
        let p = NSBezierPath()
        let base = CGFloat(j) * 90
        p.move(to: NSPoint(x: 0, y: 0))
        p.line(to: NSPoint(x: 0, y: 260 - base))
        p.curve(to: NSPoint(x: 800, y: 200 - base), controlPoint1: NSPoint(x: 260, y: 420 - base),
                controlPoint2: NSPoint(x: 520, y: 80 - base))
        p.line(to: NSPoint(x: 800, y: 0))
        p.close()
        p.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/demo\(i).jpg"))
}
print("wrote \(scenes.count) images to \(out)")
