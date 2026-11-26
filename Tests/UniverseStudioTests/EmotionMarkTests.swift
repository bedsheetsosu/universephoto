import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct EmotionMarkTests {
    @Test func popsInThenThrobs() {
        let s = (0..<24).map { Studio.markScale($0, of: 24, fps: 12) }
        #expect(s[0] < 1 && s.prefix(3).max()! > 1.2)
        #expect(s[3...].allSatisfy { $0 >= 1 && $0 <= 1.12 + 1e-9 })
        #expect(s[3...].contains { $0 > 1.05 })
    }

    @Test func eachKindDraws() {
        #expect(Studio.markStrokes(.surprise, at: .zero, size: 20).first?.text == "!")
        #expect(Studio.markStrokes(.confusion, at: .zero, size: 20).first?.text == "?")
        #expect(Studio.markStrokes(.anger, at: .zero, size: 20).count == 4)
    }

    @Test func markAboveTheLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 60, y: 80, pressure: 1), InkPoint(x: 120, y: 160, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<11 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.addEmotionMark(.anger) == 12)
        #expect(s.document().frames.allSatisfy { $0.count == 3 && $0[2].strokes.count == 4 })
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}

@MainActor
struct IdeaMarkTests {
    @Test func lightBulbHasGlassBaseAndRays() {
        let s = Studio.markStrokes(.idea, at: .zero, size: 40)
        #expect(s.filter { $0.kind == "ellipse" }.count == 2)
        #expect(s.contains { $0.kind == "roundedRect" })
        #expect(s.filter { $0.kind == nil }.count == 6)          // screw line + 5 rays
        #expect(s.allSatisfy { $0.points.allSatisfy { $0.y < 60 } })
    }
}
