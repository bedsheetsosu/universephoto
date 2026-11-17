import CoreImage
import Foundation

/// One entry of a layer's filter stack. Applied after the adjustments, in order; never changes pixels.
struct SmartFilter: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: Kind
    var amount: Double
    var enabled = true

    enum Kind: String, Codable, CaseIterable, Sendable {
        // Blur & sharpen
        case motionBlur, zoomBlur, unsharpMask, bloom, gloom
        // Stylize
        case edges, lineArt, comic, crystallize, pointillize, hexagons, kaleidoscope, dither
        // Distort
        case twirl, bump, pinch
        // Colour looks
        case sepia, thermal, xray, chrome, fade, instant, mono, noir, process, tonal, transfer

        var title: String { switch self {
        case .motionBlur: "Motion blur"; case .zoomBlur: "Zoom blur"; case .unsharpMask: "Unsharp mask"; case .bloom: "Bloom"; case .gloom: "Gloom"
        case .edges: "Find edges"; case .lineArt: "Line art"; case .comic: "Comic"; case .crystallize: "Crystallize"; case .pointillize: "Pointillize"
        case .hexagons: "Hexagons"; case .kaleidoscope: "Kaleidoscope"; case .dither: "Dither"
        case .twirl: "Twirl"; case .bump: "Bulge"; case .pinch: "Pinch"
        case .sepia: "Sepia"; case .thermal: "Thermal"; case .xray: "X-ray"; case .chrome: "Chrome"; case .fade: "Fade"; case .instant: "Instant"
        case .mono: "Mono"; case .noir: "Noir film"; case .process: "Process"; case .tonal: "Tonal"; case .transfer: "Transfer" } }

        var group: String { switch self {
        case .motionBlur, .zoomBlur, .unsharpMask, .bloom, .gloom: "Blur & sharpen"
        case .edges, .lineArt, .comic, .crystallize, .pointillize, .hexagons, .kaleidoscope, .dither: "Stylize"
        case .twirl, .bump, .pinch: "Distort"
        default: "Colour looks" } }

        /// Range of the strength slider; nil = the filter has no strength.
        var range: ClosedRange<Double>? { switch self {
        case .motionBlur: 0...80; case .zoomBlur: 0...60; case .unsharpMask: 0...3; case .bloom, .gloom: 0...2
        case .edges: 0...10; case .crystallize, .pointillize: 2...80; case .hexagons: 2...80; case .kaleidoscope: 2...16; case .dither: 0...1
        case .twirl: -12...12; case .bump: -1...1; case .pinch: 0...1; case .sepia: 0...1
        default: nil } }

        var defaultAmount: Double { switch self {
        case .motionBlur: 20; case .zoomBlur: 12; case .unsharpMask: 1; case .bloom, .gloom: 1; case .edges: 3
        case .crystallize, .pointillize, .hexagons: 16; case .kaleidoscope: 6; case .dither: 0.5
        case .twirl: 3; case .bump: 0.6; case .pinch: 0.5; case .sepia: 0.9
        default: 1 } }
    }

    init(kind: Kind) { self.kind = kind; self.amount = kind.defaultAmount }

    /// The filter applied to `image` (whose extent is the layer's document rect).
    func apply(to image: CIImage) -> CIImage {
        guard enabled else { return image }
        let e = image.extent, c = CIVector(x: e.midX, y: e.midY), r = max(e.width, e.height)
        let a = kind.range.map { min($0.upperBound, max($0.lowerBound, amount)) } ?? amount
        func f(_ name: String, _ p: [String: Any] = [:], clamp: Bool = false) -> CIImage {
            (clamp ? image.clampedToExtent() : image).applyingFilter(name, parameters: p).cropped(to: e)
        }
        switch kind {
        case .motionBlur: return f("CIMotionBlur", [kCIInputRadiusKey: a, kCIInputAngleKey: 0], clamp: true)
        case .zoomBlur: return f("CIZoomBlur", [kCIInputCenterKey: c, "inputAmount": a], clamp: true)
        case .unsharpMask: return f("CIUnsharpMask", [kCIInputRadiusKey: 2.5, kCIInputIntensityKey: a])
        case .bloom: return f("CIBloom", [kCIInputRadiusKey: 10, kCIInputIntensityKey: a], clamp: true)
        case .gloom: return f("CIGloom", [kCIInputRadiusKey: 10, kCIInputIntensityKey: a], clamp: true)
        case .edges: return f("CIEdges", [kCIInputIntensityKey: a])
        case .lineArt: return f("CILineOverlay")
        case .comic: return f("CIComicEffect")
        case .crystallize: return f("CICrystallize", [kCIInputRadiusKey: a, kCIInputCenterKey: c], clamp: true)
        case .pointillize: return f("CIPointillize", [kCIInputRadiusKey: a, kCIInputCenterKey: c], clamp: true)
        case .hexagons: return f("CIHexagonalPixellate", [kCIInputScaleKey: a, kCIInputCenterKey: c], clamp: true)
        case .kaleidoscope: return f("CIKaleidoscope", ["inputCount": Int(a.rounded()), kCIInputCenterKey: c, kCIInputAngleKey: 0], clamp: true)
        case .dither: return f("CIDither", [kCIInputIntensityKey: a])
        case .twirl: return f("CITwirlDistortion", [kCIInputCenterKey: c, kCIInputRadiusKey: r * 0.4, kCIInputAngleKey: a], clamp: true)
        case .bump: return f("CIBumpDistortion", [kCIInputCenterKey: c, kCIInputRadiusKey: r * 0.4, kCIInputScaleKey: a], clamp: true)
        case .pinch: return f("CIPinchDistortion", [kCIInputCenterKey: c, kCIInputRadiusKey: r * 0.4, kCIInputScaleKey: a], clamp: true)
        case .sepia: return f("CISepiaTone", [kCIInputIntensityKey: a])
        case .thermal: return f("CIThermal")
        case .xray: return f("CIXRay")
        case .chrome: return f("CIPhotoEffectChrome")
        case .fade: return f("CIPhotoEffectFade")
        case .instant: return f("CIPhotoEffectInstant")
        case .mono: return f("CIPhotoEffectMono")
        case .noir: return f("CIPhotoEffectNoir")
        case .process: return f("CIPhotoEffectProcess")
        case .tonal: return f("CIPhotoEffectTonal")
        case .transfer: return f("CIPhotoEffectTransfer")
        }
    }
}

/// Shapes of the gradient tool; the stroke kind keeps old documents ("gradient" = linear).
enum GradientStyle: String, CaseIterable, Sendable {
    case linear, radial, reflected
    var kind: String { switch self { case .linear: "gradient"; case .radial: "gradientRadial"; case .reflected: "gradientReflected" } }
    var title: String { switch self { case .linear: "Linear"; case .radial: "Radial"; case .reflected: "Reflected" } }
    var symbol: String { switch self { case .linear: "square.bottomhalf.filled"; case .radial: "circle.circle"; case .reflected: "square.split.1x2" } }
}
