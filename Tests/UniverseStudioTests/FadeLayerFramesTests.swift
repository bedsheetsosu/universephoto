import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FadeLayerFramesTests {
    private func three() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        return s
    }

    @Test func fadesInFromNothing() {
        let s = three()
        #expect(s.fadeLayerOverFrames(fadeIn: true) == 2)       // the last frame stays at 100 %
        #expect(s.document().frames.map { $0[1].opacity } == [0, 0.5, 1])
        #expect(s.document().frames.allSatisfy { $0[0].opacity == 1 })
    }

    @Test func fadeOutRespectsExistingOpacityAndUndoes() {
        let s = three()
        s.layers[1].opacity = 0.5; s.changed()
        s.fadeLayerOverFrames(fadeIn: false)
        #expect(s.document().frames[2][1].opacity == 0)
        s.undo()
        #expect(s.document().frames[2][1].opacity == 0.5)
    }
}
