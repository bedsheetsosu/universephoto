import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct RemoveEmptyFramesTests {
    private let dot = InkStroke(points: [InkPoint(x: 2, y: 2, pressure: 1)], color: .black, width: 2)

    @Test func dropsOnlyFramesWithoutDrawing() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10)                 // one "Sketch" layer, empty
        s.layers[0].strokes = [dot]; s.changed()             // frame 0: drawn
        s.addFrame(); s.layers[0].strokes = []; s.changed()  // frame 1: empty
        s.addFrame(); s.layers[0].strokes = [dot]; s.changed() // frame 2: drawn
        #expect(s.removeEmptyFrames() == 1)
        #expect(s.frames.count == 2)
        #expect(s.document().frames.allSatisfy { !$0[0].strokes.isEmpty })
    }

    @Test func sharedLayersDontCountAsContent() {
        var bg = ArtLayer(name: "bg"); bg.strokes = [dot]; bg.allFrames = true
        #expect(Studio.frameIsEmpty([bg, ArtLayer(name: "sketch")]))
        #expect(!Studio.frameIsEmpty([bg, { var l = ArtLayer(name: "s"); l.strokes = [dot]; return l }()]))
    }

    @Test func alwaysKeepsOneFrame() {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10)
        s.addFrame(); s.addFrame()                           // three empty frames
        #expect(s.removeEmptyFrames() == 2)
        #expect(s.frames.count == 1)
    }
}
