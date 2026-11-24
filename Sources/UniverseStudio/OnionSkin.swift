import CoreGraphics
import Foundation

/// Animate: onion skin with several frames before and after the current one, tinted red (before)
/// and green (after), fading with distance. Settings live in user defaults (Timeline → onion menu).
struct OnionSettings: Equatable {
    var before = 1, after = 0, opacity = 0.25, tinted = true
    /// Ghost only the active layer (0.94), so backgrounds and shared layers don't double up.
    var activeOnly = false

    static let beforeColor = CGColor(srgbRed: 0.93, green: 0.30, blue: 0.36, alpha: 1)
    static let afterColor = CGColor(srgbRed: 0.22, green: 0.72, blue: 0.48, alpha: 1)

    init(before: Int = 1, after: Int = 0, opacity: Double = 0.25, tinted: Bool = true) {
        self.before = before; self.after = after; self.opacity = opacity; self.tinted = tinted
    }

    init(defaults d: UserDefaults) {
        before = d.object(forKey: "onionBefore") as? Int ?? 1
        after = d.object(forKey: "onionAfter") as? Int ?? 0
        opacity = d.object(forKey: "onionOpacity") as? Double ?? 0.25
        tinted = d.object(forKey: "onionTinted") as? Bool ?? true
        activeOnly = d.object(forKey: "onionActiveOnly") as? Bool ?? false
    }

    /// The layers drawn as a ghost: all, or just the active one (when that frame has it).
    func ghostLayers(_ frame: [ArtLayer], activeID: UUID?) -> [ArtLayer] {
        guard activeOnly, let activeID else { return frame }
        return frame.filter { $0.id == activeID }.map { var l = $0; l.clipped = false; return l }
    }

    struct Ghost: Equatable { var index: Int; var alpha: Double; var isBefore: Bool }

    /// Frames to show around `current`, farthest first (so nearer ones sit on top). With `loop`,
    /// frames wrap around the ends.
    func ghosts(current: Int, count: Int, loop: Bool) -> [Ghost] {
        guard count > 1, current >= 0, current < count else { return [] }
        var out: [Ghost] = []
        func add(_ n: Int, _ sign: Int, _ isBefore: Bool) {
            guard n > 0 else { return }
            for d in stride(from: n, through: 1, by: -1) {
                var i = current + sign * d
                if loop { i = ((i % count) + count) % count } else if i < 0 || i >= count { continue }
                guard i != current, !out.contains(where: { $0.index == i }) else { continue }
                out.append(Ghost(index: i, alpha: opacity * Double(n - d + 1) / Double(n), isBefore: isBefore))
            }
        }
        add(min(before, count - 1), -1, true)
        add(min(after, count - 1), 1, false)
        return out
    }

    /// The frame picture tinted (keeps its alpha, so the drawing's shape stays readable).
    static func tint(_ image: CGImage, color: CGColor) -> CGImage? {
        guard let ctx = Renderer.context(width: image.width, height: image.height) else { return nil }
        let r = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        Renderer.drawImage(image, in: ctx, rect: r)
        ctx.setBlendMode(.sourceAtop); ctx.setFillColor(color.copy(alpha: 0.75) ?? color); ctx.fill(r)
        return ctx.makeImage()
    }
}
