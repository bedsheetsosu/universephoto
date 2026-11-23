import SwiftUI

/// Edit → Fill selection and Stroke selection: the foreground colour inside the selection, or as
/// a band along its edge (inside, centred or outside), on the active layer as a picture stroke.
extension Studio {
    enum StrokePosition: String, CaseIterable, Identifiable {
        case inside, center, outside
        var id: String { rawValue }
        var title: String { switch self { case .inside: "Inside"; case .center: "Centre"; case .outside: "Outside" } }
    }

    /// The edge band of `mask` (white = selected), `width` pixels wide.
    static func strokeBand(_ mask: [UInt8], width w: Int, height h: Int, lineWidth: Double, position: StrokePosition) -> [UInt8]? {
        let lw = max(1, lineWidth)
        let outer: [UInt8]?, inner: [UInt8]?
        switch position {
        case .inside: outer = mask; inner = modified(mask, width: w, height: h, .contract, radius: lw)
        case .center: outer = modified(mask, width: w, height: h, .expand, radius: lw / 2); inner = modified(mask, width: w, height: h, .contract, radius: lw / 2)
        case .outside: outer = modified(mask, width: w, height: h, .expand, radius: lw); inner = mask
        }
        guard let outer, let inner else { return nil }
        return zip(outer, inner).map { $0 > $1 ? $0 - $1 : 0 }
    }

    /// Puts `mask` (document pixels) painted in the foreground colour on the active layer.
    private func paintMask(_ mask: [UInt8], label: String) {
        guard canEdit, let layer = activeLayer, !layer.isAdjustmentLayer else { return }
        var c = color; c.alpha *= brushOpacity
        guard let image = PixelOps.fillImage(mask, width: width, height: height, color: c) else { return }
        let local = Self.remap(image, width: width, height: height, matrix(layer.transform).inverted()) ?? image
        guard let data = PixelOps.png(local) else { return }
        var stroke = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: c, width: 1)
        stroke.kind = "bitmap"; stroke.imageData = data
        mutateLayer(label) { $0.strokes.append(stroke) }
    }

    func fillSelection() {
        guard let mask = selectionMask() else { return }
        paintMask(mask, label: "Fill selection")
    }

    func strokeSelection(width lineWidth: Double, position: StrokePosition) {
        guard let mask = selectionMask(), let band = Self.strokeBand(mask, width: width, height: height, lineWidth: lineWidth, position: position) else { return }
        paintMask(band, label: "Stroke selection")
    }
}

struct StrokeSelectionDialog: View {
    @EnvironmentObject private var s: Studio
    @Environment(\.photoTheme) private var theme
    @AppStorage("strokeSelectionWidth") private var lineWidth = 4.0
    @AppStorage("strokeSelectionPosition") private var position = Studio.StrokePosition.center.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Stroke selection")).font(.system(size: 23, weight: .bold, design: .rounded))
            HStack {
                Text(L("Width")).font(.system(size: 11))
                Slider(value: $lineWidth, in: 1...100).controlSize(.small).accessibilityLabel(L("Width"))
                Text("\(Int(lineWidth)) px").monospacedDigit().frame(width: 52, alignment: .trailing)
            }
            Picker(L("Position"), selection: $position) {
                ForEach(Studio.StrokePosition.allCases) { Text(L($0.title)).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            Text(L("Uses the foreground colour and brush opacity.")).font(.caption).foregroundStyle(theme.secondary)
            HStack {
                Button(L("Cancel")) { s.strokeSelectionDialog = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Apply")) {
                    s.strokeSelection(width: lineWidth.rounded(), position: Studio.StrokePosition(rawValue: position) ?? .center)
                    s.strokeSelectionDialog = false
                }.buttonStyle(PhotoButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 400).background(PhotoAmbient())
    }
}
