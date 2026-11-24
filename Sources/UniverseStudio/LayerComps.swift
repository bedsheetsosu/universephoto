import SwiftUI

/// Layer comps: remember how the layers look (visible, opacity, blend, position, style) under a
/// name and switch between versions of a design. Saved in the document; every change is one
/// undo step. Layers added later keep their state when a comp is applied.
extension Studio {
    func captureStates() -> [UUID: LayerComp.State] {
        Dictionary(uniqueKeysWithValues: layers.map { ($0.id, LayerComp.State(visible: $0.visible, opacity: $0.opacity, blend: $0.blend, transform: $0.transform, style: $0.style)) })
    }

    func newLayerComp(name: String? = nil) {
        checkpoint("New layer comp")
        layerComps.append(LayerComp(name: name ?? LF("Comp %d", layerComps.count + 1), states: captureStates()))
        changed()
    }

    func applyLayerComp(_ id: UUID) {
        guard let comp = layerComps.first(where: { $0.id == id }), !isPlaying else { return }
        checkpoint("Apply layer comp")
        for i in layers.indices { if let st = comp.states[layers[i].id] {
            layers[i].visible = st.visible; layers[i].opacity = st.opacity; layers[i].blend = st.blend
            layers[i].transform = st.transform; layers[i].style = st.style
        } }
        changed()
    }

    /// Stores the current look in an existing comp.
    func updateLayerComp(_ id: UUID) {
        guard let i = layerComps.firstIndex(where: { $0.id == id }) else { return }
        checkpoint("Update layer comp"); layerComps[i].states = captureStates(); changed()
    }
    func deleteLayerComp(_ id: UUID) { checkpoint("Delete layer comp"); layerComps.removeAll { $0.id == id }; changed() }
    func renameLayerComp(_ id: UUID, to name: String) {
        guard let i = layerComps.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        checkpoint("Rename layer comp"); layerComps[i].name = name; changed()
    }
    /// The comp matching the layers right now, if any (shown as current).
    var currentLayerComp: UUID? {
        let now = captureStates()
        return layerComps.first { comp in comp.states.allSatisfy { id, st in now[id].map { $0 == st } ?? true } && !comp.states.isEmpty }?.id
    }
}

struct LayerCompList: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @State private var editing: UUID?
    @State private var draft = ""

    var body: some View {
        let current = s.currentLayerComp
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.stack.3d.down.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent)
                Text(L("Layer comps")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { withAnimation(PhotoMotion.select) { s.newLayerComp() } } label: { Image(systemName: "plus").frame(width: 14) }
                    .buttonStyle(PhotoButtonStyle()).help(L("New layer comp") + " – " + L("Remember visibility, opacity, blend mode, position and style of all layers")).accessibilityLabel(L("New layer comp"))
            }
            if s.layerComps.isEmpty {
                Text(L("Switch between versions of a design, saved with the document.")).font(.system(size: 10)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(s.layerComps) { comp in
                HStack(spacing: 8) {
                    Image(systemName: comp.id == current ? "circle.inset.filled" : "circle").font(.system(size: 10)).foregroundStyle(comp.id == current ? theme.accent : theme.secondary)
                    if editing == comp.id {
                        TextField("", text: $draft).textFieldStyle(.roundedBorder).controlSize(.small).onSubmit { s.renameLayerComp(comp.id, to: draft); editing = nil }
                    } else {
                        Button { withAnimation(PhotoMotion.select) { s.applyLayerComp(comp.id) } } label: { Text(comp.name).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                            .buttonStyle(.plain).help(L("Apply this comp"))
                    }
                    Menu {
                        Button(L("Update from current layers")) { s.updateLayerComp(comp.id) }
                        Button(L("Rename…")) { draft = comp.name; editing = comp.id }
                        Button(L("Delete"), role: .destructive) { withAnimation(PhotoMotion.select) { s.deleteLayerComp(comp.id) } }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }.padding(.vertical, 3).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }.photoCard()
    }
}
