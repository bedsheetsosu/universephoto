import Foundation
import AVFoundation
import TafelKit

/// Plays the Mac's sound with a small, bounded buffer.
///
/// Latency policy: chunks are scheduled back to back on an `AVAudioPlayerNode`. If more than
/// `maxLatency` is already queued (network burst), new chunks are dropped instead of letting the
/// delay grow. After an underrun a short silence pad absorbs network jitter.
final class AudioPlayer: @unchecked Sendable {
    var maxLatency: Double = 0.10
    var jitterPad: Double = 0.02

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let lock = NSLock()
    private let counterLock = NSLock()
    private var format: AVAudioFormat?
    private var running = false
    private var needsRestart = false
    private var queuedFrames = 0
    private var observer: NSObjectProtocol?

    init() {
        engine.attach(node)
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            // Route change (headphones, AirPlay …): the engine stopped; restart with the next chunk.
            self.lock.withLock { self.needsRestart = true }
            self.counterLock.withLock { self.queuedFrames = 0 }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Own queue: starting the engine or activating the audio session can take a moment and must
    /// never hold up the network queue that also carries the video.
    private let queue = DispatchQueue(label: "tafel.audio", qos: .userInitiated)

    func play(_ chunk: AudioChunk) {
        queue.async { self.playNow(chunk) }
    }

    private func playNow(_ chunk: AudioChunk) {
        let frames = chunk.frameCount
        guard frames > 0 else { return }
        lock.withLock {
            if format?.sampleRate != Double(chunk.sampleRate) || format?.channelCount != AVAudioChannelCount(chunk.channels) {
                setup(sampleRate: Double(chunk.sampleRate), channels: chunk.channels)
            } else if needsRestart {
                restart()
            }
            guard running, let format else { return }

            let queued = counterLock.withLock { queuedFrames }
            if Double(queued) > maxLatency * format.sampleRate { return } // drop: keep latency bounded
            if queued == 0, let pad = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(jitterPad * format.sampleRate)) {
                pad.frameLength = pad.frameCapacity // zero-filled
                schedule(pad)
            }
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
                  let out = buf.floatChannelData else { return }
            buf.frameLength = AVAudioFrameCount(frames)
            let ch = chunk.channels
            chunk.samples.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let s = raw.bindMemory(to: Int16.self)
                for f in 0..<frames {
                    for c in 0..<ch {
                        out[c][f] = Float(Int16(littleEndian: s[f * ch + c])) / 32768
                    }
                }
            }
            schedule(buf)
        }
    }

    private func schedule(_ buf: AVAudioPCMBuffer) {
        let n = Int(buf.frameLength)
        counterLock.withLock { queuedFrames += n }
        node.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.counterLock.withLock { self.queuedFrames = max(0, self.queuedFrames - n) }
        }
    }

    /// Called with `lock` held.
    private func setup(sampleRate: Double, channels: Int) {
        stopLocked()
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)) else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)
        #endif
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        format = fmt
        restart()
    }

    /// Called with `lock` held.
    private func restart() {
        needsRestart = false
        counterLock.withLock { queuedFrames = 0 }
        do {
            engine.prepare()
            try engine.start()
            node.play()
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        queue.async { self.lock.withLock { self.stopLocked() } }
    }

    private func stopLocked() {
        guard running || format != nil else { return }
        node.stop()
        engine.stop()
        running = false
        format = nil
        counterLock.withLock { queuedFrames = 0 }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
