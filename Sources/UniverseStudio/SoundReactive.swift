import Foundation

/// Animation → React to sound (0.101): the active layer follows the loudness of the sound track –
/// it grows, jumps or lights up with each beat or syllable (a quick "talking" or music effect).
/// With only one frame, frames are added first so the whole sound is covered.
enum SoundReaction: String, CaseIterable, Identifiable {
    case scale, jump, opacity
    var id: String { rawValue }
    var title: String { switch self { case .scale: "Grow with sound"; case .jump: "Jump with sound"; case .opacity: "Light up with sound" } }

    /// Loudness levels normalised to the loudest frame (0…1).
    static func normalised(_ levels: [Double]) -> [Double] {
        let top = levels.max() ?? 0
        return top > 0 ? levels.map { $0 / top } : levels.map { _ in 0 }
    }
}

extension Studio {
    /// Peak loudness under each frame of the sound.
    func soundLevels() -> [Double] {
        guard let cache = audioEngine.cache(for: audio) else { return [] }
        return frames.indices.map { i in
            let t0 = soundTime(frame: i), t1 = t0 + Double(hold(i)) / max(1, fps)
            guard t1 > 0 else { return 0 }
            return Double(cache.peaks(from: max(0, t0), to: t1, buckets: 1).first ?? 0)
        }
    }

    @discardableResult func reactToSound(_ r: SoundReaction, strength: Double = 1) -> Bool {
        guard audio != nil, let layer = activeLayer, !layer.isAdjustmentLayer, let cache = audioEngine.cache(for: audio) else { return false }
        stopPlayback(); checkpoint("React to sound")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        // Cover the sound: one frame per tick after the last frame until the sound ends.
        let end = cache.duration + AudioTiming.time(ofFrame: audio?.startFrame ?? 0, fps: fps, hold: { hold($0) })
        var total = AudioTiming.time(ofFrame: frames.count, fps: fps, hold: { hold($0) }), added = 0
        let template = frames[frames.count - 1]
        while total < end - 0.5 / max(1, fps) && frames.count + added < VideoImport.maxFrames { total += 1 / max(1, fps); added += 1 }
        if added > 0 { metaInsert(at: frames.count, holds: Array(repeating: 1, count: added)); frames.append(contentsOf: Array(repeating: template, count: added)) }
        let levels = SoundReaction.normalised(soundLevels()), id = layer.id, h = Double(height)
        frames = frames.enumerated().map { i, f in
            let v = levels.indices.contains(i) ? levels[i] : 0
            return f.map { l in
                guard l.id == id else { return l }
                var m = l
                switch r {
                case .scale: m.transform.scale = layer.transform.scale * (1 + 0.25 * strength * v)
                case .jump: m.transform.y = layer.transform.y - v * h * 0.08 * strength
                case .opacity: m.opacity = min(1, layer.opacity * (0.25 + 0.75 * v))
                }
                return m
            }
        }
        layers = frames[frameIndex]
        changed()
        return true
    }
}
