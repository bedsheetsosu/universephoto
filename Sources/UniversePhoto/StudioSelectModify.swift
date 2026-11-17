import CoreImage
import SwiftUI

/// Select → Modify: feather, expand, contract, smooth, border; and select colour range.
extension Studio {
    enum SelectionModify: String, CaseIterable, Identifiable {
        case feather, expand, contract, smooth, border
        var id: String { rawValue }
        var title: String { switch self { case .feather: "Feather"; case .expand: "Expand"; case .contract: "Contract"; case .smooth: "Smooth"; case .border: "Border" } }
    }

    private static let maskContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// A CI filter chain run on a selection mask (gray, white = selected), back to bytes.
    static func processMask(_ mask: [UInt8], width w: Int, height h: Int, _ body: (CIImage) -> CIImage) -> [UInt8]? {
        guard let gray = PixelOps.grayImage(mask, width: w, height: h) else { return nil }
        let input = CIImage(cgImage: gray)
        let out = body(input.clampedToExtent()).cropped(to: input.extent)
        guard let cg = maskContext.createCGImage(out, from: input.extent) else { return nil }
        return PixelOps.grayBytes(cg)
    }

    static func modified(_ mask: [UInt8], width w: Int, height h: Int, _ kind: SelectionModify, radius r: Double) -> [UInt8]? {
        let r = max(1, r)
        switch kind {
        case .feather:
            return processMask(mask, width: w, height: h) { $0.applyingGaussianBlur(sigma: r / 2) }
        case .expand:
            return processMask(mask, width: w, height: h) { $0.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: r]) }
        case .contract:
            return processMask(mask, width: w, height: h) { $0.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: r]) }
        case .smooth:
            return processMask(mask, width: w, height: h) { $0.applyingGaussianBlur(sigma: r / 2) }.map { $0.map { $0 >= 128 ? 255 : 0 } }
        case .border:
            guard let outer = modified(mask, width: w, height: h, .expand, radius: r / 2),
                  let inner = modified(mask, width: w, height: h, .contract, radius: r / 2) else { return nil }
            return zip(outer, inner).map { $0 > $1 ? $0 - $1 : 0 }
        }
    }

    func modifySelection(_ kind: SelectionModify, radius: Double) {
        guard let mask = selectionMask(), let out = Self.modified(mask, width: width, height: height, kind, radius: radius) else { return }
        setSelection(mask: out)
    }

    /// Selects every visible pixel close to the foreground colour (tolerance as for the wand).
    func selectColorRange() {
        guard let image = Renderer.render(layers: composite(layers), width: width, height: height), let b = PixelOps.bitmap(image) else { return }
        let c = color, t = Int(tolerance)
        let target = [Int(c.red * 255), Int(c.green * 255), Int(c.blue * 255)]
        var mask = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let p = i * 4, a = Int(b.bytes[p + 3])
            guard a > 0 else { continue }
            // Bitmap bytes are premultiplied: compare the straight colour.
            var near = true
            for k in 0..<3 where abs(Int(b.bytes[p + k]) * 255 / a - target[k]) > t { near = false; break }
            if near { mask[i] = 255 }
        }
        setSelection(mask: mask)
    }
}

struct SelectionModifyDialog: View {
    @EnvironmentObject private var s: Studio
    @Environment(\.photoTheme) private var theme
    var kind: Studio.SelectionModify
    @AppStorage("selectionModifyRadius") private var radius = 8.0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L(kind.title)).font(.system(size: 23, weight: .bold, design: .rounded))
            HStack {
                Text(L("Radius")).font(.system(size: 11))
                Slider(value: $radius, in: 1...100).controlSize(.small).accessibilityLabel(L("Radius"))
                Text("\(Int(radius)) px").monospacedDigit().frame(width: 52, alignment: .trailing)
            }
            HStack {
                Button(L("Cancel")) { s.selectionDialog = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Apply")) { s.modifySelection(kind, radius: radius.rounded()); s.selectionDialog = nil }
                    .buttonStyle(PhotoButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 400).background(PhotoAmbient())
    }
}
