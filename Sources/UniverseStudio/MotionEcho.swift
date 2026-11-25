import Foundation

/// Animate → Motion echo (0.125): lays fading ghosts of the active layer from the frames just
/// before it into every frame – the trailing smear of a fast move. The ghosts are normal layers
/// named "Echo" below the drawing; running it again replaces them, and "None" clears them.
extension Studio {
    static let echoName = "Echo"

    /// Ghost copies of the layer `activeID` taken from the `count` frames before `i`, faintest and
    /// deepest first, so they sit behind the drawing and fade into the distance.
    static func echoLayers(activeID: UUID, frames: [[ArtLayer]], at i: Int, count: Int, base: Double, falloff: Double) -> [ArtLayer] {
        var ghosts: [ArtLayer] = []
        for k in 1...max(1, count) where i - k >= 0 {
            guard var g = frames[i - k].first(where: { $0.id == activeID }) else { continue }
            g.id = UUID(); g.name = echoName; g.visible = true; g.locked = true
            g.mask = nil; g.clipped = false; g.allFrames = nil
            g.opacity = max(0, min(1, base * pow(falloff, Double(k - 1))))
            ghosts.append(g)
        }
        return ghosts.reversed()   // oldest/faintest ends up first → bottom of the insert
    }

    /// Adds (or with `count == 0`, clears) the echo ghosts across all frames. Returns ghosts added.
    @discardableResult func motionEcho(count: Int, strong: Bool = false) -> Int {
        guard frames.count > 1, let activeID = activeLayer?.id else { return 0 }
        stopPlayback(); checkpoint("Motion echo")
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        // Always strip the previous echoes first, so the command is idempotent.
        for i in frames.indices { frames[i].removeAll { $0.name == Self.echoName } }
        var added = 0
        if count > 0 {
            let base = strong ? 0.65 : 0.4, falloff = strong ? 0.72 : 0.55
            for i in frames.indices {
                let ghosts = Self.echoLayers(activeID: activeID, frames: frames, at: i, count: count, base: base, falloff: falloff)
                guard !ghosts.isEmpty, let idx = frames[i].firstIndex(where: { $0.id == activeID }) else { continue }
                frames[i].insert(contentsOf: ghosts, at: idx)
                added += ghosts.count
            }
        }
        layers = frames[frameIndex]
        // Keep the drawing selected even though ghosts shifted its index.
        selectedLayer = layers.firstIndex(where: { $0.id == activeID }) ?? min(selectedLayer, layers.count - 1)
        changed()
        return added
    }
}
