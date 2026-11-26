import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FlickerLayerTests {
    @Test func burstsBetweenCalmStretches() {
        let calm = Studio.flickerLevels(count: 96, wild: false), wild = Studio.flickerLevels(count: 96, wild: true)
        #expect(calm.contains { $0 < 1 } && calm.filter { $0 == 1 }.count > 40)
        #expect(wild.filter { $0 < 1 }.count > calm.filter { $0 < 1 }.count)
        #expect(wild.allSatisfy { $0 > 0 && $0 <= 1 })
    }

    @Test func dimsTheLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 50, height: 50, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 25, y: 25, pressure: 1)], color: .black, width: 6)]
        s.changed()
        for _ in 0..<47 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.flickerLayer(wild: true) > 0)
        #expect(s.document().frames.contains { $0[1].opacity < 0.9 })
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].opacity == 1 })
    }
}
