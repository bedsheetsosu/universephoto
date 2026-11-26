import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct SwarmTests {
    @Test func pathsLoopAndDiffer() {
        let a0 = Studio.swarmOffset(member: 0, frame: 0, of: 12, radius: 50)
        let a12 = Studio.swarmOffset(member: 0, frame: 12, of: 12, radius: 50)
        #expect(abs(a0.x - a12.x) < 1e-9 && abs(a0.y - a12.y) < 1e-9)
        let b0 = Studio.swarmOffset(member: 1, frame: 0, of: 12, radius: 50)
        #expect(a0 != b0)
    }

    @Test func addsCopiesBehindTheOriginal() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 95, y: 95, pressure: 1), InkPoint(x: 105, y: 105, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<7 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        let src = s.layers[1].id
        #expect(s.addSwarm(count: 4) == 4)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 6 && $0[5].id == src })
        #expect(f.allSatisfy { fr in fr[1...4].allSatisfy { $0.transform.scale < 1 && !$0.strokes.isEmpty } })
        #expect(Set(f.map { $0[1].transform.x }).count > 1)            // they move
        #expect(s.layers[s.selectedLayer].id == src)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
