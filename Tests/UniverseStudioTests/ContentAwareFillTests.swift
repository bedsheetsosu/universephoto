import CoreGraphics
import Testing
@testable import UniverseStudio

@MainActor
struct ContentAwareFillTests {
    /// w × h opaque picture; colour by position.
    func picture(_ w: Int, _ h: Int, _ color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> PixelOps.Bitmap {
        var b = PixelOps.Bitmap(width: w, height: h, bytes: [UInt8](repeating: 255, count: w * h * 4))
        for y in 0..<h { for x in 0..<w { let c = color(x, y), i = b.index(x, y); b.bytes[i] = c.0; b.bytes[i + 1] = c.1; b.bytes[i + 2] = c.2 } }
        return b
    }

    func hole(_ w: Int, _ h: Int, _ r: CGRect) -> [UInt8] {
        (0..<(w * h)).map { r.contains(CGPoint(x: Double($0 % w) + 0.5, y: Double($0 / w) + 0.5)) ? 255 : 0 }
    }

    @Test func plainAreaStaysPlain() {
        let b = picture(60, 60) { _, _ in (40, 120, 200) }
        var withBlob = b
        for y in 20..<40 { for x in 20..<40 { withBlob.bytes[withBlob.index(x, y)] = 255 } }
        let out = ContentAwareFill.fill(withBlob, hole: hole(60, 60, CGRect(x: 18, y: 18, width: 24, height: 24)))
        var wrong = 0
        for y in 18..<42 { for x in 18..<42 { let i = b.index(x, y); if !(out[i] == 40 && out[i + 1] == 120 && out[i + 2] == 200) { wrong += 1 } } }
        #expect(wrong == 0)
    }

    @Test func stripesContinueThroughTheHole() {
        // Vertical stripes, 4 px wide: every filled pixel must be one of the two colours,
        // and the column pattern should mostly carry on.
        let b = picture(80, 80) { x, _ in (x / 4) % 2 == 0 ? (0, 0, 0) : (255, 255, 255) }
        let out = ContentAwareFill.fill(b, hole: hole(80, 80, CGRect(x: 30, y: 30, width: 20, height: 20)))
        var right = 0, total = 0, foreign = 0
        for y in 30..<50 { for x in 30..<50 {
            let v = out[b.index(x, y)]
            if v != 0 && v != 255 { foreign += 1 }
            total += 1; if v == b.bytes[b.index(x, y)] { right += 1 }
        } }
        #expect(foreign == 0)
        #expect(Double(right) / Double(total) > 0.8)
    }

    @Test func studioPutsTheFillOnTheActiveLayer() throws {
        let s = Studio()
        let before = s.activeLayer?.strokes.count ?? 0
        s.selection = CanvasSelection(points: [CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 130)])
        s.contentAwareFill()
        let layer = try #require(s.activeLayer)
        #expect(layer.strokes.count == before + 1 && layer.strokes.last?.kind == "bitmap")
        #expect(!s.undoStack.isEmpty)
    }
}
