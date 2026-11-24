import Testing
import Foundation
import CoreGraphics
@testable import UniverseStudio

@MainActor
struct VideoImportTests {
    @Test func planKeepsTimingAndFillsTheClip() {
        let p = VideoImport.plan(holds: [1, 2], fps: 10, duration: 0.6)
        #expect(p.times.map { ($0 * 10).rounded() } == [0, 1, 3, 4, 5] && p.added == 3)
        #expect(VideoImport.plan(holds: [1], fps: 10, duration: 100, cap: 5).times.count == 5)
    }

    @Test func videoBecomesALockedBottomLayer() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var red = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 1); red.kind = "fill"
        var a = ArtLayer(name: "a"); a.strokes = [red]
        let url = dir.appendingPathComponent("clip.mp4")
        try await ImageFiles.exportVideo(frames: Array(repeating: [a], count: 6), width: 16, height: 16, fps: 6, url: url)

        let s = Studio(recoveryRoot: dir.appendingPathComponent("rec"))
        s.newDocument(width: 16, height: 16); s.newLayer(); s.fps = 6
        let plan = VideoImport.plan(holds: [1], fps: 6, duration: 1)
        let images = try await VideoImport.images(url: url, times: plan.times, maxSide: 16)
        #expect(images.count == 6 && plan.added == 5)
        let drawing = s.selectedLayer
        #expect(s.importVideoFrames(images, added: plan.added, name: "Video"))
        let d = s.document()
        #expect(d.frames.count == 6 && d.frames.allSatisfy { $0[0].locked && $0[0].opacity == 0.5 && $0[0].imageData != nil })
        #expect(s.selectedLayer == drawing + 1 && Set(d.frames.map { $0[0].id }).count == 1)
        s.undo(); #expect(s.document().frames.count <= 1 && s.layers.count == 2)
    }
}

struct VideoSoundTests {
    @Test func soundComesAlongWhenThereIsOne() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try AudioCache(track: AudioTrack(name: "t", data: testWAV(), fileExtension: "wav"))
        let f = [ArtLayer(name: "x")]
        let withSound = dir.appendingPathComponent("a.mp4"), silent = dir.appendingPathComponent("b.mp4")
        try await ImageFiles.exportVideo(frames: Array(repeating: f, count: 8), width: 16, height: 16, fps: 8, sound: (cache.url, 0, 1), url: withSound)
        try await ImageFiles.exportVideo(frames: Array(repeating: f, count: 8), width: 16, height: 16, fps: 8, url: silent)
        let data = try await VideoImport.sound(url: withSound)
        #expect((data?.count ?? 0) > 100)
        #expect(try AudioCache(track: AudioTrack(name: "v", data: data!, fileExtension: "m4a")).duration > 0.5)
        #expect(try await VideoImport.sound(url: silent) == nil)
    }
}
