import SwiftUI

/// A small picture of a layer's own content (placed, without opacity, blend or effects) on a
/// checkerboard. Rendered off the main thread when the layer changes; cached by content.
struct LayerThumbnail: View {
    @EnvironmentObject private var s: Studio
    var layer: ArtLayer
    var selected: Bool
    @Environment(\.photoTheme) private var theme
    @State private var image: CGImage?

    private static let cache = NSCache<NSString, CGImage>()

    /// Changes whenever what the thumbnail shows can change.
    nonisolated static func key(_ l: ArtLayer, width: Int, height: Int) -> String {
        "\(l.id)-\(l.strokes.count)-\(l.strokes.last?.id.uuidString ?? "")-\(l.strokes.last?.points.count ?? 0)-\(l.imageData?.count ?? 0)-\(l.mask?.count ?? 0)-\(l.transform.x),\(l.transform.y),\(l.transform.scale),\(l.transform.rotation)-\(width)x\(height)"
    }

    /// The layer drawn into a picture at most `side` pixels on its longer edge.
    nonisolated static func render(_ layer: ArtLayer, width: Int, height: Int, side: Int = 96) -> CGImage? {
        var l = layer
        l.opacity = 1; l.blend = .normal; l.visible = true; l.style = nil; l.filters = nil; l.clipped = false; l.adjustment = .init()
        guard let full = Renderer.render(layers: [l], width: width, height: height) else { return nil }
        return ImageFiles.scaled(full, by: Double(side) / Double(max(width, height)))
    }

    var body: some View {
        let key = Self.key(layer, width: s.width, height: s.height)
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(selected ? theme.accentSoft : theme.deep)
            if layer.isAdjustmentLayer {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .light)).foregroundStyle(selected ? theme.accent : theme.secondary)
            } else if let image {
                Checkerboard().clipShape(RoundedRectangle(cornerRadius: 6)).padding(3)
                Image(decorative: image, scale: 1).resizable().interpolation(.medium).aspectRatio(contentMode: .fit).padding(3)
            } else {
                Image(systemName: layer.imageData == nil ? "scribble.variable" : "photo").font(.system(size: 18, weight: .light)).foregroundStyle(selected ? theme.accent : theme.secondary)
            }
        }
        .task(id: key) {
            guard !layer.isAdjustmentLayer else { return }
            if let hit = Self.cache.object(forKey: key as NSString) { image = hit; return }
            try? await Task.sleep(for: .milliseconds(120))   // let a stroke in progress settle
            guard !Task.isCancelled else { return }
            let l = layer, w = s.width, h = s.height
            let made = await Task.detached(priority: .utility) { Self.render(l, width: w, height: h) }.value
            guard !Task.isCancelled, let made else { return }
            Self.cache.setObject(made, forKey: key as NSString)
            image = made
        }
    }
}

/// Light checkerboard for transparent thumbnails.
struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let cell = 5.0
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.96)))
            for y in stride(from: 0.0, to: size.height, by: cell) {
                for x in stride(from: 0.0, to: size.width, by: cell) where (Int(x / cell) + Int(y / cell)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color(white: 0.85)))
                }
            }
        }
    }
}
