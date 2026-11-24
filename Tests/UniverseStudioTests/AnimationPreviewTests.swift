import Testing
@testable import UniverseStudio

struct AnimationPreviewTests {
    @Test func sequenceHonoursHoldsRangeAndPingPong() {
        #expect(AnimationPreview.sequence(count: 3, range: nil, pingPong: false, hold: { $0 == 1 ? 2 : 1 }) == [0, 1, 1, 2])
        #expect(AnimationPreview.sequence(count: 4, range: nil, pingPong: true, hold: { _ in 1 }) == [0, 1, 2, 3, 2, 1])
        #expect(AnimationPreview.sequence(count: 5, range: 1...3, pingPong: false, hold: { _ in 1 }) == [1, 2, 3])
        #expect(AnimationPreview.sequence(count: 2, range: nil, pingPong: true, hold: { _ in 1 }) == [0, 1])
        #expect(AnimationPreview.sequence(count: 0, range: nil, pingPong: false, hold: { _ in 1 }).isEmpty)
    }

    @Test func ticksLoopOrEnd() {
        #expect(AnimationPreview.tick(elapsed: 1.05, fps: 10, length: 4, loop: true) == 2)
        #expect(AnimationPreview.tick(elapsed: 0.35, fps: 10, length: 4, loop: false) == 3)
        #expect(AnimationPreview.tick(elapsed: 0.45, fps: 10, length: 4, loop: false) == nil)
    }
}
