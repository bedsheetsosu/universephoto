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
        let mid = Tween.frames(from: [a], to: [b], count: 3, curve: .linear)
        #expect(mid.map { $0[0].transform.x } == [10, 20, 30])
        #expect(abs(mid[1][0].opacity - 0.6) < 1e-9)
        let other = ArtLayer(name: "only here")
        #expect(Tween.frames(from: [other], to: [b], count: 1, curve: .linear)[0][0] == other, "unmatched layers stay")
    }

    @Test func speedCurvesHaveTheRightShape() {
        // All curves pin the ends.
        for c in Easing.allCases { #expect(abs(c.value(0)) < 1e-9 && abs(c.value(1) - 1) < 1e-9) }
        // Accelerate stays behind linear early, brake runs ahead.
        #expect(Easing.accelerate.value(0.5) < 0.5 && Easing.decelerate.value(0.5) > 0.5)
        // Anticipate dips below 0 (pull back) and overshoot climbs above 1 (fly past) in the middle.
        #expect(Easing.anticipate.value(0.25) < 0)
        #expect(Easing.overshoot.value(0.75) > 1)
    }

    @Test func overshootTweenPassesTheTargetThenSettles() {
        var a = ArtLayer(name: "ball"); a.opacity = 1
        var b = a; b.transform.x = 100
        let mid = Tween.frames(from: [a], to: [b], count: 6, curve: .overshoot)
        let xs = mid.map { $0[0].transform.x }
        #expect(xs.contains { $0 > 100 }, "a layer flies past its target")
        // Opacity (and a crossfade's blend) must never leave 0…1, even while the position overshoots.
        #expect(mid.allSatisfy { $0[0].opacity >= 0 && $0[0].opacity <= 1 })
    }

    @Test func insertsAfterTheFrameOneUndoStep() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10); s.addFrame()      // frame 1 = copy, current
        s.layers[0].transform.x = 30
        s.selectFrame(0)
        #expect(s.tweenToNext(from: 0, count: 2, curve: .linear) == 2)
        let xs = s.document().frames.map { $0[0].transform.x }
        #expect(xs == [0, 10, 20, 30] && s.frameIndex == 0)
        #expect(s.tweenToNext(from: 3, count: 2, curve: .linear) == 0, "last frame has no next")
        s.undo()
        #expect(s.document().frames.count == 2)
    }
}
