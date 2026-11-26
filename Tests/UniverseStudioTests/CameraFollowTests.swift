import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct CameraFollowTests {
    @Test func pullsBackTowardsTheStart() {
        let c = (0..<5).map { CGPoint(x: Double($0) * 10, y: 0) }
        let tight = Studio.followOffsets(c, strength: 1, smooth: 0)
        #expect(tight.map(\.x) == [0, -10, -20, -30, -40])
        let loose = Studio.followOffsets(c, strength: 0.5, smooth: 1)
        #expect(loose[0] == .zero && loose[4].x > -20 && loose[4].x < 0)
    }

    @Test func keepsTheTravellerInView() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 20, y: 40, pressure: 1), InkPoint(x: 30, y: 60, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for k in 1..<10 { s.addFrame(); s.layers[1].transform.x = Double(k) * 30; s.changed() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.cameraFollow(tight: true) == 10)
        let f = s.document().frames
        let xs = f.map { CGPoint(x: 25, y: 50).applying(s.matrix($0[1].transform)).x }
        #expect(xs.max()! - xs.min()! < 40)                       // stays in view (was 270 px of travel)
        #expect(f[5][0].transform.x < -100)                        // the background slides the other way
        s.undo()
        #expect(s.document().frames[9][1].transform.x == 270)
    }
}
