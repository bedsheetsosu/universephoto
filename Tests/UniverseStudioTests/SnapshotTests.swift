import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct SnapshotTests {
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 20); return s
    }

    @Test func restoreComesBackAfterTheHistoryMovedOn() {
        let s = studio()
        s.newLayer()
        s.takeSnapshot()
        let layersAtSnapshot = s.layers.count
        for _ in 0..<70 { s.newLayer() }     // more than the 60 history steps
        #expect(s.layers.count == layersAtSnapshot + 70)
        let id = s.snapshots[0].id
        s.restoreSnapshot(id)
        #expect(s.layers.count == layersAtSnapshot)
        s.undo()
        #expect(s.layers.count == layersAtSnapshot + 70, "restoring is one undo step")
    }

    @Test func snapshotsBelongToTheirTab() {
        let s = studio()
        s.takeSnapshot(name: "A")
        #expect(s.snapshots.map(\.name) == ["A"])
        let first = s.tabID
        s.newDocument(width: 10, height: 10)
        #expect(s.tabID != first && s.snapshots.isEmpty)
        s.switchTab(first)
        #expect(s.snapshots.map(\.name) == ["A"])
        s.renameSnapshot(s.snapshots[0].id, to: "Before colours")
        s.renameSnapshot(s.snapshots[0].id, to: "  ")
        #expect(s.snapshots[0].name == "Before colours")
        s.deleteSnapshot(s.snapshots[0].id)
        #expect(s.snapshots.isEmpty)
    }
}
