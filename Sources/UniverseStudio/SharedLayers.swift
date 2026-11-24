import Foundation

/// Animate: a layer marked "Same in all frames" is one drawing for the whole animation – editing
/// it in any frame changes it everywhere (backgrounds, a character's held parts).
extension Studio {
    /// Every frame gets the current frame's version of each shared layer (matched by id; inserted
    /// at the same place when a frame lacks it).
    static func syncedFrames(_ frames: [[ArtLayer]], from current: [ArtLayer]) -> [[ArtLayer]] {
        let shared = current.enumerated().filter { $0.element.allFrames == true }
        guard !shared.isEmpty else { return frames }
        return frames.map { frame in
            var f = frame
            for (index, layer) in shared {
                if let i = f.firstIndex(where: { $0.id == layer.id }) { f[i] = layer } else { f.insert(layer, at: min(index, f.count)) }
            }
            return f
        }
    }

    func toggleAllFrames() {
        guard layers.indices.contains(selectedLayer) else { return }
        mutateLayer("Same in all frames") { $0.allFrames = $0.allFrames == true ? nil : true }
        if layers[selectedLayer].allFrames == true { frames = Self.syncedFrames(frames, from: layers) }
        else {
            // Off: each frame keeps its own copy from now on.
            let id = layers[selectedLayer].id
            frames = frames.map { $0.map { var l = $0; if l.id == id { l.allFrames = nil }; return l } }
        }
        changed()
    }
}
