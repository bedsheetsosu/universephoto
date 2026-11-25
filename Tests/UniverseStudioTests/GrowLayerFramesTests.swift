import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct GrowLayerFramesTests {
    @Test func growsFromAlmostNothingAndUndoes() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        #expect(s.growLayerOverFrames(grow: true) == 2)
        #expect(s.document().frames.map { $0[1].transform.scale } == [0.01, 0.5, 1])
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.scale == 1 })
        s.growLayerOverFrames(grow: false)
        #expect(s.document().frames.map { $0[1].transform.scale } == [1, 0.5, 0.01])
    }
}

@MainActor
struct PopLayerFramesTests {
    @Test func overshootsThenSettles() {
        let ramp = (0..<11).map { Studio.popRamp($0, of: 11) }
        #expect(abs(ramp[0]) < 1e-9 && abs(ramp[10] - 1) < 1e-9)
        #expect(ramp.max()! > 1.05)                                  // goes past full size
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for _ in 0..<9 { s.addFrame() }
        s.selectedLayer = 1
        s.growLayerOverFrames(grow: true, pop: true)
        let sc = s.document().frames.map { $0[1].transform.scale }
        #expect(sc.first == 0.01 && abs(sc.last! - 1) < 1e-9 && sc.max()! > 1.05)
    }
}
