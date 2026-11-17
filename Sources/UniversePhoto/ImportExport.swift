import AppKit
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation
import CoreVideo

/// Flattened image interchange. The native document remains the lossless layered format.
/// Inputs are decoded with ImageIO and EXIF orientation applied, then normalized to sRGB.
enum ImageFiles {
    enum FileError: LocalizedError {
        case unsupported(String), invalidImage, dimensions, outputExists, encoder(String), noFrames
        var errorDescription: String? {
            switch self {
            case .unsupported(let detail): return LocalizedText.string("This format is not supported:") + " " + LocalizedText.string(detail)
            case .invalidImage: return LocalizedText.string("The image file is invalid or could not be decoded.")
            case .dimensions: return LocalizedText.string("Images support 1–8192 pixels per side and up to 64 million pixels. MP4 requires even dimensions.")
            case .outputExists: return LocalizedText.string("The destination file already exists. Choose a different name.")
            case .encoder(let detail): return LocalizedText.string("Export failed:") + " " + LocalizedText.string(detail)
            case .noFrames: return LocalizedText.string("At least one frame is required for export.")
            }
        }
    }

    static let supportedImports: [UTType] = [.png, .jpeg, .tiff]
    static let supportedExports: [UTType] = [.png, .jpeg, .tiff]

    static func validate(width: Int, height: Int) throws {
        guard (1...8192).contains(width), (1...8192).contains(height), width * height <= 64_000_000 else { throw FileError.dimensions }
    }

    static func importImage(url: URL) throws -> (width: Int, height: Int, layer: ArtLayer) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let rawType = CGImageSourceGetType(source), let type = UTType(rawType as String),
              supportedImports.contains(where: { type.conforms(to: $0) }) else { throw FileError.unsupported(url.pathExtension) }
        guard CGImageSourceGetCount(source) == 1 else { throw FileError.unsupported("Multipage or animated images must first be separated into individual images.") }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw FileError.invalidImage }
        try validate(width: width, height: height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let context = bitmap(width: decoded.width, height: decoded.height) else { throw FileError.invalidImage }
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        guard let normalized = context.makeImage() else { throw FileError.invalidImage }
        var layer = ArtLayer(name: url.deletingPathExtension().lastPathComponent)
        layer.imageData = try encoded(image: normalized, type: .png)
        return (normalized.width, normalized.height, layer)
    }

    /// JPEG is explicitly flattened over white. PNG and TIFF retain transparency.
    static func export(image: CGImage, url: URL, type: UTType) throws {
        guard supportedExports.contains(type) else { throw FileError.unsupported(type.identifier) }
        try validate(width: image.width, height: image.height)
        let data = try encoded(image: image, type: type)
        // Atomic replacement is intentional: native save panels ask before replacing a file.
        try data.write(to: url, options: .atomic)
    }

    static func exportSequence(frames: [[ArtLayer]], width: Int, height: Int, directory: URL) throws {
        guard !frames.isEmpty else { throw FileError.noFrames }
        try validate(width: width, height: height)
        let files = frames.indices.map { directory.appendingPathComponent(String(format: "frame-%04d.png", $0 + 1)) }
        guard !files.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else { throw FileError.outputExists }
        let staging = directory.appendingPathComponent(".universephoto-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        for (index, frame) in frames.enumerated() {
            guard let image = Renderer.render(layers: frame, width: width, height: height) else { throw FileError.encoder("Frame \(index + 1)") }
            try encoded(image: image, type: .png).write(to: staging.appendingPathComponent(files[index].lastPathComponent), options: .atomic)
        }
        for file in files { try FileManager.default.moveItem(at: staging.appendingPathComponent(file.lastPathComponent), to: file) }
    }

    /// GIF retains binary transparency. Its palette and centisecond timing are inherently lossy.
    static func exportGIF(frames: [[ArtLayer]], width: Int, height: Int, fps: Double, url: URL) throws {
        try validateAnimation(frames: frames, width: width, height: height, fps: fps)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else { throw FileError.encoder("GIF") }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = max(0.01, (100 / fps).rounded() / 100)
        for frame in frames {
            guard let image = Renderer.render(layers: frame, width: width, height: height) else { throw FileError.encoder("GIF frame") }
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw FileError.encoder("Could not finish the GIF export") }
        try (data as Data).write(to: url, options: .atomic)
    }

    /// H.264 MP4, opaque over white, no audio. Each input frame occupies exactly 1/fps seconds.
    /// Call from a background task; rendering is deliberately synchronous and deterministic.
    static func exportVideo(frames: [[ArtLayer]], width: Int, height: Int, fps: Double, url: URL) async throws {
        try validateAnimation(frames: frames, width: width, height: height, fps: fps)
        guard width.isMultiple(of: 2), height.isMultiple(of: 2) else { throw FileError.dimensions }
        let staging = url.deletingLastPathComponent().appendingPathComponent(".universephoto-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: staging) }
        let writer = try AVAssetWriter(outputURL: staging, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else { throw FileError.encoder("H.264 is not available on this system") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FileError.encoder("MP4 start") }
        writer.startSession(atSourceTime: .zero)
        do {
            for (index, frame) in frames.enumerated() {
                let deadline = Date().addingTimeInterval(30)
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    guard writer.status == .writing, Date() < deadline else { throw writer.error ?? FileError.encoder("MP4 timeout") }
                    try await Task.sleep(for: .milliseconds(5))
                }
                try Task.checkCancellation()
                guard let image = Renderer.render(layers: frame, width: width, height: height),
                      let pool = adaptor.pixelBufferPool else { throw FileError.encoder("MP4 buffer") }
                var pixelBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
                      let pixelBuffer else { throw FileError.encoder("MP4 memory allocation") }
                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { throw FileError.encoder("MP4 drawing context") }
                context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 60000)
                guard adaptor.append(pixelBuffer, withPresentationTime: time) else { throw writer.error ?? FileError.encoder("MP4 frame") }
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(seconds: Double(frames.count) / fps, preferredTimescale: 60000))
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? FileError.encoder("MP4 completion") }
            // Save panels confirm replacement before this entry point is called.
            if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: staging) }
            else { try FileManager.default.moveItem(at: staging, to: url) }
        } catch { writer.cancelWriting(); throw error }
    }

    private static func validateAnimation(frames: [[ArtLayer]], width: Int, height: Int, fps: Double) throws {
        guard !frames.isEmpty else { throw FileError.noFrames }
        try validate(width: width, height: height)
        guard fps.isFinite, (1...120).contains(fps), frames.count <= 10_000 else { throw FileError.encoder("Animation supports 1–120 FPS and up to 10,000 frames") }
    }

    private static func encoded(image: CGImage, type: UTType) throws -> Data {
        var output = image
        if type == .jpeg {
            guard let context = bitmap(width: image.width, height: image.height) else { throw FileError.invalidImage }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = context.makeImage() else { throw FileError.invalidImage }; output = flattened
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { throw FileError.encoder(type.identifier) }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileError.encoder(type.identifier) }
        return data as Data
    }

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
