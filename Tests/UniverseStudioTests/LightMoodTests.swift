import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct LightMoodTests {
    @Test func fadesOverTheRange() {
        let r = 2...8
        #expect(Studio.moodOpacity(0, range: r, mood: .dayToNight) == 0)
        #expect(Studio.moodOpacity(10, range: r, mood: .dayToNight) == 0.8)
        #expect(Studio.moodOpacity(0, range: r, mood: .nightToDay) == 0.8)
        let mid = Studio.moodOpacity(5, range: r, mood: .dayToNight)
        #expect(mid > 0.2 && mid < 0.6)
    }

    @Test func layerOnTopThatDarkens() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 20, height: 20, background: .white)
        for _ in 0..<5 { s.addFrame() }
        s.selectFrame(0)
        #expect(s.addLightMood(.dayToNight) == 6)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.last!.blend == .multiply && $0.last!.strokes.first?.kind == "fill" })
        #expect(f[0].last!.opacity == 0 && f[5].last!.opacity == 0.8)
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
