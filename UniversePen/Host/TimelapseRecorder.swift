import Foundation
import AVFoundation
import CoreVideo

/// Records the captured picture as a time-lapse movie (public AVFoundation API).
///
/// It takes one captured frame every `speed / 30` seconds and writes them at 30 fps, so the
/// movie plays `speed` times faster. ScreenCaptureKit only delivers frames when something on
/// screen changes, so idle time is skipped automatically. Files go to ~/Movies/UniversePen.
final class TimelapseRecorder: @unchecked Sendable {
    static let outputFPS: Int32 = 30

    let speed: Int
    let url: URL
    private let queue = DispatchQueue(label: "universepen.timelapse", qos: .utility)
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var size: (Int, Int)?
    private var lastKept: Double?
    private var frames: Int64 = 0
    private var finished = false

    /// Called (main queue) with the frame count, and when the recording stops by itself.
    var onProgress: ((Int64) -> Void)?
    var onStoppedBySize: ((URL?) -> Void)?

    init(speed: Int) throws {
        self.speed = max(speed, 1)
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("UniversePen")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        url = dir.appendingPathComponent("UniversePen Timelapse \(f.string(from: Date())).mp4")
    }

    /// From the capture queue. Keeps a frame only every `speed / 30` seconds of real time.
    func append(_ pb: CVPixelBuffer, at seconds: Double) {
        queue.async { [self] in
            guard !finished else { return }
            if let last = lastKept, seconds - last < Double(speed) / Double(Self.outputFPS) { return }
            let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
            if writer == nil {
                guard setUp(width: w, height: h) else { finished = true; return }
            } else if let s = size, s != (w, h) {
                // The picture size changed (other source / resolution): close this file cleanly.
                finish { url in DispatchQueue.main.async { self.onStoppedBySize?(url) } }
                return
            }
            guard let input, input.isReadyForMoreMediaData, let adaptor else { return }
            if adaptor.append(pb, withPresentationTime: CMTime(value: frames, timescale: Self.outputFPS)) {
                frames += 1
                lastKept = seconds
                let n = frames
                DispatchQueue.main.async { self.onProgress?(n) }
            }
        }
    }

    private func setUp(width w: Int, height h: Int) -> Bool {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(w * h * 4, 4_000_000)],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        size = (w, h)
        return true
    }

    /// Blocking stop for app quit, so the movie is not left unreadable (waits at most 3 s).
    func stopAndWait() {
        let done = DispatchSemaphore(value: 0)
        queue.async { [self] in finish { _ in done.signal() } }
        _ = done.wait(timeout: .now() + 3)
    }

    /// Finishes the file. `url` is nil if nothing was recorded (the empty file is removed).
    func stop(_ done: @escaping (URL?) -> Void) {
        queue.async { [self] in finish { url in DispatchQueue.main.async { done(url) } } }
    }

    private func finish(_ done: @escaping (URL?) -> Void) {
        guard !finished else { done(nil); return }
        finished = true
        guard let writer, let input, frames > 0 else {
            writer?.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            done(nil)
            return
        }
        input.markAsFinished()
        let url = self.url
        writer.finishWriting { done(writer.status == .completed ? url : nil) }
    }
}

/// Thread-safe slot the capture queue reads the current recorder from.
final class TimelapseSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _recorder: TimelapseRecorder?
    var recorder: TimelapseRecorder? {
        get { lock.withLock { _recorder } }
        set { lock.withLock { _recorder = newValue } }
    }
    func append(_ pb: CVPixelBuffer, _ pts: CMTime) {
        guard let r = recorder else { return }
        r.append(pb, at: pts.isValid ? pts.seconds : ProcessInfo.processInfo.systemUptime)
    }
}
