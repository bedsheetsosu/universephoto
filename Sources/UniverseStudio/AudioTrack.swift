import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// Animate: one sound track, embedded in the project file. It starts at a chosen frame, plays in
/// sync with playback, gives a short snippet when stepping through frames (lip sync) and goes into
/// MP4 exports. Its waveform is drawn under the frames in the timeline.
struct AudioTrack: Codable, Equatable, Sendable {
    /// Identifies the sound data (new for every import), so caches never compare megabytes.
    var id = UUID()
    var name: String
    var data: Data
    var fileExtension: String
    /// Frame at which the sound starts (0 = with the first frame).
    var startFrame = 0
    var volume = 1.0

    static let maxBytes = 40 * 1024 * 1024

    /// The data never changes for one id, so equality skips comparing megabytes of sound.
    static func == (a: AudioTrack, b: AudioTrack) -> Bool {
        a.id == b.id && a.name == b.name && a.startFrame == b.startFrame && a.volume == b.volume && a.fileExtension == b.fileExtension
    }
}

extension ImageFiles {
    /// Lays `audio` under the finished video at `soundStart` seconds (negative = the sound's
    /// beginning is cut off) and writes the result to `output` as MP4 with AAC sound.
    static func addSound(video: URL, audio: URL, soundStart: Double, volume: Double, output: URL) async throws {
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
        let comp = AVMutableComposition()
        guard let vSrc = try await videoAsset.loadTracks(withMediaType: .video).first,
              let vDst = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw FileError.encoder("MP4 sound") }
        let vDuration = try await videoAsset.load(.duration)
        try vDst.insertTimeRange(CMTimeRange(start: .zero, duration: vDuration), of: vSrc, at: .zero)
        var mix: AVMutableAudioMix?
        if let aSrc = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let aDst = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let aDuration = try await audioAsset.load(.duration).seconds
            let from = max(0, -soundStart), at = max(0, soundStart)
            let length = min(aDuration - from, vDuration.seconds - at)
            if length > 0.01 {
                try aDst.insertTimeRange(CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 48000), duration: CMTime(seconds: length, preferredTimescale: 48000)),
                                         of: aSrc, at: CMTime(seconds: at, preferredTimescale: 48000))
                let params = AVMutableAudioMixInputParameters(track: aDst); params.setVolume(Float(volume), at: .zero)
                mix = AVMutableAudioMix(); mix?.inputParameters = [params]
            }
        }
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else { throw FileError.encoder("MP4 sound") }
        session.outputURL = output; session.outputFileType = .mp4; session.audioMix = mix
        try? FileManager.default.removeItem(at: output)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in session.exportAsynchronously { c.resume() } }
        guard session.status == .completed else { throw session.error ?? FileError.encoder("MP4 sound") }
    }
}

enum AudioTiming {
    /// Seconds from frame 0 to the start of frame `i`, holds included.
    static func time(ofFrame i: Int, fps: Double, hold: (Int) -> Int) -> Double {
        Double((0..<max(0, i)).reduce(0) { $0 + max(1, hold($1)) }) / max(1, fps)
    }

    /// Position in the sound for frame `i` (negative = before the sound starts).
    static func soundTime(frame i: Int, startFrame: Int, fps: Double, hold: (Int) -> Int) -> Double {
        time(ofFrame: i, fps: fps, hold: hold) - time(ofFrame: startFrame, fps: fps, hold: hold)
    }

    /// Peak per bucket (0…1) for `buckets` equal slices of `samples`.
    static func peaks(_ samples: [Float], buckets: Int) -> [Float] {
        guard buckets > 0, !samples.isEmpty else { return [] }
        let per = max(1, samples.count / buckets)
        return (0..<buckets).map { b in
            let lo = b * per, hi = min(samples.count, lo + per)
            guard lo < hi else { return 0 }
            var m: Float = 0
            for i in lo..<hi { m = max(m, abs(samples[i])) }
            return min(1, m)
        }
    }
}

/// Decoded sound: a temporary file for AVFoundation, mono samples for the waveform.
final class AudioCache {
    let url: URL
    let samples: [Float]
    let sampleRate: Double
    var duration: Double { Double(samples.count) / max(1, sampleRate) }

    init(track: AudioTrack) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("UniverseStudioAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("\(track.id.uuidString).\(track.fileExtension.isEmpty ? "m4a" : track.fileExtension)")
        if !FileManager.default.fileExists(atPath: url.path) { try track.data.write(to: url, options: .atomic) }
        let file = try AVAudioFile(forReading: url)
        sampleRate = file.processingFormat.sampleRate
        // Waveform from a mono reading, at most ~3 minutes worth to keep it quick.
        let frames = AVAudioFrameCount(min(file.length, AVAudioFramePosition(sampleRate * 180)))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { samples = []; return }
        try file.read(into: buffer, frameCount: frames)
        if let ch = buffer.floatChannelData {
            let n = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
            samples = (0..<n).map { i in (0..<channels).reduce(Float(0)) { $0 + ch[$1][i] } / Float(max(1, channels)) }
        } else { samples = [] }
    }

    /// Peaks for the stretch of sound from `t0` to `t1` seconds.
    func peaks(from t0: Double, to t1: Double, buckets: Int) -> [Float] {
        let lo = max(0, Int(t0 * sampleRate)), hi = min(samples.count, Int(t1 * sampleRate))
        guard hi > lo else { return Array(repeating: 0, count: buckets) }
        return AudioTiming.peaks(Array(samples[lo..<hi]), buckets: buckets)
    }
}

extension Studio {
    static let audioTypes: [UTType] = [.mp3, .mpeg4Audio, .wav, .aiff, .audio]

    /// Embeds the sound. Returns false when it is too big or not readable as audio.
    @discardableResult func setAudio(data: Data, name: String, fileExtension: String) -> Bool {
        guard data.count <= AudioTrack.maxBytes else { return false }
        let track = AudioTrack(name: name, data: data, fileExtension: fileExtension.lowercased())
        guard (try? AudioCache(track: track)) != nil else { return false }
        checkpoint("Add sound"); audio = track; changed()
        return true
    }

    func removeAudio() { guard audio != nil else { return }; stopPlayback(); checkpoint("Remove sound"); audio = nil; changed() }

    func setAudioStart(_ frame: Int) {
        guard var a = audio, frame != a.startFrame else { return }
        checkpoint("Sound start"); a.startFrame = max(0, min(frame, max(0, frames.count - 1))); audio = a; changed()
    }

    func setAudioVolume(_ v: Double) { guard var a = audio else { return }; a.volume = max(0, min(1, v)); audio = a; audioEngine.player?.volume = Float(a.volume) }

    /// Selects a frame from the timeline or the menu; plays the frame's bit of sound (lip sync).
    func stepToFrame(_ i: Int) {
        stopPlayback(); selectFrame(i)
        guard audio != nil, UserDefaults.standard.object(forKey: "audioScrub") as? Bool ?? true else { return }
        audioEngine.snippet(track: audio, at: soundTime(frame: frameIndex), length: Double(hold(frameIndex)) / max(1, fps))
    }

    func soundTime(frame i: Int) -> Double { AudioTiming.soundTime(frame: i, startFrame: audio?.startFrame ?? 0, fps: fps, hold: { hold($0) }) }

    func importAudioPanel() {
        let p = NSOpenPanel(); p.title = L("Import sound"); p.prompt = L("Import"); p.allowedContentTypes = Self.audioTypes
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let data = try Data(contentsOf: url)
            if !setAudio(data: data, name: url.deletingPathExtension().lastPathComponent, fileExtension: url.pathExtension) {
                report(StudioError.message(data.count > AudioTrack.maxBytes ? "The sound file is larger than 40 MB." : "This file could not be read as sound."))
            }
        } catch { report(error) }
    }
}

/// Plays the embedded sound in step with the timeline.
@MainActor final class AudioEngine {
    private(set) var player: AVAudioPlayer?
    private var cache: AudioCache?
    private var loadedID: UUID?
    private var stopWork: DispatchWorkItem?

    func cache(for track: AudioTrack?) -> AudioCache? {
        guard let track else { player = nil; cache = nil; loadedID = nil; return nil }
        if track.id != loadedID || cache == nil {
            cache = try? AudioCache(track: track); loadedID = track.id
            player = cache.flatMap { try? AVAudioPlayer(contentsOf: $0.url) }; player?.prepareToPlay()
        }
        player?.volume = Float(track.volume)
        return cache
    }

    /// Plays from `time` seconds of the sound (waits silently while it is negative).
    func play(track: AudioTrack?, at time: Double) {
        guard cache(for: track) != nil, let player else { return }
        stopWork?.cancel(); player.stop()
        if time < 0 { player.currentTime = 0; player.play(atTime: player.deviceCurrentTime - time) }
        else if time < player.duration { player.currentTime = time; player.play() }
    }

    /// A short snippet for stepping through frames.
    func snippet(track: AudioTrack?, at time: Double, length: Double) {
        guard time >= 0 else { return }
        play(track: track, at: time)
        let work = DispatchWorkItem { [weak self] in self?.player?.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.12, length), execute: work)
    }

    /// Re-aligns a running sound when playback jumped (loop, range, ping-pong).
    func keepInSync(track: AudioTrack?, at time: Double, forward: Bool) {
        guard let player, track != nil else { return }
        if !forward { player.stop(); return }
        if time < 0 { if player.isPlaying { player.stop() }; return }
        if !player.isPlaying || abs(player.currentTime - time) > 0.12 { play(track: track, at: time) }
    }

    func stop() { stopWork?.cancel(); player?.stop() }
}
