import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct MotionPathTests {
    @Test func followsTheLayerAcrossFrames() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 40); s.newLayer()
        var r = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1), InkPoint(x: 10, y: 10, pressure: 1)], color: .black, width: 1)
        r.kind = "rectangle"; r.filled = true
        s.layers[1].strokes = [r]
        #expect(s.motionPathPoints().isEmpty, "one frame: no path")
        s.addFrame(); s.layers[1].transform.x = 20
        s.addFrame(); s.layers[1].transform.y = 10
        let p = s.motionPathPoints().map { $0.map { CGPoint(x: $0.x.rounded(), y: $0.y.rounded()) } }
        #expect(p == [CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 5), CGPoint(x: 25, y: 15)])
        #expect(Studio.pathMoves(p))
        #expect(!Studio.pathMoves([CGPoint(x: 1, y: 1), nil, CGPoint(x: 1.2, y: 1)]))
        s.selectedLayer = 0
        #expect(s.motionPathPoints().allSatisfy { $0 == nil || $0 == CGPoint(x: 20, y: 20) } )
    }
}
