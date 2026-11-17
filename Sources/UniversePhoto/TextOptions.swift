import AppKit
import SwiftUI

/// Text tool extras: several lines, alignment, tracking, line spacing, italic.
enum TextAlign: String, CaseIterable, Sendable {
    case left, center, right
    var symbol: String { switch self { case .left: "text.alignleft"; case .center: "text.aligncenter"; case .right: "text.alignright" } }
    var title: String { switch self { case .left: "Align left"; case .center: "Align center"; case .right: "Align right" } }
}

extension Renderer {
    /// Lines of a text stroke: each line's CTLine and its left x, anchored at `origin` (y down, top of the first line).
    static func textLines(_ stroke: InkStroke, at origin: CGPoint) -> [(line: CTLine, x: Double, baseline: Double)] {
        let size = max(6, stroke.width)
        let font = CTFontCreateWithName((stroke.fontName ?? "Helvetica") as CFString, size, nil)
        var attr: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                   NSAttributedString.Key(kCTForegroundColorAttributeName as String): stroke.color.cgColor]
        if let t = stroke.tracking, t != 0 { attr[NSAttributedString.Key(kCTKernAttributeName as String)] = t * size / 1000 }
        let spacing = size * max(0.5, stroke.lineSpacing ?? 1.2)
        let align = TextAlign(rawValue: stroke.textAlign ?? "") ?? .left
        let rows = (stroke.text ?? "").components(separatedBy: .newlines)
        return rows.enumerated().map { i, row in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: row, attributes: attr))
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            let x = align == .left ? origin.x : align == .center ? origin.x - w / 2 : origin.x - w
            // First baseline one font size below the click, like before 0.18.
            return (line, x, origin.y + size + Double(i) * spacing)
        }
    }
}

/// Popover of the options bar with the text editor and the paragraph settings.
struct TextOptionsPopover: View {
    @EnvironmentObject private var s: Studio
    @Environment(\.photoTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Text")).font(.system(size: 13, weight: .semibold))
            TextEditor(text: $s.textContent).font(.system(size: 12)).frame(width: 260, height: 90).scrollContentBackground(.hidden)
                .padding(6).background(theme.deep.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel(L("Text"))
            HStack {
                Picker(L("Alignment"), selection: $s.textAlign) { ForEach(TextAlign.allCases, id: \.self) { Image(systemName: $0.symbol).help(L($0.title)).accessibilityLabel(L($0.title)).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 120)
                Spacer()
                Toggle(L("Bold"), isOn: $s.textBold).toggleStyle(.checkbox)
                Toggle(L("Italic"), isOn: $s.textItalic).toggleStyle(.checkbox)
            }
            row(L("Tracking"), $s.textTracking, -200...800, "")
            row(L("Line spacing"), $s.textLineSpacing, 0.6...3, "×", decimals: true)
        }.padding(16).font(.system(size: 11))
    }

    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ suffix: String, decimals: Bool = false) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Slider(value: value, in: range).controlSize(.small).accessibilityLabel(title)
            Text(decimals ? String(format: "%.1f%@", value.wrappedValue, suffix) : "\(Int(value.wrappedValue))\(suffix)").monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }
}
