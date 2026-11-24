import Foundation

/// Animation → Weather (0.108): snow, rain or sparkles on a new layer over the whole animation.
/// Every particle travels a whole number of canvas heights per loop, so the effect repeats without
/// a seam. From one frame it makes new frames; on an animation it covers the frames already there.
enum Weather: String, CaseIterable, Identifiable {
    case snow, rain, sparkle
    var id: String { rawValue }
    var title: String { switch self { case .snow: "Snow"; case .rain: "Rain"; case .sparkle: "Sparkles" } }
    var symbol: String { switch self { case .snow: "snowflake"; case .rain: "cloud.rain"; case .sparkle: "sparkles" } }

    struct Particle { var x: Double; var y: Double; var size: Double; var speed: Int; var phase: Double }

    /// Fixed particles for a canvas (same seed → same weather, so undo/redo and tests agree).
    static func particles(_ w: Weather, width: Double, height: Double, seed: UInt64 = 7) -> [Particle] {
        var g = SplitMix(seed)
        let n = max(8, Int(width * height / (w == .rain ? 9000 : w == .snow ? 7000 : 16000)))
        return (0..<n).map { _ in
            Particle(x: g.next() * width, y: g.next() * height,
                     size: w == .rain ? 1 + g.next() * 1.5 : w == .snow ? 2 + g.next() * 5 : 2 + g.next() * 4,
                     speed: w == .rain ? 2 + Int(g.next() * 2) : w == .snow ? 1 : 0, phase: g.next())
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
