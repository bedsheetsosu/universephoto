import CoreGraphics
import CoreVideo
import Vision

/// Select → Subject and Layer → Remove background, with the system's on-device foreground
/// segmentation (Vision, macOS 14+). Nothing leaves the Mac.
enum SubjectMask {
    enum Failure: Error { case nothingFound }

    /// One byte per pixel (255 = subject, row 0 = top) at the picture's size, or nil when the
    /// picture has no recognisable foreground.
    static func mask(for image: CGImage) throws -> [UInt8]? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
        let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        return bytes(buffer, width: image.width, height: image.height)
    }

    /// A one-channel float (0…1) or byte pixel buffer as mask bytes at `width` × `height`.
    static func bytes(_ buffer: CVPixelBuffer, width w: Int, height h: Int) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bw = CVPixelBufferGetWidth(buffer), bh = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard bw > 0, bh > 0 else { return nil }
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let sy = min(bh - 1, y * bh / h)
            let line = base.advanced(by: sy * row)
            for x in 0..<w {
                let sx = min(bw - 1, x * bw / w)
                let v: Double
                switch format {
                case kCVPixelFormatType_OneComponent32Float: v = Double(line.assumingMemoryBound(to: Float32.self)[sx])
                case kCVPixelFormatType_OneComponent8: v = Double(line.assumingMemoryBound(to: UInt8.self)[sx]) / 255
                default: return nil
                }
                out[y * w + x] = UInt8(max(0, min(255, v * 255)).rounded())
            }
        }
        return out
    }
}

extension Studio {
    /// The visible picture's subject as a mask (document pixels).
    func subjectMask() -> [UInt8]? {
        guard let image = Renderer.render(layers: composite(layers), width: width, height: height) else { return nil }
        return try? SubjectMask.mask(for: image)
    }

    /// Select → Subject. Returns false when nothing was found (the selection stays as it was).
    @discardableResult func selectSubject() -> Bool {
        guard let mask = subjectMask() else { return false }
        setSelection(mask: mask); return true
    }

    /// Layer → Remove background: a layer mask that shows only the subject (undoable, editable).
    @discardableResult func removeBackground() -> Bool {
        guard canEdit, let layer = activeLayer, !layer.isAdjustmentLayer, let mask = subjectMask() else { return false }
        let previous = selection
        setSelection(mask: mask)
        maskFromSelection(reveal: true)
        selection = previous
        return true
    }
}
