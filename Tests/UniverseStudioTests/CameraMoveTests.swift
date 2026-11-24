import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct CameraMoveTests {
    func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 200, height: 100, background: .white)
        return s
    }

    @Test func cameraComposesWithLayerTransform() {
        var l = ArtLayer(name: "A"); l.transform.x = 10; l.transform.scale = 2
        let m = CameraMove.apply(l, zoom: 1.5, dx: 4, dy: -2)
        #expect(m.transform.x == 19 && m.transform.y == -2 && m.transform.scale == 3)
        var adj = ArtLayer(name: "Adj"); adj.adjustsBelow = true
        #expect(CameraMove.apply(adj, zoom: 2, dx: 5, dy: 5).transform.scale == 1)
    }

    @Test func pansStayInsideAndShakeLoops() {
        for c in [CameraMove.panLeft, .panRight, .panUp, .panDown] {
            for t in [0.0, 0.5, 1.0] {
                let cam = c.camera(t, w: 200, h: 100)
                #expect(abs(cam.dx) <= 200 * (cam.zoom - 1) / 2 && abs(cam.dy) <= 100 * (cam.zoom - 1) / 2)
            }
        }
        #expect(CameraMove.zoomIn.camera(0, w: 1, h: 1).zoom == 1 && CameraMove.zoomIn.camera(1, w: 1, h: 1).zoom == 1.25)
        #expect(CameraMove.shake.steps(4) == [0, 0.25, 0.5, 0.75])
    }

    @Test func makesFramesOrRunsOverExistingOnes() {
        let s = studio()
        #expect(s.cameraMove(.zoomIn, count: 5) == 5)
        let scales = s.document().frames.map { $0[1].transform.scale }
        #expect(scales.first == 1 && scales.last == 1.25)
        #expect(s.cameraMove(.panRight, count: 0) == 5)
        #expect(s.document().frames[0][1].transform.x != 0)
        s.undo(); s.undo()
        #expect(s.cameraMove(.shake, count: 0) == 0)
    }
}
