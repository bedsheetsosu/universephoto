import CoreGraphics
import Foundation

/// Shapes of the rectangle tool; stroke kinds keep old documents working ("rectangle").
enum ShapeStyle: String, CaseIterable, Sendable {
    case rectangle, rounded, polygon, star
    var kind: String { switch self { case .rectangle: "rectangle"; case .rounded: "roundedRect"; case .polygon: "polygon"; case .star: "star" } }
    var title: String { switch self { case .rectangle: "Rectangle"; case .rounded: "Rounded"; case .polygon: "Polygon"; case .star: "Star" } }
    var symbol: String { switch self { case .rectangle: "rectangle"; case .rounded: "app"; case .polygon: "hexagon"; case .star: "star" } }
    /// Range of the shape's own value (corner radius in px, corners, points); nil = none.
    var parameter: ClosedRange<Double>? { switch self { case .rectangle: nil; case .rounded: 2...200; case .polygon: 3...12; case .star: 4...12 } }
    var parameterTitle: String { self == .rounded ? "Corner radius" : self == .polygon ? "Corners" : "Points" }
}

enum ShapeGeometry {
    static let closedKinds: Set<String> = ["rectangle", "ellipse", "roundedRect", "polygon", "star"]

    /// Outline of a closed shape kind filling `rect` (y down: the first corner points up).
    static func path(kind: String, in rect: CGRect, parameter: Double?) -> CGPath? {
        switch kind {
        case "rectangle": return CGPath(rect: rect, transform: nil)
        case "ellipse": return CGPath(ellipseIn: rect, transform: nil)
        case "roundedRect":
            let r = min(max(0, parameter ?? 16), min(rect.width, rect.height) / 2)
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        case "polygon", "star":
            let star = kind == "star"
            let n = max(star ? 4 : 3, min(12, Int((parameter ?? (star ? 5 : 6)).rounded())))
            let count = star ? n * 2 : n
            let p = CGMutablePath()
            for i in 0..<count {
                let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(count)
                let f = star && i % 2 == 1 ? 0.45 : 1
                let pt = CGPoint(x: rect.midX + cos(a) * rect.width / 2 * f, y: rect.midY + sin(a) * rect.height / 2 * f)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
            return p
        default: return nil
        }
    }

    /// Filled head of an arrow ending at `q`, coming from `p`.
    static func arrowHead(from p: CGPoint, to q: CGPoint, width: Double) -> CGPath {
        let size = max(12, width * 3.2), a = atan2(q.y - p.y, q.x - p.x), spread = 0.45
        let path = CGMutablePath()
        path.move(to: CGPoint(x: q.x + cos(a) * width * 0.6, y: q.y + sin(a) * width * 0.6))
        path.addLine(to: CGPoint(x: q.x - cos(a - spread) * size, y: q.y - sin(a - spread) * size))
        path.addLine(to: CGPoint(x: q.x - cos(a + spread) * size, y: q.y - sin(a + spread) * size))
        path.closeSubpath()
        return path
    }
}
