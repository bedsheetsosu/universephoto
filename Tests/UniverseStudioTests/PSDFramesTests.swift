import Testing
import Foundation
@testable import UniverseStudio

struct PSDFramesTests {
    @Test func oneLayerPerFrameRoundTrip() throws {
        var dot = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1); dot.kind = "fill"
        var a = ArtLayer(name: "a"); a.strokes = [dot]
        let layers = try PSD.frameLayers(frames: [[a], [ArtLayer(name: "b")], [a]], holds: [1, 3], labels: ["", "", "run"], width: 8, height: 8)
        #expect(layers.map(\.name) == ["Frame 01", "Frame 02 ×3", "Frame 03 · run"])
        #expect(layers.map(\.visible) == [true, false, false])
        let data = try PSD.writeFrames(frames: [[a], [a]], holds: [], labels: [], width: 8, height: 8, scale: 0.5)
        let back = try PSD.read(data, title: "x")
        #expect(back.width == 4, "w \(back.width)"); #expect(back.layers.count == 2, "n \(back.layers.count)"); #expect(back.layers.last?.name == "Frame 02", "names \(back.layers.map(\.name))")
    }
}
