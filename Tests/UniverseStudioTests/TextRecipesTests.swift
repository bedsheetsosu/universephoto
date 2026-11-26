import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct TextRecipesTests {
    private func title() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        var t = InkStroke(points: [InkPoint(x: 40, y: 80, pressure: 1)], color: .black, width: 30)
        t.kind = "text"; t.text = "Hallo"
        s.layers[1].strokes = [t]; s.changed(); s.selectedLayer = 1
        return s
    }

    @Test func bouncyTitleSplitsLettersAndPops() {
        let s = title()
        #expect(s.applyRecipe(.bouncyTitle))
        let f = s.document().frames
        #expect(f.allSatisfy { $0[1].strokes.count == 5 })
        #expect(f.contains { $0[1].transform.scale < 1 })
        #expect(Set(f.map { $0[1].strokes.map(\.points[0].y) }).count > 3)
    }

    @Test func partyTitleIsColourfulAndBobs() {
        let s = title()
        #expect(s.applyRecipe(.partyTitle))
        let f = s.document().frames
        #expect(Set(f[0][1].strokes.map { "\($0.color)" }).count > 1)
        #expect(Set(f.map { "\($0[1].transform.y)" }).count > 3)
    }
}

@MainActor
struct TitleInOutTests {
    @Test func dropsInHoldsAndLeaves() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 200, background: .white)
        var t = InkStroke(points: [InkPoint(x: 40, y: 80, pressure: 1)], color: .black, width: 30)
        t.kind = "text"; t.text = "Hi!"
        s.layers[1].strokes = [t]; s.changed(); s.selectedLayer = 1
        let rest = Studio.letterStrokes(t).map(\.points[0])
        #expect(s.applyRecipe(.titleInOut))
        let f = s.document().frames
        #expect(f[0][1].strokes.dropFirst().allSatisfy { $0.color.alpha == 0 })
        #expect(f.contains { $0[1].strokes.map(\.points[0]) == rest && $0[1].strokes.allSatisfy { $0.color.alpha > 0 } })
        #expect(f.last![1].strokes.allSatisfy { $0.color.alpha == 0 })
    }
}
