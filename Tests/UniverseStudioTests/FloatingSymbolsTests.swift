import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FloatingSymbolsTests {
    @Test func riseFadeAndTakeTurns() {
        let a = (0..<24).compactMap { Studio.symbolState(0, of: 3, frame: $0, count: 24) }
        #expect(a.count >= 20)
        #expect(a.map(\.rise) == a.map(\.rise).sorted())             // keeps rising within its life
        #expect(a.last!.alpha < 0.3)                                  // fades out at the top
        let b = Studio.symbolState(1, of: 3, frame: 0, count: 24)!
        #expect(abs(b.rise - 1.0 / 3) < 1e-9)                         // the next one is a third further on
    }

    @Test func symbolsAboveTheLayer() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 80, y: 120, pressure: 1), InkPoint(x: 120, y: 160, pressure: 1)], color: .black, width: 4)]
        s.changed()
        for _ in 0..<11 { s.addFrame() }
        s.selectFrame(0); s.selectedLayer = 1
        #expect(s.addFloatingSymbols(.hearts) == 3)
        let f = s.document().frames
        #expect(f.allSatisfy { $0.count == 3 && $0[2].strokes.allSatisfy { $0.text == "♥" && $0.points[0].y < 120 } })
        #expect(f.contains { $0[2].strokes.count == 3 })
        s.undo()
        #expect(s.document().frames.allSatisfy { $0.count == 2 })
    }
}
