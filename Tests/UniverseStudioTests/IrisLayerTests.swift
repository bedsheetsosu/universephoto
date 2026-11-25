import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct IrisLayerTests {
    @Test func opensFromTheMiddle() throws {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 40, background: .white)
        s.addFrame(); s.addFrame()
        s.selectedLayer = 0                                         // the white background
        #expect(s.irisLayer(open: true) == 2)
        let f = s.document().frames
        #expect(f[0][0].mask?.count == 1 && f[1][0].mask?.count == 2 && f[2][0].mask == nil)
        // Middle frame: centre visible, corner hidden.
        let img = try #require(Renderer.render(layers: [f[1][0]], width: 40, height: 40))
        let ctx = try #require(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 40, height: 40))
        let px = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        #expect(px[(20 * 40 + 20) * 4 + 3] > 200)
        #expect(px[(1 * 40 + 1) * 4 + 3] < 30)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[0].mask == nil })
    }
}
