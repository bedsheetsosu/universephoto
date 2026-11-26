import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct GustLayerTests {
    @Test func bendsHoldsAndSpringsBack() {
        let a = (0..<41).map { Studio.gustLean($0, of: 41, degrees: 20) }
        #expect(a[0] == 0 && a[40] == 0)
        #expect(a[10...20].allSatisfy { $0 > 18 })              // holding against the wind
        #expect(a[21...].contains { $0 < -2 })                   // swings past upright on the way back
    }

    @Test func bendsOnItsFoot() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 50, y: 20, pressure: 1), InkPoint(x: 50, y: 90, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<19 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.gustLayer(degrees: 25) > 0)
        let local = s.contentBounds(s.layers[1])!, foot = CGPoint(x: local.midX, y: local.maxY)
        for f in s.document().frames {
            let p = foot.applying(s.matrix(f[1].transform))
            #expect(abs(p.x - foot.x) < 0.01 && abs(p.y - foot.y) < 0.01)
        }
    }
}
