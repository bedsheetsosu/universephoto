import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SmearFrameTests {
    private func movingPair() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        s.addFrame(); s.layers[1].transform.x = 60; s.changed()
        s.selectFrame(0)
        return s
    }

    @Test func smearSpreadsTheLayerAcrossTheMove() {
        let s = movingPair()
        s.insertSmear(after: 0, copies: 4)
        #expect(s.frames.count == 3 && s.frameIndex == 1)
        let f = s.document().frames[1]
        let smears = f.filter { $0.name == Studio.smearName }
        #expect(smears.count == 4)
        let xs = smears.map(\.transform.x)
        #expect(xs.first == 0 && xs.last == 60)              // spans both poses
        #expect(xs == xs.sorted())                           // evenly stepped across
    }

    @Test func endsAreFirmerThanTheMiddle() {
        var a = ArtLayer(name: "ball"); a.opacity = 1
        var b = a; b.transform.x = 100
        let ls = Studio.smearLayers(a, b, copies: 5)
        #expect(ls.first!.opacity > ls[2].opacity && ls.last!.opacity > ls[2].opacity)
        #expect(ls.allSatisfy { $0.locked && $0.name == Studio.smearName })
    }

    @Test func oneUndoStep() {
        let s = movingPair()
        s.insertSmear(after: 0, copies: 3)
        s.undo()
        #expect(s.frames.count == 2)
    }
}
