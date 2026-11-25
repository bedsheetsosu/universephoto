import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SquashStretchTests {
    @Test func stretchesInFlightAndSquashesOnLanding() {
        // A hop: up, top, down, ground (landing), up again.
        let c = Studio.squashStretchCurve([0, -40, -50, -40, 0, -40], amount: 1)
        #expect(c[4] < 1)                         // landing frame is squashed
        #expect(c[1] > 1 && c[3] > 1)             // fast frames are stretched
        #expect(abs(c[2] - 1) < 0.2)              // the top hangs nearly round
    }

    @Test func keepsVolumeAndSurvivesTheFile() throws {
        var t = LayerTransform(); t.scale = 2; t.stretch = 1.25
        #expect(abs(t.scaleX * t.scaleY - 4) < 1e-9)
        let back = try JSONDecoder().decode(LayerTransform.self, from: JSONEncoder().encode(t))
        #expect(back == t)
        let old = try JSONDecoder().decode(LayerTransform.self, from: Data(#"{"x":1,"y":2,"scale":1,"rotation":0}"#.utf8))
        #expect(old.stretch == nil && old.scaleX == 1)
    }

    @Test func appliesAfterABounceAndUndoes() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100, background: .white)
        for _ in 0..<8 { s.addFrame() }
        s.selectedLayer = 1
        s.bounceLayer(height: 50, bounces: 2)
        #expect(s.squashStretch() > 0)
        let st = s.document().frames.map { $0[1].transform.stretch ?? 1 }
        #expect(st.contains { $0 < 1 } && st.contains { $0 > 1 })
        s.undo()
        #expect(s.document().frames.allSatisfy { $0[1].transform.stretch == nil })
    }
}
