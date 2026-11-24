import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct TweenTests {
    @Test func mathIsShortWayAndEased() {
        #expect(Tween.lerpAngle(350, 10, 0.5) == 360)
        #expect(Tween.lerpAngle(10, 350, 0.5) == 0)
        #expect(Tween.ease(0.5, eased: true) == 0.5 && Tween.ease(0.25, eased: true) < 0.25)
    }

    @Test func inBetweensMoveAndFade() {
        var a = ArtLayer(name: "ball"); a.opacity = 1
        var b = a; b.transform.x = 40; b.opacity = 0.2
        let mid = Tween.frames(from: [a], to: [b], count: 3, eased: false)
        #expect(mid.map { $0[0].transform.x } == [10, 20, 30])
        #expect(abs(mid[1][0].opacity - 0.6) < 1e-9)
        let other = ArtLayer(name: "only here")
        #expect(Tween.frames(from: [other], to: [b], count: 1, eased: false)[0][0] == other, "unmatched layers stay")
    }

    @Test func insertsAfterTheFrameOneUndoStep() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10); s.addFrame()      // frame 1 = copy, current
        s.layers[0].transform.x = 30
        s.selectFrame(0)
        #expect(s.tweenToNext(from: 0, count: 2, eased: false) == 2)
        let xs = s.document().frames.map { $0[0].transform.x }
        #expect(xs == [0, 10, 20, 30] && s.frameIndex == 0)
        #expect(s.tweenToNext(from: 3, count: 2, eased: false) == 0, "last frame has no next")
        s.undo()
        #expect(s.document().frames.count == 2)
    }
}
