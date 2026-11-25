import Foundation

/// Animation → Weather (0.108): snow, rain or sparkles on a new layer over the whole animation.
/// Every particle travels a whole number of canvas heights per loop, so the effect repeats without
/// a seam. From one frame it makes new frames; on an animation it covers the frames already there.
enum Weather: String, CaseIterable, Identifiable {
    case snow, rain, sparkle, confetti, bubbles, fireflies   // the last three since 0.187
    var id: String { rawValue }
    var title: String { switch self {
        case .snow: "Snow"; case .rain: "Rain"; case .sparkle: "Sparkles"
        case .confetti: "Confetti"; case .bubbles: "Bubbles"; case .fireflies: "Fireflies" } }
    var symbol: String { switch self {
        case .snow: "snowflake"; case .rain: "cloud.rain"; case .sparkle: "sparkles"
        case .confetti: "party.popper"; case .bubbles: "bubbles.and.sparkles"; case .fireflies: "light.min" } }

    static let confettiColors: [CodableColor] = [
        CodableColor(red: 0.98, green: 0.36, blue: 0.42, alpha: 1), CodableColor(red: 1, green: 0.78, blue: 0.25, alpha: 1),
        CodableColor(red: 0.35, green: 0.8, blue: 0.6, alpha: 1), CodableColor(red: 0.38, green: 0.58, blue: 1, alpha: 1),
        CodableColor(red: 0.72, green: 0.45, blue: 1, alpha: 1)]

    struct Particle { var x: Double; var y: Double; var size: Double; var speed: Int; var phase: Double }

    /// Fixed particles for a canvas (same seed → same weather, so undo/redo and tests agree).
    static func particles(_ w: Weather, width: Double, height: Double, seed: UInt64 = 7) -> [Particle] {
        var g = SplitMix(seed)
        let density: Double = switch w { case .rain: 9000; case .snow: 7000; case .confetti: 9000; case .bubbles: 22000; case .fireflies: 30000; case .sparkle: 16000 }
        let n = max(8, Int(width * height / density))
        return (0..<n).map { _ in
            Particle(x: g.next() * width, y: g.next() * height,
                     size: w == .rain ? 1 + g.next() * 1.5 : w == .snow ? 2 + g.next() * 5 : w == .bubbles ? 4 + g.next() * 12 : w == .confetti ? 3 + g.next() * 4 : 2 + g.next() * 4,
                     speed: w == .rain ? 2 + Int(g.next() * 2) : w == .snow || w == .confetti || w == .bubbles ? 1 : 0, phase: g.next())
        }
    }

    /// The strokes of frame `t` (0…1 over the loop).
    static func strokes(_ w: Weather, _ ps: [Particle], t: Double, width: Double, height: Double) -> [InkStroke] {
        func pt(_ x: Double, _ y: Double) -> InkPoint { InkPoint(x: x, y: y, pressure: 1) }
        let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        return ps.compactMap { p in
            switch w {
            case .snow:
                let y = (p.y + Double(p.speed) * t * height).truncatingRemainder(dividingBy: height)
                let x = p.x + sin((t + p.phase) * 2 * .pi) * p.size * 2
                return InkStroke(points: [pt(x, y), pt(x + 0.01, y)], color: white, width: p.size)
            case .rain:
                let y = (p.y + Double(p.speed) * t * height).truncatingRemainder(dividingBy: height)
                let len = 10 + p.size * 8
                return InkStroke(points: [pt(p.x, y), pt(p.x - len * 0.25, y + len)],
                                 color: CodableColor(red: 0.75, green: 0.85, blue: 1, alpha: 0.6), width: p.size)
            case .sparkle:
                let glow = max(0, sin((t + p.phase) * 2 * .pi))
                guard glow > 0.05 else { return nil }
                return InkStroke(points: [pt(p.x, p.y), pt(p.x + 0.01, p.y)],
                                 color: CodableColor(red: 1, green: 0.95, blue: 0.7, alpha: glow), width: p.size * (0.4 + glow))
            case .confetti:
                // Falls one canvas height per loop, swaying and tumbling (whole turns, so it loops).
                let y = (p.y + t * height).truncatingRemainder(dividingBy: height)
                let x = p.x + sin((t + p.phase) * 2 * .pi) * 14
                let a = (t * 3 + p.phase) * 2 * .pi, len = p.size * 1.6 * (0.35 + 0.65 * abs(cos(a)))
                let c = confettiColors[Int(p.phase * Double(confettiColors.count)) % confettiColors.count]
                return InkStroke(points: [pt(x - len / 2, y), pt(x + len / 2, y + sin(a) * 2)], color: c, width: max(1.5, p.size * 0.6))
            case .bubbles:
                // Rise one canvas height per loop, wobbling sideways; drawn as thin rings.
                let r = p.size
                var y = (p.y - t * (height + 2 * r)).truncatingRemainder(dividingBy: height + 2 * r)
                if y < -r { y += height + 2 * r }
                let x = p.x + sin((t * 2 + p.phase) * 2 * .pi) * 6
                var ring = InkStroke(points: [pt(x - r, y - r), pt(x + r, y + r)], color: CodableColor(red: 0.8, green: 0.93, blue: 1, alpha: 0.75), width: 1.4)
                ring.kind = "ellipse"
                return ring
            case .fireflies:
                // Wander on a small loop and glow up and down.
                let x = p.x + cos((t + p.phase) * 2 * .pi) * 24
                let y = p.y + sin((t * 2 + p.phase) * 2 * .pi) * 12
                let glow = 0.25 + 0.75 * max(0, sin((t * 2 + p.phase * 3) * 2 * .pi))
                return InkStroke(points: [pt(x, y), pt(x + 0.01, y)], color: CodableColor(red: 0.85, green: 1, blue: 0.45, alpha: glow), width: p.size * (0.8 + glow))
            }
        }
    }

    /// Small deterministic random numbers in 0..<1.
    struct SplitMix {
        var state: UInt64
        init(_ seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
    }
}

extension Studio {
    /// Adds a weather layer on top. `count` > 1 and a single frame: makes that many frames first;
    /// otherwise covers the frames already there. Returns the number of frames.
    @discardableResult func addWeather(_ w: Weather, count: Int) -> Int {
        stopPlayback(); checkpoint("Weather")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        if frames.count == 1 {
            guard count > 1 else { return 0 }
            metaInsert(at: 1, holds: Array(repeating: 1, count: count - 1))
            frames += Array(repeating: frames[0], count: count - 1)
        }
        let wd = Double(width), ht = Double(height), ps = Weather.particles(w, width: wd, height: ht)
        let layer = ArtLayer(name: L(w.title))
        for i in frames.indices {
            var l = layer
            l.strokes = Weather.strokes(w, ps, t: Double(i) / Double(frames.count), width: wd, height: ht)
            frames[i].append(l)
        }
        layers = frames[frameIndex]; selectedLayer = layers.count - 1
        changed()
        return frames.count
    }
}
