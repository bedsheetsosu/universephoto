import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct ImportFramesTests {
    private func solid(_ w: Int, _ h: Int) -> CGImage {
        let ctx = Renderer.context(width: w, height: h)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    @Test func gifFramesKeepTheirTiming() throws {
        var dot = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1); dot.kind = "fill"
        var a = ArtLayer(name: "a"); a.strokes = [dot]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageFiles.exportGIF(frames: [[a], [ArtLayer(name: "b")], [a]], width: 8, height: 8, fps: 10, url: url)
        let decoded = try ImageFiles.decodeFrames(url: url)
        #expect(decoded.count == 3 && abs((decoded[0].delay ?? 0) - 0.1) < 0.001)
        #expect(ImageFiles.holds(decoded.map(\.delay), fps: 20) == [2, 2, 2])
        #expect(ImageFiles.holds([nil, 0.25], fps: 12) == [1, 3])
    }

    @Test func fittedCentresAndOnlyShrinks() throws {
        let big = try #require(ImageFiles.fitted(solid(20, 10), width: 10, height: 10))
        let b = try #require(PixelOps.bitmap(big))
        #expect(b.bytes[(1 * 10 + 5) * 4 + 3] == 0 && b.bytes[(5 * 10 + 5) * 4 + 3] == 255, "20×10 → 10×5 in the middle")
        let smallImage = try #require(ImageFiles.fitted(solid(2, 2), width: 10, height: 10))
        let small = try #require(PixelOps.bitmap(smallImage))
        #expect(small.bytes[(0 * 10 + 0) * 4 + 3] == 0 && small.bytes[(4 * 10 + 4) * 4 + 3] == 255 && small.bytes[(6 * 10 + 6) * 4 + 3] == 0)
    }

    @Test func framesGoAfterTheCurrentOneIntoTheSelectedLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10); s.newLayer(); s.addFrame(); s.selectFrame(0)
        let before = s.frames.count
        #expect(s.importFrames([(solid(4, 4), 0.25), (solid(4, 4), nil)]) == 2)
        #expect(s.frames.count == before + 2 && s.frameIndex == 1)
        #expect(s.layers[s.selectedLayer].imageData != nil && s.layers.count == 2)
        #expect(s.hold(1) == 3 && s.hold(2) == 1)
        s.undo()
        #expect(s.document().frames.count == before)
    }
}
