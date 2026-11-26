import SwiftUI

/// The sections of Animation → Layer effects, as their own views (0.219): in one piece the menu
/// grew too big for the compiler to type-check in reasonable time.

struct LayerEffectsMove: View {
    @ObservedObject var studio: Studio
    var body: some View {
        Group {
        Menu(L("Bounce to the beat")) {
            ForEach([90.0, 120.0, 140.0], id: \.self) { bpm in
                Button(LF("%@ BPM", String(Int(bpm)))) { studio.onSelectedLayers { studio.beatBounce(bpm: bpm) } }
            }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer squashes and springs up on every beat at the chosen tempo – timed by the real frame times"))
        }
        Group {
        Menu(L("Travel over the frames")) {
            ForEach([false, true], id: \.self) { eased in
                Button(L(eased ? "Left to right, soft" : "Left to right")) { studio.onSelectedLayers { studio.travelLayer(dx: Double(studio.width), dy: 0, eased: eased) } }
                Button(L(eased ? "Right to left, soft" : "Right to left")) { studio.onSelectedLayers { studio.travelLayer(dx: -Double(studio.width), dy: 0, eased: eased) } }
                Button(L(eased ? "Up, soft" : "Up")) { studio.onSelectedLayers { studio.travelLayer(dx: 0, dy: -Double(studio.height), eased: eased) } }
                Button(L(eased ? "Down, soft" : "Down")) { studio.onSelectedLayers { studio.travelLayer(dx: 0, dy: Double(studio.height), eased: eased) } }
                Divider()
            }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer crosses the whole canvas over the existing frames – its own motion stays"))
        Menu(L("Orbit")) {
            Button(L("Small circle")) { studio.onSelectedLayers { studio.orbitLayer(radius: 20) } }
            Button(L("Big circle")) { studio.onSelectedLayers { studio.orbitLayer(radius: 80) } }
            Button(L("Flat ellipse")) { studio.onSelectedLayers { studio.orbitLayer(radius: 80, squash: 0.35) } }
            Divider()
            Button(L("Small circle, other way")) { studio.onSelectedLayers { studio.orbitLayer(radius: 20, clockwise: false) } }
            Divider()
            Button(L("Figure eight")) { studio.onSelectedLayers { studio.orbitLayer(radius: 70, figureEight: true) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer runs on a circle or a figure eight that starts at its position – a seamless loop"))
        Menu(L("Spiral")) {
            Button(L("Whirl in")) { studio.onSelectedLayers { studio.spiralLayer(radius: 120, turns: 1.5) } }
            Button(L("Whirl out")) { studio.onSelectedLayers { studio.spiralLayer(radius: 120, turns: 1.5, out: true) } }
            Button(L("Big whirl in")) { studio.onSelectedLayers { studio.spiralLayer(radius: 260, turns: 2.5) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer whirls in on a narrowing spiral and lands on its place – or whirls out from it"))
        Menu(L("Bounce over the frames")) {
            Button(L("One big jump")) { studio.onSelectedLayers { studio.bounceLayer(height: Double(studio.height) * 0.3, bounces: 1) } }
            Button(L("Ball, 3 hops")) { studio.onSelectedLayers { studio.bounceLayer(height: Double(studio.height) * 0.3, bounces: 3) } }
            Button(L("Small hops")) { studio.onSelectedLayers { studio.bounceLayer(height: Double(studio.height) * 0.08, bounces: 4, decay: 0.85) } }
            Divider()
            Button(L("Ball, 3 hops, squashy")) { studio.onSelectedLayers { studio.bounceWithSquash(height: Double(studio.height) * 0.3, bounces: 3) } }
            Button(L("One big jump, squashy")) { studio.onSelectedLayers { studio.bounceWithSquash(height: Double(studio.height) * 0.3, bounces: 1) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer hops across the frames, each hop lower, and lands where it started"))
        Menu(L("Walk bob")) {
            Button(L("Calm walk (4 steps)")) { studio.onSelectedLayers { studio.walkBob(steps: 4, height: 5, tilt: 3) } }
            Button(L("Quick walk (8 steps)")) { studio.onSelectedLayers { studio.walkBob(steps: 8, height: 6, tilt: 4) } }
            Button(L("Waddle")) { studio.onSelectedLayers { studio.walkBob(steps: 4, height: 3, tilt: 10) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer bobs up with every step and tips from foot to foot – pair it with Travel"))
        }
        Group {
        Menu(L("Shake layer")) {
            Button(L("Trembling")) { studio.onSelectedLayers { studio.shakeLayer(amount: 3) } }
            Button(L("Shaking")) { studio.onSelectedLayers { studio.shakeLayer(amount: 10) } }
            Button(L("Rattling, with turn")) { studio.onSelectedLayers { studio.shakeLayer(amount: 8, turn: true) } }
        }.disabled(studio.frames.count < 2)
            .help(L("Small random jolts of the active layer in every frame – fear, cold or an impact"))
        Menu(L("Sway layer (rotate)")) {
            Button(L("Gentle")) { studio.onSelectedLayers { studio.swayLayer(degrees: 6) } }
            Button(L("Strong")) { studio.onSelectedLayers { studio.swayLayer(degrees: 16) } }
            Divider()
            Button(L("Hanging, gentle")) { studio.onSelectedLayers { studio.swayLayer(degrees: 10, hanging: true) } }
            Button(L("Hanging, strong")) { studio.onSelectedLayers { studio.swayLayer(degrees: 25, hanging: true) } }
        }.disabled(studio.frames.count < 2)
            .help(L("Rocks the active layer back and forth across the frames – a gentle swing, or hanging from its top like a pendulum"))
        Menu(L("Swing to rest")) {
            Button(L("Hanging, hit")) { studio.onSelectedLayers { studio.swingToRest(degrees: 25, hanging: true) } }
            Button(L("Standing, knocked")) { studio.onSelectedLayers { studio.swingToRest(degrees: 15, hanging: false) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer was just knocked – it swings hard, then less and less until it is still"))
        Menu(L("Float layer (drift)")) {
            Button(L("Up and down, gentle")) { studio.onSelectedLayers { studio.floatLayer(amplitude: 18, horizontal: false) } }
            Button(L("Up and down, strong")) { studio.onSelectedLayers { studio.floatLayer(amplitude: 44, horizontal: false) } }
            Divider()
            Button(L("Side to side, gentle")) { studio.onSelectedLayers { studio.floatLayer(amplitude: 18, horizontal: true) } }
            Button(L("Side to side, strong")) { studio.onSelectedLayers { studio.floatLayer(amplitude: 44, horizontal: true) } }
        }.disabled(studio.frames.count < 2)
            .help(L("A soft, seamless drift over the whole animation – gentle secondary motion"))
        Menu(L("Spin over the frames")) {
            Button(L("Clockwise, 1 turn")) { studio.onSelectedLayers { studio.spinLayerOverFrames(turns: 1) } }
            Button(L("Clockwise, 2 turns")) { studio.onSelectedLayers { studio.spinLayerOverFrames(turns: 2) } }
            Divider()
            Button(L("Counter-clockwise, 1 turn")) { studio.onSelectedLayers { studio.spinLayerOverFrames(turns: -1) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer turns full circles across the existing frames – a seamless loop"))
        }
        Group {
        Menu(L("Gust of wind")) {
            Button(L("From the left")) { studio.onSelectedLayers { studio.gustLayer(degrees: 18) } }
            Button(L("From the right")) { studio.onSelectedLayers { studio.gustLayer(degrees: -18) } }
            Button(L("Storm")) { studio.onSelectedLayers { studio.gustLayer(degrees: 35) } }
        }.disabled(studio.frames.count < 4)
            .help(L("A gust bends the active layer over on its foot; it holds against the wind, then springs back"))
        Menu(L("Jump")) {
            Button(L("Small hop")) { studio.onSelectedLayers { studio.jumpLayer(height: Double(studio.height) * 0.12) } }
            Button(L("Big jump")) { studio.onSelectedLayers { studio.jumpLayer(height: Double(studio.height) * 0.35) } }
        }.disabled(studio.frames.count < 4)
            .help(L("One cartoon jump in place – crouch, take off stretched, land squashed and spring back"))
        Menu(L("Wander")) {
            Button(L("Small")) { studio.onSelectedLayers { studio.wanderLayer(radius: 12) } }
            Button(L("Wide")) { studio.onSelectedLayers { studio.wanderLayer(radius: 40) } }
            Button(L("Another path")) { studio.onSelectedLayers { studio.wanderLayer(radius: 25, seed: UInt64.random(in: 1...UInt64.max)) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer drifts around on a soft, random path that closes into a loop – a fly, a firefly, a balloon"))
        }
    }
}

struct LayerEffectsShape: View {
    @ObservedObject var studio: Studio
    var body: some View {
        Group {
        Menu(L("Wavy text")) {
            Button(L("Wave")) { studio.onSelectedLayers { studio.wavyText(hop: false) } }
            Button(L("Letters hop in turn")) { studio.onSelectedLayers { studio.wavyText(hop: true) } }
            Divider()
            Button(L("Rainbow letters")) { studio.onSelectedLayers { studio.rainbowLetters() } }
            Button(L("Shaky letters")) { studio.onSelectedLayers { studio.shakyLetters() } }
            Button(L("Letters drop in")) { studio.onSelectedLayers { studio.lettersDropIn() } }
            Button(L("Letters pop in")) { studio.onSelectedLayers { studio.lettersPopIn() } }
            Button(L("Letters fly apart")) { studio.onSelectedLayers { studio.lettersScatter() } }
        }.disabled(studio.frames.count < 2)
            .help(L("The letters of the text on the active layer move one by one – a wave, letters hopping in turn, running rainbow colours or trembling letters"))
        Menu(L("Eye blink")) {
            Button(L("Every 2 seconds")) { studio.onSelectedLayers { studio.eyeBlink(everySeconds: 2) } }
            Button(L("Every 4 seconds")) { studio.onSelectedLayers { studio.eyeBlink(everySeconds: 4) } }
            Button(L("Often (every second)")) { studio.onSelectedLayers { studio.eyeBlink(everySeconds: 1) } }
        }.disabled(studio.frames.count < 5)
            .help(L("The active layer – eyes on their own layer – shuts for a moment now and then, like a real blink"))
        }
        Group {
        Menu(L("Squash & stretch")) {
            Button(L("Normal")) { studio.onSelectedLayers { studio.squashStretch(amount: 1) } }
            Button(L("Cartoony")) { studio.onSelectedLayers { studio.squashStretch(amount: 1.8) } }
            Divider()
            Button(L("None")) { studio.onSelectedLayers { studio.clearSquashStretch() } }
        }.disabled(studio.frames.count < 3)
            .help(L("Stretches the active layer while it moves fast and squashes it where it lands – pairs with Bounce"))
        Menu(L("Breathe")) {
            Button(L("Calm")) { studio.onSelectedLayers { studio.stretchEffect(jelly: false, amount: 0.04) } }
            Button(L("Deep")) { studio.onSelectedLayers { studio.stretchEffect(jelly: false, amount: 0.1) } }
        }.disabled(studio.frames.count < 2)
            .help(L("A calm stretch in and out as a loop – an idle character or a sleeping animal"))
        Menu(L("Jelly")) {
            Button(L("Soft")) { studio.onSelectedLayers { studio.stretchEffect(jelly: true, amount: 0.2) } }
            Button(L("Wobbly")) { studio.onSelectedLayers { studio.stretchEffect(jelly: true, amount: 0.4) } }
        }.disabled(studio.frames.count < 2)
            .help(L("A damped wobble that starts strong and settles – after a landing or a poke"))
        Menu(L("Grow over the frames")) {
            Button(L("Grow")) { studio.onSelectedLayers { studio.growLayerOverFrames(grow: true) } }
            Button(L("Shrink")) { studio.onSelectedLayers { studio.growLayerOverFrames(grow: false) } }
            Divider()
            Button(L("Pop in (overshoot)")) { studio.onSelectedLayers { studio.growLayerOverFrames(grow: true, pop: true) } }
            Button(L("Pop out (overshoot)")) { studio.onSelectedLayers { studio.growLayerOverFrames(grow: false, pop: true) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer grows out of nothing or shrinks away across the existing frames"))
        Menu(L("Pulse size")) {
            Button(L("Subtle")) { studio.onSelectedLayers { studio.scalePulseLayer(amount: 0.08) } }
            Button(L("Strong")) { studio.onSelectedLayers { studio.scalePulseLayer(amount: 0.22) } }
            Divider()
            Button(L("Heartbeat")) { studio.onSelectedLayers { studio.scalePulseLayer(amount: 0.18, heartbeat: true) } }
        }.disabled(studio.frames.count < 2)
            .help(L("Grows and shrinks the active layer across the frames – a gentle breathing or heartbeat"))
        }
        Group {
        Menu(L("Boil all frames")) {
            Button(L("Normal")) { studio.onSelectedLayers { studio.boilAllFrames(amount: 1.5) } }
            Button(L("Stronger")) { studio.onSelectedLayers { studio.boilAllFrames(amount: 3) } }
        }.disabled(studio.frames.count < 2)
            .help(L("Wobbles the active layer a little in every frame – a living, hand-drawn line across the whole animation"))
        }
    }
}

struct LayerEffectsAppear: View {
    @ObservedObject var studio: Studio
    var body: some View {
        Group {
        Menu(L("Burst like a balloon")) {
            Button(L("With sparks")) { studio.popAway(.sparks) }
            Button(L("With confetti")) { studio.popAway(.confetti) }
            Button(L("With hearts")) { studio.popAway(.hearts) }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer swells and bursts like a balloon on the current frame – scrub to where it should pop first"))
        Menu(L("Rise up")) {
            Button(L("Rise up")) { studio.onSelectedLayers { studio.riseUp() } }
            Button(L("Sink down")) { studio.onSelectedLayers { studio.riseUp(sink: true) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer rises out of the ground at its bottom edge – from behind a wall or a counter – or sinks back down"))
        }
        Group {
        Menu(L("Flicker")) {
            Button(L("Now and then")) { studio.onSelectedLayers { studio.flickerLayer(wild: false) } }
            Button(L("Broken neon")) { studio.onSelectedLayers { studio.flickerLayer(wild: true) } }
        }.disabled(studio.frames.count < 3)
            .help(L("The active layer flickers irregularly – a broken neon sign, a candle, a failing torch"))
        Menu(L("Stamp")) {
            Button(L("Quick slam")) { studio.onSelectedLayers { studio.stampLayer(hitAfter: max(2, Int((studio.fps * 0.25).rounded()))) } }
            Button(L("Slow fall")) { studio.onSelectedLayers { studio.stampLayer(hitAfter: max(3, Int((studio.fps * 0.6).rounded()))) } }
            Button(L("Without shaking")) { studio.onSelectedLayers { studio.stampLayer(hitAfter: max(2, Int((studio.fps * 0.25).rounded())), shake: 0) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer comes down like a rubber stamp – huge and faint, then slams onto its place and the picture jolts"))
        Menu(L("Fade over the frames")) {
            Button(L("Fade in")) { studio.onSelectedLayers { studio.fadeLayerOverFrames(fadeIn: true) } }
            Button(L("Fade out")) { studio.onSelectedLayers { studio.fadeLayerOverFrames(fadeIn: false) } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer fades in or out across the existing frames – no frames added"))
        Menu(L("Wipe")) {
            Section(L("Reveal")) { ForEach(Studio.WipeDirection.allCases) { d in Button(L(d.title)) { studio.onSelectedLayers { studio.wipeLayer(d, reveal: true) } } } }
            Section(L("Wipe away")) { ForEach(Studio.WipeDirection.allCases) { d in Button(L(d.title)) { studio.onSelectedLayers { studio.wipeLayer(d, reveal: false) } } } }
            Section(L("Circle")) {
                Button(L("Iris open")) { studio.onSelectedLayers { studio.irisLayer(open: true) } }
                Button(L("Iris close")) { studio.onSelectedLayers { studio.irisLayer(open: false) } }
            }
            Divider()
            Button(L("Remove mask in all frames")) { studio.onSelectedLayers { studio.clearMaskAllFrames() } }
        }.disabled(studio.frames.count < 2)
            .help(L("The active layer is revealed or wiped away from one side across the frames – done with its mask"))
        Menu(L("Pulse layer (glow)")) {
            Button(L("Subtle")) { studio.onSelectedLayers { studio.pulseLayer(floor: 0.45) } }
            Button(L("Strong")) { studio.onSelectedLayers { studio.pulseLayer(floor: 0.1) } }
            Divider()
            Button(L("None")) { studio.onSelectedLayers { studio.unpulseLayer() } }
        }.disabled(studio.frames.count < 2)
            .help(L("Fades the active layer up and down across the frames – a soft glow or breathing"))
        Menu(L("Blink layer")) {
            Button(L("Every frame")) { studio.onSelectedLayers { studio.blinkLayer(period: 1) } }
            Button(L("Every 2 frames")) { studio.onSelectedLayers { studio.blinkLayer(period: 2) } }
            Button(L("Every 3 frames")) { studio.onSelectedLayers { studio.blinkLayer(period: 3) } }
            Divider()
            Button(L("Steady (show always)")) { studio.onSelectedLayers { studio.steadyLayer() } }
        }.disabled(studio.frames.count < 2)
            .help(L("Switches the active layer on and off across the frames – a blinking light or sign"))
        }
        Group {
        Menu(L("Motion echo")) {
            ForEach([2, 3, 4], id: \.self) { n in Button(LF("%d ghosts", n)) { studio.onSelectedLayers { studio.motionEcho(count: n) } } }
            Menu(L("Stronger")) { ForEach([2, 3, 4], id: \.self) { n in Button(LF("%d ghosts", n)) { studio.onSelectedLayers { studio.motionEcho(count: n, strong: true) } } } }
            Divider()
            Button(L("None")) { studio.onSelectedLayers { studio.motionEcho(count: 0) } }
        }.disabled(studio.frames.count < 2)
            .help(L("Fading ghosts of the active layer from the frames before it – a motion trail"))
        }
    }
}
