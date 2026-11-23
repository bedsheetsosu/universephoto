import CoreGraphics
import Testing
@testable import UniversePhoto

@MainActor
struct PenPathTests {
    @Test func encodingRoundTripsCornersAndCurves() {
        let path = PenPath(nodes: [.init(anchor: CGPoint(x: 10, y: 10), out: nil), .init(anchor: CGPoint(x: 50, y: 20), out: CGPoint(x: 70, y: 40))], closed: true)
        let back = PenPath(encoded: path.encoded, closed: true)
        #expect(back == path)
        #expect(PenPath.inHandle(path.nodes[1]) == CGPoint(x: 30, y: 0))
    }

    @Test func flattenedFollowsTheCurve() {
        let line = PenPath(nodes: [.init(anchor: .zero, out: nil), .init(anchor: CGPoint(x: 100, y: 0), out: nil)])
        let pts = line.flattened(step: 10)
        #expect(pts.first == .zero && pts.last == CGPoint(x: 100, y: 0))
        #expect(pts.allSatisfy { abs($0.y) < 0.001 })
        // A curve bulges away from the chord.
        let curve = PenPath(nodes: [.init(anchor: .zero, out: CGPoint(x: 0, y: 60)), .init(anchor: CGPoint(x: 100, y: 0), out: CGPoint(x: 100, y: -60))])
        #expect((curve.flattened().map(\.y).max() ?? 0) > 20)
    }

    @Test func clicksBuildAndCloseThePath() {
        let s = Studio()
        s.tool = .pen
        #expect(s.penClick(at: CGPoint(x: 10, y: 10), closeDistance: 5) == 0)
        _ = s.penClick(at: CGPoint(x: 100, y: 10), closeDistance: 5)
        s.penDrag(node: 1, to: CGPoint(x: 120, y: 30))
        #expect(s.penPath?.nodes[1].out == CGPoint(x: 120, y: 30))
        _ = s.penClick(at: CGPoint(x: 60, y: 90), closeDistance: 5)
        #expect(s.penClick(at: CGPoint(x: 12, y: 11), closeDistance: 5) == nil)
        #expect(s.penPath?.closed == true && s.penPath?.nodes.count == 3)
        s.pathToSelection()
        #expect(s.selection != nil && (s.selection?.points.count ?? 0) > 10)
    }

    @Test func filledPathPaintsInside() throws {
        let s = Studio()
        s.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1); s.brushOpacity = 1
        s.penPath = PenPath(nodes: [.init(anchor: CGPoint(x: 100, y: 100), out: nil), .init(anchor: CGPoint(x: 300, y: 100), out: nil), .init(anchor: CGPoint(x: 200, y: 300), out: nil)], closed: true)
        let before = s.activeLayer?.strokes.count ?? 0
        s.commitPath(fill: true)
        let layer = try #require(s.activeLayer)
        #expect(layer.strokes.count == before + 1 && layer.strokes.last?.kind == "path")
        let image = try #require(Renderer.render(layers: [layer], width: s.width, height: s.height))
        let c = Renderer.sample(image, at: CGPoint(x: 200, y: 160))
        #expect(c.red > 0.9 && c.green < 0.1)
        let outside = Renderer.sample(image, at: CGPoint(x: 110, y: 280))
        #expect(outside.red < 0.5 || outside.alpha < 0.5)
    }
}
