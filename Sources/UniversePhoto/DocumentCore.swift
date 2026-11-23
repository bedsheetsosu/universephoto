import AppKit
import SwiftUI

struct InkPoint: Codable, Equatable, Sendable {
    var x: Double; var y: Double; var pressure: Double
    var tiltX: Double? = nil; var tiltY: Double? = nil; var rotation: Double? = nil
}
struct CodableColor: Codable, Hashable, Sendable {
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
    /// Pixel content for kind "bitmap" (paint bucket, raster results): PNG in layer coordinates.
    var imageData: Data? = nil
    /// Selection as a pixel mask (magic wand, inverted selections): 8-bit gray PNG, white = selected.
    var selectionMask: Data? = nil
    /// Retouch brushes (dodge, burn, blur, sharpen, smudge): 0…1.
    var strength: Double? = nil
    /// Text: PostScript font name (nil = Helvetica, as before 0.8).
    var fontName: String? = nil
    /// Closed shapes: filled instead of outlined (nil = outline, as before 0.14).
    var filled: Bool? = nil
    /// Pressure brush tip (nil = round, as before 0.15).
    var brushTip: String? = nil
    /// Text (0.18): alignment around the click (left, center, right), tracking in 1/1000 em, line spacing × size.
    var textAlign: String? = nil
    var tracking: Double? = nil
    var lineSpacing: Double? = nil
    /// Painted on a layer with locked transparency: only lands on pixels already there (source atop).
    var atop: Bool? = nil
    /// Kind "path" (pen tool): points are anchor/out-handle pairs; closed path or not.
    var pathClosed: Bool? = nil
    /// Kind "path": three points per node (anchor, out-, in-handle) instead of two.
    var pathTriples: Bool? = nil
    /// Symmetry painting: "v", "h", "vh" or "r<N>", around (symmetryX, symmetryY) in layer pixels.
    var symmetry: String? = nil
    var symmetryX: Double? = nil
    var symmetryY: Double? = nil
    /// Freehand kinds: the pressure brush and the retouch brushes (smoothed, every point kept).
    var isFreehand: Bool { kind == nil || ["dodge", "burn", "blurBrush", "sharpenBrush", "clone", "heal", "smudge", "liquify"].contains(kind!) }
}
enum LayerBlend: String, Codable, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten
    case colorBurn, linearBurn, colorDodge, linearDodge, softLight, hardLight, difference, exclusion, hue, saturation, color, luminosity
    var title: String { switch self {
    case .normal: "Normal"; case .multiply: "Multiply"; case .screen: "Screen"; case .overlay: "Overlay"; case .darken: "Darken"; case .lighten: "Lighten"
    case .colorBurn: "Color burn"; case .linearBurn: "Linear burn"; case .colorDodge: "Color dodge"; case .linearDodge: "Linear dodge (add)"
    case .softLight: "Soft light"; case .hardLight: "Hard light"; case .difference: "Difference"; case .exclusion: "Exclusion"
    case .hue: "Hue"; case .saturation: "Saturation"; case .color: "Color"; case .luminosity: "Luminosity" } }
}
struct LayerTransform: Codable, Equatable, Sendable {
    var x = 0.0; var y = 0.0; var scale = 1.0; var rotation = 0.0
}
struct LayerAdjustment: Codable, Equatable, Sendable {
    var brightness = 0.0; var contrast = 1.0; var saturation = 1.0; var exposure = 0.0; var blur = 0.0; var inverted = false
    // Added in 0.3; older documents decode them with neutral values.
    var hue = 0.0              // degrees, −180…180
    var vibrance = 0.0         // −1…1
    var temperature = 0.0      // −1 (cooler) … 1 (warmer)
    var tint = 0.0             // −1 (green) … 1 (magenta)
    var levelsBlack = 0.0      // 0…0.9 input black point
    var levelsWhite = 1.0      // 0.1…1 input white point
    var gamma = 1.0            // 0.2…5 midtones
    var sharpen = 0.0          // 0…2
    var noiseReduction = 0.0   // 0…1
    var vignette = 0.0         // 0…2
    var posterize = 0.0        // 0 = off, else 2…32 levels
    var pixelate = 0.0         // 0 = off, else block size in px
    var grain = 0.0            // 0…1 film grain
    /// Tone curves by channel ("rgb", "red", "green", "blue"); nil = straight.
    var curves: [String: [CurvePoint]]? = nil
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v(_ k: CodingKeys, _ d: Double) throws -> Double { try c.decodeIfPresent(Double.self, forKey: k) ?? d }
        brightness = try v(.brightness, 0); contrast = try v(.contrast, 1); saturation = try v(.saturation, 1)
        exposure = try v(.exposure, 0); blur = try v(.blur, 0); inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? false
        hue = try v(.hue, 0); vibrance = try v(.vibrance, 0); temperature = try v(.temperature, 0); tint = try v(.tint, 0)
        levelsBlack = try v(.levelsBlack, 0); levelsWhite = try v(.levelsWhite, 1); gamma = try v(.gamma, 1)
        sharpen = try v(.sharpen, 0); noiseReduction = try v(.noiseReduction, 0); vignette = try v(.vignette, 0)
        posterize = try v(.posterize, 0); pixelate = try v(.pixelate, 0); grain = try v(.grain, 0)
        curves = try c.decodeIfPresent([String: [CurvePoint]].self, forKey: .curves)
    }
    var numbers: [Double] { (curves ?? [:]).values.flatMap { $0.flatMap { [$0.x, $0.y] } } + [brightness, contrast, saturation, exposure, blur, hue, vibrance, temperature, tint, levelsBlack, levelsWhite, gamma, sharpen, noiseReduction, vignette, posterize, pixelate, grain] }
}
struct ArtLayer: Codable, Identifiable, Equatable, Sendable {
    var id = UUID(); var name: String; var visible = true; var strokes: [InkStroke] = []
    var opacity = 1.0; var blend = LayerBlend.normal; var locked = false
    var transform = LayerTransform(); var adjustment = LayerAdjustment()
    var imageData: Data? = nil
    // White reveals; black hides. Rendered in layer coordinates.
    var mask: [InkStroke]? = nil
    /// Clipping mask: only shows where the nearest unclipped layer below has pixels.
    var clipped = false
    /// Layer effects (drop shadow, outer glow, stroke, colour overlay); nil = none.
    var style: LayerStyle? = nil
    /// The group (folder) this layer belongs to, see `ArtDocument.groups`.
    var groupID: UUID? = nil
    /// Smart filters, applied after the adjustments in order; never change the pixels.
    var filters: [SmartFilter]? = nil
    /// Adjustment layer (0.17): no pixels of its own; its adjustments, filters and mask act on everything below.
    var adjustsBelow: Bool? = nil
    /// Lock transparency (0.20): new paint only lands where the layer already has pixels.
    var lockAlpha: Bool? = nil
    var isAdjustmentLayer: Bool { adjustsBelow == true }
    init(name: String) { self.name = name }
    enum CodingKeys: String, CodingKey { case id, name, visible, strokes, opacity, blend, locked, transform, adjustment, imageData, mask, clipped, style, groupID, filters, adjustsBelow, lockAlpha }
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
        clipped = try c.decodeIfPresent(Bool.self, forKey: .clipped) ?? false
        style = try c.decodeIfPresent(LayerStyle.self, forKey: .style)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        filters = try c.decodeIfPresent([SmartFilter].self, forKey: .filters)
        adjustsBelow = try c.decodeIfPresent(Bool.self, forKey: .adjustsBelow)
        lockAlpha = try c.decodeIfPresent(Bool.self, forKey: .lockAlpha)
    }
}
struct ArtDocument: Codable, Equatable, Sendable {
    var version = 2; var title: String; var width: Int; var height: Int; var layers: [ArtLayer]; var frames: [[ArtLayer]] = []
    var fps: Double? = 12
    var activeFrame: Int? = 0
    /// Layer groups (folders); layers point to them with `groupID`. Shared by all frames.
    var groups: [LayerGroup]? = nil
    /// Guide lines (0.22).
    var guides: [Guide]? = nil
}
struct LayerGroup: Codable, Equatable, Identifiable, Sendable {
    var id = UUID(); var name: String; var visible = true; var opacity = 1.0; var collapsed = false
}
extension JSONEncoder { static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e } }

enum Tool: String, CaseIterable, Identifiable {
    case brush, eraser, eyedropper, move, crop, rectangleSelection, ellipseSelection, lasso, wand, fill, bucket, gradient, clone, heal, smudge, liquify, dodge, pen, focus, text, rectangle, ellipse, line, pan
    var id: String { rawValue }
    var symbol: String { switch self {
    case .brush: "paintbrush.pointed"; case .eraser: "eraser"; case .eyedropper: "eyedropper"; case .move: "move.3d"; case .crop: "crop"; case .rectangleSelection: "rectangle.dashed"; case .ellipseSelection: "circle.dashed"; case .lasso: "lasso"; case .wand: "wand.and.stars"; case .fill: "drop.fill"; case .bucket: "paintbrush.pointed.fill"; case .clone: "seal"; case .heal: "bandage"; case .smudge: "hand.point.up.left"; case .liquify: "drop.halffull"; case .pen: "point.bottomleft.forward.to.point.topright.scurvepath"; case .dodge: "circle.lefthalf.striped.horizontal"; case .focus: "drop.degreesign"; case .gradient: "rectangle.lefthalf.filled"; case .text: "textformat"; case .rectangle: "rectangle"; case .ellipse: "circle"; case .line: "line.diagonal"; case .pan: "hand.draw"
    } }
    var key: String { switch self { case .brush: "b"; case .eraser: "e"; case .eyedropper: "i"; case .move: "v"; case .crop: "h"; case .rectangleSelection: "m"; case .ellipseSelection: "u"; case .lasso: "l"; case .wand: "w"; case .fill: "g"; case .bucket: "k"; case .clone: "s"; case .heal: "j"; case .smudge: "f"; case .liquify: "q"; case .pen: "a"; case .dodge: "o"; case .focus: "y"; case .gradient: "d"; case .text: "t"; case .rectangle: "r"; case .ellipse: "c"; case .line: "n"; case .pan: "p" } }

    var english: String { switch self { case .brush: "Brush"; case .eraser: "Eraser"; case .eyedropper: "Eyedropper"; case .move: "Move"; case .crop: "Crop"; case .rectangleSelection: "Rectangle selection"; case .ellipseSelection: "Ellipse selection"; case .lasso: "Lasso"; case .wand: "Magic wand"; case .fill: "Fill layer"; case .bucket: "Paint bucket"; case .clone: "Clone stamp"; case .heal: "Healing brush"; case .smudge: "Smudge"; case .liquify: "Liquify"; case .pen: "Pen"; case .dodge: "Dodge and burn"; case .focus: "Blur and sharpen"; case .gradient: "Gradient"; case .text: "Text"; case .rectangle: "Rectangle"; case .ellipse: "Ellipse"; case .line: "Line"; case .pan: "Hand" } }
}
struct CanvasSelection: Equatable {
    var points: [CGPoint]; var ellipse = false
    /// Pixel selection (magic wand, inverse): DeviceGray, document size, white = selected.
    var mask: CGImage? = nil
    /// The mask as PNG, put on strokes drawn inside the selection.
    var maskData: Data? = nil
    static func == (a: CanvasSelection, b: CanvasSelection) -> Bool { a.points == b.points && a.ellipse == b.ellipse && a.mask === b.mask }
    var bounds: CGRect { guard let p = points.first else { return .zero }; return points.dropFirst().reduce(CGRect(x:p.x,y:p.y,width:0,height:0)) { $0.union(CGRect(x:$1.x,y:$1.y,width:0,height:0)) } } }
struct CanvasGeometry {
    var size: CGSize; var document: CGSize; var zoom: Double; var pan: CGSize; var rotation: Double; var mirrored: Bool
    var scale: Double { min((size.width - 72) / document.width, (size.height - 72) / document.height) * zoom }
    var transform: CGAffineTransform { CGAffineTransform(translationX: size.width/2 + pan.width, y: size.height/2 + pan.height).rotated(by: rotation * .pi / 180).scaledBy(x: mirrored ? -scale : scale, y: scale).translatedBy(x: -document.width/2, y: -document.height/2) }
    func toDocument(_ point: CGPoint) -> CGPoint { point.applying(transform.inverted()) }
}

/// One-click starting points for the adjustments (they only set values; everything stays editable).
enum AdjustmentLook: String, CaseIterable, Identifiable {
    case film, vivid, noir, cool, warm, retro
    var id: String { rawValue }
    var title: String { switch self { case .film: "Film"; case .vivid: "Vivid"; case .noir: "Noir"; case .cool: "Cool"; case .warm: "Warm"; case .retro: "Retro" } }
    var symbol: String { switch self { case .film: "film"; case .vivid: "sparkles"; case .noir: "moon"; case .cool: "snowflake"; case .warm: "sun.max"; case .retro: "camera.filters" } }
    func apply(to a: inout LayerAdjustment) {
        a = LayerAdjustment()
        switch self {
        case .film: a.grain = 0.35; a.vignette = 0.6; a.temperature = 0.15; a.contrast = 1.08; a.levelsBlack = 0.03
        case .vivid: a.vibrance = 0.6; a.contrast = 1.12; a.sharpen = 0.4
        case .noir: a.saturation = 0; a.contrast = 1.35; a.vignette = 0.9; a.grain = 0.2
        case .cool: a.temperature = -0.45; a.tint = -0.05; a.vibrance = 0.2
        case .warm: a.temperature = 0.45; a.vibrance = 0.15; a.exposure = 0.1
        case .retro: a.saturation = 0.75; a.temperature = 0.3; a.contrast = 0.85; a.gamma = 1.1; a.grain = 0.25; a.vignette = 0.5
        }
    }
}

/// Photoshop-style layer effects. They follow the layer's pixels and stay editable.
struct LayerStyle: Codable, Equatable, Sendable {
    struct Shadow: Codable, Equatable, Sendable {
        var on = false; var color = CodableColor(red: 0, green: 0, blue: 0, alpha: 1); var opacity = 0.6
        var angle = 120.0      // degrees, light from the upper left like Photoshop
        var distance = 8.0; var blur = 12.0
    }
    struct Glow: Codable, Equatable, Sendable {
        var on = false; var color = CodableColor(red: 1, green: 0.95, blue: 0.6, alpha: 1); var opacity = 0.75; var size = 18.0
    }
    struct Outline: Codable, Equatable, Sendable {
        var on = false; var color = CodableColor(red: 0, green: 0, blue: 0, alpha: 1); var opacity = 1.0; var width = 3.0
    }
    struct Overlay: Codable, Equatable, Sendable {
        var on = false; var color = CodableColor(red: 1, green: 0.4, blue: 0.5, alpha: 1); var opacity = 1.0
    }
    struct GradientOverlay: Codable, Equatable, Sendable {
        var on = false; var from = CodableColor(red: 0.5, green: 0.89, blue: 0.83, alpha: 1); var to = CodableColor(red: 0.75, green: 0.55, blue: 1, alpha: 1)
        var angle = 90.0; var opacity = 1.0
    }
    var shadow = Shadow(); var glow = Glow(); var outline = Outline(); var overlay = Overlay()
    /// Since 0.16; older files decode them switched off.
    var innerShadow = Shadow(on: false, opacity: 0.55, distance: 5, blur: 8)
    var innerGlow = Glow(on: false, color: CodableColor(red: 1, green: 1, blue: 1, alpha: 1), opacity: 0.6, size: 10)
    var gradient = GradientOverlay()
    var isActive: Bool { shadow.on || glow.on || outline.on || overlay.on || innerShadow.on || innerGlow.on || gradient.on }
    var numbers: [Double] { [shadow.opacity, shadow.angle, shadow.distance, shadow.blur, glow.opacity, glow.size, outline.opacity, outline.width, overlay.opacity,
                             innerShadow.opacity, innerShadow.angle, innerShadow.distance, innerShadow.blur, innerGlow.opacity, innerGlow.size, gradient.angle, gradient.opacity] }
    init() {}
    enum CodingKeys: String, CodingKey { case shadow, glow, outline, overlay, innerShadow, innerGlow, gradient }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), d = LayerStyle()
        shadow = try c.decodeIfPresent(Shadow.self, forKey: .shadow) ?? d.shadow
        glow = try c.decodeIfPresent(Glow.self, forKey: .glow) ?? d.glow
        outline = try c.decodeIfPresent(Outline.self, forKey: .outline) ?? d.outline
        overlay = try c.decodeIfPresent(Overlay.self, forKey: .overlay) ?? d.overlay
        innerShadow = try c.decodeIfPresent(Shadow.self, forKey: .innerShadow) ?? d.innerShadow
        innerGlow = try c.decodeIfPresent(Glow.self, forKey: .innerGlow) ?? d.innerGlow
        gradient = try c.decodeIfPresent(GradientOverlay.self, forKey: .gradient) ?? d.gradient
    }
}
