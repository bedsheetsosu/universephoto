import AppKit
import CoreText

/// Editing placed text: with the text tool a click on existing text on the active layer picks it,
/// its settings move into the options bar, and changes there rewrite that text (one undo step
/// per burst of changes). Esc or another tool ends the editing.
extension Renderer {
    /// Bounds of a text stroke in layer pixels.
    static func textBounds(_ stroke: InkStroke) -> CGRect {
        guard let first = stroke.points.first else { return .null }
        var box = CGRect.null
        for row in textLines(stroke, at: CGPoint(x: first.x, y: first.y)) {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let w = CTLineGetTypographicBounds(row.line, &ascent, &descent, nil)
            box = box.union(CGRect(x: row.x, y: row.baseline - ascent, width: max(w, 1), height: ascent + descent))
        }
        return box
    }
}

/// What the options bar shows for text; a change rewrites the edited text.
struct TextEditKey: Hashable {
    var text: String; var family: String; var bold: Bool; var italic: Bool; var size: Double
    var color: CodableColor; var opacity: Double; var align: TextAlign; var tracking: Double; var spacing: Double
}

extension Studio {
    var textEditKey: TextEditKey {
        TextEditKey(text: textContent, family: fontFamily, bold: textBold, italic: textItalic, size: brushSize, color: color,
                    opacity: brushOpacity, align: textAlign, tracking: textTracking, spacing: textLineSpacing)
    }

    /// The topmost text on the active layer under `p` (document pixels).
    func textStroke(at p: CGPoint) -> InkStroke? {
        guard let layer = activeLayer else { return nil }
        let local = p.applying(matrix(layer.transform).inverted())
        return layer.strokes.reversed().first { $0.kind == "text" && Renderer.textBounds($0).insetBy(dx: -4, dy: -4).contains(local) }
    }

    /// Picks the text under `p` for editing; false when there is none.
    @discardableResult func beginTextEdit(at p: CGPoint) -> Bool {
        guard canEdit, let stroke = textStroke(at: p) else { editingText = nil; return false }
        editingText = nil   // no rewrite while the settings are loaded
        textContent = stroke.text ?? ""
        let font = stroke.fontName.flatMap { NSFont(name: $0, size: 12) }
        if let family = font?.familyName { fontFamily = family }
        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        textBold = traits.contains(.boldFontMask); textItalic = traits.contains(.italicFontMask)
        brushSize = stroke.width
        var c = stroke.color; brushOpacity = max(0.05, c.alpha); c.alpha = 1; color = c
        textAlign = TextAlign(rawValue: stroke.textAlign ?? "") ?? .left
        textTracking = stroke.tracking ?? 0; textLineSpacing = stroke.lineSpacing ?? 1.2
        editingText = stroke.id
        return true
    }

    /// Writes the options bar's text settings into the edited text.
    func syncEditedText() {
        guard let id = editingText, canEdit, let i = activeLayer?.strokes.firstIndex(where: { $0.id == id }) else { return }
        var s = layers[selectedLayer].strokes[i]
        s.text = textContent
        s.fontName = NSFontManager.shared.font(withFamily: fontFamily, traits: NSFontTraitMask(rawValue: (textBold ? NSFontTraitMask.boldFontMask.rawValue : 0) | (textItalic ? NSFontTraitMask.italicFontMask.rawValue : 0)), weight: 5, size: 12)?.fontName ?? s.fontName
        s.width = max(10, brushSize)
        var c = color; c.alpha *= brushOpacity; s.color = c
        s.textAlign = textAlign == .left ? nil : textAlign.rawValue
        s.tracking = textTracking == 0 ? nil : textTracking
        s.lineSpacing = abs(textLineSpacing - 1.2) < 0.01 ? nil : textLineSpacing
        guard s != layers[selectedLayer].strokes[i] else { return }
        mutateLayer("Edit text") { $0.strokes[i] = s }
    }
}
