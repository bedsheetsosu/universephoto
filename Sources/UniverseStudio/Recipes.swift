import Foundation

/// Animation → Effects → Recipes (0.199): one click, a whole little animation – several layer
/// effects stacked on the active layer, as one undo step. From a single frame the frames are made
/// first (2 s); on an animation they play over the play range (or all frames).
enum Recipe: String, CaseIterable, Identifiable {
    case bouncingEntrance, popTitle, windUpExit, happyIdle, dropAndShake
    var id: String { rawValue }
    var title: String { switch self {
        case .bouncingEntrance: "Bouncing entrance"; case .popTitle: "Pop-in title"; case .windUpExit: "Wind-up exit"
        case .happyIdle: "Happy idle"; case .dropAndShake: "Heavy drop" } }
    var symbol: String { switch self {
        case .bouncingEntrance: "figure.run"; case .popTitle: "textformat.size.larger"; case .windUpExit: "arrow.right.to.line"
        case .happyIdle: "face.smiling"; case .dropAndShake: "arrow.down.to.line" } }
    var hint: String { switch self {
        case .bouncingEntrance: "Hops in from the left with squash, stretch, dust and a shadow"
        case .popTitle: "Pops up with an overshoot, fades in and wobbles"
        case .windUpExit: "Winds up, then shoots off to the right with speed lines"
        case .happyIdle: "Breathes and bobs gently as a loop"
        case .dropAndShake: "Falls in from above, squashes and shakes the picture" } }
}

extension Studio {
    @discardableResult func applyRecipe(_ r: Recipe) -> Bool {
        guard let id = activeLayer?.id, activeLayer?.allFrames != true else { return false }
        let start = undoStack.count
        if frames.count < 2 { extendAnimation(by: max(2, Int((fps * 2).rounded()) - 1)); playRange = nil }
        selectedLayer = layers.firstIndex { $0.id == id } ?? selectedLayer
        let w = Double(width), h = Double(height)
        switch r {
        case .bouncingEntrance:
            travelLayer(dx: w * 0.6, dy: 0, eased: false)
            shiftLayerAllFrames(dx: -w * 0.6, dy: 0)
            bounceWithSquash(height: h * 0.3, bounces: 3)
            addLandingDust()
            addGroundShadow()
        case .popTitle:
            growLayerOverFrames(grow: true, pop: true)
            fadeLayerOverFrames(fadeIn: true)
            stretchEffect(jelly: true, amount: 0.15)
        case .windUpExit:
            travelLayer(dx: w * 1.2, dy: 0, eased: false)
            easeLayerMotion(.anticipate)
            addSpeedLines()
        case .happyIdle:
            stretchEffect(jelly: false, amount: 0.05)
            floatLayer(amplitude: 8, horizontal: false)
        case .dropAndShake:
            // The fall takes the first 60 %, so there are frames after the landing to squash and shake in.
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            playRange = all.lowerBound...(all.lowerBound + max(2, Int(Double(all.count - 1) * 0.6)))
            travelLayer(dx: 0, dy: h * 0.7, eased: false)
            shiftLayerAllFrames(dx: 0, dy: -h * 0.7)
            easeLayerMotion(.slowIn)
            playRange = saved
            squashStretch(amount: 1.4)
            impactShake(strength: 10)
        }
        selectedLayer = layers.firstIndex { $0.id == id } ?? selectedLayer
        guard undoStack.count > start else { return false }
        if undoStack.count > start + 1 { undoStack.removeSubrange((start + 1)...) }    // one undo step
        if let i = undoStack.indices.last { undoStack[i].label = r.title }
        return true
    }
}
