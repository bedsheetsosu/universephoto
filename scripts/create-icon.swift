// Original, code-drawn application artwork; no external image assets.
// Same family as UniversePen's icon: indigo night plate with stars, mint-to-violet glow.
// Motif: a tilted photo print showing a ringed planet rising over mountains.
import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let variants = [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")]

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient { CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)! }
let mint = rgb(0.55, 0.95, 0.88), sky = rgb(0.55, 0.80, 1.0), violet = rgb(0.75, 0.55, 1.0)

/// Deterministic stars (same picture at every size).
struct Rand { var s: UInt64 = 0x5EED_1234; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

func draw(_ c: CGContext, detail: Bool) {
    // Plate: the macOS squircle-ish rounded square, indigo top right to deep navy bottom left.
    let plateRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let plate = CGPath(roundedRect: plateRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.35))
    c.addPath(plate); c.setFillColor(rgb(0.16, 0.15, 0.36)); c.fillPath()
    c.restoreGState()
    c.saveGState(); c.addPath(plate); c.clip()
    c.drawLinearGradient(gradient([rgb(0.29, 0.22, 0.52), rgb(0.19, 0.20, 0.42), rgb(0.08, 0.09, 0.22)], [0, 0.5, 1]),
                         start: CGPoint(x: 820, y: 920), end: CGPoint(x: 180, y: 110), options: [])
    c.drawRadialGradient(gradient([rgb(0.55, 0.40, 0.95, 0.35), rgb(0.55, 0.40, 0.95, 0)]), startCenter: CGPoint(x: 700, y: 760), startRadius: 0,
                         endCenter: CGPoint(x: 700, y: 760), endRadius: 420, options: [])
    // Stars.
    var r = Rand()
    for i in 0..<(detail ? 70 : 18) {
        let p = CGPoint(x: 120 + r.next() * 784, y: 120 + r.next() * 784), size = 2 + r.next() * r.next() * 7
        let a = 0.35 + r.next() * 0.6
        if i % 9 == 0 && detail {   // a few soft glowing ones
            c.drawRadialGradient(gradient([rgb(1, 1, 1, 0.7), rgb(1, 1, 1, 0)]), startCenter: p, startRadius: 0, endCenter: p, endRadius: 16, options: [])
        }
        c.setFillColor(rgb(1, 1, 1, a)); c.fillEllipse(in: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
    }
    c.restoreGState()

    // The photo print, tilted, with a soft drop shadow.
    c.saveGState()
    c.translateBy(x: 512, y: 500); c.rotate(by: -0.12)
    let card = CGRect(x: -250, y: -230, width: 500, height: 470)
    let border: CGFloat = 26
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -22), blur: 44, color: rgb(0.02, 0.02, 0.10, 0.6))
    c.addPath(CGPath(roundedRect: card, cornerWidth: 46, cornerHeight: 46, transform: nil)); c.setFillColor(rgb(0.97, 0.98, 1)); c.fillPath()
    c.restoreGState()
    // Frame: frosted white, a touch of mint at the edge.
    c.saveGState()
    c.addPath(CGPath(roundedRect: card, cornerWidth: 46, cornerHeight: 46, transform: nil)); c.clip()
    c.drawLinearGradient(gradient([rgb(1, 1, 1), rgb(0.88, 0.93, 0.98)]), start: CGPoint(x: 0, y: card.maxY), end: CGPoint(x: 0, y: card.minY), options: [])
    c.restoreGState()

    // The picture inside.
    let pic = card.insetBy(dx: border, dy: border)
    let picPath = CGPath(roundedRect: pic, cornerWidth: 24, cornerHeight: 24, transform: nil)
    c.saveGState(); c.addPath(picPath); c.clip()
    // Sky: violet at the top, mint glow on the horizon.
    c.drawLinearGradient(gradient([rgb(0.20, 0.16, 0.45), rgb(0.42, 0.33, 0.80), rgb(0.55, 0.85, 0.95)], [0, 0.55, 1]),
                         start: CGPoint(x: 0, y: pic.maxY), end: CGPoint(x: 0, y: pic.minY + 90), options: [.drawsAfterEndLocation])
    // Tiny stars in the picture's sky.
    if detail { var rs = Rand(s: 99); for _ in 0..<14 { let p = CGPoint(x: pic.minX + rs.next() * pic.width, y: pic.midY + 30 + rs.next() * (pic.height / 2 - 40)); c.setFillColor(rgb(1, 1, 1, 0.8)); c.fillEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)) } }
    // Planet with a glow and a ring.
    let pc = CGPoint(x: pic.midX + 55, y: pic.midY + 55), pr: CGFloat = 78
    c.drawRadialGradient(gradient([rgb(0.70, 1, 0.95, 0.55), rgb(0.70, 1, 0.95, 0)]), startCenter: pc, startRadius: pr * 0.8, endCenter: pc, endRadius: pr * 2, options: [])
    c.saveGState()
    c.addEllipse(in: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)); c.clip()
    c.drawLinearGradient(gradient([mint, sky, violet]), start: CGPoint(x: pc.x - pr, y: pc.y + pr), end: CGPoint(x: pc.x + pr, y: pc.y - pr), options: [])
    c.restoreGState()
    c.saveGState()
    c.translateBy(x: pc.x, y: pc.y); c.rotate(by: 0.32)
    let t = CGAffineTransform(scaleX: pr * 1.75, y: pr * 0.45)
    let front = CGMutablePath(); front.addArc(center: .zero, radius: 1, startAngle: .pi, endAngle: 2 * .pi, clockwise: false, transform: t)
    let back = CGMutablePath(); back.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: .pi, clockwise: false, transform: t)
    c.setLineCap(.round); c.setLineWidth(13)
    // back part (behind the planet): only outside the planet disc
    c.saveGState()
    c.addRect(CGRect(x: -400, y: -400, width: 800, height: 800)); c.addEllipse(in: CGRect(x: -pr, y: -pr, width: pr * 2, height: pr * 2)); c.clip(using: .evenOdd)
    c.addPath(back); c.setStrokeColor(rgb(1, 1, 1, 0.85)); c.strokePath()
    c.restoreGState()
    c.addPath(front); c.setStrokeColor(rgb(1, 1, 1, 0.95)); c.strokePath()
    c.restoreGState()
    // Mountains: two layers, back one lighter.
    func ridge(_ pts: [(CGFloat, CGFloat)], _ color: CGColor) {
        let p = CGMutablePath(); p.move(to: CGPoint(x: pic.minX - 10, y: pic.minY - 10))
        for (x, y) in pts { p.addLine(to: CGPoint(x: pic.minX + x * pic.width, y: pic.minY + y * pic.height)) }
        p.addLine(to: CGPoint(x: pic.maxX + 10, y: pic.minY - 10)); p.closeSubpath()
        c.addPath(p); c.setFillColor(color); c.fillPath()
    }
    ridge([(0, 0.34), (0.18, 0.48), (0.32, 0.36), (0.52, 0.56), (0.70, 0.40), (0.86, 0.50), (1, 0.38)], rgb(0.30, 0.27, 0.60))
    ridge([(0, 0.20), (0.22, 0.36), (0.40, 0.22), (0.60, 0.32), (0.80, 0.16), (1, 0.26)], rgb(0.13, 0.12, 0.32))
    c.restoreGState()
    c.restoreGState()

    // A sparkle in UniversePen's mint, top left: the "Universe" touch.
    let sp = CGPoint(x: 268, y: 770), arm: CGFloat = 62
    c.drawRadialGradient(gradient([rgb(0.6, 1, 0.92, 0.6), rgb(0.6, 1, 0.92, 0)]), startCenter: sp, startRadius: 0, endCenter: sp, endRadius: 70, options: [])
    let star = CGMutablePath()
    for i in 0..<8 {
        let a = Double(i) * .pi / 4, len = i % 2 == 0 ? arm : arm * 0.22
        let p = CGPoint(x: sp.x + cos(a) * len, y: sp.y + sin(a) * len)
        i == 0 ? star.move(to: p) : star.addLine(to: p)
    }
    star.closeSubpath()
    c.addPath(star); c.setFillColor(rgb(0.92, 1, 0.98)); c.fillPath()
}

for (size, name) in variants {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(ctx, detail: size >= 64)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
}
