import AppKit
import SwiftUI

struct InkPoint: Codable, Equatable, Sendable {
    var x: Double; var y: Double; var pressure: Double
    var tiltX: Double? = nil; var tiltY: Double? = nil; var rotation: Double? = nil
}
struct CodableColor: Codable, Equatable, Sendable {
    var red: Double; var green: Double; var blue: Double; var alpha: Double
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    static let black = CodableColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
    static let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    init(red: Double, green: Double, blue: Double, alpha: Double) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }
    init(_ color: Color) { let c = NSColor(color).usingColorSpace(.sRGB) ?? .black; self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent) }
}
struct InkStroke: Codable, Equatable, Identifiable, Sendable {
    var id = UUID(); var points: [InkPoint]; var color: CodableColor; var width: Double; var isEraser = false
    // nil preserves the v1 freehand representation.
    var kind: String? = nil // rectangle, ellipse, line, text, fill, gradient
    var text: String? = nil
    var secondaryColor: CodableColor? = nil
    var selectionPoints: [InkPoint]? = nil
    var selectionEllipse: Bool? = nil
}
enum LayerBlend: String, Codable, CaseIterable, Sendable { case normal, multiply, screen, overlay, darken, lighten }
struct LayerTransform: Codable, Equatable, Sendable {
    var x = 0.0; var y = 0.0; var scale = 1.0; var rotation = 0.0
}
struct LayerAdjustment: Codable, Equatable, Sendable {
    var brightness = 0.0; var contrast = 1.0; var saturation = 1.0; var exposure = 0.0; var blur = 0.0; var inverted = false
}
struct ArtLayer: Codable, Identifiable, Equatable, Sendable {
    var id = UUID(); var name: String; var visible = true; var strokes: [InkStroke] = []
    var opacity = 1.0; var blend = LayerBlend.normal; var locked = false
    var transform = LayerTransform(); var adjustment = LayerAdjustment()
    var imageData: Data? = nil
    // White reveals; black hides. Rendered in layer coordinates.
    var mask: [InkStroke]? = nil
    init(name: String) { self.name = name }
    enum CodingKeys: String, CodingKey { case id, name, visible, strokes, opacity, blend, locked, transform, adjustment, imageData, mask }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(); name = try c.decode(String.self, forKey: .name)
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        strokes = try c.decodeIfPresent([InkStroke].self, forKey: .strokes) ?? []
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        blend = try c.decodeIfPresent(LayerBlend.self, forKey: .blend) ?? .normal
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        transform = try c.decodeIfPresent(LayerTransform.self, forKey: .transform) ?? .init()
        adjustment = try c.decodeIfPresent(LayerAdjustment.self, forKey: .adjustment) ?? .init()
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        mask = try c.decodeIfPresent([InkStroke].self, forKey: .mask)
    }
}
struct ArtDocument: Codable, Equatable, Sendable {
    var version = 2; var title: String; var width: Int; var height: Int; var layers: [ArtLayer]; var frames: [[ArtLayer]] = []
    var fps: Double? = 12
    var activeFrame: Int? = 0
}
extension JSONEncoder { static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e } }

enum Tool: String, CaseIterable, Identifiable {
    case brush, eraser, eyedropper, move, rectangleSelection, ellipseSelection, lasso, fill, gradient, text, rectangle, ellipse, line, pan
    var id: String { rawValue }
    var symbol: String { switch self {
    case .brush: "paintbrush.pointed"; case .eraser: "eraser"; case .eyedropper: "eyedropper"; case .move: "move.3d"; case .rectangleSelection: "rectangle.dashed"; case .ellipseSelection: "circle.dashed"; case .lasso: "lasso"; case .fill: "drop.fill"; case .gradient: "rectangle.lefthalf.filled"; case .text: "textformat"; case .rectangle: "rectangle"; case .ellipse: "circle"; case .line: "line.diagonal"; case .pan: "hand.draw"
    } }
    var key: String { switch self { case .brush: "b"; case .eraser: "e"; case .eyedropper: "i"; case .move: "v"; case .rectangleSelection: "m"; case .ellipseSelection: "u"; case .lasso: "l"; case .fill: "g"; case .gradient: "d"; case .text: "t"; case .rectangle: "r"; case .ellipse: "c"; case .line: "n"; case .pan: "p" } }

    var english: String { switch self { case .brush: "Brush"; case .eraser: "Eraser"; case .eyedropper: "Eyedropper"; case .move: "Move"; case .rectangleSelection: "Rectangle selection"; case .ellipseSelection: "Ellipse selection"; case .lasso: "Lasso"; case .fill: "Fill layer"; case .gradient: "Gradient"; case .text: "Text"; case .rectangle: "Rectangle"; case .ellipse: "Ellipse"; case .line: "Line"; case .pan: "Hand" } }
}
struct CanvasSelection: Equatable { var points: [CGPoint]; var ellipse = false; var bounds: CGRect { guard let p = points.first else { return .zero }; return points.dropFirst().reduce(CGRect(x:p.x,y:p.y,width:0,height:0)) { $0.union(CGRect(x:$1.x,y:$1.y,width:0,height:0)) } } }
struct CanvasGeometry {
    var size: CGSize; var document: CGSize; var zoom: Double; var pan: CGSize; var rotation: Double; var mirrored: Bool
    var scale: Double { min((size.width - 72) / document.width, (size.height - 72) / document.height) * zoom }
    var transform: CGAffineTransform { CGAffineTransform(translationX: size.width/2 + pan.width, y: size.height/2 + pan.height).rotated(by: rotation * .pi / 180).scaledBy(x: mirrored ? -scale : scale, y: scale).translatedBy(x: -document.width/2, y: -document.height/2) }
    func toDocument(_ point: CGPoint) -> CGPoint { point.applying(transform.inverted()) }
}
