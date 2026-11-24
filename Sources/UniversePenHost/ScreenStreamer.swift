import Foundation
import ScreenCaptureKit
import AppKit
import CoreMedia
import TafelKit

struct StreamStats: Equatable {
    var fps: Double = 0
    var mbps: Double = 0
    var dropped: Int = 0
    /// Current encoder target (changes when adaptive quality is on).
    var targetMbps: Double = 0
}

/// ScreenCaptureKit -> VideoToolbox pipeline. One instance per running stream.
final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Every complete captured frame (capture queue), e.g. for the time-lapse recorder.
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    private var stream: SCStream?
    private var encoder: VideoEncoder?
    private let sampleQueue = DispatchQueue(label: "tafel.capture", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "tafel.capture.audio", qos: .userInteractive)
    private var capturesAudio = false
    /// Mac sound as 16-bit PCM (audio queue).
    var onAudio: ((AudioChunk) -> Void)?

    /// Encoded output (callback thread).
    var onEncoded: ((VideoFormat?, VideoFrame) -> Void)?
    /// Return false to skip encoding a captured frame (network backlog).
    var shouldEncode: (() -> Bool)?
    var onStats: ((StreamStats) -> Void)?
    var onStopped: ((Error?) -> Void)?

    private(set) var outputWidth = 0
    private(set) var outputHeight = 0
    private(set) var encoderDescription = ""

    private let statsLock = NSLock()
    private var frameCount = 0
    private var byteCount = 0
    private var dropped = 0
    private var statsTimer: DispatchSourceTimer?
    // Adaptive bitrate (sample queue only)
    private var maxMbps: Double = 30
    private var targetMbps: Double = 30
    private var adaptive = true
    private var lastDropped = 0
    private var calmSeconds = 0

    /// What is captured right now (for full-resolution screenshots).
    private var currentFilter: SCContentFilter?
    private var currentSourceRect: CGRect?
    /// 10-bit 4:2:0 straight from ScreenCaptureKit for Main10 (no conversion), else 8-bit full range
    /// (all 256 steps instead of 220).
    private var pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

    func start(filter: SCContentFilter, sourceRect: CGRect?, width: Int, height: Int, quality: StreamQuality) async throws {
        currentFilter = filter
        currentSourceRect = sourceRect
        let enc = try VideoEncoder(codec: quality.codec, width: width, height: height, quality: quality)
        enc.onOutput = { [weak self] format, frame in
            guard let self else { return }
            self.statsLock.withLock {
                self.frameCount += 1
                self.byteCount += frame.data.count
            }
            self.onEncoded?(format, frame)
        }
        encoder = enc
        maxMbps = quality.bitrateMbps
        targetMbps = quality.bitrateMbps
        adaptive = quality.adaptive
        outputWidth = width
        outputHeight = height
        pixelFormat = enc.tenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        encoderDescription = "\(quality.codec.rawValue.uppercased()) \(width)×\(height) · " + (enc.tenBit ? "10 bit · " : "8 bit · ")
            + (enc.isHardware ? "Hardware" : "Software") + (enc.usesLowLatencyRC ? " · Low-Latency-RC" : "")

        let cfg = SCStreamConfiguration()
        cfg.width = width
        cfg.height = height
        if let sourceRect { cfg.sourceRect = sourceRect }
        cfg.scalesToFit = true
        // Capture the full backing pixels of HiDPI displays ("automatic" may pick the point size
        // and upscale it, which looks blurry on the iPad).
        cfg.captureResolution = .best
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(quality.fps, 1)))
        cfg.pixelFormat = pixelFormat
        cfg.colorSpaceName = CGColorSpace.displayP3
        cfg.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        cfg.queueDepth = 3
        cfg.showsCursor = true
        capturesAudio = quality.audio
        applyAudio(cfg)

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if capturesAudio { try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue) }
        try await s.startCapture()
        stream = s
        startStatsTimer()
    }

    /// Live update of the captured area (region mode sliders) without restarting.
    func updateSourceRect(_ rect: CGRect, width: Int, height: Int, fps: Int) async {
        guard let stream else { return }
        currentSourceRect = rect
        let cfg = SCStreamConfiguration()
        cfg.width = width
        cfg.height = height
        cfg.sourceRect = rect
        cfg.scalesToFit = true
        // Capture the full backing pixels of HiDPI displays ("automatic" may pick the point size
        // and upscale it, which looks blurry on the iPad).
        cfg.captureResolution = .best
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
        cfg.pixelFormat = pixelFormat
        cfg.colorSpaceName = CGColorSpace.displayP3
        cfg.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        cfg.queueDepth = 3
        cfg.showsCursor = true
        applyAudio(cfg)
        try? await stream.updateConfiguration(cfg)
    }

    private func applyAudio(_ cfg: SCStreamConfiguration) {
        cfg.capturesAudio = capturesAudio
        cfg.sampleRate = 48_000
        cfg.channelCount = 2
        // Never feed our own process back (we play nothing, but stay safe).
        cfg.excludesCurrentProcessAudio = true
    }

    func requestKeyframe() { encoder?.requestKeyframe() }

    /// Still image of exactly what is streamed, at the full pixel resolution of the source
    /// (not the stream size). PNG, or JPEG if the PNG would be too big for the wire.
    func screenshot() async -> Data? {
        guard let filter = currentFilter else { return nil }
        let scale = CGFloat(filter.pointPixelScale)
        let rect = currentSourceRect ?? filter.contentRect
        let cfg = SCStreamConfiguration()
        if let r = currentSourceRect { cfg.sourceRect = r }
        cfg.width = max(Int((rect.width * scale).rounded()), 1)
        cfg.height = max(Int((rect.height * scale).rounded()), 1)
        cfg.captureResolution = .best
        cfg.showsCursor = false
        cfg.colorSpaceName = CGColorSpace.displayP3
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { return nil }
        let rep = NSBitmapImageRep(cgImage: img)
        if let png = rep.representation(using: .png, properties: [:]), png.count <= 24 * 1024 * 1024 { return png }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }

    func stop() async {
        statsTimer?.cancel()
        statsTimer = nil
        if let s = stream {
            stream = nil
            try? await s.stopCapture()
        }
        encoder?.invalidate()
        encoder = nil
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sbuf: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            if sbuf.isValid, let chunk = Self.pcm16(sbuf) { onAudio?(chunk) }
            return
        }
        guard type == .screen, sbuf.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sbuf, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw), status == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sbuf) else { return }
        onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sbuf))
        if let shouldEncode, !shouldEncode() {
            statsLock.withLock { dropped += 1 }
            return
        }
        encoder?.encode(pixelBuffer, pts: CMSampleBufferGetPresentationTimeStamp(sbuf),
                        captureTime: Date().timeIntervalSince1970)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStopped?(error)
    }

    /// Converts a ScreenCaptureKit audio buffer (normally Float32, non-interleaved) into
    /// interleaved signed 16-bit PCM.
    static func pcm16(_ sbuf: CMSampleBuffer) -> AudioChunk? {
        guard let desc = CMSampleBufferGetFormatDescription(sbuf),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return nil }
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = Int(asbd.mChannelsPerFrame)
        guard asbd.mFormatID == kAudioFormatLinearPCM, channels > 0, channels <= 8 else { return nil }
        let frames = CMSampleBufferGetNumSamples(sbuf)
        guard frames > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        var sizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sbuf, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil,
                                                                bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                                                                flags: 0, blockBufferOut: nil)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sbuf, bufferListSizeNeededOut: nil, bufferListOut: abl, bufferListSize: sizeNeeded,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer) == noErr else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(abl)

        // Output is always stereo (mono is duplicated, extra channels dropped).
        let outCh = 2
        var out = Data(count: frames * outCh * 2)
        out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
            let o = dst.bindMemory(to: Int16.self)
            func sample(_ frame: Int, _ ch: Int) -> Float {
                let c = min(ch, channels - 1)
                if nonInterleaved {
                    guard c < buffers.count, let p = buffers[c].mData else { return 0 }
                    return isFloat ? p.assumingMemoryBound(to: Float.self)[frame]
                                   : Float(p.assumingMemoryBound(to: Int16.self)[frame]) / 32768
                } else {
                    guard let p = buffers[0].mData else { return 0 }
                    let i = frame * channels + c
                    return isFloat ? p.assumingMemoryBound(to: Float.self)[i]
                                   : Float(p.assumingMemoryBound(to: Int16.self)[i]) / 32768
                }
            }
            for f in 0..<frames {
                for ch in 0..<outCh {
                    let v = max(-1, min(1, sample(f, ch)))
                    o[f * outCh + ch] = Int16(v * 32767).littleEndian
                }
            }
        }
        return AudioChunk(sampleRate: Int(asbd.mSampleRate), channels: outCh,
                          captureTime: Date().timeIntervalSince1970, samples: out)
    }

    /// Network can't keep up (frames dropped because the socket is backed up) → lower the bitrate
    /// quickly; after 4 calm seconds raise it slowly again, up to the chosen maximum.
    private func adapt(droppedNow: Int) {
        let delta = droppedNow - lastDropped
        lastDropped = droppedNow
        guard adaptive else { return }
        var next = targetMbps
        if delta >= 3 {
            next = max(4, targetMbps * 0.75)
            calmSeconds = 0
        } else if delta == 0 {
            calmSeconds += 1
            if calmSeconds >= 4, targetMbps < maxMbps { next = min(maxMbps, targetMbps * 1.15); calmSeconds = 0 }
        } else {
            calmSeconds = 0
        }
        if abs(next - targetMbps) > 0.01 {
            targetMbps = next
            encoder?.setBitrate(mbps: next)
        }
    }

    private func startStatsTimer() {
        let t = DispatchSource.makeTimerSource(queue: sampleQueue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            var s: StreamStats = self.statsLock.withLock {
                defer { self.frameCount = 0; self.byteCount = 0 }
                return StreamStats(fps: Double(self.frameCount), mbps: Double(self.byteCount) * 8 / 1_000_000, dropped: self.dropped)
            }
            self.adapt(droppedNow: s.dropped)
            s.targetMbps = self.targetMbps
            self.onStats?(s)
        }
        t.resume()
        statsTimer = t
    }
}
