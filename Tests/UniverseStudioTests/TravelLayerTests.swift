import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct TravelLayerTests {
    @Test func addsTheDistanceAcrossTheFrames() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 1, 2, 3, 4] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()                 // a little own motion
        }
        s.selectedLayer = 1
        #expect(s.travelLayer(dx: 100, dy: 0, eased: false) == 4)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 26, 52, 78, 104])
        s.undo()
        s.travelLayer(dx: 0, dy: 40, eased: true)
        let ys = s.document().frames.map { $0[1].transform.y }
        #expect(ys.first == 0 && ys.last == 40 && ys[1] < 10)        // slow start
    }
}
