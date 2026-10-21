// Draws the 1024 px app icon: a pilot lamp over a speaker-cone impulse. Usage: swift make_icon.swift out.png
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 100, dy: 100), xRadius: 185, yRadius: 185)
NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.13, alpha: 1).setFill()
bg.fill()
// grille cloth lines
ctx.saveGState()
bg.addClip()
NSColor(calibratedWhite: 1, alpha: 0.04).setStroke()
for i in stride(from: -900.0, to: 1100, by: 26) {
    let p = NSBezierPath(); p.move(to: NSPoint(x: i, y: 0)); p.line(to: NSPoint(x: i + 1024, y: 1024)); p.lineWidth = 6; p.stroke()
}
ctx.restoreGState()
// impulse response trace
let trace = NSBezierPath()
let x0 = 190.0, x1 = 834.0, mid = 450.0
trace.move(to: NSPoint(x: x0, y: mid))
trace.line(to: NSPoint(x: 300, y: mid))
for i in 0..<240 {
    let t = Double(i) / 240
    let x = 300 + t * (x1 - 300)
    let y = mid + 230 * exp(-t * 5.5) * sin(t * 62) * (i == 0 ? 0 : 1)
    trace.line(to: NSPoint(x: x, y: y))
}
trace.lineWidth = 22; trace.lineJoinStyle = .round; trace.lineCapStyle = .round
NSColor(calibratedRed: 0.91, green: 0.59, blue: 0.18, alpha: 1).setStroke()
trace.stroke()
// pilot lamp
let lamp = CGRect(x: 690, y: 690, width: 92, height: 92)
for r in stride(from: 70.0, to: 0, by: -10) {
    NSColor(calibratedRed: 0.94, green: 0.63, blue: 0.25, alpha: 0.05).setFill()
    NSBezierPath(ovalIn: lamp.insetBy(dx: -r, dy: -r)).fill()
}
NSColor(calibratedRed: 1, green: 0.72, blue: 0.33, alpha: 1).setFill()
NSBezierPath(ovalIn: lamp).fill()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
