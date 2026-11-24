import CoreGraphics
import Testing
@testable import UniverseStudio

@MainActor
struct SymmetryTests {
    func stroke(_ code: String?) -> InkStroke {
        var s = InkStroke(points: [InkPoint(x: 100, y: 100, pressure: 1), InkPoint(x: 140, y: 120, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 12)
        s.symmetry = code; s.symmetryX = 300; s.symmetryY = 200
        return s
    }

    @Test func copiesLandWhereTheyShould() {
        let v = Symmetry.copies(of: stroke("v"))
        #expect(v.count == 2 && v[1].points[0].x == 500 && v[1].points[0].y == 100 && v[1].symmetry == nil)
        let q = Symmetry.copies(of: stroke("vh"))
        #expect(q.count == 4 && q[3].points[0].x == 500 && q[3].points[0].y == 300)
        let r = Symmetry.copies(of: stroke("r4"))
        #expect(r.count == 4)
        // A quarter turn around (300, 200) takes (100, 100) to (400, 0).
        #expect(abs(r[1].points[0].x - 400) < 0.001 && abs(r[1].points[0].y - 0) < 0.001)
        #expect(Symmetry.copies(of: stroke(nil)).count == 1)
    }

    @Test func rendererPaintsTheMirror() throws {
        var layer = ArtLayer(name: "t")
        layer.strokes = [stroke("v")]
        let image = try #require(Renderer.render(layers: [layer], width: 600, height: 400))
        #expect(Renderer.sample(image, at: CGPoint(x: 100, y: 100)).red > 0.9)
        #expect(Renderer.sample(image, at: CGPoint(x: 500, y: 100)).red > 0.9)
        #expect(Renderer.sample(image, at: CGPoint(x: 300, y: 300)).alpha < 0.1)
    }

    @Test func codes() {
        #expect(Symmetry.off.code(segments: 6) == nil)
        #expect(Symmetry.radial.code(segments: 100) == "r24")
        #expect(Symmetry.quad.code(segments: 6) == "vh")
    }
}

@MainActor
struct SymmetryCentreTests {
    @Test func pivotDefaultsToTheCanvasCentre() {
        let s = Studio()
        #expect(s.symmetryPivot == CGPoint(x: Double(s.width) / 2, y: Double(s.height) / 2))
        s.symmetryCenter = CGPoint(x: 10, y: 20)
        #expect(s.symmetryPivot == CGPoint(x: 10, y: 20))
        // An off-centre mirror: (0, 0) around x = 10 lands at x = 20.
        var stroke = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 4)
        stroke.symmetry = "v"; stroke.symmetryX = s.symmetryPivot.x; stroke.symmetryY = s.symmetryPivot.y
        #expect(Symmetry.copies(of: stroke)[1].points[0].x == 20)
    }
}
