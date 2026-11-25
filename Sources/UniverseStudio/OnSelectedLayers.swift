import Foundation

/// Layer effects on every selected layer (0.192): runs a one-layer effect once per selected layer
/// (each in turn as the active one) and folds the undo steps into one. With a single layer
/// selected – or when the active layer isn't part of the selection – it just runs on the active
/// layer as before. The active layer stays active afterwards.
extension Studio {
    @discardableResult func onSelectedLayers(_ effect: () -> Int) -> Int {
        guard let active = activeLayer?.id else { return 0 }
        let ids = layers.map(\.id).filter { selectedIDs.contains($0) }
        guard ids.count > 1, ids.contains(active) else { return effect() }
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
