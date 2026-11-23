import CoreGraphics

/// Symmetry painting: brush and eraser strokes are drawn again mirrored or turned around the
/// canvas centre. The stroke stores only the mode and centre, so it stays one stroke (one undo
/// step, live while drawing) and keeps its symmetry in the file.
enum Symmetry: String, CaseIterable, Identifiable, Sendable {
    case off, vertical, horizontal, quad, radial
    var id: String { rawValue }
    var title: String { switch self { case .off: "No symmetry"; case .vertical: "Mirror left–right"; case .horizontal: "Mirror top–bottom"; case .quad: "Four quadrants"; case .radial: "Radial" } }
    var symbol: String { switch self { case .off: "circle.slash"; case .vertical: "arrow.left.and.right.righttriangle.left.righttriangle.right"; case .horizontal: "arrow.up.and.down.righttriangle.up.righttriangle.down"; case .quad: "square.grid.2x2"; case .radial: "asterisk" } }

    /// Stored code: "v", "h", "vh" or "r<N>"; nil for off.
    func code(segments: Int) -> String? {
        switch self { case .off: nil; case .vertical: "v"; case .horizontal: "h"; case .quad: "vh"; case .radial: "r\(max(2, min(24, segments)))" }
    }

    /// The point transforms of a stored code around `c` (the first is always the identity).
    static func transforms(_ code: String, center c: CGPoint) -> [CGAffineTransform] {
        let mx = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * c.x, ty: 0)
        let my = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 2 * c.y)
        switch code {
        case "v": return [.identity, mx]
        case "h": return [.identity, my]
        case "vh": return [.identity, mx, my, mx.concatenating(my)]
        default:
            guard code.hasPrefix("r"), let n = Int(code.dropFirst()), n >= 2 else { return [.identity] }
            return (0..<min(n, 24)).map { k in
                CGAffineTransform(translationX: -c.x, y: -c.y).concatenating(CGAffineTransform(rotationAngle: Double(k) * 2 * .pi / Double(n))).concatenating(CGAffineTransform(translationX: c.x, y: c.y))
            }
        }
    }

    /// The stroke's copies (itself first) with points moved; symmetry fields cleared.
    static func copies(of stroke: InkStroke) -> [InkStroke] {
        guard let code = stroke.symmetry, let x = stroke.symmetryX, let y = stroke.symmetryY else { return [stroke] }
        return transforms(code, center: CGPoint(x: x, y: y)).map { t in
            var s = stroke
            s.symmetry = nil; s.symmetryX = nil; s.symmetryY = nil
            s.points = stroke.points.map { p in
                var q = p; let m = CGPoint(x: p.x, y: p.y).applying(t); q.x = m.x; q.y = m.y; return q
            }
            return s
        }
    }
}
