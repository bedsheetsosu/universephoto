import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

struct BrushDynamicsTests {
    private func render(_ stroke: InkStroke) -> CGImage? {
        var layer = ArtLayer(name: "L"); layer.strokes = [stroke]
        return Renderer.render(layers: [layer], width: 200, height: 100)
    }
    private func line(scatter: Double? = nil, size: Double? = nil, hue: Double? = nil) -> InkStroke {
        var s = InkStroke(points: stride(from: 20.0, through: 180, by: 4).map { InkPoint(x: $0, y: 50, pressure: 1) },
                          color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 12)
        s.scatter = scatter; s.sizeJitter = size; s.hueJitter = hue
        return s
    }
    private func alphaRows(_ img: CGImage) -> (onPath: Int, offPath: Int) {
        guard let b = PixelOps.bitmap(img) else { return (0, 0) }
        var on = 0, off = 0
        for y in 0..<b.height { for x in 0..<b.width where b.bytes[b.index(x, y) + 3] > 40 { if abs(y - 50) <= 6 { on += 1 } else { off += 1 } } }
        return (on, off)
    }

    @Test func plainBrushStaysOnItsLine() throws {
        let r = alphaRows(try #require(render(line())))
        #expect(r.offPath == 0 && r.onPath > 1000)
    }

    @Test func scatterThrowsDabsOffThePathTheSameWayEveryTime() throws {
        let stroke = line(scatter: 1)
        let a = try #require(render(stroke)), b = try #require(render(stroke))
        #expect(alphaRows(a).offPath > 100)
        #expect(PixelOps.bitmap(a)?.bytes == PixelOps.bitmap(b)?.bytes, "seeded by the stroke")
    }

    @Test func sizeJitterOnlyMakesDabsSmaller() throws {
        let r = alphaRows(try #require(render(line(size: 1))))
        #expect(r.offPath == 0, "never bigger than the brush")
    }

    @Test func hueJitterTintsButKeepsBrightness() throws {
        let img = try #require(render(line(hue: 1)))
        let b = try #require(PixelOps.bitmap(img))
        var tinted = 0
        for x in stride(from: 24, to: 176, by: 3) { let i = b.index(x, 50); if b.bytes[i + 1] > 40 || b.bytes[i + 2] > 40 { tinted += 1 } }
        #expect(tinted > 5)
        let c = CodableColor(red: 1, green: 0, blue: 0, alpha: 0.5).hueShifted(by: 1.0 / 3)
        #expect(abs(c.green - 1) < 0.001 && c.red < 0.001 && c.alpha == 0.5)
        let grey = CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        #expect(grey.hueShifted(by: 0.2) == grey)
    }
}
