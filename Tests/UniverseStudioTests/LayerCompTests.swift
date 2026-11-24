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

@MainActor
struct CropRatioTests {
    @Test func newFrameKeepsTheRatio() {
        let s = Studio(); s.newDocument(width: 1000, height: 800)
        s.cropRatio = .r16x9
        s.cropDrag(.new(CGPoint(x: 100, y: 100)), to: CGPoint(x: 260, y: 130))
        let r = s.cropRect!
        #expect(abs(r.width / r.height - 16.0 / 9) < 0.02 && r.width == 160)
        s.cropPortrait = true
        #expect(abs(s.cropRect!.width / s.cropRect!.height - 9.0 / 16) < 0.03, "swapping refits the open frame")
    }

    @Test func cornerAndSideDragsKeepTheRatio() {
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        // Bottom-right corner: the top-left corner stays.
        let c = Studio.frameDrag(.edge(left: false, right: true, top: false, bottom: true, start), to: CGPoint(x: 500, y: 150), ratio: 2)
        #expect(c == CGRect(x: 100, y: 100, width: 400, height: 200))
        // Top side: width follows, centred.
        let t = Studio.frameDrag(.edge(left: false, right: false, top: true, bottom: false, start), to: CGPoint(x: 0, y: 50), ratio: 2)
        #expect(t == CGRect(x: 50, y: 50, width: 300, height: 150))
    }

    @Test func clampedToTheCanvasStillKeepsTheRatio() {
        let s = Studio(); s.newDocument(width: 400, height: 300)
        s.cropRatio = .square
        s.cropDrag(.new(CGPoint(x: 300, y: 200)), to: CGPoint(x: 600, y: 600))
        let r = s.cropRect!
        #expect(r.width == r.height && CGRect(x: 0, y: 0, width: 400, height: 300).contains(r))
        #expect(Studio.fit(2, in: CGRect(x: 0, y: 0, width: 100, height: 100)) == CGRect(x: 0, y: 25, width: 100, height: 50))
    }
}
