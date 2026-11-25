import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct OnSelectedLayersTests {
    @Test func everySelectedLayerInOneUndoStep() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.newLayer()                                             // three layers
        s.addFrame(); s.addFrame()
        s.selectedLayer = 1
        let active = s.layers[1].id
        s.selectedIDs = [s.layers[1].id, s.layers[2].id]
        let steps = s.undoStack.count
        #expect(s.onSelectedLayers { s.fadeLayerOverFrames(fadeIn: true) } == 4)
        let f = s.document().frames
        #expect(f[0][1].opacity == 0 && f[0][2].opacity == 0 && f[0][0].opacity == 1)
        #expect(s.undoStack.count == steps + 1 && s.activeLayer?.id == active)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.allSatisfy { $0.opacity == 1 } })
    }

    @Test func singleLayerRunsAsBefore() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.addFrame()
        s.selectedLayer = 1; s.selectedIDs = []
        #expect(s.onSelectedLayers { s.fadeLayerOverFrames(fadeIn: true) } == 1)
        #expect(s.document().frames[0][0].opacity == 1)
    }
}
