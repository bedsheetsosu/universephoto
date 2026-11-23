import CoreGraphics
import Foundation
import Testing
@testable import UniversePhoto

@MainActor
struct ShortcutsAndLiquifyTests {
    @Test func toolKeysAreUnique() {
        let keys = Tool.allCases.map(\.key)
        #expect(Set(keys).count == keys.count)
        // Plain-letter menu keys must not collide with a tool key.
        for menuKey in ["x"] { #expect(!keys.contains(menuKey)) }
    }

    @Test func liquifyStaysInsideTheSelection() throws {
        let s = Studio()
        s.newLayer()
        // Vertical stripes so any push is visible.
        for x in stride(from: 0, to: 400, by: 20) {
            var r = InkStroke(points: [InkPoint(x: Double(x), y: 0, pressure: 1), InkPoint(x: Double(x + 10), y: 400, pressure: 1)], color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), width: 1)
            r.kind = "rectangle"; r.filled = true
            s.add(r)
        }
        s.selection = CanvasSelection(points: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 400)])
        let before = try #require(s.rawLayerPixels())
        s.brushSize = 300; s.toolStrength = 1; s.liquifyMode = .push
        let id = UUID()
        s.beginLiquify(id: id, at: CGPoint(x: 200, y: 200))
        s.liquify(id: id, to: CGPoint(x: 260, y: 200))
        var stroke = InkStroke(points: [InkPoint(x: 200, y: 200, pressure: 1)], color: .white, width: 300); stroke.id = id; stroke.kind = "liquify"
        s.finishLiquify(stroke)
        let after = try #require(s.rawLayerPixels())
        // Right of the selection nothing moved; inside it something did.
        var outside = 0, inside = 0
        for x in stride(from: 205, to: 340, by: 3) { if Renderer.sample(before, at: CGPoint(x: x, y: 200)).alpha != Renderer.sample(after, at: CGPoint(x: x, y: 200)).alpha { outside += 1 } }
        for x in stride(from: 60, to: 195, by: 3) { if Renderer.sample(before, at: CGPoint(x: x, y: 200)).alpha != Renderer.sample(after, at: CGPoint(x: x, y: 200)).alpha { inside += 1 } }
        #expect(outside == 0)
        #expect(inside > 0)
    }
}
