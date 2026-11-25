import Foundation

/// Animate → right-click a frame → Flash (0.127): drops a single solid-colour frame in after this
/// one – the white or black blink animators use for an impact or a camera flash. It is one normal
/// layer filled with the colour, so you can recolour it or lower its opacity afterwards. Hold 1,
/// one undo step.
extension Studio {
    /// A frame that is one layer filled edge to edge with `color`.
    static func flashFrameLayers(color: CodableColor) -> [ArtLayer] {
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: color, width: 1)
        fill.kind = "fill"
        var layer = ArtLayer(name: L("Flash"))
        layer.strokes = [fill]
        return [layer]
    }

    func insertFlash(after index: Int, color: CodableColor) {
        guard frames.indices.contains(index) else { return }
        stopPlayback(); checkpoint("Flash frame")
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        metaInsert(at: index + 1, holds: [1])
        frames.insert(Self.flashFrameLayers(color: color), at: index + 1)
        if frameIndex > index { frameIndex += 1 }
        selectFrame(index + 1)
        changed()
    }
}
