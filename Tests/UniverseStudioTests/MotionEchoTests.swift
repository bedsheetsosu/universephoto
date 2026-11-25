import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct MotionEchoTests {
    /// Three frames; the active layer (index 1) moves across. Returns the studio on frame 2.
    private func moving() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10, background: .white)
        s.layers[1].transform.x = 0; s.changed()
        s.addFrame(); s.layers[1].transform.x = 20; s.changed()
        s.addFrame(); s.layers[1].transform.x = 40; s.changed()
        return s   // on frame 2, selectedLayer = 1
    }

    @Test func ghostsAppearBehindAndFade() {
        let s = moving()
        let added = s.motionEcho(count: 2)
        #expect(added == 3)                                  // frame0: 0, frame1: 1, frame2: 2
        let f2 = s.document().frames[2]
        let echoes = f2.filter { $0.name == Studio.echoName }
        #expect(echoes.count == 2)
        // The drawing is still selected, and the ghosts sit below it.
        #expect(s.activeLayer?.name != Studio.echoName)
        let drawIdx = f2.firstIndex { $0.id == s.activeLayer!.id }!
        #expect(f2.prefix(drawIdx).contains { $0.name == Studio.echoName })
        // Nearer ghost is more opaque than the farther one.
        let faint = echoes.map(\.opacity).min()!, bright = echoes.map(\.opacity).max()!
        #expect(faint < bright && bright <= 1)
    }

    @Test func rerunReplacesNotStacks() {
        let s = moving()
        s.motionEcho(count: 3)
        s.motionEcho(count: 2)                               // fewer now
        let counts = s.document().frames.map { f in f.filter { $0.name == Studio.echoName }.count }
        #expect(counts == [0, 1, 2])                          // not 3/5/…, so no stacking
    }

    @Test func noneClearsEcho() {
        let s = moving()
        s.motionEcho(count: 3)
        let cleared = s.motionEcho(count: 0)
        #expect(cleared == 0)
        #expect(s.document().frames.allSatisfy { f in !f.contains { $0.name == Studio.echoName } })
    }

    @Test func oneUndoStep() {
        let s = moving()
        let before = s.document().frames.map(\.count)
        s.motionEcho(count: 3)
        s.undo()
        #expect(s.document().frames.map(\.count) == before)
    }
}
