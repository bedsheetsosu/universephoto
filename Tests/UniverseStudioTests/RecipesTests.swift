import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RecipesTests {
    private func oneFrame() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 90, y: 150, pressure: 1), InkPoint(x: 110, y: 170, pressure: 1)], color: .black, width: 8)]
        s.changed()
        s.selectedLayer = 1
        return s
    }

    @Test(arguments: Recipe.allCases)
    func everyRecipeMakesAnAnimationInOneStep(_ r: Recipe) {
        let s = oneFrame()
        let steps = s.undoStack.count
        #expect(s.applyRecipe(r))
        #expect(s.frames.count == 24)
        #expect(s.undoStack.count == steps + 1)
        let xs = Set(s.document().frames.map { "\($0.last!.transform)" })
        #expect(xs.count > 3 || s.document().frames.contains { $0.count > 2 })   // something really moves or was added
        s.undo()
        #expect(s.document().frames.count <= 1)
    }

    @Test func heavyDropLandsAndShakes() {
        let s = oneFrame()
        s.applyRecipe(.dropAndShake)
        let f = s.document().frames
        #expect(f.contains { ($0[1].transform.stretch ?? 1) < 1 })                // squashed on landing
        #expect(f.contains { $0[0].transform.x != 0 || $0[0].transform.y != 0 }) // background jolted
    }
}
