import Foundation

/// Animation → Motion preset (0.99): one frame in, a whole movement out. The active layer of the
/// current frame is copied into new frames and moved, turned, scaled or faded along a curve.
/// Looping presets (spin, pulse, float, swing, shake) close seamlessly; the others end at rest.
enum MotionPreset: String, CaseIterable, Identifiable {
    case bounce, shake, spin, pulse, float, swing, slideIn, slideOut, fadeIn, fadeOut, pop, dropIn
    var id: String { rawValue }
    var title: String { switch self {
    case .bounce: "Bounce"; case .shake: "Shake"; case .spin: "Spin"; case .pulse: "Pulse"; case .float: "Float"; case .swing: "Swing"
    case .slideIn: "Slide in"; case .slideOut: "Slide out"; case .fadeIn: "Fade in"; case .fadeOut: "Fade out"; case .pop: "Pop in"; case .dropIn: "Drop in" } }
    var symbol: String { switch self {
    case .bounce: "arrow.up.and.down"; case .shake: "waveform.path"; case .spin: "arrow.clockwise"; case .pulse: "heart"; case .float: "cloud"; case .swing: "metronome"
    case .slideIn: "arrow.right.to.line"; case .slideOut: "arrow.right.circle"; case .fadeIn: "circle.lefthalf.filled"; case .fadeOut: "circle.dotted"; case .pop: "sparkle"; case .dropIn: "arrow.down.to.line" } }
    var loops: Bool { [.shake, .spin, .pulse, .float, .swing, .bounce].contains(self) }

    /// Offset, rotation (°), scale factor and opacity factor at `t` (0…1) for a canvas of `w` × `h`.
    func pose(_ t: Double, w: Double, h: Double) -> (dx: Double, dy: Double, rot: Double, scale: Double, alpha: Double) {
        let ease = t * t * (3 - 2 * t), out = 1 - pow(1 - t, 3)
        switch self {
        case .bounce: return (0, -abs(sin(t * .pi)) * h * 0.15, 0, 1, 1)
        case .shake: return (sin(t * .pi * 8) * w * 0.015, 0, sin(t * .pi * 16) * 2, 1, 1)
        case .spin: return (0, 0, t * 360, 1, 1)
        case .pulse: return (0, 0, 0, 1 + 0.12 * sin(t * .pi * 2) * sin(t * .pi * 2) * (sin(t * .pi * 2) >= 0 ? 1 : 0.4), 1)
        case .float: return (0, sin(t * .pi * 2) * h * 0.03, sin(t * .pi * 4) * 1.5, 1, 1)
        case .swing: return (0, 0, sin(t * .pi * 2) * 12, 1, 1)
        case .slideIn: return (-(1 - out) * w, 0, 0, 1, 1)
        case .slideOut: return (ease * ease * w, 0, 0, 1, 1)
        case .fadeIn: return (0, 0, 0, 1, ease)
        case .fadeOut: return (0, 0, 0, 1, 1 - ease)
        case .pop:
            // Overshoot then settle: 0 → 1.15 → 1.
            let s = t < 0.6 ? 1.15 * (1 - pow(1 - t / 0.6, 2)) : 1.15 - 0.15 * ((t - 0.6) / 0.4)
            return (0, 0, 0, max(0.001, s), min(1, t * 4))
        case .dropIn:
            // Falls from above and bounces twice, smaller each time.
            let y: Double
            if t < 0.5 { let u = t / 0.5; y = -(1 - u * u) * h * 0.6 }
            else if t < 0.8 { let u = (t - 0.5) / 0.3; y = -sin(u * .pi) * h * 0.08 }
            else { let u = (t - 0.8) / 0.2; y = -sin(u * .pi) * h * 0.02 }
            return (0, y, 0, 1, 1)
        }
    }

    /// Positions along the curve for `n` frames: looping presets stop just before 1 so the cycle
    /// joins up; one-shot presets run from 0 to exactly 1.
    func steps(_ n: Int) -> [Double] {
        guard n > 1 else { return [loops ? 0 : 1] }
        return (0..<n).map { loops ? Double($0) / Double(n) : Double($0) / Double(n - 1) }
    }
}

extension Studio {
    /// Replaces the current frame with `count` frames of the preset (the active layer moves; the
    /// rest stays). Returns how many frames the movement has.
    @discardableResult func applyMotionPreset(_ p: MotionPreset, count: Int) -> Int {
        guard count > 1, let id = activeLayer?.id, !(activeLayer?.isAdjustmentLayer ?? true) else { return 0 }
        stopPlayback(); checkpoint("Motion preset")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let source = frames[frameIndex], w = Double(width), h = Double(height)
        let made: [[ArtLayer]] = p.steps(count).map { t in
            let pose = p.pose(t, w: w, h: h)
            return source.map { l in
                guard l.id == id else { return l }
                var m = l
                m.transform.x += pose.dx; m.transform.y += pose.dy; m.transform.rotation += pose.rot
                m.transform.scale *= pose.scale; m.opacity *= pose.alpha
                return m
            }
        }
        frames[frameIndex] = made[0]
        metaInsert(at: frameIndex + 1, holds: Array(repeating: 1, count: made.count - 1))
        frames.insert(contentsOf: made.dropFirst(), at: frameIndex + 1)
        layers = frames[frameIndex]
        changed()
        return made.count
    }
}
