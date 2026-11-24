import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct LayerCompTests {
    private func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 20); s.newLayer(); return s
    }

    @Test func applyBringsTheLookBack() {
        let s = studio()
        s.newLayerComp(name: "A")
        let id = s.layers[1].id
        s.layers[1].visible = false; s.layers[1].opacity = 0.3; s.layers[1].transform.x = 12
        #expect(s.currentLayerComp == nil)
        s.applyLayerComp(s.layerComps[0].id)
        let l = s.layers.first { $0.id == id }!
        #expect(l.visible && l.opacity == 1 && l.transform.x == 0)
        #expect(s.currentLayerComp == s.layerComps[0].id)
        s.undo()
        #expect(s.layers.first { $0.id == id }!.opacity == 0.3, "applying is one undo step")
    }

    @Test func newLayersKeepTheirStateAndCompsAreSaved() throws {
        let s = studio()
        s.newLayerComp()
        s.newLayer(); s.layers[s.layers.count - 1].opacity = 0.5
        let newID = s.layers[s.layers.count - 1].id
        s.applyLayerComp(s.layerComps[0].id)
        #expect(s.layers.first { $0.id == newID }!.opacity == 0.5)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).universephoto")
        defer { try? FileManager.default.removeItem(at: url) }
        try s.save(to: url)
        let t = studio()
        try t.open(url)
        #expect(t.layerComps.count == 1 && t.layerComps[0].name == LF("Comp %d", 1))
    }

    @Test func updateRenameDelete() {
        let s = studio()
        s.newLayerComp(name: "A")
        let id = s.layerComps[0].id
        s.layers[0].visible = false
        s.updateLayerComp(id)
        #expect(s.currentLayerComp == id)
        s.renameLayerComp(id, to: "Night"); s.renameLayerComp(id, to: " ")
        #expect(s.layerComps[0].name == "Night")
        s.deleteLayerComp(id)
        #expect(s.layerComps.isEmpty)
        s.undo()
        #expect(s.layerComps.count == 1)
    }
}
