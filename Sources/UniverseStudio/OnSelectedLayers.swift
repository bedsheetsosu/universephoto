import Foundation

/// Layer effects on every selected layer (0.192): runs a one-layer effect once per selected layer
/// (each in turn as the active one) and folds the undo steps into one. With a single layer
/// selected – or when the active layer isn't part of the selection – it just runs on the active
/// layer as before. The active layer stays active afterwards.
extension Studio {
    @discardableResult func onSelectedLayers(_ effect: @escaping () -> Int) -> Int {
        let total = runOnSelectedLayers(effect)
        if total > 0 { lastEffect = effect; lastEffectLabel = undoStack.last?.label }
        return total
    }

    /// Animation → Repeat last effect (0.230): the last layer effect or layer motion again – on the
    /// layers selected now and the current play range, so it can be stacked or moved on quickly.
    @discardableResult func repeatLastEffect() -> Int {
        guard let effect = lastEffect else { return 0 }
        return onSelectedLayers(effect)
    }

    private func runOnSelectedLayers(_ effect: () -> Int) -> Int {
        // Layers marked "Same in all frames" are one drawing for every frame: a per-frame effect
        // would collapse to the current frame's version, so they are left out (0.198).
        guard let active = activeLayer?.id else { return 0 }
        let ids = layers.filter { selectedIDs.contains($0.id) && $0.allFrames != true }.map(\.id)
        guard ids.count > 1, ids.contains(active) else { return activeLayer?.allFrames == true ? 0 : effect() }
        let start = undoStack.count, keepIDs = selectedIDs
        var total = 0
        for id in ids {
            guard let i = layers.firstIndex(where: { $0.id == id }) else { continue }
            selectedLayer = i
            total += effect()
        }
        selectedLayer = layers.firstIndex { $0.id == active } ?? selectedLayer
        selectedIDs = keepIDs
        if undoStack.count > start + 1 { undoStack.removeSubrange((start + 1)...) }   // one step for all
        return total
    }
}
