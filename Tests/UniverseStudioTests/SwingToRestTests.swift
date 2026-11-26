import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct SwingToRestTests {
    @Test func swingsLessAndLess() {
        let a = (0..<48).map { Studio.swingToRest($0, of: 48, degrees: 20) }
        #expect(a[0] == 0 && a[47] == 0)
        #expect(a.contains { $0 > 5 } && a.contains { $0 < -5 })     // both ways
        let firstHalf = a[0..<24].map(abs).max()!, secondHalf = a[24...].map(abs).max()!
        #expect(secondHalf < firstHalf * 0.4)
    }

    @Test func standsOnItsBottom() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 50, y: 20, pressure: 1), InkPoint(x: 50, y: 90, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<15 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.swingToRest(degrees: 15, hanging: false) > 0)
        let local = s.contentBounds(s.layers[1])!, foot = CGPoint(x: local.midX, y: local.maxY)
        for f in s.document().frames {
            let p = foot.applying(s.matrix(f[1].transform))
            #expect(abs(p.x - foot.x) < 0.01 && abs(p.y - foot.y) < 0.01)
        }
    }
}
