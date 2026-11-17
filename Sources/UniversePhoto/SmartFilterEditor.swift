import SwiftUI

/// The active layer's smart filter stack: add from a grouped menu, switch off, reorder, remove.
struct SmartFilterEditor: View {
    @Environment(\.photoTheme) private var theme
    var filters: [SmartFilter]
    var set: ([SmartFilter]) -> Void

    private static let groups = ["Blur & sharpen", "Stylize", "Distort", "Colour looks"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Smart filters").uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(theme.secondary)
                Spacer()
                Menu {
                    ForEach(Self.groups, id: \.self) { group in
                        Section(L(group)) {
                            ForEach(SmartFilter.Kind.allCases.filter { $0.group == group }, id: \.self) { kind in
                                Button(L(kind.title)) { withAnimation(PhotoMotion.panel) { set(filters + [SmartFilter(kind: kind)]) } }
                            }
                        }
                    }
                } label: { Label(L("Add filter"), systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
            }
            if filters.isEmpty {
                Text(L("Filters stay editable: switch them off, reorder or remove them at any time.")).font(.system(size: 10)).foregroundStyle(theme.secondary).lineSpacing(3)
            }
            ForEach(Array(filters.enumerated()), id: \.element.id) { i, f in row(i, f) }
        }
    }

    private func row(_ i: Int, _ f: SmartFilter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { update(i) { $0.enabled.toggle() } } label: { Image(systemName: f.enabled ? "eye" : "eye.slash").frame(width: 16) }
                    .buttonStyle(PhotoPress()).foregroundStyle(f.enabled ? theme.accent : theme.secondary)
                    .help(L(f.enabled ? "Hide filter" : "Show filter")).accessibilityLabel(L(f.enabled ? "Hide filter" : "Show filter"))
                Text(L(f.kind.title)).font(.system(size: 11, weight: .medium)).foregroundStyle(f.enabled ? theme.text : theme.secondary)
                Spacer()
                Button { move(i, by: -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(PhotoPress()).disabled(i == 0)
                    .help(L("Move up")).accessibilityLabel(L("Move up"))
                Button { move(i, by: 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(PhotoPress()).disabled(i == filters.count - 1)
                    .help(L("Move down")).accessibilityLabel(L("Move down"))
                Button { withAnimation(PhotoMotion.panel) { var l = filters; l.remove(at: i); set(l) } } label: { Image(systemName: "xmark") }
                    .buttonStyle(PhotoPress()).help(L("Remove filter")).accessibilityLabel(L("Remove filter"))
            }.font(.system(size: 10))
            if let range = f.kind.range {
                Slider(value: Binding(get: { f.amount }, set: { v in update(i) { $0.amount = v } }), in: range)
                    .controlSize(.mini).disabled(!f.enabled).accessibilityLabel(L(f.kind.title))
            }
        }
        .padding(8).background(theme.deep.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func update(_ i: Int, _ change: (inout SmartFilter) -> Void) {
        guard filters.indices.contains(i) else { return }
        var l = filters; change(&l[i]); set(l)
    }

    private func move(_ i: Int, by d: Int) {
        let j = i + d
        guard filters.indices.contains(i), filters.indices.contains(j) else { return }
        var l = filters; l.swapAt(i, j)
        withAnimation(PhotoMotion.select) { set(l) }
    }
}
