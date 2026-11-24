import Foundation
import VideoToolbox
import CoreMedia
import TafelKit

enum EncoderError: Error, LocalizedError {
    case create(OSStatus)
    var errorDescription: String? {
        switch self {
        case .create(let s): return L("VideoToolbox-Encoder konnte nicht erstellt werden (%d).", Int(s))
        }
    }
}

/// Hardware H.264/HEVC encoder tuned for latency (no B-frames, real-time, low-latency rate control).
final class VideoEncoder {
    let codec: VideoCodec
    let width: Int
    let height: Int
    private(set) var usesLowLatencyRC = false
    private(set) var isHardware = false
    let tenBit: Bool

    /// Called on VideoToolbox's callback thread. `format` is non-nil whenever parameter sets changed.
    var onOutput: ((VideoFormat?, VideoFrame) -> Void)?

    private var session: VTCompressionSession?
    private let lock = NSLock()
    private var forceKeyframe = true
    private var lastFormat: VideoFormat?

    init(codec: VideoCodec, width: Int, height: Int, quality: StreamQuality) throws {
        self.codec = codec
        self.width = width
        self.height = height
        self.tenBit = quality.usesTenBit

        let codecType = codec == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC
        var s: VTCompressionSession?
        let lowLatency: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true,
        ]
        var status = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                                codecType: codecType, encoderSpecification: lowLatency as CFDictionary,
                                                imageBufferAttributes: nil, compressedDataAllocator: nil,
                                                outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        if status == noErr {
            usesLowLatencyRC = true
        } else {
            // Fallback: hardware preferred, normal rate control.
            let hw: [CFString: Any] = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true]
            status = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                                codecType: codecType, encoderSpecification: hw as CFDictionary,
                                                imageBufferAttributes: nil, compressedDataAllocator: nil,
                                                outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        }
        guard status == noErr, let session = s else { throw EncoderError.create(status) }
        self.session = session

        func set(_ key: CFString, _ value: CFTypeRef) { VTSessionSetProperty(session, key: key, value: value) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        // Emit every frame before accepting the next one: no look-ahead buffering in the encoder.
        set(kVTCompressionPropertyKey_MaxFrameDelayCount, NSNumber(value: 0))
        set(kVTCompressionPropertyKey_ProfileLevel,
            codec == .h264 ? kVTProfileLevel_H264_High_AutoLevel
                : (tenBit ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel))
        set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: Int(quality.bitrateMbps * 1_000_000)))
        set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: quality.fps))
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: 5))
        // Colour: the capture is Display P3 with the sRGB tone curve (what macOS draws in);
        // tag the stream exactly like that so the iPad shows the same colours and shadows.
        set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_P3_D65)
        set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_sRGB)
        set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        // Allow short bursts (e.g. scrolling) up to 2x average within one second.
        let limit = [NSNumber(value: Int(quality.bitrateMbps * 2_000_000 / 8)), NSNumber(value: 1)] as CFArray
        set(kVTCompressionPropertyKey_DataRateLimits, limit)

        // The low-latency session was created with RequireHardwareAcceleratedVideoEncoder, so it
        // is hardware by construction (that encoder does not answer the property query).
        var hwFlag: CFBoolean?
        if usesLowLatencyRC {
            isHardware = true
        } else if VTSessionCopyProperty(session, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                                 allocator: nil, valueOut: &hwFlag) == noErr {
            isHardware = (hwFlag == kCFBooleanTrue)
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit { invalidate() }

    func requestKeyframe() { lock.withLock { forceKeyframe = true } }

    /// Live bitrate change (adaptive quality), no restart needed.
    func setBitrate(mbps: Double) {
        guard let s = lock.withLock({ session }) else { return }
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: Int(mbps * 1_000_000)))
        let limit = [NSNumber(value: Int(mbps * 2_000_000 / 8)), NSNumber(value: 1)] as CFArray
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_DataRateLimits, value: limit)
    }

    func invalidate() {
        lock.withLock {
            if let s = session {
                VTCompressionSessionInvalidate(s)
                session = nil
            }
        }
    }

    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime, captureTime: Double) {
        let (session, key): (VTCompressionSession?, Bool) = lock.withLock {
            let k = forceKeyframe
            forceKeyframe = false
            return (self.session, k)
        }
        guard let session else { return }
        let props: CFDictionary? = key ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer, presentationTimeStamp: pts,
                                        duration: .invalid, frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, sbuf in
            guard let self else { return }
            guard status == noErr else {
                // A lost frame would leave the iPad decoding on top of a gap (frozen or smeared
                // picture until the next periodic keyframe). Restart the chain right away.
                NSLog("Tafel: encoder error %d, forcing keyframe", status)
                self.requestKeyframe()
                return
            }
            guard let sbuf else { return } // dropped by the encoder itself: references stay consistent
            self.handle(sbuf, captureTime: captureTime)
        }
    }

    private func handle(_ sbuf: CMSampleBuffer, captureTime: Double) {
        guard let block = CMSampleBufferGetDataBuffer(sbuf) else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sbuf, createIfNecessary: false) as? [[CFString: Any]]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKey = !notSync

        var format: VideoFormat?
        if isKey, let desc = CMSampleBufferGetFormatDescription(sbuf) {
            let sets = Self.parameterSets(desc, codec: codec)
            let f = VideoFormat(codec: codec, width: width, height: height, parameterSets: sets, displayP3: true, sRGBTransfer: true)
            // Sent with every keyframe so a client that missed one can always resync.
            format = f
            lock.withLock { lastFormat = f }
        }

        let length = CMBlockBufferGetDataLength(block)
        var data = Data(count: length)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base) == kCMBlockBufferNoErr
        }
        guard ok else { return }
        onOutput?(format, VideoFrame(isKeyframe: isKey, captureTime: captureTime, data: data))
    }

    static func parameterSets(_ desc: CMFormatDescription, codec: VideoCodec) -> [Data] {
        var count = 0
        var sets: [Data] = []
        switch codec {
        case .h264:
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(desc, parameterSetIndex: 0, parameterSetPointerOut: nil,
                                                               parameterSetSizeOut: nil, parameterSetCountOut: &count,
                                                               nalUnitHeaderLengthOut: nil)
            for i in 0..<count {
                var p: UnsafePointer<UInt8>?
                var size = 0
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(desc, parameterSetIndex: i, parameterSetPointerOut: &p,
                                                                      parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                      nalUnitHeaderLengthOut: nil) == noErr, let p {
                    sets.append(Data(bytes: p, count: size))
                }
            }
        case .hevc:
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(desc, parameterSetIndex: 0, parameterSetPointerOut: nil,
                                                               parameterSetSizeOut: nil, parameterSetCountOut: &count,
                                                               nalUnitHeaderLengthOut: nil)
            for i in 0..<count {
                var p: UnsafePointer<UInt8>?
                var size = 0
                if CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(desc, parameterSetIndex: i, parameterSetPointerOut: &p,
                                                                      parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                      nalUnitHeaderLengthOut: nil) == noErr, let p {
                    sets.append(Data(bytes: p, count: size))
                }
            }
        }
        return sets
    }
}
