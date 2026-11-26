import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct BeatBounceTests {
    @Test func squashOnTheBeatUpBetween() {
        #expect(Studio.beatPose(0).lift == 0 && Studio.beatPose(0).stretch < 1)
        #expect(Studio.beatPose(0.56).lift > 0.95)
        #expect(Studio.beatPose(2.0).stretch == Studio.beatPose(0).stretch)
    }

    @Test func beatsFollowRealTime() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 60, pressure: 1), InkPoint(x: 140, y: 160, pressure: 1)], color: .black, width: 8)]
        s.changed(); s.selectedLayer = 1
        s.extendAnimation(by: 23)
        #expect(s.beatBounce(bpm: 120) == 24)
        let f = s.document().frames
        // 120 BPM at the document fps: a beat every fps/2 frames → squashed there.
        let every = Int((s.fps / 2).rounded())
        #expect((f[0][1].transform.stretch ?? 1) < 1)
        #expect((f[every][1].transform.stretch ?? 1) < 1)
        #expect(f[every / 2][1].transform.y < f[0][1].transform.y)
    }
}
