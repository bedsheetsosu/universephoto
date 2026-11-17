import Foundation
import CoreGraphics

/// Layer groups (folders) and selecting several layers.
extension Studio {
    /// Layers as they are composited: a hidden group hides its layers, the group's opacity
    /// multiplies theirs (like Photoshop's "pass through" groups, per layer).
    func composite(_ stack: [ArtLayer]) -> [ArtLayer] {
        guard !groups.isEmpty else { return stack }
        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        return stack.map { layer in
            guard let id = layer.groupID, let g = byID[id] else { return layer }
            var l = layer
            if !g.visible { l.visible = false }
            l.opacity *= g.opacity
            return l
        }
    }

    /// The layers a command acts on: every selected layer, at least the active one (bottom to top).
    var selectedIndices: [Int] {
        var ids = selectedIDs
        if let active = activeLayer?.id { ids.insert(active) }
        return layers.indices.filter { ids.contains(layers[$0].id) }
    }

    /// Click in the layer list: plain = only this one, ⌘ = add/remove, ⇧ = range from the active one.
    func selectLayer(_ index: Int, command: Bool = false, shift: Bool = false) {
        guard layers.indices.contains(index) else { return }
        let id = layers[index].id
        if shift, layers.indices.contains(selectedLayer) {
            let range = min(index, selectedLayer)...max(index, selectedLayer)
            selectedIDs = Set(range.map { layers[$0].id })
        } else if command {
            var ids = selectedIDs
            if let active = activeLayer?.id { ids.insert(active) }
            if ids.contains(id) && ids.count > 1 { ids.remove(id) } else { ids.insert(id) }
            selectedIDs = ids
            if !ids.contains(id), let other = layers.lastIndex(where: { ids.contains($0.id) }) { selectedLayer = other; maskEditing = false; return }
        } else {
            selectedIDs = []
        }
        selectedLayer = index; maskEditing = false
    }

    func group(of layer: ArtLayer?) -> LayerGroup? {
        guard let id = layer?.groupID else { return nil }
        return groups.first { $0.id == id }
    }

    /// Puts the selected layers into a new group, gathered right below the top-most one, order kept.
    func groupSelected() {
        guard !isPlaying else { return }
        let picked = selectedIndices
        guard !picked.isEmpty, let top = picked.last else { return }
        checkpoint("Group layers")
        let g = LayerGroup(name: L("Group") + " \(groups.count + 1)")
        var moving = picked.map { layers[$0] }
        for i in moving.indices { moving[i].groupID = g.id }
        let below = picked.filter { $0 < top }.count           // removed layers under the insertion point
        for i in picked.reversed() { layers.remove(at: i) }
        let insertAt = top - below
        layers.insert(contentsOf: moving, at: insertAt)
        groups.append(g)
        selectedLayer = insertAt + moving.count - 1
        selectedIDs = Set(moving.map(\.id))
        pruneGroups(); changed()
    }

    /// Dissolves the active layer's group; its layers stay where they are.
    func ungroup() {
        guard let g = group(of: activeLayer) else { return }
        checkpoint("Ungroup")
        for i in layers.indices where layers[i].groupID == g.id { layers[i].groupID = nil }
        for f in frames.indices { for i in frames[f].indices where frames[f][i].groupID == g.id { frames[f][i].groupID = nil } }
        groups.removeAll { $0.id == g.id }
        changed()
    }

    func updateGroup(_ id: UUID, _ label: String, _ body: (inout LayerGroup) -> Void) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        checkpoint(label)
        body(&groups[i])
        changed()
    }

    /// Selects every layer of a group (click on its header).
    func selectGroup(_ id: UUID) {
        let members = layers.indices.filter { layers[$0].groupID == id }
        guard let top = members.last else { return }
        selectedLayer = top; selectedIDs = Set(members.map { layers[$0].id }); maskEditing = false
    }

    /// Drops groups no layer (in any frame) belongs to any more.
    func pruneGroups() {
        guard !groups.isEmpty else { return }
        var used = Set(layers.compactMap(\.groupID))
        for f in frames { used.formUnion(f.compactMap(\.groupID)) }
        groups.removeAll { !used.contains($0.id) }
    }

    // MARK: Moving several layers

    /// Start of a move: remembers the transforms of every selected, unlocked layer.
    func beginMove() -> [UUID: LayerTransform] {
        var out: [UUID: LayerTransform] = [:]
        for i in selectedIndices where !layers[i].locked { out[layers[i].id] = layers[i].transform }
        return out
    }

    func move(_ start: [UUID: LayerTransform], by delta: CGSize) {
        for i in layers.indices { if let t = start[layers[i].id] { layers[i].transform.x = t.x + delta.width; layers[i].transform.y = t.y + delta.height } }
    }
}
