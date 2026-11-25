import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FollowChainTests {
    @Test func eachLinkRunsOneStepLater() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)   // [background, sketch]
        s.newLayer()                                                // a third layer on top
        s.selectFrame(0)
        let ids = s.layers.map(\.id)
        for (k, y) in [0.0, 10, 0, -10].enumerated() {
            if k > 0 { s.addFrame() }
            s.layers[0].transform.y = y; s.changed()                 // bottom layer leads
        }
        s.selectedLayer = 0
        s.selectedIDs = Set(ids)
        #expect(s.followInChain(step: 1) > 0)
        let f = s.document().frames
        #expect(f.map { $0[1].transform.y } == [-10, 0, 10, 0])       // one frame behind
        #expect(f.map { $0[2].transform.y } == [0, -10, 0, 10])       // two frames behind
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[2].transform.y == 0 })
    }
}
