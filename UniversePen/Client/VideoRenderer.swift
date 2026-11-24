import Foundation
import AVFoundation
import CoreMedia
import TafelKit

/// Hardware decode + display via AVSampleBufferDisplayLayer, every frame marked
/// "display immediately" (no buffering, no timebase).
final class VideoRenderer: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()

    /// Stream pixel size changed (main thread).
    var onSize: ((CGSize) -> Void)?
    /// A frame with new content arrived (not just a periodic keyframe), any thread.
    var onContentChange: (() -> Void)?
    /// Ask the host for a new keyframe (any thread).
    var requestKeyframe: (() -> Void)?

    private let lock = NSLock()
    private var description: CMVideoFormatDescription?
    private var format: VideoFormat?
    private var waitingForKeyframe = true
    private var lastKeyframeRequest = Date.distantPast

    private var failObserver: NSObjectProtocol?

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColorBlack
        // A decode error does not always flip the renderer to .failed – the picture just stops
        // updating. Resync on the next keyframe instead.
        failObserver = NotificationCenter.default.addObserver(
            forName: AVSampleBufferVideoRenderer.didFailToDecodeNotification, object: layer.sampleBufferRenderer, queue: nil
        ) { [weak self] _ in self?.resync() }
    }

    deinit {
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
    }

    /// Drop everything queued and wait for a fresh keyframe.
    private func resync() {
        layer.sampleBufferRenderer.flush()
        lock.withLock { waitingForKeyframe = true }
        askForKeyframe()
    }

    /// `keepImage`: leave the last picture on screen (reconnecting after a short drop-out).
    func reset(keepImage: Bool = false) {
        lock.withLock {
            description = nil
            format = nil
            waitingForKeyframe = true
        }
        layer.sampleBufferRenderer.flush(removingDisplayedImage: !keepImage, completionHandler: nil)
    }

    func handle(format f: VideoFormat) {
        let changed: Bool = lock.withLock { format != f }
        guard changed else { return }
        guard let desc = Self.makeDescription(f) else { return }
        let sizeChanged: Bool = lock.withLock {
            let s = format?.width != f.width || format?.height != f.height
            format = f
            description = desc
            return s
        }
        if sizeChanged {
            let size = CGSize(width: f.width, height: f.height)
            DispatchQueue.main.async { self.onSize?(size) }
        }
    }

    func handle(frame: VideoFrame) {
        // The Mac only sends delta frames when the picture changes (keyframes also come periodically).
        if !frame.isKeyframe { onContentChange?() }
        let desc: CMVideoFormatDescription? = lock.withLock {
            if waitingForKeyframe {
                if frame.isKeyframe { waitingForKeyframe = false } else { return nil }
            }
            return description
        }
        guard let desc else { askForKeyframe(); return }
        let renderer = layer.sampleBufferRenderer
        // .failed, or decoding was interrupted (app in background, media services reset).
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            resync()
            if !frame.isKeyframe { return }
            lock.withLock { waitingForKeyframe = false }
        }
        guard let sample = Self.makeSample(frame.data, desc) else { return }
        renderer.enqueue(sample)
    }

    private func askForKeyframe() {
        let now = Date()
        let should: Bool = lock.withLock {
            guard now.timeIntervalSince(lastKeyframeRequest) > 0.5 else { return false }
            lastKeyframeRequest = now
            return true
        }
        if should { requestKeyframe?() }
    }

    static func makeDescription(_ f: VideoFormat) -> CMVideoFormatDescription? {
        let buffers: [UnsafeMutablePointer<UInt8>] = f.parameterSets.map { d in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: max(d.count, 1))
            d.copyBytes(to: p, count: d.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers = buffers.map { UnsafePointer($0) }
        let sizes = f.parameterSets.map(\.count)
        var desc: CMFormatDescription?
        let status: OSStatus
        switch f.codec {
        case .h264:
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: pointers.count, parameterSetPointers: pointers,
                parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &desc)
        case .hevc:
            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: pointers.count, parameterSetPointers: pointers,
                parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &desc)
        }
        guard status == noErr, let desc else { return nil }
        return f.displayP3 ? withP3(desc, sRGB: f.sRGBTransfer) : desc
    }

    /// Same description plus Display P3 colour tags, so the display layer colour-manages it.
    static func withP3(_ desc: CMVideoFormatDescription, sRGB: Bool) -> CMVideoFormatDescription {
        var ext = (CMFormatDescriptionGetExtensions(desc) as? [CFString: Any]) ?? [:]
        ext[kCMFormatDescriptionExtension_ColorPrimaries] = kCMFormatDescriptionColorPrimaries_P3_D65
        ext[kCMFormatDescriptionExtension_TransferFunction] = sRGB ? kCMFormatDescriptionTransferFunction_sRGB
                                                                   : kCMFormatDescriptionTransferFunction_ITU_R_709_2
        ext[kCMFormatDescriptionExtension_YCbCrMatrix] = kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
        let dims = CMVideoFormatDescriptionGetDimensions(desc)
        var out: CMVideoFormatDescription?
        let st = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: CMFormatDescriptionGetMediaSubType(desc),
                                                width: dims.width, height: dims.height, extensions: ext as CFDictionary,
                                                formatDescriptionOut: &out)
        return st == noErr ? (out ?? desc) : desc
    }

    static func makeSample(_ data: Data, _ desc: CMVideoFormatDescription) -> CMSampleBuffer? {
        let n = data.count
        guard n > 0 else { return nil }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: n,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: n, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return nil }
        let copied = data.withUnsafeBytes { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: n) == kCMBlockBufferNoErr
        }
        guard copied else { return nil }
        var sample: CMSampleBuffer?
        var size = n
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: desc,
                                        sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

private let UIColorBlack = CGColor(gray: 0, alpha: 1)
