import SwiftUI

/// Image → Replace colour: pixels close to a chosen colour (fuzziness) get their hue, saturation
/// and lightness shifted, softly at the edge of the range. Only inside the selection, if there is
/// one. Lands on the active layer as one picture stroke painted "atop", so transparency stays.
struct ColorReplacement: Equatable {
    var source: CodableColor
    var fuzziness = 40.0        // 0…200, like Photoshop (distance in 0…255 RGB units)
    var hue = 0.0               // −180…180 degrees
    var saturation = 0.0        // −100…100
    var lightness = 0.0         // −100…100

    /// How strongly a colour (0…1 RGB) is replaced, 0…1.
    func weight(r: Double, g: Double, b: Double) -> Double {
        let d = (pow(r - source.red, 2) + pow(g - source.green, 2) + pow(b - source.blue, 2)).squareRoot() * 255
        let f = max(1, fuzziness)
        return max(0, min(1, 1 - d / f))
    }

    /// The colour after the shifts.
    func replaced(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        var (h, s, l) = Self.hsl(r, g, b)
        h = (h + hue / 360).truncatingRemainder(dividingBy: 1); if h < 0 { h += 1 }
        s = max(0, min(1, saturation >= 0 ? s + (1 - s) * saturation / 100 : s * (1 + saturation / 100)))
        l = max(0, min(1, lightness >= 0 ? l + (1 - l) * lightness / 100 : l * (1 + lightness / 100)))
        return Self.rgb(h, s, l)
    }

    static func hsl(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        guard d > 1e-6 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        return (h / 6, s, l)
    }
    static func rgb(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        guard s > 1e-6 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func f(_ t0: Double) -> Double {
            var t = t0; if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return (f(h + 1.0 / 3), f(h), f(h - 1.0 / 3))
    }
}

extension Studio {
    /// The replacement pixels (premultiplied RGBA, layer pixels) and how many pixels it touches.
    func replacementPixels(_ rep: ColorReplacement) -> ([UInt8], Int)? {
        guard let image = rawLayerPixels(), let b = PixelOps.bitmap(image) else { return nil }
        let sel = selectionInLayerPixels()
        var out = [UInt8](repeating: 0, count: b.bytes.count), touched = 0
        for i in 0..<(b.width * b.height) {
            let p = i * 4, a = Double(b.bytes[p + 3]) / 255
            guard a > 0 else { continue }
            let r = Double(b.bytes[p]) / 255 / a, g = Double(b.bytes[p + 1]) / 255 / a, bl = Double(b.bytes[p + 2]) / 255 / a
            var w = rep.weight(r: r, g: g, b: bl)
            if let sel { w *= Double(sel[i]) / 255 }
            guard w > 0.002 else { continue }
            touched += 1
            let (nr, ng, nb) = rep.replaced(r: r, g: g, b: bl)
            // Painted atop with alpha w: blends the new colour over the old one by w.
            out[p] = UInt8(min(255, nr * w * 255)); out[p + 1] = UInt8(min(255, ng * w * 255)); out[p + 2] = UInt8(min(255, nb * w * 255)); out[p + 3] = UInt8(min(255, w * 255))
        }
        return (out, touched)
    }

    @discardableResult func replaceColor(_ rep: ColorReplacement) -> Int {
        guard canEdit, let layer = activeLayer, !layer.isAdjustmentLayer, let (bytes, touched) = replacementPixels(rep), touched > 0,
              let picture = ContentAwareFill.image(bytes, width: width, height: height), let data = PixelOps.png(picture) else { return 0 }
        var stroke = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1)
        stroke.kind = "bitmap"; stroke.imageData = data; stroke.atop = true
        mutateLayer("Replace color") { $0.strokes.append(stroke) }
        return touched
    }
}

struct ReplaceColorDialog: View {
    @EnvironmentObject private var s: Studio
    @Environment(\.photoTheme) private var theme
    @State private var rep = ColorReplacement(source: .black)
    @State private var touched = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Replace color")).font(.system(size: 23, weight: .bold, design: .rounded))
            HStack(spacing: 12) {
                swatch(rep.source); Image(systemName: "arrow.right").foregroundStyle(theme.secondary)
                let (r, g, b) = rep.replaced(r: rep.source.red, g: rep.source.green, b: rep.source.blue)
                swatch(CodableColor(red: r, green: g, blue: b, alpha: 1))
                Text(L("The colour to replace is the foreground colour – pick it with the eyedropper first.")).font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            slider(L("Fuzziness"), $rep.fuzziness, 0...200, "")
            slider(L("Hue"), $rep.hue, -180...180, "°")
            slider(L("Saturation"), $rep.saturation, -100...100, "")
            slider(L("Lightness"), $rep.lightness, -100...100, "")
            Text(touched == 0 ? L("No pixels in range.") : LF("%d pixels in range", touched)).font(.caption).foregroundStyle(theme.secondary).monospacedDigit()
            HStack {
                Spacer()
                Button(L("Cancel")) { s.replaceColorDialog = false }.keyboardShortcut(.cancelAction)
                Button(L("Replace")) { s.replaceColor(rep); s.replaceColorDialog = false }.buttonStyle(PhotoButtonStyle(prominent: true)).keyboardShortcut(.defaultAction).disabled(touched == 0)
            }
        }
        .padding(26).frame(width: 440)
        .onAppear { rep.source = s.color; recount() }
        .onChange(of: rep.fuzziness) { recount() }
    }
    private func recount() { touched = s.replacementPixels(rep)?.1 ?? 0 }
    private func swatch(_ c: CodableColor) -> some View {
        RoundedRectangle(cornerRadius: 8).fill(Color(red: c.red, green: c.green, blue: c.blue)).frame(width: 40, height: 40).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.outline))
    }
    private func slider(_ t: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ unit: String) -> some View {
        HStack { Text(t).frame(width: 90, alignment: .leading); Slider(value: v, in: r); Text("\(Int(v.wrappedValue.rounded()))\(unit)").monospacedDigit().frame(width: 44, alignment: .trailing).foregroundStyle(theme.secondary) }
    }
}
