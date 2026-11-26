import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct SpotlightTests {
    @Test func darkAroundLightInside() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 45, y: 45, pressure: 1), InkPoint(x: 55, y: 55, pressure: 1)], color: .black, width: 2)]
        s.changed(); s.addFrame(); s.selectFrame(0); s.selectedLayer = 1
        #expect(s.addSpotlight() == 2)
        let img = Renderer.render(layers: s.document().frames[0], width: 100, height: 100)!
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        func red(_ x: Int, _ y: Int) -> Int { Int(p[(y * 100 + x) * 4]) }
        #expect(red(35, 50) > 230)                    // inside the light: white background
        #expect(red(3, 3) < 90)                       // the corner is dark
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
