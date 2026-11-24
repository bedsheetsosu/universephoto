import Foundation

/// Animation → Camera move (0.107): a virtual camera zooms, pans or shakes over the whole picture.
/// From one frame it makes new frames; on an existing animation it runs over all frames, so the
/// drawing keeps moving while the camera glides. Every layer moves together (adjustment layers
/// keep their place); nothing is resampled, only the layer transforms change.
enum CameraMove: String, CaseIterable, Identifiable {
    case zoomIn, zoomOut, panLeft, panRight, panUp, panDown, shake
    var id: String { rawValue }
    var title: String { switch self {
    case .zoomIn: "Zoom in"; case .zoomOut: "Zoom out"; case .panLeft: "Pan left"; case .panRight: "Pan right"
    case .panUp: "Pan up"; case .panDown: "Pan down"; case .shake: "Camera shake" } }
    var symbol: String { switch self {
    case .zoomIn: "plus.magnifyingglass"; case .zoomOut: "minus.magnifyingglass"; case .panLeft: "arrow.left"; case .panRight: "arrow.right"
    case .panUp: "arrow.up"; case .panDown: "arrow.down"; case .shake: "waveform.path.ecg" } }
    var loops: Bool { self == .shake }

    /// Camera zoom and offset at `t` (0…1) for a `w` × `h` canvas. Pans zoom in a little so no
    /// empty edge shows.
    func camera(_ t: Double, w: Double, h: Double) -> (zoom: Double, dx: Double, dy: Double) {
        let e = t * t * (3 - 2 * t), z = 1.2, px = w * (z - 1) / 2 * 0.9, py = h * (z - 1) / 2 * 0.9
        switch self {
        case .zoomIn: return (1 + 0.25 * e, 0, 0)
        case .zoomOut: return (1.25 - 0.25 * e, 0, 0)
        // The camera moves left, so the picture slides right.
        case .panLeft: return (z, px * (2 * e - 1), 0)
        case .panRight: return (z, -px * (2 * e - 1), 0)
        case .panUp: return (z, 0, py * (2 * e - 1))
        case .panDown: return (z, 0, -py * (2 * e - 1))
        case .shake:
            let a = w * 0.012
            return (1.03, a * (sin(t * .pi * 14) + 0.5 * sin(t * .pi * 30)), a * (cos(t * .pi * 18) + 0.4 * sin(t * .pi * 26)))
        }
    }

    func steps(_ n: Int) -> [Double] {
        guard n > 1 else { return [0] }
        return (0..<n).map { loops ? Double($0) / Double(n) : Double($0) / Double(n - 1) }
    }

    /// The layer as seen through the camera (zoom and offset around the canvas centre).
    static func apply(_ l: ArtLayer, zoom k: Double, dx: Double, dy: Double) -> ArtLayer {
        guard !l.isAdjustmentLayer else { return l }
        var m = l
        m.transform.x = dx + k * l.transform.x; m.transform.y = dy + k * l.transform.y
        m.transform.scale = l.transform.scale * k
        return m
    }
}

extension Studio {
    /// `count` > 1: replaces the current frame with that many camera frames. `count` 0: runs the
    /// camera over the frames that are already there. Returns the number of frames touched.
    @discardableResult func cameraMove(_ c: CameraMove, count: Int) -> Int {
        let w = Double(width), h = Double(height)
        if count == 0 {
            guard frames.count > 1 else { return 0 }
            stopPlayback(); checkpoint("Camera move")
            frames[frameIndex] = layers
            let ts = c.steps(frames.count)
            for i in frames.indices {
                let cam = c.camera(ts[i], w: w, h: h)
                frames[i] = frames[i].map { CameraMove.apply($0, zoom: cam.zoom, dx: cam.dx, dy: cam.dy) }
            }
            layers = frames[frameIndex]
            changed()
            return frames.count
        }
        guard count > 1 else { return 0 }
        stopPlayback(); checkpoint("Camera move")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let source = frames[frameIndex]
        let made: [[ArtLayer]] = c.steps(count).map { t in
            let cam = c.camera(t, w: w, h: h)
            return source.map { CameraMove.apply($0, zoom: cam.zoom, dx: cam.dx, dy: cam.dy) }
        }
        frames[frameIndex] = made[0]
        metaInsert(at: frameIndex + 1, holds: Array(repeating: 1, count: made.count - 1))
        frames.insert(contentsOf: made.dropFirst(), at: frameIndex + 1)
        layers = frames[frameIndex]
        changed()
        return made.count
    }
}
