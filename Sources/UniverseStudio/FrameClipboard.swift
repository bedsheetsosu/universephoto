import CoreGraphics
import Foundation

/// Animate: copy and paste frames (inside the app, the system clipboard is left alone) and a
/// pinned reference frame shown in blue behind the drawing, like a light table.
extension Studio {
    func copyFrame(_ index: Int) { copyFrames([index]) }

    /// Copies frames in timeline order.
    func copyFrames(_ indices: [Int]) {
        let picked = indices.filter { frames.indices.contains($0) }.sorted()
        guard !picked.isEmpty else { return }
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        frameClipboard = picked.map { (frames[$0], hold($0)) }
    }

    /// Inserts the copied frame after `index` and shows it.
    @discardableResult func pasteFrame(after index: Int) -> Bool {
        guard let clip = frameClipboard, !clip.isEmpty, !frames.isEmpty || index == 0 else { return false }
        stopPlayback(); checkpoint("Paste frame")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let at = min(index + 1, frames.count)
        metaInsert(at: at, holds: clip.map(\.hold))
        frames.insert(contentsOf: Self.syncedFrames(clip.map(\.layers), from: layers), at: at)
        selectedFrames = []
        frameIndex = at; layers = frames[at]; selection = nil
        changed()
        return true
    }

    func toggleReference(_ index: Int) { referenceFrame = referenceFrame == index ? nil : index }

    static let referenceColor = CGColor(srgbRed: 0.25, green: 0.52, blue: 0.95, alpha: 1)
}
