import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SharedLayerTests {
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 10, height: 10); s.newLayer()     // 0 background, 1 drawing
        s.addFrame(); s.addFrame(); s.selectFrame(0)
        s.selectedLayer = 0
        return s
    }

    @Test func editOnceChangesEveryFrame() throws {
        let s = studio()
        s.toggleAllFrames()
        s.layers[0].name = "Sky"
        s.selectFrame(2)
        #expect(s.layers[0].name == "Sky" && s.layers[0].allFrames == true)
        s.layers[0].opacity = 0.5
        let d = s.document()
        #expect(d.frames.allSatisfy { $0[0].opacity == 0.5 && $0[0].name == "Sky" })
        let back = try JSONDecoder().decode(ArtDocument.self, from: JSONEncoder().encode(d))
        #expect(back.frames[1][0].allFrames == true)
    }

    @Test func blankFrameKeepsSharedLayersAndOffUnshares() {
        let s = studio()
        var dot = InkStroke(points: [InkPoint(x: 1, y: 1, pressure: 1)], color: .black, width: 2)
        dot.kind = nil
        s.layers[0].strokes = [dot]; s.layers[1].strokes = [dot]
        s.toggleAllFrames()
        s.blankFrame()
        #expect(s.layers[0].strokes.count == 1 && s.layers[1].strokes.isEmpty)
        s.toggleAllFrames()                                   // off
        s.layers[0].name = "only here"
        s.selectFrame(0)
        #expect(s.layers[0].name != "only here" && s.layers[0].allFrames == nil)
    }

    @Test func missingLayerIsInserted() {
        var shared = ArtLayer(name: "bg"); shared.allFrames = true
        let out = Studio.syncedFrames([[ArtLayer(name: "a")]], from: [shared, ArtLayer(name: "b")])
        #expect(out[0].map(\.name) == ["bg", "a"])
    }
}
