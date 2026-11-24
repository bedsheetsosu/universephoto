import Testing
import Foundation
import AVFoundation
@testable import UniverseStudio

/// 16-bit mono PCM WAV with a sine tone in the second half (silence first).
func testWAV(seconds: Double = 1, rate: Int = 8000) -> Data {
    let n = Int(Double(rate) * seconds)
    var pcm = Data()
    for i in 0..<n {
        let v: Int16 = i < n / 2 ? 0 : Int16(sin(Double(i) * 2 * .pi * 440 / Double(rate)) * 20000)
        withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
    }
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVEfmt ".utf8))
    u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
    return d
}

@MainActor
struct AudioTrackTests {
    private func studio(frames n: Int = 4) -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 8, height: 8); for _ in 1..<n { s.addFrame() }; s.fps = 4
        return s
    }

    @Test func timingFollowsHolds() {
        let hold: (Int) -> Int = { $0 == 1 ? 3 : 1 }
        #expect(AudioTiming.time(ofFrame: 3, fps: 4, hold: hold) == 1.25)
        #expect(AudioTiming.soundTime(frame: 0, startFrame: 2, fps: 4, hold: hold) == -1)
        #expect(AudioTiming.peaks([0, 0.5, -1, 0.2], buckets: 2) == [0.5, 1])
    }

    @Test func importUndoAndSave() throws {
        let s = studio()
        #expect(!s.setAudio(data: Data("not audio".utf8), name: "x", fileExtension: "wav"))
        #expect(s.setAudio(data: testWAV(), name: "voice", fileExtension: "WAV"))
        #expect(s.audio?.fileExtension == "wav")
        s.setAudioStart(2)
        #expect(s.soundTime(frame: 3) == 0.25)
        let back = try JSONDecoder().decode(ArtDocument.self, from: JSONEncoder().encode(s.document()))
        #expect(back.audio == s.audio && back.audio?.data == s.audio?.data)
        s.undo(); #expect(s.audio?.startFrame == 0)
        s.undo(); #expect(s.audio == nil)
    }

    @Test func waveformShowsTheTone() throws {
        let cache = try AudioCache(track: AudioTrack(name: "t", data: testWAV(), fileExtension: "wav"))
        #expect(abs(cache.duration - 1) < 0.01)
        let quiet = cache.peaks(from: 0, to: 0.4, buckets: 4), loud = cache.peaks(from: 0.6, to: 1, buckets: 4)
        #expect(quiet.allSatisfy { $0 < 0.01 } && loud.allSatisfy { $0 > 0.4 })
    }

    @Test func mp4CarriesTheSound() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try AudioCache(track: AudioTrack(name: "t", data: testWAV(), fileExtension: "wav"))
        let out = dir.appendingPathComponent("a.mp4")
        let f = [ArtLayer(name: "x")]
        try await ImageFiles.exportVideo(frames: Array(repeating: f, count: 8), width: 16, height: 16, fps: 8, sound: (cache.url, 0.25, 1), url: out)
        let asset = AVURLAsset(url: out)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.1)
    }
}
