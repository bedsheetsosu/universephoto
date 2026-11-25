import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct WipeLayerTests {
    @Test func revealGrowsFromTheLeft() {
        #expect(Studio.wipeHidden(.leftToRight, progress: 1, reveal: true, width: 100, height: 50) == nil)
        #expect(Studio.wipeHidden(.leftToRight, progress: 0.25, reveal: true, width: 100, height: 50)?.0.x == 25)
        #expect(Studio.wipeHidden(.leftToRight, progress: 0, reveal: false, width: 100, height: 50) == nil)
    }

    @Test func masksEveryFrameButTheLastAndUndoes() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        #expect(s.wipeLayer(.leftToRight, reveal: true) == 2)
        let f = s.document().frames
        #expect(f[0][1].mask?.count == 1 && f[1][1].mask?.count == 1 && f[2][1].mask == nil)
        #expect(f[0][1].mask?.first?.kind == "rectangle" && f[0][1].mask?.first?.filled == true)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].mask == nil })
    }
}

@MainActor
struct WipeRenderTests {
    @Test func hiddenSideRendersTransparent() throws {
        var layer = ArtLayer(name: "red")
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .black, width: 1); fill.kind = "fill"
        layer.strokes = [fill]
        let (a, b) = try #require(Studio.wipeHidden(.leftToRight, progress: 0.5, reveal: true, width: 20, height: 10))
        var cover = InkStroke(points: [a, b], color: .black, width: 1); cover.kind = "rectangle"; cover.filled = true
        layer.mask = [cover]
        let img = try #require(Renderer.render(layers: [layer], width: 20, height: 10))
        let ctx = try #require(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 80,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 20, height: 10))
        let px = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        let alpha = { (x: Int) in px[(5 * 20 + x) * 4 + 3] }
        #expect(alpha(3) > 200)        // left half visible
        #expect(alpha(16) < 30)        // right half hidden
    }
}
