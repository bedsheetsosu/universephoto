import XCTest
@testable import UniversePhoto

final class UniversePhotoTests: XCTestCase {
    @MainActor func testLayerUndoRedoAndDuplicate() {
        let studio = Studio()
        let start = studio.layers.count   // 1, or 2 with the white background (the default)
        studio.newLayer()
        XCTAssertEqual(studio.layers.count, start + 1)
        studio.undo()
        XCTAssertEqual(studio.layers.count, start)
        studio.redo()
        XCTAssertEqual(studio.layers.count, start + 1)
        studio.duplicateLayer()
        XCTAssertEqual(studio.layers.count, start + 2)
    }

    func testDocumentRoundTrip() throws {
        let document = ArtDocument(title: "Test", width: 1200, height: 800, layers: [ArtLayer(name: "Ink")])
        let data = try JSONEncoder.pretty.encode(document)
        let decoded = try JSONDecoder().decode(ArtDocument.self, from: data)
        XCTAssertEqual(decoded.title, "Test")
        XCTAssertEqual(decoded.layers.first?.name, "Ink")
    }
}
