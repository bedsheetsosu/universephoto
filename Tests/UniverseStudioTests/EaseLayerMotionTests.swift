import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct EaseLayerMotionTests {
    @Test func evenGlideGetsSlowEnds() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in [0.0, 10, 20, 30, 40] {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        s.selectedLayer = 1
        #expect(s.easeLayerMotion(.inOut) == 2)                        // ends and middle stay
        let xs = s.document().frames.map { $0[1].transform.x }
        #expect(xs[0] == 0 && xs[2] == 20 && xs[4] == 40)
        #expect(xs[1] < 10 && xs[3] > 30)
        s.undo()
        s.easeLayerMotion(.slowIn)
        #expect(s.document().frames.map { $0[1].transform.x } == [0, 2.5, 10, 22.5, 40])
    }
}

@MainActor
struct BackEaseTests {
    @Test func windsUpBehindTheStartAndOvershootsTheEnd() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        for x in stride(from: 0.0, through: 90, by: 10) {
            if x > 0 { s.addFrame() }
            s.layers[1].transform.x = x; s.changed()
        }
        s.selectedLayer = 1
        s.easeLayerMotion(.anticipate)
        var xs = s.document().frames.map { $0[1].transform.x }
        #expect(xs.first == 0 && abs(xs.last! - 90) < 1e-9 && xs.min()! < -1)
        s.undo()
        s.easeLayerMotion(.overshoot)
        xs = s.document().frames.map { $0[1].transform.x }
        #expect(xs.max()! > 91 && abs(xs.last! - 90) < 1e-9)
        #expect(Studio.sampled([0, 10, 20], at: -0.5) == -5 && Studio.sampled([0, 10, 20], at: 2.5) == 25)
    }
}
