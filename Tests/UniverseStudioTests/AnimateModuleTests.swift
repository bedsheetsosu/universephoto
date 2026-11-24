import Testing
import Foundation
@testable import UniverseStudio

@MainActor
struct AnimateModuleTests {
    func studio() -> Studio {
        let s = Studio(recoveryRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        s.newDocument(width: 40, height: 30, background: .white); s.module = .photo
        return s
    }

    @Test func pushMakesAnimationThenAddsFrames() {
        let s = studio()
        let photoID = s.tabID
        s.layers[1].strokes = [InkStroke(points: [InkPoint(x: 1, y: 1, pressure: 1), InkPoint(x: 9, y: 9, pressure: 1)], color: .black, width: 3)]
        s.changed()
        #expect(s.push(asNew: s.returnTab(animate: true) == nil))
        #expect(s.module == .animate && s.currentTabIsAnimation && s.tabID != photoID)
        #expect(s.layers.count == 2 && s.layers[1].strokes.count == 1 && s.dirty)
        // Back to Photo: the photo document is there again, the animation stays open.
        s.enter(.photo)
        #expect(s.tabID == photoID && !s.currentTabIsAnimation && s.tabs(animate: true).count == 1)
        #expect(s.push(asNew: s.returnTab(animate: true) == nil))
        #expect(s.tabs(animate: true).count == 1 && s.document().frames.count == 2 && s.frameIndex == 1)
    }

    @Test func pushBackToPhotoAsLayerOrPicture() {
        let s = studio()
        let photoID = s.tabID
        #expect(s.push(asNew: true))
        #expect(s.returnTab(animate: false)?.id == photoID)
        #expect(s.push(asNew: false))
        #expect(s.module == .photo && s.tabID == photoID && s.layers.count == 3 && s.layers[2].imageData != nil)
        let before = s.tabs(animate: false).count
        s.enter(.animate)
        #expect(s.push(asNew: true))
        #expect(s.module == .photo && s.tabs(animate: false).count == before + 1)
    }

    @Test func modulesKeepTheirDocumentsApart() {
        let s = studio()
        s.enter(.animate)
        #expect(s.currentTabIsAnimation && s.tabs(animate: true).count == 1)
        let anim = s.tabID
        s.newDocument()
        #expect(s.tabs(animate: true).count == 2)
        s.closeTab(s.tabID)
        #expect(s.tabID == anim)
        s.closeTab(anim)
        #expect(s.currentTabIsAnimation && s.tabs(animate: true).count == 1)
        s.enter(.photo)
        #expect(!s.currentTabIsAnimation)
    }

    @Test func animateComesWithPhoto() {
        #expect(ModuleSettings.enabled("photo") == [.photo, .animate])
        #expect(ModuleSettings.enabled("photo,pen,!animate") == [.photo, .pen])
        #expect(ModuleSettings.store([.photo, .pen]) == "photo,pen,!animate")
        #expect(ModuleSettings.enabled(ModuleSettings.store([.animate])) == [.animate])
    }
}
