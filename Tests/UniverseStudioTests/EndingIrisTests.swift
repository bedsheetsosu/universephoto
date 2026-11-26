import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct EndingIrisTests {
    @Test func blackClosesInOverEverything() {
        for heart in [false, true] {
            let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            s.newDocument(width: 160, height: 120, background: .white)
            s.extendAnimation(by: 11)
            #expect(s.addEndingIris(heart: heart) == 12)
            let f = s.document().frames
            #expect(f.allSatisfy { $0.last!.name == L("Ending") })
            #expect(f[0].last!.mask?.count == 2)
            #expect(f.last!.last!.mask == nil)                      // fully black at the end
            let px = ImageFiles.renderFrame(f[0], 160, 120, 160, 120)!
            let mid = ImageFiles.renderFrame(f[6], 160, 120, 160, 120)!
            #expect(Self.luma(px, 2, 2) > 0.9)                       // first frame: corners still visible
            #expect(Self.luma(mid, 2, 2) < 0.1 && Self.luma(mid, 80, 60) > 0.9)
        }
    }

    static func luma(_ img: CGImage, _ x: Int, _ y: Int) -> Double {
        var p = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &p, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
        return (Double(p[0]) + Double(p[1]) + Double(p[2])) / 765
    }
}
