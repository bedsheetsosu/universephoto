import XCTest
@testable import UniversePhoto

@MainActor final class GuideTests: XCTestCase {
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 100)
        return s
    }

    func testSnapsToGuidesEdgesAndCentre() {
        let s = studio()
        s.addGuide(vertical: true, at: 40)
        XCTAssertEqual(s.snappedToGuides(CGPoint(x: 43, y: 30), tolerance: 5), CGPoint(x: 40, y: 30))
        XCTAssertEqual(s.snappedToGuides(CGPoint(x: 98, y: 52), tolerance: 5), CGPoint(x: 100, y: 50), "Canvas centre")
        XCTAssertEqual(s.snappedToGuides(CGPoint(x: 197, y: 3), tolerance: 5), CGPoint(x: 200, y: 0), "Edges")
        XCTAssertEqual(s.snappedToGuides(CGPoint(x: 60, y: 30), tolerance: 5), CGPoint(x: 60, y: 30), "Too far: unchanged")
        s.snapToGuides = false
        XCTAssertEqual(s.snappedToGuides(CGPoint(x: 43, y: 30), tolerance: 5), CGPoint(x: 43, y: 30))
    }

    func testMoveRemoveUndoAndSave() throws {
        let s = studio()
        s.addGuide(vertical: false, at: 30)
        let id = try XCTUnwrap(s.guides.first?.id)
        XCTAssertEqual(s.guide(near: CGPoint(x: 5, y: 32), tolerance: 4)?.id, id)
        s.moveGuide(id, to: 70.4)
        XCTAssertEqual(s.guides.first?.position, 70)
        let saved = try JSONDecoder().decode(ArtDocument.self, from: JSONEncoder().encode(s.document()))
        XCTAssertEqual(saved.guides, s.guides)
        s.moveGuide(id, to: -20)
        XCTAssertTrue(s.guides.isEmpty, "Dragged off the canvas: removed")
        s.undo()
        XCTAssertTrue(s.guides.isEmpty, "Undo goes back before the guide was added")
        s.guidesLocked = true; s.addGuide(vertical: true, at: 10)
        XCTAssertNil(s.guide(near: CGPoint(x: 10, y: 10), tolerance: 4), "Locked guides can't be grabbed")
    }

    func testGuidesFollowRotationAndCrop() {
        let s = studio()
        s.addGuide(vertical: true, at: 40); s.addGuide(vertical: false, at: 20)
        s.rotateCanvas(.clockwise)   // 100×200; x' = 100 - y, y' = x
        XCTAssertEqual(Set(s.guides.map { "\($0.vertical) \($0.position)" }), ["false 40.0", "true 80.0"])
        s.crop(to: CGRect(x: 50, y: 0, width: 50, height: 100))
        XCTAssertEqual(s.guides.map { "\($0.vertical) \($0.position)" }.sorted(), ["false 40.0", "true 30.0"])
    }

    func testGuidesFromSelection() {
        let s = studio()
        s.selection = CanvasSelection(points: [CGPoint(x: 10, y: 20), CGPoint(x: 60, y: 80)])
        s.guidesFromSelection()
        XCTAssertEqual(s.guides.map(\.position), [10, 60, 20, 80])
    }
}
