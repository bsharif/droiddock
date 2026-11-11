// Draws the 1024x1024 app icon to the path given as the first argument.
// Run: swift packaging/make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: macOS-style rounded square with a deep teal gradient.
let inset: CGFloat = 100
let bg = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bgPath = NSBezierPath(roundedRect: bg, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.55, blue: 0.45, alpha: 1),
                    NSColor(srgbRed: 0.07, green: 0.30, blue: 0.26, alpha: 1)])!
    .draw(in: bgPath, angle: -90)

let white = NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1)

// Phone on the left.
let phone = NSRect(x: 215, y: 300, width: 210, height: 400)
let phonePath = NSBezierPath(roundedRect: phone, xRadius: 40, yRadius: 40)
phonePath.lineWidth = 28
white.setStroke()
phonePath.stroke()
white.setFill()
NSBezierPath(roundedRect: NSRect(x: 290, y: 645, width: 60, height: 14), xRadius: 7, yRadius: 7).fill()

// Laptop on the right.
let screen = NSRect(x: 575, y: 420, width: 240, height: 170)
let screenPath = NSBezierPath(roundedRect: screen, xRadius: 20, yRadius: 20)
screenPath.lineWidth = 28
screenPath.stroke()
NSBezierPath(roundedRect: NSRect(x: 540, y: 360, width: 310, height: 32), xRadius: 16, yRadius: 16).fill()

// Two arrows in the gap: phone to Mac (top), Mac to phone (bottom).
func arrow(y: CGFloat, toRight: Bool) {
    let x1: CGFloat = 455, x2: CGFloat = 545
    let p = NSBezierPath()
    p.lineWidth = 24
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    p.move(to: NSPoint(x: x1, y: y))
    p.line(to: NSPoint(x: x2, y: y))
    let tip = toRight ? x2 : x1
    let back: CGFloat = toRight ? -30 : 30
    p.move(to: NSPoint(x: tip + back, y: y + 28))
    p.line(to: NSPoint(x: tip, y: y))
    p.line(to: NSPoint(x: tip + back, y: y - 28))
    NSColor(srgbRed: 0.98, green: 0.80, blue: 0.40, alpha: 1).setStroke()
    p.stroke()
}
arrow(y: 560, toRight: true)
arrow(y: 450, toRight: false)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
