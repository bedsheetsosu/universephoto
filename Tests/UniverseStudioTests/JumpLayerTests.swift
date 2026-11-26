import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct JumpLayerTests {
    @Test func crouchFlyLandRest() {
        let p = (0..<21).map { Studio.jumpPose($0, of: 21) }
        #expect(p[0].lift == 0 && abs(p[0].stretch - 1) < 1e-9)
        #expect(p[3].lift == 0 && p[3].stretch < 0.85)              // crouched
        #expect(p[9].lift > 0.9)                                    // near the top
        #expect(p[16].lift == 0 && p[16].stretch < 0.9)             // landing squash
        #expect(abs(p[20].stretch - 1) < 1e-9 && p[20].lift == 0)   // at rest
    }

    @Test func staysOnItsFeetWhileSquashing() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 40, y: 50, pressure: 1), InkPoint(x: 60, y: 90, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<20 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.jumpLayer(height: 40) > 0)
        let f = s.document().frames, local = s.contentBounds(s.layers[1])!
        let foot = CGPoint(x: local.midX, y: local.maxY)
        let crouch = foot.applying(s.matrix(f[3][1].transform))
        #expect(abs(crouch.y - foot.y) < 0.01)
        #expect(foot.applying(s.matrix(f[10][1].transform)).y < foot.y - 30)
    }
}
