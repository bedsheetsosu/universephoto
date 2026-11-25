// Original, code-drawn application artwork; no external image assets.
// Same family as UniversePen's icon: indigo night plate, mint-to-violet glow.
// Motif (0.135): a single confident calligraphic brush stroke – drawing, animation, motion – with
// a glossy sheen, a soft drop shadow, and one mint spark. Clean and premium.
import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let variants = [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")]

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient { CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)! }
let mint = rgb(0.56, 0.96, 0.86), sky = rgb(0.46, 0.80, 1.0), violet = rgb(0.80, 0.56, 1.0)

struct Rand { var s: UInt64 = 0x5EED_1234; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

/// Apple-style continuous rounded square (superellipse). `n` ~5 matches the macOS squircle.
func squircle(center: CGPoint, half: CGFloat, n: Double = 5) -> CGPath {
    let p = CGMutablePath(), steps = 240
    for i in 0...steps {
        let th = Double(i) / Double(steps) * 2 * .pi
        let cx = cos(th), sy = sin(th)
        let x = center.x + half * CGFloat(copysign(pow(abs(cx), 2 / n), cx))
        let y = center.y + half * CGFloat(copysign(pow(abs(sy), 2 / n), sy))
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath(); return p
}

func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
    let u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}
func cubicTan(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
    let u = 1 - t, a = 3 * u * u, b = 6 * u * t, c = 3 * t * t
    return CGPoint(x: a * (p1.x - p0.x) + b * (p2.x - p1.x) + c * (p3.x - p2.x),
                   y: a * (p1.y - p0.y) + b * (p2.y - p1.y) + c * (p3.y - p2.y))
}

// Hero brush stroke: a clean rising comet sweep, tapered to a point at both ends.
let s0 = CGPoint(x: 300, y: 452), s1 = CGPoint(x: 408, y: 470), s2 = CGPoint(x: 588, y: 548), s3 = CGPoint(x: 706, y: 702)
func strokeOutline(widthScale: CGFloat, maxW: CGFloat = 156) -> CGPath {
    let n = 90
    var top: [CGPoint] = [], bot: [CGPoint] = []
    for i in 0...n {
        let t = Double(i) / Double(n)
        let p = cubic(s0, s1, s2, s3, t), d = cubicTan(s0, s1, s2, s3, t)
        let len = max(0.0001, hypot(d.x, d.y)), nx = -d.y / len, ny = d.x / len
        let w = maxW * widthScale * CGFloat(pow(sin(.pi * t), 0.62)) / 2
        top.append(CGPoint(x: p.x + nx * w, y: p.y + ny * w))
        bot.append(CGPoint(x: p.x - nx * w, y: p.y - ny * w))
    }
    let path = CGMutablePath()
    path.move(to: top[0]); for q in top.dropFirst() { path.addLine(to: q) }
    for q in bot.reversed() { path.addLine(to: q) }
    path.closeSubpath(); return path
}

func draw(_ c: CGContext, detail: Bool) {
    let center = CGPoint(x: 512, y: 512), plate = squircle(center: center, half: 412)
    // Drop shadow of the whole plate.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: rgb(0, 0, 0, 0.38))
    c.addPath(plate); c.setFillColor(rgb(0.12, 0.12, 0.30)); c.fillPath()
    c.restoreGState()

    c.saveGState(); c.addPath(plate); c.clip()
    // Indigo night: lighter top-right, deep navy bottom-left.
    c.drawLinearGradient(gradient([rgb(0.25, 0.21, 0.48), rgb(0.15, 0.15, 0.34), rgb(0.06, 0.07, 0.17)], [0, 0.52, 1]),
                         start: CGPoint(x: 840, y: 900), end: CGPoint(x: 150, y: 150), options: [])
    // Soft violet glow behind the stroke.
    c.drawRadialGradient(gradient([rgb(0.55, 0.42, 0.98, 0.42), rgb(0.55, 0.42, 0.98, 0)]), startCenter: CGPoint(x: 560, y: 560), startRadius: 0,
                         endCenter: CGPoint(x: 560, y: 560), endRadius: 470, options: [])
    // Faint, sparse stars for the "universe" identity.
    if detail {
        var r = Rand()
        for _ in 0..<26 {
            let p = CGPoint(x: 150 + r.next() * 724, y: 150 + r.next() * 724), sz = 1.5 + r.next() * r.next() * 5
            c.setFillColor(rgb(1, 1, 1, 0.18 + r.next() * 0.42))
            c.fillEllipse(in: CGRect(x: p.x - sz / 2, y: p.y - sz / 2, width: sz, height: sz))
        }
    }

    // Glow around the stroke itself.
    let mid = cubic(s0, s1, s2, s3, 0.5)
    c.drawRadialGradient(gradient([rgb(0.6, 0.95, 0.95, 0.5), rgb(0.6, 0.95, 0.95, 0)]), startCenter: mid, startRadius: 40, endCenter: mid, endRadius: 320, options: [])

    // Soft contact shadow under the stroke.
    let hero = strokeOutline(widthScale: 1)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: rgb(0.02, 0.02, 0.08, 0.55))
    c.addPath(hero); c.setFillColor(rgb(0.1, 0.1, 0.25)); c.fillPath()
    c.restoreGState()

    // The stroke, filled along its length mint → sky → violet.
    c.saveGState(); c.addPath(hero); c.clip()
    c.drawLinearGradient(gradient([mint, sky, violet], [0, 0.46, 0.92]),
                         start: CGPoint(x: 300, y: 430), end: CGPoint(x: 720, y: 710), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Gentle sheen: a soft brighter core, not a white wash.
    c.setBlendMode(.plusLighter)
    let sheen = strokeOutline(widthScale: 0.4)
    c.saveGState(); c.translateBy(x: -4, y: 12); c.addPath(sheen)
    c.drawLinearGradient(gradient([rgb(1, 1, 1, 0.28), rgb(1, 1, 1, 0.02)]), start: CGPoint(x: 0, y: 720), end: CGPoint(x: 0, y: 420), options: [.drawsAfterEndLocation])
    c.restoreGState()
    c.restoreGState()

    // Top rim light on the plate edge for the glassy, premium feel.
    c.saveGState(); c.addPath(plate); c.clip()
    c.setBlendMode(.plusLighter)
    c.drawLinearGradient(gradient([rgb(1, 1, 1, 0.14), rgb(1, 1, 1, 0)]), start: CGPoint(x: 512, y: 920), end: CGPoint(x: 512, y: 720), options: [])
    c.restoreGState()

    // One mint spark near the stroke's tip.
    let sp = cubic(s0, s1, s2, s3, 0.985), arm: CGFloat = 54
    c.drawRadialGradient(gradient([rgb(0.7, 1, 0.95, 0.7), rgb(0.7, 1, 0.95, 0)]), startCenter: sp, startRadius: 0, endCenter: sp, endRadius: 78, options: [])
    let star = CGMutablePath()
    for i in 0..<8 {
        let a = Double(i) * .pi / 4, len = i % 2 == 0 ? arm : arm * 0.2
        let p = CGPoint(x: sp.x + cos(a) * len, y: sp.y + sin(a) * len)
        i == 0 ? star.move(to: p) : star.addLine(to: p)
    }
    star.closeSubpath(); c.addPath(star); c.setFillColor(rgb(0.95, 1, 0.99)); c.fillPath()
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
