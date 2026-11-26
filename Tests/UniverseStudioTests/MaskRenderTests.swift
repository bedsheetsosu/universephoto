import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

/// 0.220: a pure black mask hides completely, the rest shows completely, and the mask isn't upside
/// down. (Effects used the soft ink `.black` before, which left ~9 % showing.)
struct MaskRenderTests {
    private func alpha(_ img: CGImage, x: Int, yDown: Int) -> UInt8 {
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.data!.assumingMemoryBound(to: UInt8.self)[(yDown * img.width + x) * 4 + 3]
    }

    @Test func blackHidesFully() {
        var l = ArtLayer(name: "x")
        var b = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 20, y: 20, pressure: 1)], color: .black, width: 1)
        b.kind = "rectangle"; b.filled = true
        l.strokes = [b]
        var c = InkStroke(points: [InkPoint(x: -5, y: 10, pressure: 1), InkPoint(x: 30, y: 30, pressure: 1)], color: .maskBlack, width: 1)
        c.kind = "rectangle"; c.filled = true
        l.mask = [c]                                  // hides the lower half (y down)
        let img = Renderer.render(layers: [l], width: 20, height: 20)!
        #expect(alpha(img, x: 5, yDown: 3) == 255)
        #expect(alpha(img, x: 5, yDown: 16) == 0)
    }
}
