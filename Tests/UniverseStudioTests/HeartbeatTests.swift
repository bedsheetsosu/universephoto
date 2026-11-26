import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct HeartbeatTests {
    @Test func twoBeatsThenRest() {
        let f = (0..<24).map { Studio.heartbeatFactor(frameIndexInRange: $0, count: 24, amount: 0.2) }
        #expect(f[0] == 1)
        // local maxima above 1
        let peaks = (1..<23).filter { f[$0] > 1.01 && f[$0] >= f[$0 - 1] && f[$0] > f[$0 + 1] }
        #expect(peaks.count == 2)
        #expect(f[peaks[0]] > f[peaks[1]])            // lub is stronger than dub
        #expect(f[12...].allSatisfy { $0 == 1 })        // second half rests
    }

    @Test func appliesAroundTheDrawing() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 20, y: 20, pressure: 1), InkPoint(x: 30, y: 30, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<11 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.scalePulseLayer(amount: 0.2, heartbeat: true) == 12)
        #expect(s.document().frames.contains { $0[1].transform.scale > 1.1 })
    }
}
