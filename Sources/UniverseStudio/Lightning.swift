import Foundation

/// Animation → Effects → Light → Lightning (0.249): now and then the whole picture lights up in the
/// typical double flash of a thunderstorm – bright, a flicker, bright again, gone. A white layer on
/// top in Screen mode, so dark scenes light up and light ones barely change. Pairs with Day to night.
/// Over the play range (or all frames). One undo step. Returns how many strikes there are.
extension Studio {
    /// Flash brightness per frame for `n` frames, a strike about every `gap` frames.
    static func lightningLevels(count n: Int, gap: Int, seed: UInt64 = 0x7B0) -> [Double] {
        var out = Array(repeating: 0.0, count: n)
        guard n >= 6, gap >= 6 else { return out }
        let jitter = shakeOffsets(count: n / gap + 2, seed: seed)
        var at = gap / 2, k = 0
        while at + 3 < n {
            for (o, v) in [0.95, 0.3, 0.8, 0.15].enumerated() { out[at + o] = v }
            at += max(6, gap + Int((jitter[k].0 * Double(gap) * 0.4).rounded())); k += 1
        }
        return out
    }

    @discardableResult func addLightning(everySeconds: Double) -> Int {
        guard frames.count >= 6 else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let levels = Studio.lightningLevels(count: r.count, gap: max(6, Int((fps * everySeconds).rounded())))
        let strikes = levels.filter { $0 == 0.95 }.count
        guard strikes > 0 else { return 0 }
        checkpoint("Lightning")
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: CodableColor(red: 0.92, green: 0.95, blue: 1, alpha: 1), width: 1)
        fill.kind = "fill"
        var layer = ArtLayer(name: L("Lightning")); layer.strokes = [fill]; layer.blend = .screen
        for i in frames.indices {
            var l = layer; l.opacity = r.contains(i) ? levels[i - r.lowerBound] : 0
            frames[i].append(l)
        }
        layers = frames[frameIndex]; selectedLayer = layers.count - 1
        changed()
        return strikes
    }
}
