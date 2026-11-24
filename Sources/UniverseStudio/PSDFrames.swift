import Foundation

/// Export → "PSD · Frames as layers" (0.95): every frame flattened into one layer, named
/// "Frame 01" (with its hold, e.g. "Frame 02 ×3"), bottom = first frame. Only the first frame is
/// visible, ready for Photoshop's "Make Frames From Layers".
extension PSD {
    static func frameLayers(frames: [[ArtLayer]], holds: [Int], labels: [String], width: Int, height: Int, outWidth: Int? = nil, outHeight: Int? = nil) throws -> [ArtLayer] {
        try frames.enumerated().map { i, frame in
            guard let image = ImageFiles.renderFrame(frame, width, height, outWidth ?? width, outHeight ?? height) else { throw ImageFiles.FileError.encoder("Frame \(i + 1)") }
            let hold = holds.indices.contains(i) ? max(1, holds[i]) : 1
            let label = labels.indices.contains(i) && !labels[i].isEmpty ? " · \(labels[i])" : ""
            var l = ArtLayer(name: String(format: "Frame %02d", i + 1) + (hold > 1 ? " ×\(hold)" : "") + label)
            l.imageData = try Renderer.png(image)
            l.visible = i == 0
            return l
        }
    }

    static func writeFrames(frames: [[ArtLayer]], holds: [Int], labels: [String], width: Int, height: Int, scale: Double = 1) throws -> Data {
        let (w, h) = ImageFiles.outputSize(width, height, scale: scale)
        return try write(layers: frameLayers(frames: frames, holds: holds, labels: labels, width: width, height: height, outWidth: w, outHeight: h), width: w, height: h)
    }
}
