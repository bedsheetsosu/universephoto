// Original, code-drawn application artwork; no external image assets.
import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let variants = [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")]
for (size, name) in variants {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = graphics
    graphics.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let plate = NSBezierPath(roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848), xRadius: 192, yRadius: 192)
    NSGradient(starting: NSColor(srgbRed: 0.45, green: 0.30, blue: 0.95, alpha: 1), ending: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.30, alpha: 1))!.draw(in: plate, angle: -65)
    graphics.cgContext.saveGState()
    graphics.cgContext.translateBy(x: 512, y: 512)
    graphics.cgContext.rotate(by: -0.45)
    let orbit = NSBezierPath(ovalIn: NSRect(x: -306, y: -166, width: 612, height: 332))
    orbit.lineWidth = 25
    NSColor(srgbRed: 0.72, green: 0.78, blue: 1, alpha: 0.75).setStroke(); orbit.stroke()
    graphics.cgContext.restoreGState()
    let nib = NSBezierPath()
    nib.move(to: NSPoint(x: 346, y: 306)); nib.line(to: NSPoint(x: 404, y: 577)); nib.line(to: NSPoint(x: 621, y: 731)); nib.line(to: NSPoint(x: 735, y: 617)); nib.line(to: NSPoint(x: 574, y: 407)); nib.close()
    NSColor.white.setFill(); nib.fill()
    let slit = NSBezierPath(); slit.move(to: NSPoint(x: 354, y: 314)); slit.line(to: NSPoint(x: 508, y: 470)); slit.lineWidth = 19; slit.lineCapStyle = .round
    NSColor(srgbRed: 0.30, green: 0.22, blue: 0.66, alpha: 1).setStroke(); slit.stroke()
    NSBezierPath(ovalIn: NSRect(x: 477, y: 443, width: 61, height: 61)).fill()
    NSColor(srgbRed: 0.35, green: 0.94, blue: 0.85, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 213, y: 629, width: 94, height: 94)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
}
