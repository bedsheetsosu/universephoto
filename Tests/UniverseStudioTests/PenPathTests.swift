import CoreGraphics
import Testing
@testable import UniverseStudio

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

@MainActor
struct PenEditTests {
    func studioWithPath() -> Studio {
        let s = Studio()
        s.penPath = PenPath(nodes: [.init(anchor: CGPoint(x: 10, y: 10), out: nil), .init(anchor: CGPoint(x: 100, y: 10), out: CGPoint(x: 120, y: 30)), .init(anchor: CGPoint(x: 60, y: 90), out: nil)])
        return s
    }

    @Test func anchorsMoveWithTheirHandles() {
        let s = studioWithPath()
        let grab = s.penPress(at: CGPoint(x: 101, y: 11), tolerance: 5)
        #expect(grab == .anchor(1))
        s.penMove(.anchor(1), to: CGPoint(x: 110, y: 20))
        #expect(s.penPath?.nodes[1].anchor == CGPoint(x: 110, y: 20))
        #expect(s.penPath?.nodes[1].out == CGPoint(x: 130, y: 40))
        #expect(s.penPath?.nodes.count == 3)
    }

    @Test func handlesStayMirrored() {
        let s = studioWithPath()
        #expect(s.penHit(at: CGPoint(x: 80, y: -10), tolerance: 5) == .inHandle(1))
        s.penMove(.inHandle(1), to: CGPoint(x: 100, y: -20))
        #expect(s.penPath?.nodes[1].out == CGPoint(x: 100, y: 40))
    }

    @Test func optionMakesACornerAndBackspaceRemoves() {
        let s = studioWithPath()
        #expect(s.penPress(at: CGPoint(x: 100, y: 10), tolerance: 5, corner: true) == nil)
        #expect(s.penPath?.nodes[1].out == nil)
        // The first point still closes an open path.
        #expect(s.penPress(at: CGPoint(x: 10, y: 10), tolerance: 5) == nil && s.penPath?.closed == true)
        s.penDeleteLast()
        #expect(s.penPath?.closed == false && s.penPath?.nodes.count == 3)
        s.penDeleteLast(); s.penDeleteLast(); s.penDeleteLast()
        #expect(s.penPath == nil)
    }
}

@MainActor
struct PenInsertTests {
    @Test func insertingKeepsTheCurveShape() {
        var path = PenPath(nodes: [.init(anchor: .zero, out: CGPoint(x: 0, y: 80)), .init(anchor: CGPoint(x: 200, y: 0), out: CGPoint(x: 200, y: -80))])
        let before = path.flattened(step: 1)
        let i = path.insert(segment: 0, t: 0.4)
        #expect(i == 1 && path.nodes.count == 3)
        // Every point of the new outline lies on the old one.
        let after = path.flattened(step: 1)
        let worst = after.map { q in before.map { hypot($0.x - q.x, $0.y - q.y) }.min() ?? 0 }.max() ?? 0
        #expect(worst < 1.5)
        // The end node's handle on that segment is now its own, and survives the round trip.
        #expect(path.nodes[2].inH != nil && path.hasOwnInHandles)
        #expect(PenPath(encoded: path.encoded, closed: false, triples: true) == path)
    }

    @Test func straightSegmentsGetACornerPoint() {
        var path = PenPath(nodes: [.init(anchor: .zero, out: nil), .init(anchor: CGPoint(x: 100, y: 0), out: nil)])
        let hit = path.segmentHit(CGPoint(x: 50, y: 2), tolerance: 4)
        #expect(hit?.segment == 0)
        path.insert(segment: 0, t: hit!.t)
        #expect(path.nodes.count == 3 && path.nodes[1].out == nil && !path.hasOwnInHandles)
        #expect(abs(path.nodes[1].anchor.x - 50) < 1.5)
    }

    @Test func pressOnSegmentAndOptionDragBreaksHandles() {
        let s = Studio()
        s.penPath = PenPath(nodes: [.init(anchor: .zero, out: nil), .init(anchor: CGPoint(x: 100, y: 0), out: CGPoint(x: 120, y: 30)), .init(anchor: CGPoint(x: 100, y: 100), out: nil)])
        // ⌥ on the out-handle: from then on the in-handle stays put.
        #expect(s.penPress(at: CGPoint(x: 120, y: 30), tolerance: 4, corner: true) == .outHandle(1))
        let inBefore = PenPath.inHandle(s.penPath!.nodes[1])
        s.penMove(.outHandle(1), to: CGPoint(x: 140, y: 0))
        #expect(PenPath.inHandle(s.penPath!.nodes[1]) == inBefore)
        // A press in the middle of the first segment inserts a point and grabs it.
        let onCurve = PenPath.point(s.penPath!.controls(0), 0.4)
        let grab = s.penPress(at: onCurve, tolerance: 6)
        #expect(grab == .anchor(1) && s.penPath?.nodes.count == 4)
    }
}

@MainActor
struct PenReopenTests {
    @Test func finishedPathsReopenAndChangeLive() throws {
        let s = Studio()
        s.color = CodableColor(red: 0, green: 1, blue: 0, alpha: 1); s.brushOpacity = 1; s.brushSize = 8
        s.penPath = PenPath(nodes: [.init(anchor: CGPoint(x: 100, y: 100), out: nil), .init(anchor: CGPoint(x: 300, y: 100), out: nil), .init(anchor: CGPoint(x: 200, y: 300), out: nil)], closed: true)
        s.commitPath(fill: true)
        s.penPath = nil
        let count = s.activeLayer?.strokes.count ?? 0
        let id = try #require(s.activeLayer?.strokes.last?.id)
        // A press inside the filled triangle reopens it.
        #expect(s.penPress(at: CGPoint(x: 200, y: 160), tolerance: 6) == nil)
        #expect(s.editingPath == id && s.penPath?.nodes.count == 3 && s.color.green == 1)
        // Moving a point rewrites the same stroke; no new one appears.
        s.penMove(.anchor(2), to: CGPoint(x: 200, y: 400))
        s.syncEditedPath()
        let edited = try #require(s.activeLayer?.strokes.first { $0.id == id })
        #expect(PenPath(encoded: edited.points, closed: true).nodes[2].anchor == CGPoint(x: 200, y: 400))
        // Switching to stroke keeps the id, a new colour applies to it.
        s.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        s.commitEditedPathStyle()
        s.commitPath(fill: false)
        let restyled = try #require(s.activeLayer?.strokes.first { $0.id == id })
        #expect(restyled.filled == nil && restyled.color.red == 1)
        #expect(s.activeLayer?.strokes.count == count)
    }
}
