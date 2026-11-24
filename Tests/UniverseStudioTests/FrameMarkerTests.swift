import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct FrameMarkerTests {
    private func studio(_ n: Int) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 4, height: 4)
        for _ in 1..<n { s.addFrame() }
        for i in 0..<n { s.selectFrame(i); s.layers[0].name = "F\(i)" }
        s.selectFrame(0)
        return s
    }

    @Test func sectionsRunToTheNextMarker() throws {
        let s = studio(6)
        s.setLabel(" walk ", for: 0); s.setLabel("jump", for: 4)
        #expect(s.markerSections.map(\.name) == ["walk", "jump"])
        #expect(s.markerSections.map(\.range) == [0...3, 4...5])
        s.playSection("jump")
        #expect(s.playRange == 4...5 && s.frameIndex == 4)
        let back = try JSONDecoder().decode(ArtDocument.self, from: JSONEncoder().encode(s.document()))
        #expect(back.frameLabels?[4] == "jump")
        s.setLabel("", for: 4); s.setLabel("", for: 0)
        #expect(s.frameLabels.isEmpty)
        s.undo(); #expect(s.label(0) == "walk")
    }

    @Test func markersMoveWithTheirFrames() {
        let s = studio(4)
        s.setLabel("a", for: 1); s.setHold(2, for: 1)
        s.selectFrame(0); s.addFrame()                   // insert at 1
        #expect(s.label(2) == "a" && s.hold(2) == 2)
        s.moveFrame(from: 2, to: 0)
        #expect(s.label(0) == "a" && s.hold(0) == 2)
        s.reverseFrames()
        #expect(s.label(4) == "a")
        s.selectFrame(4); s.removeFrame()
        #expect(s.frameLabels.isEmpty && s.frameHolds.isEmpty)
    }

    @Test func spriteSheetTags() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let json = url.deletingPathExtension().appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: json) }
        let f = [ArtLayer(name: "x")]
        try SpriteSheet.export(frames: [f, f, f], width: 4, height: 4, fps: 12, holds: [], loop: true, labels: ["", "run", ""], url: url)
        let m = try JSONDecoder().decode(SpriteSheet.Meta.self, from: Data(contentsOf: json))
        #expect(m.tags == [.init(name: "run", from: 1, to: 2)])
    }
}
