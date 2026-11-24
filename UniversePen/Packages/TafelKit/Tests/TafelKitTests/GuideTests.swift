import XCTest
import CoreGraphics
@testable import TafelKit

final class GuideTests: XCTestCase {
    func testTwoPointPerspectivePicksTheMatchingVanishingPoint() {
        let g = PerspectiveGuide(points: [CGPoint(x: 0, y: 100), CGPoint(x: 1000, y: 100)])
        let start = CGPoint(x: 500, y: 400)
        // Heading up-left, towards the left point.
        let left = g.snapLine(start: start, toward: CGPoint(x: 480, y: 388))!
        let p = left.project(CGPoint(x: 0, y: 100))
        XCTAssertEqual(p.x, 0, accuracy: 0.01); XCTAssertEqual(p.y, 100, accuracy: 0.01)
        // Heading straight up: the vertical.
        let up = g.snapLine(start: start, toward: CGPoint(x: 501, y: 380))!
        XCTAssertEqual(up.project(CGPoint(x: 700, y: 0)).x, 500, accuracy: 0.01)
    }

    func testOnePointHasHorizontals() {
        let g = PerspectiveGuide(points: [CGPoint(x: 500, y: 300)])
        let h = g.snapLine(start: CGPoint(x: 100, y: 700), toward: CGPoint(x: 130, y: 701))!
        XCTAssertEqual(h.project(CGPoint(x: 900, y: 0)).y, 700, accuracy: 0.01)
    }

    func testThreePointHasNoFreeVertical() {
        let g = PerspectiveGuide(points: [CGPoint(x: 0, y: 100), CGPoint(x: 1000, y: 100), CGPoint(x: 500, y: 5000)])
        XCTAssertEqual(g.directions(at: CGPoint(x: 400, y: 400)).count, 3)
    }

    func testPerspectiveHandles() {
        let g = PerspectiveGuide.defaultLayout(count: 2, in: CGSize(width: 1000, height: 700))
        XCTAssertEqual(g.handle(at: CGPoint(x: 85, y: 285)), 0)
        XCTAssertNil(g.handle(at: CGPoint(x: 500, y: 500)))
    }

    func testEllipseProjectionAndSnap() {
        let e = EllipseGuide(center: CGPoint(x: 0, y: 0), rx: 200, ry: 100, angle: .pi / 2)
        // Rotated 90°: the long axis is vertical.
        let p = e.project(CGPoint(x: 0, y: 250))
        XCTAssertEqual(p.y, 200, accuracy: 0.5); XCTAssertEqual(p.x, 0, accuracy: 0.5)
        XCTAssertTrue(e.snaps(CGPoint(x: 0, y: 215)))
        XCTAssertFalse(e.snaps(CGPoint(x: 0, y: 300)))
        XCTAssertTrue(e.containsBody(CGPoint(x: 0, y: 0)))
        XCTAssertFalse(e.containsBody(CGPoint(x: 0, y: 195)))   // on the outline band: Pencil snaps there
    }

    func testEllipseHandleDrag() {
        var e = EllipseGuide(center: CGPoint(x: 100, y: 100), rx: 80, ry: 40)
        XCTAssertEqual(e.handle(at: CGPoint(x: 182, y: 100)), 0)
        XCTAssertEqual(e.handle(at: CGPoint(x: 100, y: 58)), 1)
        e.drag(handle: 1, to: CGPoint(x: 100, y: 20))
        XCTAssertEqual(e.ry, 80, accuracy: 0.001)
        XCTAssertEqual(e.rx, 80, accuracy: 0.001)
    }

    func testGridLines() {
        let r = CGRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertEqual(GridStyle.thirds.lines(in: r).count, 4)
        XCTAssertEqual(GridStyle.quarters.lines(in: r).count, 6)
        XCTAssertEqual(GridStyle.squares.lines(in: r).count, 7 + 5)   // cell 37.5: 7 verticals, 5 horizontals
        XCTAssertTrue(GridStyle.off.lines(in: r).isEmpty)
    }

    func testGuideStorageRoundTrip() {
        for g in [DrawingGuide.none, .ruler, .perspective(1), .perspective(2), .perspective(3), .ellipse] {
            XCTAssertEqual(DrawingGuide(storageName: g.storageName), g)
        }
    }

    func testGridCells() {
        let r = CGRect(x: 0, y: 0, width: 400, height: 200)
        XCTAssertEqual(GridStyle.squares.lines(in: r, cells: 4).count, 3 + 1)
    }

    func testEllipseSnapsToCircle() {
        var e = EllipseGuide(center: .zero, rx: 100, ry: 60)
        e.drag(handle: 1, to: CGPoint(x: 0, y: -97))
        XCTAssertEqual(e.ry, 100, accuracy: 0.001)
    }
}
