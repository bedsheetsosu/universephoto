import Testing
import Foundation
@testable import UniverseStudio

struct PlaybackModeTests {
    private func run(_ start: Int, _ n: Int, count: Int, range: ClosedRange<Int>? = nil, loop: Bool = true, ping: Bool = false) -> [Int] {
        var out: [Int] = [], cur = start, fwd = true
        for _ in 0..<n {
            guard let next = Playback.step(current: cur, count: count, range: range, loop: loop, pingPong: ping, forward: fwd) else { break }
            cur = next.index; fwd = next.forward; out.append(cur)
        }
        return out
    }

    @Test func loopOnceAndPingPong() {
        #expect(run(0, 5, count: 3) == [1, 2, 0, 1, 2])
        #expect(run(0, 5, count: 3, loop: false) == [1, 2])
        #expect(run(0, 7, count: 3, ping: true) == [1, 2, 1, 0, 1, 2, 1])
        #expect(run(0, 7, count: 3, loop: false, ping: true) == [1, 2, 1, 0])
    }

    @Test func rangeLimitsPlayback() {
        #expect(run(1, 5, count: 6, range: 1...3) == [2, 3, 1, 2, 3])
        #expect(run(5, 2, count: 6, range: 1...3) == [1, 2], "outside the range jumps to its start")
        #expect(run(1, 5, count: 6, range: 1...3, ping: true) == [2, 3, 2, 1, 2])
        #expect(Playback.clamp(0...9, count: 4) == nil && Playback.clamp(2...9, count: 4) == 2...3)
    }

    @MainActor @Test func markersFromTheTimeline() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 4, height: 4); for _ in 0..<4 { s.addFrame() }   // 5 frames
        s.setPlayStart(1); #expect(s.playRange == 1...4)
        s.setPlayEnd(3); #expect(s.playRange == 1...3)
        s.setPlayStart(0); s.setPlayEnd(4); #expect(s.playRange == nil, "everything = no range")
        s.setPlayEnd(2); #expect(s.inPlayRange(2) && !s.inPlayRange(3))
    }
}
