import Foundation

/// Animation → One after another (0.114): the layers of the current frame come in one by one –
/// fading, popping, sliding or dropping in – each a little after the one below, then the whole
/// picture rests. The bottom layer (the background) and shared layers stay put.
enum Stagger {
    static let styles: [MotionPreset] = [.fadeIn, .pop, .slideIn, .dropIn]

    /// Ids of the layers that come in, bottom to top.
    static func movingLayers(_ frame: [ArtLayer]) -> [UUID] {
        frame.enumerated().filter { i, l in
            (i > 0 || frame.count == 1) && l.visible && !l.isAdjustmentLayer && l.allFrames != true
        }.map(\.element.id)
    }

    /// Progress (−∞…1, clamped at 1) of entrant `j` in frame `f`.
    static func progress(frame f: Int, entrant j: Int, gap: Int, duration: Int) -> Double {
        min(1, Double(f - j * gap) / Double(max(1, duration)))
    }
}

extension Studio {
    /// Replaces the current frame with the entrance (last frame held for `restTicks`). Returns the
    /// number of frames, 0 when there is nothing to bring in.
    @discardableResult func staggerIn(_ style: MotionPreset, gap: Int, duration: Int, restTicks: Int = 12) -> Int {
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let source = frames[frameIndex], ids = Stagger.movingLayers(source)
        guard !ids.isEmpty, gap >= 0, duration >= 1 else { return 0 }
        stopPlayback(); checkpoint("One after another")
        let count = (ids.count - 1) * gap + duration + 1
        let w = Double(width), h = Double(height)
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let made: [[ArtLayer]] = (0..<count).map { f in
            source.map { l in
                guard let j = order[l.id] else { return l }
                let t = Stagger.progress(frame: f, entrant: j, gap: gap, duration: duration)
                var m = l
                guard t >= 0 else { m.opacity = 0; return m }
                let p = style.pose(t, w: w, h: h)
                m.transform.x += p.dx; m.transform.y += p.dy
                self.pivotEdit(&m, .centre) { $0.rotation += p.rot; $0.scale *= p.scale }   // around the drawing (0.191)
                m.opacity *= p.alpha
                return m
            }
        }
        frames[frameIndex] = made[0]
        metaInsert(at: frameIndex + 1, holds: Array(repeating: 1, count: made.count - 2) + [max(1, restTicks)])
        frames.insert(contentsOf: made.dropFirst(), at: frameIndex + 1)
        layers = frames[frameIndex]
        changed()
        return made.count
    }
}
