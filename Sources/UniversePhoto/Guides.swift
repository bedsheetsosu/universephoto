import CoreGraphics
import Foundation

/// A guide line: vertical (x = position) or horizontal (y = position), in document pixels.
struct Guide: Codable, Equatable, Identifiable, Sendable {
    var id = UUID(); var vertical: Bool; var position: Double
}

extension Studio {
    /// Snaps a document point to guides, canvas edges and the canvas centre within `tolerance` px.
    func snappedToGuides(_ p: CGPoint, tolerance: Double) -> CGPoint {
        guard snapToGuides else { return p }
        func nearest(_ v: Double, _ targets: [Double]) -> Double {
            guard let best = targets.min(by: { abs($0 - v) < abs($1 - v) }), abs(best - v) <= tolerance else { return v }
            return best
        }
        let shown = showGuides ? guides : []
        let xs = shown.filter(\.vertical).map(\.position) + [0, Double(width) / 2, Double(width)]
        let ys = shown.filter { !$0.vertical }.map(\.position) + [0, Double(height) / 2, Double(height)]
        return CGPoint(x: nearest(p.x, xs), y: nearest(p.y, ys))
    }

    func addGuide(vertical: Bool, at position: Double) {
        checkpoint("New guide")
        guides.append(Guide(vertical: vertical, position: min(max(0, position.rounded()), Double(vertical ? width : height))))
        showGuides = true; changed()
    }

    /// The guide whose line is within `tolerance` px of a document point, if any.
    func guide(near p: CGPoint, tolerance: Double) -> Guide? {
        guard showGuides, !guidesLocked else { return nil }
        return guides.min { abs(($0.vertical ? p.x : p.y) - $0.position) < abs(($1.vertical ? p.x : p.y) - $1.position) }
            .flatMap { abs(($0.vertical ? p.x : p.y) - $0.position) <= tolerance ? $0 : nil }
    }

    /// Moves a guide; dragged off the canvas it is removed (like dragging it back onto the ruler).
    func moveGuide(_ id: UUID, to position: Double) {
        guard let i = guides.firstIndex(where: { $0.id == id }) else { return }
        let limit = Double(guides[i].vertical ? width : height)
        if position < -4 || position > limit + 4 { guides.remove(at: i) } else { guides[i].position = min(max(0, position.rounded()), limit) }
        changed()
    }

    func clearGuides() { guard !guides.isEmpty else { return }; checkpoint("Clear guides"); guides = []; changed() }

    /// Guides along the selection's edges (or the canvas centre without a selection).
    func guidesFromSelection() {
        checkpoint("New guide")
        if let b = selection?.bounds {
            guides += [Guide(vertical: true, position: b.minX.rounded()), Guide(vertical: true, position: b.maxX.rounded()),
                       Guide(vertical: false, position: b.minY.rounded()), Guide(vertical: false, position: b.maxY.rounded())]
        } else {
            guides += [Guide(vertical: true, position: (Double(width) / 2).rounded()), Guide(vertical: false, position: (Double(height) / 2).rounded())]
        }
        showGuides = true; changed()
    }
}

import SwiftUI

struct NewGuideDialog: View {
    @EnvironmentObject private var s: Studio
    @State private var vertical = true
    @State private var position = 0.0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("New guide")).font(.system(size: 23, weight: .bold, design: .rounded))
            Picker(L("Orientation"), selection: $vertical) { Text(L("Vertical")).tag(true); Text(L("Horizontal")).tag(false) }.pickerStyle(.segmented)
            HStack { Text(L("Position")); TextField("px", value: $position, format: .number).textFieldStyle(.roundedBorder).accessibilityLabel(L("Position")); Text("px") }
            HStack {
                Button(L("Cancel")) { s.guideDialog = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Add")) { s.addGuide(vertical: vertical, at: position); s.guideDialog = false }
                    .buttonStyle(PhotoButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(position < 0 || position > Double(vertical ? s.width : s.height))
            }
        }.padding(28).frame(width: 380).background(PhotoAmbient())
        .onAppear { position = (Double(vertical ? s.width : s.height) / 2).rounded() }
        .onChange(of: vertical) { _, v in position = (Double(v ? s.width : s.height) / 2).rounded() }
    }
}
