import XCTest
@testable import UniversePhoto

final class PersistenceTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("UniversePhoto-Persistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    private func ink(x: Double = 24, color: CodableColor = .black) -> InkStroke {
        InkStroke(points: [InkPoint(x: x, y: 16, pressure: 0.5), InkPoint(x: x + 8, y: 20, pressure: 1)], color: color, width: 12)
    }

    @MainActor func testActualSaveOpenPreservesMasksTransformsFramesAndDirtyState() throws {
        let dir = try temporaryDirectory(), url = dir.appendingPathComponent("Roundtrip.universephoto")
        let studio = Studio(recoveryRoot: dir.appendingPathComponent("Recovery"))
        studio.add(ink())
        studio.mutateLayer("Style") {
            $0.opacity = 0.65; $0.blend = .multiply
            $0.transform = LayerTransform(x: 12, y: -8, scale: 1.2, rotation: 17)
            $0.adjustment.brightness = 0.15
            $0.mask = [InkStroke(points: [InkPoint(x: 5, y: 5, pressure: 1)], color: .black, width: 9)]
        }
        studio.addFrame(); studio.add(ink(x: 64)); studio.fps = 18
        XCTAssertTrue(studio.dirty)
        try studio.save(to: url)
        XCTAssertFalse(studio.dirty)
        let expected = studio.document()
        let reopened = Studio(recoveryRoot: dir.appendingPathComponent("OtherRecovery"))
        try reopened.open(url)
        XCTAssertEqual(reopened.document(), expected)
        XCTAssertEqual(reopened.frameIndex, 1)
        XCTAssertFalse(reopened.dirty)
        reopened.add(ink(x: 85)); XCTAssertTrue(reopened.dirty)
        reopened.undo(); XCTAssertFalse(reopened.dirty)
        XCTAssertEqual(reopened.document(), expected)
    }

    @MainActor func testV1DocumentLoadsWithDefaultsAndRecoversMatchingFrame() throws {
        let dir = try temporaryDirectory(), url = dir.appendingPathComponent("Legacy.universephoto")
        func oldLayer(_ name: String) -> [String: Any] {
            ["id": UUID().uuidString, "name": name, "visible": true, "strokes": [
                ["id": UUID().uuidString, "points": [["x": 12.0, "y": 20.0, "pressure": 0.7]],
                 "color": ["red": 0.1, "green": 0.2, "blue": 0.3, "alpha": 1.0], "width": 8.0, "isEraser": false]
            ]]
        }
        let first = oldLayer("First"), last = oldLayer("Legacy ink")
        let v1: [String: Any] = ["version": 1, "title": "Legacy", "width": 1200, "height": 800,
                                 "layers": [last], "frames": [[first], [last]]]
        try JSONSerialization.data(withJSONObject: v1).write(to: url)
        let studio = Studio(recoveryRoot: dir.appendingPathComponent("Recovery"))
        try studio.open(url)
        XCTAssertEqual(studio.layers[0].name, "Legacy ink")
        XCTAssertEqual(studio.activeLayer?.opacity, 1)
        XCTAssertEqual(studio.activeLayer?.blend, .normal)
        XCTAssertEqual(studio.activeLayer?.transform, LayerTransform())
        XCTAssertEqual(studio.fps, 12)
        XCTAssertEqual(studio.frameIndex, 1)
        XCTAssertEqual(studio.layers[0].strokes[0].points[0].pressure, 0.7)
        XCTAssertNil(studio.layers[0].strokes[0].points[0].tiltX)
    }

    @MainActor func testFrameUndoRestoresActiveFrameWithoutOverwritingAnotherFrame() throws {
        let dir = try temporaryDirectory()
        let studio = Studio(recoveryRoot: dir)
        studio.add(ink()); studio.addFrame(); studio.add(ink(x: 50)); studio.addFrame(); studio.add(ink(x: 90))
        studio.selectFrame(0)
        let before = studio.document()
        studio.addFrame()
        XCTAssertEqual(studio.frameIndex, 1)
        studio.undo()
        XCTAssertEqual(studio.frameIndex, 0)
        XCTAssertEqual(studio.document(), before)
        studio.redo()
        XCTAssertEqual(studio.frameIndex, 1)
        XCTAssertEqual(studio.frames.count, 4)
    }

    @MainActor func testLayerOpacityAndTransformUndoRedo() throws {
        let studio = Studio(recoveryRoot: try temporaryDirectory())
        studio.mutateLayer("Layer transform") { $0.opacity = 0.4; $0.transform.x = 19; $0.transform.rotation = 75 }
        let changed = studio.activeLayer
        studio.undo()
        XCTAssertEqual(studio.activeLayer?.opacity, 1)
        XCTAssertEqual(studio.activeLayer?.transform, LayerTransform())
        studio.redo(); XCTAssertEqual(studio.activeLayer, changed)
    }

    @MainActor func testTabsPreserveIndependentArtworkHistoryAndActiveFrame() throws {
        let studio = Studio(recoveryRoot: try temporaryDirectory())
        studio.add(ink()); studio.addFrame(); studio.add(ink(x: 72))
        let firstID = studio.tabID, firstDocument = studio.document(), firstHistory = studio.undoStack.count
        studio.newDocument(width: 320, height: 240); studio.add(ink(x: 95, color: .white))
        let secondID = studio.tabID, secondDocument = studio.document()
        studio.switchTab(firstID)
        XCTAssertEqual(studio.document(), firstDocument)
        XCTAssertEqual(studio.frameIndex, 1)
        XCTAssertEqual(studio.undoStack.count, firstHistory)
        studio.undo(); XCTAssertEqual(studio.layers[0].strokes.count, 1)
        studio.switchTab(secondID)
        XCTAssertEqual(studio.document(), secondDocument)
        XCTAssertEqual(studio.width, 320)
        studio.undo(); XCTAssertTrue(studio.layers[0].strokes.isEmpty)
        XCTAssertFalse(studio.dirty)
    }

    @MainActor func testInvalidOpenDoesNotReplaceCurrentArtworkAndValidatesEveryFrame() throws {
        let dir = try temporaryDirectory(), url = dir.appendingPathComponent("Invalid.universephoto")
        let studio = Studio(recoveryRoot: dir); studio.add(ink())
        let before = studio.document(), count = studio.tabs.count
        var bad = before; bad.version = 99
        try JSONEncoder().encode(bad).write(to: url)
        XCTAssertThrowsError(try studio.open(url))
        XCTAssertEqual(studio.document(), before); XCTAssertEqual(studio.tabs.count, count)
        bad = before; var badLayer = ArtLayer(name: "Invalid frame"); badLayer.transform.scale = 0; bad.frames = [[badLayer]]
        XCTAssertThrowsError(try Studio.validate(bad))
        bad = before; bad.fps = 0
        XCTAssertThrowsError(try Studio.validate(bad))
        bad = before; bad.width = 8192; bad.height = 8192
        XCTAssertThrowsError(try Studio.validate(bad))
    }
}
