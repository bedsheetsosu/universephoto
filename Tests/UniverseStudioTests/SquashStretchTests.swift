import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct SquashStretchTests {
    @Test func stretchesInFlightAndSquashesOnLanding() {
        // A hop: up, top, down, ground (landing), up again.
        let c = Studio.squashStretchCurve([0, -40, -50, -40, 0, -40], amount: 1)
        #expect(c[4] < 1)                         // landing frame is squashed
        #expect(c[1] > 1 && c[3] > 1)             // fast frames are stretched
        #expect(abs(c[2] - 1) < 0.2)              // the top hangs nearly round
    }

    @Test func keepsVolumeAndSurvivesTheFile() throws {
        var t = LayerTransform(); t.scale = 2; t.stretch = 1.25
        #expect(abs(t.scaleX * t.scaleY - 4) < 1e-9)
        let back = try JSONDecoder().decode(LayerTransform.self, from: JSONEncoder().encode(t))
        #expect(back == t)
        let old = try JSONDecoder().decode(LayerTransform.self, from: Data(#"{"x":1,"y":2,"scale":1,"rotation":0}"#.utf8))
        #expect(old.stretch == nil && old.scaleX == 1)
    }

    @Test func appliesAfterABounceAndUndoes() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        for _ in 0..<8 { s.addFrame() }
        s.selectedLayer = 1
        s.bounceLayer(height: 50, bounces: 2)
        #expect(s.squashStretch() > 0)
        let st = s.document().frames.map { $0[1].transform.stretch ?? 1 }
        #expect(st.contains { $0 < 1 } && st.contains { $0 > 1 })
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.stretch == nil })
    }
}

@MainActor
struct SquashRenderTests {
    @Test func stretchReachesThePicture() throws {
        func rows(_ stretch: Double?) throws -> Int {
            var l = ArtLayer(name: "box")
            var r = InkStroke(points: [InkPoint(x: 15, y: 15, pressure: 1), InkPoint(x: 25, y: 25, pressure: 1)], color: .black, width: 1)
            r.kind = "rectangle"; r.filled = true
            l.strokes = [r]; l.transform.stretch = stretch
            let img = try #require(Renderer.render(layers: [l], width: 40, height: 40))
            let ctx = try #require(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: 40, height: 40))
            let px = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
            return (0..<40).filter { y in px[(y * 40 + 20) * 4 + 3] > 128 }.count
        }
        let tall = try rows(2), plain = try rows(nil), flat = try rows(0.5)
        #expect(tall > plain + 5)                            // taller
        #expect(flat < plain - 3)                            // flatter
    }

    @Test func squashyBounceIsOneUndoStep() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        for _ in 0..<8 { s.addFrame() }
        s.selectedLayer = 1
        s.bounceWithSquash(height: 40, bounces: 2)
        #expect(s.document().frames.contains { $0[1].transform.stretch != nil })
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.y == 0 && $0[1].transform.stretch == nil })
    }
}
