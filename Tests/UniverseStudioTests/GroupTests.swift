import XCTest
@testable import UniverseStudio

@MainActor final class GroupTests: XCTestCase {
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10)
        for _ in 0..<3 { s.newLayer() }          // 4 layers: Sketch, Layer 2, Layer 3, Layer 4
        return s
    }

    func testGroupingGathersSelectedLayersInOrder() {
        let s = studio()
        let names = s.layers.map(\.name)
        s.selectLayer(0); s.selectLayer(2, command: true)              // Sketch and Layer 3
        s.groupSelected()
        XCTAssertEqual(s.groups.count, 1)
        let grouped = s.layers.filter { $0.groupID != nil }.map(\.name)
        XCTAssertEqual(grouped, [names[0], names[2]], "Order kept")
        let idx = s.layers.indices.filter { s.layers[$0].groupID != nil }
        XCTAssertEqual(idx.last! - idx.first!, 1, "Contiguous")
        XCTAssertEqual(s.layers.last?.name, names[3], "Layers above the group stay on top")
        s.undo()
        XCTAssertTrue(s.groups.isEmpty); XCTAssertEqual(s.layers.map(\.name), names)
    }

    func testShiftSelectsARange() {
        let s = studio()
        s.selectLayer(1); s.selectLayer(3, shift: true)
        XCTAssertEqual(s.selectedIndices, [1, 2, 3])
        s.selectLayer(0)
        XCTAssertEqual(s.selectedIndices, [0])
    }

    func testHiddenGroupAndGroupOpacityAffectTheComposite() throws {
        let s = studio()
        var f = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1)
        f.kind = "fill"
        s.selectLayer(3); s.add(f)
        s.groupSelected()
        let id = try XCTUnwrap(s.groups.first?.id)
        s.updateGroup(id, "Group opacity") { $0.opacity = 0.5 }
        let half = Renderer.sample(try XCTUnwrap(Renderer.render(layers: s.composite(s.layers), width: 10, height: 10)), at: CGPoint(x: 5, y: 5))
        XCTAssertEqual(half.alpha, 0.5, accuracy: 0.02)
        s.updateGroup(id, "Group visibility") { $0.visible = false }
        XCTAssertEqual(Renderer.sample(try XCTUnwrap(Renderer.render(layers: s.composite(s.layers), width: 10, height: 10)), at: CGPoint(x: 5, y: 5)).alpha, 0)
        XCTAssertTrue(s.layers[3].visible, "The layer's own switch is untouched")
    }

    func testUngroupAndPruneAndSaveRoundTrip() throws {
        let s = studio()
        s.selectLayer(1); s.selectLayer(2, command: true); s.groupSelected()
        let data = try JSONEncoder().encode(s.document())
        let back = try JSONDecoder().decode(ArtDocument.self, from: data)
        XCTAssertEqual(back.groups?.count, 1)
        XCTAssertEqual(back.layers.filter { $0.groupID == back.groups?.first?.id }.count, 2)
        s.ungroup()
        XCTAssertTrue(s.groups.isEmpty); XCTAssertTrue(s.layers.allSatisfy { $0.groupID == nil })
        s.undo(); XCTAssertEqual(s.groups.count, 1)
        // Deleting every member drops the group.
        while let i = s.layers.firstIndex(where: { $0.groupID != nil }) { s.selectedLayer = i; s.deleteLayer() }
        XCTAssertTrue(s.groups.isEmpty)
    }

    func testMovingSeveralLayersTogether() {
        let s = studio()
        s.selectLayer(0); s.selectLayer(1, command: true)
        let start = s.beginMove()
        XCTAssertEqual(start.count, 2)
        s.move(start, by: CGSize(width: 7, height: -3))
        XCTAssertEqual(s.layers[0].transform.x, 7); XCTAssertEqual(s.layers[1].transform.y, -3); XCTAssertEqual(s.layers[2].transform.x, 0)
    }
}
