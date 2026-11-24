import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SoundReactiveTests {
    @Test func quietFirstHalfLoudSecondHalf() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 100, height: 100); s.newLayer(); s.fps = 4
        #expect(!s.reactToSound(.scale), "needs a sound track")
        #expect(s.setAudio(data: testWAV(seconds: 1), name: "beat", fileExtension: "wav"))
        #expect(s.reactToSound(.jump))
        let ys = s.document().frames.map { $0[1].transform.y }
        #expect(ys.count == 4)
        #expect(ys[0] == 0 && ys[1] == 0 && ys[3] < -7, "silent frames stay, loud frames jump")
        #expect(SoundReaction.normalised([0, 2, 1]) == [0, 1, 0.5] && SoundReaction.normalised([0, 0]) == [0, 0])
        s.undo(); #expect(s.document().frames.count <= 1)
    }
}
