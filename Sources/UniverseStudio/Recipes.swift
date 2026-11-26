import Foundation

/// Animation → Effects → Recipes (0.199): one click, a whole little animation – several layer
/// effects stacked on the active layer, as one undo step. From a single frame the frames are made
/// first (2 s); on an animation they play over the play range (or all frames).
enum Recipe: String, CaseIterable, Identifiable {
    case bouncingEntrance, popTitle, windUpExit, happyIdle, dropAndShake, magicItem, hangingSign, walkBy, peekaboo, rocketLaunch, sleepy, inLove, nervous, angry, surprised, stormyNight, snowyEvening, bouncyTitle, partyTitle, titleInOut, pondering, greeting, callForHelp, dizzy, brightIdea, sad, shy, tadaTitle
    var id: String { rawValue }
    /// Menu groups (0.239): ins and outs, loops, feelings.
    static let groups: [(title: String, recipes: [Recipe])] = [
        ("Ins & outs", [.bouncingEntrance, .popTitle, .walkBy, .peekaboo, .dropAndShake, .windUpExit, .rocketLaunch]),
        ("Loops", [.happyIdle, .magicItem, .hangingSign, .sleepy]),
        ("Feelings", [.inLove, .nervous, .angry, .surprised, .pondering, .dizzy, .brightIdea, .sad, .shy]),
        ("Talking", [.greeting, .callForHelp]),
        ("Text", [.bouncyTitle, .partyTitle, .titleInOut, .tadaTitle]),
        ("Scenes", [.stormyNight, .snowyEvening]),
    ]
    var title: String { switch self {
        case .bouncingEntrance: "Bouncing entrance"; case .popTitle: "Pop-in title"; case .windUpExit: "Wind-up exit"
        case .happyIdle: "Happy idle"; case .dropAndShake: "Heavy drop"
        case .magicItem: "Magic item"; case .hangingSign: "Hanging sign"; case .walkBy: "Walking by"; case .peekaboo: "Peek-a-boo"; case .rocketLaunch: "Rocket launch"
        case .sleepy: "Sleepy"; case .inLove: "In love"; case .nervous: "Nervous"
        case .angry: "Angry"; case .surprised: "Surprised"; case .pondering: "Pondering"; case .dizzy: "Dizzy"; case .brightIdea: "Bright idea"; case .sad: "Sad"; case .shy: "Shy"
        case .stormyNight: "Stormy night"; case .snowyEvening: "Snowy evening"
        case .bouncyTitle: "Bouncy title"; case .partyTitle: "Party title"; case .titleInOut: "Title in & out"; case .tadaTitle: "Ta-da title"
        case .greeting: "Greeting"; case .callForHelp: "Call for help" } }
    var symbol: String { switch self {
        case .bouncingEntrance: "figure.run"; case .popTitle: "textformat.size.larger"; case .windUpExit: "arrow.right.to.line"
        case .happyIdle: "face.smiling"; case .dropAndShake: "arrow.down.to.line"
        case .magicItem: "sparkles"; case .hangingSign: "lightbulb"; case .walkBy: "figure.walk"; case .peekaboo: "eyes"; case .rocketLaunch: "airplane.departure"
        case .sleepy: "moon.zzz"; case .inLove: "heart"; case .nervous: "exclamationmark.bubble"
        case .angry: "flame"; case .surprised: "exclamationmark"; case .pondering: "bubble.left"; case .dizzy: "star.circle"; case .brightIdea: "lightbulb.max"; case .sad: "drop"; case .shy: "face.smiling.inverse"
        case .stormyNight: "cloud.bolt.rain"; case .snowyEvening: "cloud.snow"
        case .bouncyTitle: "textformat"; case .partyTitle: "party.popper"; case .titleInOut: "arrow.up.and.down.text.horizontal"; case .tadaTitle: "sun.max"
        case .greeting: "hand.wave"; case .callForHelp: "megaphone" } }
    var hint: String { switch self {
        case .bouncingEntrance: "Hops in from the left with squash, stretch, dust and a shadow"
        case .popTitle: "Pops up with an overshoot, fades in and wobbles"
        case .windUpExit: "Winds up, then shoots off to the right with speed lines"
        case .happyIdle: "Breathes and bobs gently as a loop"
        case .dropAndShake: "Falls in from above, squashes, freezes for a beat and shakes the picture"
        case .magicItem: "Floats gently with twinkling sparkles around it"
        case .hangingSign: "Swings from its top like a sign or lamp in the wind"
        case .walkBy: "Walks across the picture from left to right, bobbing with every step"
        case .peekaboo: "Rises up from its bottom edge, looks around for a moment and ducks back down"
        case .rocketLaunch: "Rumbles, then shoots up and out of the picture faster and faster, trailing smoke"
        case .sleepy: "Breathes slowly while Z's float up – a loop"
        case .inLove: "Heart beating, little hearts rising – a loop"
        case .nervous: "Trembles a little while sweat drops run down – a loop"
        case .angry: "Shakes with rage, a throbbing vein beside it"
        case .surprised: "Jumps with a start, a big ! pops up"
        case .shy: "Sways bashfully from side to side while its cheeks blush"
        case .sad: "Sinks a little and breathes slowly while tears roll down"
        case .brightIdea: "Perks up with a little hop as a light bulb pops on above it"
        case .dizzy: "Wobbles in a little circle while stars circle above its head"
        case .pondering: "Tilts slowly from side to side while a thought bubble fills with dots"
        case .stormyNight: "Night falls, rain pours, lightning flashes – the whole picture"
        case .snowyEvening: "Snow falls in a warm evening light – the whole picture"
        case .bouncyTitle: "Pops in, then its letters hop one after another"
        case .partyTitle: "Letters wave in running rainbow colours while it bobs"
        case .tadaTitle: "Letters pop in one by one in front of turning rays, with sparkles"
        case .titleInOut: "Letters drop in one by one, the title stays, then they fly apart"
        case .greeting: "A little hop, then a speech bubble says the Text tool's text (or Hello!)"
        case .callForHelp: "Trembles while a shout bubble yells the Text tool's text" } }
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
        case .magicItem:
            floatLayer(amplitude: 10, horizontal: false)
            addSparkles(count: 6)
        case .hangingSign:
            swayLayer(degrees: 14, hanging: true)
        case .walkBy:
            travelLayer(dx: w * 1.2, dy: 0, eased: false)
            shiftLayerAllFrames(dx: -w * 0.6, dy: 0)
            walkBob(steps: 6, height: max(3, h * 0.02), tilt: 4)
            addGroundShadow()
            addFootprints(every: max(2, (Playback.clamp(playRange, count: frames.count)?.count ?? frames.count) / 6))
        case .sleepy:
            stretchEffect(jelly: false, amount: 0.06)
            addFloatingSymbols(.sleep, count: 3)
        case .inLove:
            scalePulseLayer(amount: 0.12, heartbeat: true)
            addFloatingSymbols(.hearts, count: 3)
        case .bouncyTitle:
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            let popEnd = all.lowerBound + max(2, all.count / 4)
            if popEnd < all.upperBound { playRange = all.lowerBound...popEnd; growLayerOverFrames(grow: true, pop: true) }
            playRange = saved
            wavyText(hop: true)
        case .tadaTitle:
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            let popEnd = all.lowerBound + max(2, all.count / 2)
            if popEnd <= all.upperBound {
                playRange = all.lowerBound...popEnd
                if activeLayer?.strokes.contains(where: { $0.kind == "text" }) == true { lettersPopIn() } else { growLayerOverFrames(grow: true, pop: true) }
            }
            playRange = saved
            addRayBurst(rays: 16)
            addSparkles(count: 5)
        case .titleInOut:
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            let mid = all.lowerBound + max(2, all.count * 2 / 5)
            let hasText = activeLayer?.strokes.contains { $0.kind == "text" } == true
            if mid < all.upperBound - 1 {
                // Without text the layer as a whole pops in and bursts at the end.
                playRange = all.lowerBound...mid
                if hasText { lettersDropIn() } else { growLayerOverFrames(grow: true, pop: true) }
                playRange = mid...all.upperBound
                if hasText { lettersScatter() } else { popAway(.confetti) }
            } else if hasText { lettersDropIn() } else { growLayerOverFrames(grow: true, pop: true) }
            playRange = saved
        case .partyTitle:
            wavyText(hop: false)
            rainbowLetters()
            floatLayer(amplitude: 6, horizontal: false)
        case .stormyNight:
            addLightMood(.dayToNight)
            addWeather(.rain, count: 0)
            addLightning(everySeconds: 2)
        case .snowyEvening:
            addLightMood(.sunset)
            addWeather(.snow, count: 0)
        case .greeting:
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            let hop = all.lowerBound + max(3, all.count / 3)
            if hop <= all.upperBound { playRange = all.lowerBound...hop; jumpLayer(height: h * 0.06) }
            playRange = saved
            addSpeechBubble()
        case .callForHelp:
            shakeLayer(amount: 3)
            addSpeechBubble(shout: true)
        case .shy:
            swayLayer(degrees: 3)
            addBlush()
        case .sad:
            shiftLayerAllFrames(dx: 0, dy: h * 0.02)
            stretchEffect(jelly: false, amount: 0.04)
            addTears()
        case .brightIdea:
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            let hop = all.lowerBound + max(3, all.count / 3)
            if hop <= all.upperBound { playRange = all.lowerBound...hop; jumpLayer(height: h * 0.05) }
            playRange = saved
            addEmotionMark(.idea)
        case .dizzy:
            orbitLayer(radius: max(3, Double(min(width, height)) * 0.015))
            swayLayer(degrees: 5)
            addDizzyStars(count: 3)
        case .pondering:
            swayLayer(degrees: 4)
            addThoughtBubble()
        case .angry:
            shakeLayer(amount: 5, turn: true)
            addEmotionMark(.anger)
        case .surprised:
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            let jumpEnd = all.lowerBound + max(3, all.count / 2)
            if jumpEnd <= all.upperBound { playRange = all.lowerBound...jumpEnd; jumpLayer(height: h * 0.1) }
            playRange = saved
            addEmotionMark(.surprise)
        case .nervous:
            shakeLayer(amount: 2)
            addSweatDrop(drops: 2)
        case .rocketLaunch:
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            let lift = all.lowerBound + max(1, all.count * 3 / 10)
            if lift > all.lowerBound { playRange = all.lowerBound...lift; shakeLayer(amount: 3) }
            if all.upperBound - lift >= 2 {
                playRange = lift...all.upperBound
                travelLayer(dx: 0, dy: -h * 1.2, eased: false)
                easeLayerMotion(.slowIn)
            }
            playRange = saved
            addSmokeTrail(every: 1)
        case .peekaboo:
            // Up in the first third, a little look around, down again in the last quarter.
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            let up = all.lowerBound...(all.lowerBound + max(1, all.count / 3))
            let down = max(up.upperBound + 1, all.upperBound - max(1, all.count / 4))...all.upperBound
            if up.count >= 2 { playRange = up; riseUp() }
            if down.lowerBound - 1 > up.upperBound {
                playRange = up.upperBound...(down.lowerBound - 1); swayLayer(degrees: 6)
            }
            if down.count >= 2 { playRange = down; riseUp(sink: true) }
            playRange = saved
        case .dropAndShake:
            // The fall takes the first 60 %, so there are frames after the landing to squash and shake in.
            let saved = playRange, all = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
            playRange = all.lowerBound...(all.lowerBound + max(2, Int(Double(all.count - 1) * 0.6)))
            travelLayer(dx: 0, dy: h * 0.7, eased: false)
            shiftLayerAllFrames(dx: 0, dy: -h * 0.7)
            easeLayerMotion(.slowIn)
            playRange = saved
            squashStretch(amount: 1.4)
            addGroundShadow()
            impactShake(strength: 10)
            impactZoom(amount: 0.06)
            hitStop(extra: 2)
        }
        selectedLayer = layers.firstIndex { $0.id == id } ?? selectedLayer
        guard undoStack.count > start else { return false }
        if undoStack.count > start + 1 { undoStack.removeSubrange((start + 1)...) }    // one undo step
        if let i = undoStack.indices.last { undoStack[i].label = r.title }
        return true
    }
}
