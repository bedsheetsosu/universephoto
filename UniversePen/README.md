# UniversePen – iPad + Äbbl™ Pencil Pro as a pen display for the Mac

Part of [UniverseStudio](../README.md): this folder holds the iPad app, `TafelKit`, the plugin SDK and tools; the Mac host is built into UniverseStudio. Free and open source. No account, no cloud, no ads, no subscription. Formerly called "Tafel": folders, targets and the `TafelKit` package still use that name in the code. Two native apps:

- **UniversePen Host** (macOS 15+): streams a screen region or a window and turns pen, gesture and keyboard input from the iPad into macOS input.
- **UniversePen** (iPadOS 18+): full-screen view, Pencil input with pressure, tilt, barrel roll, hover, squeeze, double-tap, finger gestures.

Target hardware: iPad Air 11" M4 + Äbbl Pencil Pro, MacBook Air M5, Affinity.

---

> **Mac side now also in UniverseStudio (2026-11-24):** the UniversePen host is built into
> [UniverseStudio](https://github.com/bedsheetsosu/universestudio) as a module, so one Mac app does
> both. The stand-alone `TafelHost` target here still builds and works; only one of the two may run
> at a time. The root `Package.swift` exposes `TafelKit` so UniverseStudio can depend on this repo.

## Honest status (1.0.0, 2026-11-17)

| Area | Status | How it was checked |
|---|---|---|
| Wire protocol, framing, pairing code, geometry, tilt, pressure curve | implemented | 21 unit tests (`swift test` in `Packages/TafelKit`) |
| TLS-PSK encryption, wrong key is rejected | implemented | real TLS handshakes over localhost (tests) |
| Pairing → key handover → control + video connection → pen/shortcut events reach the host, ping/RTT | implemented | integration test with a real `HostServer` + real client `Session` over 127.0.0.1 |
| Video encoder (VideoToolbox, hardware, low-latency rate control) → wire → client decoder, H.264 and HEVC at 2360×1640 | implemented | pipeline test on this Mac: 10/10 frames encoded and decoded again, keyframe on request |
| Keyboard shortcuts following the active layout (QWERTZ) | implemented | layout resolution tested (without sending events) |
| Screen capture (ScreenCaptureKit) | **runs on real hardware** (2026-11-15) | streaming to the iPad in daily use, e.g. second screen at 2360×1640, HEVC, 60 fps (reported by the developer API) |
| Tablet events to macOS (pressure, tilt, rotation, proximity) | **runs on real hardware** (2026-11-15) | Affinity reads pressure, tilt and rotation from the synthetic tablet events (see the Affinity row) |
| Pencil input, hover, squeeze, double-tap, gestures on the iPad | **runs on real hardware** (2026-11-15) | pressure, tilt, barrel roll, squeeze, double-tap and pinch/rotate checked live via the developer API; hover confirmed in Affinity |
| Affinity compatibility | **works on real hardware** (2026-11-15) | in regular use: pressure → stroke width, tilt and barrel roll, hover brush preview, gestures and shortcuts (zoom, pan, undo, squeeze/double-tap) |
| Pressure curve editor & per-app shortcut bar | **runs on real hardware** (2026-11-15) | freely drawable curve with live test, smoothing, hold keys, the bar follows the Mac app |
| Tablet mode with app-bound presets (osu!), key pad, tip threshold, area rotation, instant ink, hover dot | **runs on real hardware** (2026-11-15) | confirmed by use |
| Plugins, time-lapse | implemented, builds (2026-11-15) | plugin runtime and examples tested on the Mac (filters, actions, timeout); time-lapse writer tested with synthetic frames – **not yet confirmed in daily use** |
| Source switching from the iPad, undo scrub, game mode, custom colours / flowing background, pen taps in games (osu!: pointer follows every tap) | **runs on real hardware** (2026-11-15) | confirmed by use |
| Squeeze radial menu, per-app Pencil profiles, Mac menu bar (status, iPad battery, mode) | **runs on real hardware** (2026-11-15) | radial menu with hover + squeeze, Affinity profile switching with the front app, battery shown in the menu bar |
| Second screen (like Sidecar) | **runs on real hardware**, experimental | the only private API (`CGVirtualDisplay`), used only in this mode |
| USB cable | **runs on real hardware** (2026-11-15, iPad Air M4 ↔ MacBook Air M5) | all three connections over the USB Ethernet interface (Mac `en8`); falls back to Wi-Fi. Undocumented, see limits |
| UltraUI (new design of both apps: iPad menu with four tabs, settings with search, start screen, Mac window with sidebar, menu bar panel) | **runs on real hardware** (2026-11-17) | screenshots from the iPad and the Mac (incl. the pairing sheet's code boxes); the tablet-area animation is built but **not yet seen on the iPad** |
| Sound from the Mac | **data flows** (listening test pending) | ScreenCaptureKit audio → 16-bit PCM → iPad, buffer max. ~100 ms; the Mac keeps playing the sound itself |

Confirmed so far on one setup (iPad Air M4, Pencil Pro, MacBook Air M5, Affinity). Other apps, devices and macOS versions are untested.

---

## Build and install

Requirements: Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd universepen
```

```bash
xcodegen generate
```

```bash
open Tafel.xcodeproj
```

- **UniversePen Host** (Mac, bundle ID `local.universepen.host`; up to 0.1.1 it was "Tafel Host", `local.tafel.host` – its settings are taken over on first launch, permissions have to be granted again): runs without an App ID and without a developer account. Not sandboxed (see permissions). The default is ad-hoc signing – then macOS forgets Accessibility and Screen Recording after **every rebuild**. Fix: create `Config/HostSigning.local.xcconfig` (not in git) with `CODE_SIGN_IDENTITY = <SHA-1 of your "Apple Development" certificate>` (`security find-identity -v -p codesigning`). The signature then stays the same and the permissions are kept.
- **UniversePen** (iPad): pick your team under *Signing & Capabilities*. With a free Äbbl account the app runs for 7 days and uses up one App ID. If `local.tafel.pad` is already taken, change the bundle ID in `project.yml` and regenerate. Developer Mode must be on on the iPad.

### Without a Mac: sideload the IPA

Every [release](https://github.com/bedsheetsosu/universestudio/releases) has an **unsigned** `UniversePen-<version>-unsigned.ipa`. iPadOS only runs apps that are signed for your device, so a sideloading tool has to sign it with your own Äbbl account first – e.g. SideStore, AltStore or Sideloadly (the last two also run on Windows). With a free account the app runs for 7 days at a time and the tool usually changes the bundle ID; both are fine.

For now the iPad still needs the Mac app (UniversePen Host) on the other side – there is no Windows host yet. The IPA just means you don't need Xcode for the iPad part.

Tests:

```bash
cd Packages/TafelKit && swift test
```

```bash
xcodebuild -project Tafel.xcodeproj -scheme PipelineTests -derivedDataPath build/dd test
```

## Getting started

On first launch both apps walk you through a short **setup**. On the iPad it is an assistant: it asks what you use UniversePen for (drawing, gaming/aiming with tablet mode, or both) and which Pencil you have (Pro, with hover, without hover), then only shows the pages that fit – drawing extras, tablet area / key pad / tip threshold, colours – and creates "Drawing" and "Gaming" profiles if you pick both. On the Mac: permissions, source, pairing. You can run it again from iPad → Settings, or in the Mac window → General.

1. Start UniversePen Host. Allow **Screen Recording** and **Accessibility** (buttons in the app). Without Accessibility, macOS silently drops all input.
   Note: with ad-hoc signed builds macOS may forget the permissions after a rebuild – then remove the old entry in System Settings and allow it again.
2. On the Mac, click **"Pair iPad …"** (Mac window or menu bar) → a 12-character code appears (valid for 2 minutes).
3. Open UniversePen on the iPad → tap the Mac under "Pair new" → enter the code. From then on the iPad connects automatically whenever the Mac is reachable.
4. Pick a source on the Mac: **Full display** (default, the choice is remembered; 16:10 Macs get thin bars at the top and bottom), **iPad region** (fills the iPad edge to edge), a single **Window**, or the experimental **Second screen**.

---

## Design (UltraUI)

Both apps are built from one small design system (`Packages/TafelKit/Sources/TafelKit/UltraUI.swift`):

- **iPad menu:** while connected, the round button at the top right opens a control centre with four tabs – **Tools** (drawing aids, stroke, view, Mac), **Source** (what the Mac sends, tablet mode, view only, finger mode, per-app game mode), **Clipboard** (both directions, reference picture, keyboard, text snippets) and **More** (profiles, plugin actions, gestures & shortcuts, settings, disconnect). The next touch on the picture closes it; a Pencil stroke goes on to the Mac.
- **Settings** on the iPad: a sidebar with search (by page or setting) instead of one long list.
- **Start screen and setup:** glass cards for your Macs, the pairing code in twelve boxes (a hidden text field underneath is there for paste, dictation and hardware keyboards), setup pages that arrive with a short staggered entrance.
- **Mac window:** a Liquid Glass sidebar and six pages – Overview, Source, Pairing, Streaming, General, Developer (⌘1–⌘6). The pairing code floats over the window.
- **Menu bar:** a panel with the connection, the source and quick actions (window to the iPad, palette, time-lapse, heat guard) as tiles.
- Real Liquid Glass (iPadOS/macOS 26) only on still backgrounds. Over the live Mac picture the panels use a calm frosted material instead: Liquid Glass adapts to what is behind it, and over moving video that looks like pulsing. Older systems get the material everywhere.
- "Reduce Motion" turns the springs into short fades.

---

## Phase 1: What public APIs can do – and what they can't

### Video

| Goal | Public API | Result |
|---|---|---|
| Capture the Mac screen/a window | ScreenCaptureKit (`SCStream`, `SCContentFilter`) | ✅ screen, region (`sourceRect`) or a single window |
| Low-latency hardware encoding | VideoToolbox, `kVTVideoEncoderSpecification_EnableLowLatencyRateControl` | ✅ H.264 and HEVC, confirmed as hardware encoder on this Mac |
| Hardware decoding on the iPad | `AVSampleBufferDisplayLayer` with "display immediately" | ✅ |
| Same colours as on the Mac | ScreenCaptureKit in Display P3, stream tagged P3 + sRGB tone curve; HEVC in 10 bit (Main10, `x420` frames straight from ScreenCaptureKit), 8 bit in full range | ✅ no lifted shadows (older versions tagged BT.709) and no banding in soft gradients. iPad → Settings → Image → "10-bit colour" (switches to HEVC). |
| **iPad as an additional, separate display** at native resolution | only `CGVirtualDisplay` – **private** | ⚠️ not available through public APIs. Äbbl's own solution is Sidecar. UniversePen offers it as a deliberate, experimental exception (see "Second screen"). |
| Native iPad resolution without black bars | region in the iPad aspect ratio (2360×1640 ≈ 1.44:1) taken from the Mac screen (1470×956 pt ≈ 1.54:1) | ✅ "iPad region" mode: fills the iPad completely, size and position via sliders. The rest of the Mac screen is not visible on the iPad. |

### Connection

| Goal | Result |
|---|---|
| Wi-Fi | ✅ Bonjour + TCP, `Network.framework` |
| Without a router | ✅ Äbbl peer-to-peer Wi-Fi (AWDL, `includePeerToPeer`), **off by default**: while AWDL is active the Wi-Fi radio hops channels periodically, which costs noticeable latency on normal Wi-Fi. Switch on both sides. |
| **USB** | ⚠️ No custom USB protocol (usbmuxd is undocumented, DriverKit needs Äbbl entitlements). **But:** with a cable, iPadOS gives the Mac a normal USB Ethernet interface (NCM, e.g. `en8` on the Mac). UniversePen only uses plain Network.framework for it: the Mac listens on all interfaces, the iPad first connects with `requiredInterfaceType = .wiredEthernet` and falls back to Wi-Fi after 2.5 s. **Finding 2026-11-15:** `NWPathMonitor` on the iPad only shows `en0` (Wi-Fi), so `requiredInterfaceType = .wiredEthernet` fails. But Bonjour also finds the Mac via `en2` and `anpi0`; pinning the connection with `requiredInterface` to the `en2` that Bonjour returns makes it run over the cable (Mac side `en8`). That is plain Network.framework, but **undocumented** – an iPadOS update may change it; then the Wi-Fi fallback kicks in. iPad → Settings shows "Path", the Mac shows "Via USB cable (en8)". |

### Pen input on the iPad (UIKit, all public)

| Property | API | Result |
|---|---|---|
| Position, up to 240 Hz | `UITouch.preciseLocation`, `coalescedTouches` | ✅ all intermediate samples are sent |
| Pressure | `force / maximumPossibleForce` | ✅ with an adjustable curve |
| Tilt, azimuth | `altitudeAngle`, `azimuthAngle(in:)` | ✅ as a tilt vector −1…1 |
| Barrel roll (Pencil Pro) | `UITouch.rollAngle`, `UIHoverGestureRecognizer.rollAngle` (iPadOS 17.5+) | ✅ as rotation in degrees |
| Hover | `UIHoverGestureRecognizer` (iPads with hover, M4 Air ✅) | ✅ as proximity + mouse movement |
| Squeeze, double-tap | `UIPencilInteraction` `didReceiveSqueeze` / `didReceiveTap` | ✅ freely assignable shortcuts |
| Predicted touches | `predictedTouches` | deliberately **not** used: they would create strokes that were never drawn |
| Late pressure updates | `estimatedPropertiesExpectingUpdates` | **not** used: the first value is sent right away (latency before accuracy) |

### Input on the Mac

| Property | Public API | Result |
|---|---|---|
| Pen position, click, drag | `CGEvent` mouse events, `CGEvent.post` (needs Accessibility) | ✅ |
| Pressure, tilt, rotation, proximity | `CGEventTypes.h`: subtype `kCGEventMouseSubtypeTabletPoint`, fields `kCGMouseEventPressure`, `kCGTabletEventPointPressure`, `kCGTabletEventTiltX/Y`, `kCGTabletEventRotation`, event type `kCGEventTabletProximity` | ✅ implemented. Cocoa apps read this as `NSEvent.pressure/.tilt/.rotation`. **Affinity accepts them** (pressure, tilt, rotation, confirmed 2026-11-15). |
| Real virtual tablet HID device | DriverKit `HIDDriverKit` with the virtual HID entitlement | ❌ Äbbl only grants the entitlement on request |
| Pinch to zoom | magnify gesture events can't be created with public APIs | substitute: scrolling with ⌘/⌥/⌃ or ⌘+/⌘−, selectable |
| Rotate the canvas | no public rotation gesture | substitute: freely assignable shortcuts per rotation step (default: off) |
| Pan | `CGEvent` scroll events in pixels | ✅ two fingers |

**Fallback if Affinity ignores the tablet fields:** with public APIs there is no better way than `CGEvent`. What's left is position/click (drawing without pressure) plus pressure substitutes via shortcuts (e.g. brush size `[` / `]` on the shortcut bar). That would be a real limitation, not a workaround.

---

## Architecture

```
iPad (UniversePen)                                 Mac (UniversePen Host)
┌──────────────────────────┐   TLS 1.2 PSK / TCP   ┌─────────────────────────────┐
│ CanvasView (UIKit)       │  control connection   │ HostServer                  │
│  Pencil → PenSample ─────┼──────────────────────►│  → InputInjector → CGEvent  │
│  gestures → scroll/keys  │  (noDelay, small)     │     (tablet fields, keys)   │
│  ping ◄──────────────────┼───────────────────────┤  pong                       │
│                          │                       │                             │
│ VideoRenderer            │  video connection     │ ScreenStreamer              │
│  AVSampleBufferDisplay◄──┼───────────────────────┤  ScreenCaptureKit           │
│  Layer (HW decode)       │  (H.264/HEVC)         │  → VideoEncoder (VT, HW)    │
└──────────────────────────┘                       └─────────────────────────────┘
              Bonjour _tafel._tcp (+ _tafelpair._tcp only while pairing)
```

- **Two connections**, so large video frames never hold up pen packets (no head-of-line blocking).
- **Frame dropping before the encoder:** if more than ~2 frames are queued in the socket, the next frame isn't encoded at all – the image stays current instead of lagging.
- No B-frames, real-time mode, keyframe on connect and on request (decoder errors).
- `Packages/TafelKit`: shared code (protocol, pairing, geometry, transport, keychain).
- `Host/`: Mac app. `Client/`: iPad app. `PipelineTests/`: integration tests on the Mac.

### Security

- Connections only with paired devices: without the key the TLS handshake fails (tested).
- Pairing: 12 characters of Crockford Base32 (60 bits); the pairing listener is open for only 2 minutes and closes after the first pairing. A TLS PSK is derived from it via HKDF. Over that, the iPad gets **its own** random 256-bit key, stored in the keychain on both sides (this device only).
- Encryption: TLS 1.2 with `TLS_PSK_WITH_AES_128_GCM_SHA256` (as in Äbbl's peer-to-peer sample code). Limitation: **no forward secrecy** – anyone who later gets hold of an iPad's key could decrypt that iPad's previously recorded traffic.
- **One key per iPad** (since 0.8): the Mac's listener holds every paired iPad's key and TLS picks it by the identity the iPad sends. Mac window → Pairing lists the iPads with their key fingerprints (the iPad shows its own under Settings → Connection); "Remove" stops one iPad at once, the others stay paired. iPads paired before 0.8 used one shared key; the next time such an iPad connects, the Mac hands it its own key over the encrypted connection, and "Older pairings → Remove" retires the shared key. "Unpair all" removes every key.
- No external servers, no telemetry. Local network only.

### School-managed devices

UniversePen does not change profiles, restrictions or MDM settings and does not try to get around them. On a managed iPad, installing via Xcode (Developer Mode) or local network access may be blocked by policy – then UniversePen won't work there, and that is intended.

---

## Connection drops

- The USB network link to the iPad occasionally drops for ~3 s (in the Mac log from `remoted`: `kIONetworkLinkStateInactive`). Seen on a USB 2 connection (High Speed); whether another cable helps is still open.
- UniversePen detects this after 2.5 s without a ping reply (instead of after a long TCP timeout), keeps the last frame on screen and reconnects automatically for up to 30 s: over the cable first, otherwise Wi-Fi. While on Wi-Fi, UniversePen checks every 10 s whether the cable works again and switches back (after a failure at most once per minute). Confirmed on real hardware (2026-11-15).
- On the Mac, any pressed pen/mouse/key state is released when the connection drops.
- Encoder or decoder errors trigger a new full frame immediately instead of freezing until the next periodic keyframe (5 s).
- While an iPad is connected the Mac's display does not go to sleep (a power assertion, visible in `pmset -g assertions`), and connecting wakes a sleeping display.
- If the Mac's screen capture stops by itself (display change, window closed) while an iPad is connected, it is restarted (up to 3 times in 30 s). After the Mac or its displays wake up, the capture is started fresh, so the iPad never keeps a frozen picture.
- Coming back to the iPad app retries a failed connection and asks a live one for a fresh full frame.

## Palette window

Bring one Mac panel (layers, colours, brushes …) onto the iPad as a small floating live window – handy in "iPad region" mode, where the panel itself is outside the streamed area. Choose the area on the Mac (Mac window → Source → Palette → "Choose", or iPad menu → Tools → "Palette", then drag out a rectangle on the Mac; Esc cancels). On the iPad, drag the window by its bar, resize it at the corner, fold it up, or close it (which forgets the area). Taps and drags on it are clicks and drags at that spot on the Mac. Up to 10 JPEG frames per second at ≤ 900 px, and only when the panel changes; they share the video connection, so pen input is never delayed. The area is remembered on the Mac.

## Perspective and ellipse guides

iPad menu → Tools, next to the ruler (one aid at a time, iPad only – nothing is drawn on the Mac):
- **Perspective (1, 2 or 3 vanishing points):** drag the round knobs with a finger. Every Pencil stroke picks, after its first 10 pt, the line through its start point towards the vanishing point that best matches its direction (plus verticals with 1–2 points and horizontals with 1 point) and stays on it – like the drawing guides of iPad painting apps, but in any Mac app.
- **Ellipse template:** drag inside to move it, two fingers turn (snaps to 0/45/90°) and scale it, the two knobs change each axis (it snaps to a circle when both are within 6 pt). Strokes that start on its outline band follow the ellipse.
- **Hover preview:** while the Pencil hovers, the ruler edge or ellipse outline it would snap to lights up.
- The Pencil Pro gives a haptic tick when a stroke locks onto the ruler, a vanishing line, the ellipse or a grid line.
- While drawing in perspective, the vanishing line the stroke follows is drawn bright.
- **Lock the aid** (menu → Tools, below the drawing aids): its knobs and body ignore fingers, so nothing moves by accident.
- **Per app:** each Mac app keeps its own aid. Switching apps brings back the ruler/perspective/ellipse you last used there (none for apps where you never used one).

## Rope stabilizer, fixed pressure, tools on gestures

- **Rope stabilizer** (iPad → Settings → Pencil, 0–60 pt): the stroke hangs on an invisible string behind the Pencil; jitter shorter than the string never reaches the Mac. Steady lines and lettering without the lag of averaging. Not combined with the ruler/perspective/ellipse aids, which are straight already.
- **Pressure curve presets:** Soft, Linear, Firm and S-curve buttons under the curve editor (then fine-tune the points).
- **Squeeze and hold** (Settings → Pencil): squeezing longer than 0.35 s holds a key on the Mac (⇧ ⌥ ⌘ ⌃ or Space) until you let go – a spring-loaded tool, e.g. Space to pan while drawing. A short squeeze still runs its normal action.
- **Fixed pressure:** every stroke at one pressure (5–100 %) for even ink lines.
- **iPad tools on gestures:** ruler, perspective 1/2/3, ellipse, shape recognition, laser, screenshot and palette can be put on double-tap, squeeze, finger gestures, radial menu items and bar buttons ("iPad tool"), and toggled from Shortcuts ("Toggle iPad Tool").

## Mirror view, break reminder

- **Mirror view** (menu → Tools, or as an iPad tool on a gesture): flips the picture on the iPad only, to check proportions the way painters look at a drawing in a mirror. The Mac stays as it is; Pencil input and tilt are mirrored back, so strokes land where they should. Works together with the local zoom.
- **Turn the view** (zoom method "Only on the iPad"): two fingers turn the picture on the iPad like a sheet of paper (snaps to 0/90/180/270°); pinch and pan keep working, the pill shows angle and zoom and resets both. Pencil position and tilt are turned back, so the Mac gets upright input.
- **Grayscale preview** (menu → Tools): the picture in grey on the iPad only, to check light and dark values while painting in colour.
- **Speed pressure** (Settings → Pencil, 0–100 %): faster strokes get lighter, slow ones stay full – like an ink nib.
- **Composition grid** (menu → Tools, style below the tiles): thirds, quarters or squares (2–32 across and opacity in Settings → General) over the picture on the iPad only; it zooms, turns and mirrors with the picture. With "Snap strokes to the grid" (Settings → General) a stroke that starts within 24 pt of a grid line follows it.
- **Reference picture:** its bar now also flips it horizontally and shows it in grey; both are remembered.
- **Session summary:** disconnecting shows how long you drew and how many strokes went to the Mac.
- **Pressure meter** (Settings → Pencil): a small bar bottom left shows the pressure that reaches the Mac, handy for tuning the curve.
- **Reference picture:** double-tap it to lock it for tracing.
- **Slow Wi-Fi hint:** if Wi-Fi round trips stay above 35 ms for 10 s, the iPad suggests the USB cable (once per sitting).
- **Undo/redo buttons** (Settings → Pencil): two round buttons at the bottom edge, on the side opposite the shortcut bar.
- **Break reminder** (Settings → General: 30/45/60/90 min): a gentle toast after that much drawing time; five minutes without input count as the break.

## Shape recognition

iPad → Settings → Pencil → "Shape recognition" (off by default). Hold the Pencil still for half a second at the end of a stroke: if it looks like a line, an arrow (shaft plus one or two barbs), an open polyline, a triangle, a rectangle (snapped to right angles and to horizontal/vertical within 6°), a pentagon, an ellipse or a circle, UniversePen lifts the pen on the Mac, sends Undo (⌘Z) and draws the clean shape as a new stroke with the stroke's average pressure. The Pencil Pro gives a haptic tick. Works in any Mac app whose Undo removes the last stroke. Not in tablet mode or with the ruler.

## Small things

- **Hover tilt** (Settings → Pencil, with the hover dot): a short line from the dot shows which way and how far the Pencil leans – useful before a tilt-shaded stroke.
- **Connect sound** (Mac window → General): a short system sound when an iPad connects or goes away.
- **Open at login** (Mac window → General), via the system's login items (the app should be in Applications).
- **View only** and the **finger mode** (off / mouse / pen / pointer) are in the iPad menu → Source; palette, time-lapse and heat guard are also tiles in the Mac menu bar panel.
- **Text snippets** (Settings → Text snippets): saved texts in the menu → Clipboard; one tap types them on the Mac.

## iPad battery warning

When the connected iPad drops to 15 % and is not charging, the Mac's menu bar icon turns into an empty battery and the iPad shows a reminder (once, until it is above 20 % or charging again).

## Mac shortcuts

The laser pointer colour (red, green, yellow, blue, magenta) is chosen in the Mac window → Source.


System-wide, from any app: **⌃⌥⌘T** switches the iPad into or out of tablet mode, **⌃⌥⌘P** lets you drag out the palette area, **⌃⌥⌘I** moves the front app's window to where the iPad looks (the second screen, or the centre of the streamed display/region), shrinking it to fit if needed (uses Accessibility). Also in the menu bar panel.

## Heat guard (Mac)

On by default (Mac window → Streaming, or a tile in the menu bar panel). macOS reports how hot the Mac is (`ProcessInfo.thermalState`). At "serious" UniversePen streams at most 30 fps, ≤ 25 Mbit/s and without full source resolution; at "critical" also ≤ 15 Mbit/s and ≤ 75 % resolution. When the Mac has cooled off, the iPad's own settings apply again. It only ever lowers settings. Made for the fanless MacBook Air.

While the iPad is dimmed (Settings → "Dim after"), the Mac stops capturing and encoding altogether and starts again the moment you touch the iPad.

## Gestures & shortcuts page

iPad menu → More → "Gestures & shortcuts": one page with what double-tap, squeeze, every finger gesture and the Mac hot keys do right now (for the app in front on the Mac).

## Automatic tablet mode

Menu → Source (or Settings → Image) → "Tablet mode automatically" (listed under the app in front): while that Mac app is in front (e.g. osu!), the iPad switches into tablet mode by itself and back to the picture when another app comes to the front. Several apps can be on the list.

## Quick tools, orientation lock

- The menu's Tools tab shows every iPad tool as a tile in four groups (drawing aids, stroke, view, Mac), lit while it is on.
- **Lock orientation** (menu → Tools → "Orientation"): keeps the current orientation, so an iPad lying flat on the desk does not turn by itself.

## Shortcuts, Siri, Control Center

The iPad app offers actions in the Shortcuts app: **Connect to Mac** (optionally a specific paired Mac), **Disconnect from Mac**, **Tablet Mode** and **Laser Pointer** (on / off / toggle) and **Take Mac Screenshot**. They also work with Siri and Spotlight (e.g. "Connect UniversePen"). For Control Center or the Lock Screen, add the system "Shortcut" control and pick one of them. All actions are translated into the 7 app languages.

The Mac app has its own actions: **Pair iPad**, **Set Source** (full display, second screen, iPad region, window), **Time-lapse** (on / off / toggle), **Switch iPad Profile** (the profiles of the connected iPad) and **Move Front Window to iPad** – for Shortcuts, Spotlight and keyboard shortcuts assigned there. They act on the running UniversePen Host, so the window, the menu bar and the iPad change right away.

## Accessibility

- VoiceOver: all icon buttons have labels; selected menu entries and the active profile are announced as selected. The Mac picture is a single element with *direct interaction*, so the Pencil and fingers keep working with VoiceOver on.
- Reduce Motion (iPad and Mac): springs become short fades, the flowing background stands still.
- Settings and menus use system text styles and grow with the text size.

## Second screen (experimental, private API)

**A deliberate exception to the "public APIs only" rule, added on request (2026-11-15).**

- "Second screen" mode: UniversePen uses the **private** CoreGraphics class `CGVirtualDisplay` to create an additional Mac display "UniversePen (iPad)" – 1180×820 pt, HiDPI (2360×1640 pixels), 60 Hz, rotated in portrait – and streams it edge to edge. Like Sidecar, but without needing the same Äbbl ID (pairing by code), so it also works with devices you can't sign in to with your own account.
- Arrange it under System Settings → Displays. Without the iPad the display is removed after 10 s (short USB dropouts are bridged) and macOS brings the windows back; when UniversePen Host quits, it's removed immediately.
- Checked on real hardware (macOS on MacBook Air M5): the display appears, stream at 2360×1640.
- **Risk:** Äbbl can change or remove this interface with any macOS update. UniversePen then reports "not available"; all other modes are unaffected. The declarations are isolated in `Host/Private/CGVirtualDisplayPrivate.h` and only used by `Host/VirtualDisplay.swift`.
- No changes to MDM, profiles or system settings; it only creates a display session.
- Free alternative without a private API: an HDMI/USB-C display dummy plug + "Full display" mode on that display (usually 16:9 → bars).

## Radial menu, per-app Pencil profiles, menu bar

- **Radial menu:** set squeeze (or double-tap) to "Radial menu". 2–8 round buttons appear on an open arc around the Pencil tip (where it hovers), like the squeeze palettes of drawing apps; the arc opens upwards and turns away from screen edges. Hover over a button (its name shows beside it) and squeeze again, or tap it; tap the tip or outside to close. Highlight and pick give a haptic tick on the Pencil Pro. Items: iPad → Settings → Radial menu. While the ring is open, nothing is sent to the Mac.
- **Per-app Pencil profiles:** pressure curve, smoothing, double-tap and squeeze can have their own values per Mac app (iPad → Settings → Pencil → "Settings for"). They switch automatically with the app in front on the Mac, like the per-app shortcut bars.
- **Full Mac resolution (on by default):** with a region (or a mirrored display), the Mac sends all captured pixels unscaled and the iPad scales them down when showing them – noticeably sharper than scaling on the Mac (confirmed 2026-11-15). Costs more bitrate; iPad → Settings → Image to switch off. **The second screen is always sent at the iPad's own pixels** (since 2026-11-17): it is shown whole, so a "more space" step's extra pixels (up to 1.6×) only cost encoder and decoder work – that made the Mac hot and dropped frames (37 instead of 60 fps measured at 2952×2052). The second screen offers five sharp HiDPI steps (1180×820 to 1888×1312 points); the default step is 1:1 with the iPad's pixels and the sharpest.
- **Switch the source from the iPad:** menu → Source: full display, iPad region, second screen, or a window from the Mac's window list – no trip to the Mac.
- **Undo scrub:** rest two fingers briefly, then drag left (undo) or right (redo), one step per 40 pt (adjustable). A pill shows the count. iPads have no haptic engine for fingers, so the feedback is visual only.
- **Game mode** (e.g. osu!): menu → Source → "Game mode" (listed under the app in front). While that app is in front on the Mac: 60 fps, full resolution, ≥ 60 Mbit/s, no adaptive bitrate, no smoothing. The iPad Air's display is 60 Hz, so more than 60 fps isn't possible.
- **Colours:** pick an accent (presets or the system colour wheel) on iPad → Settings → Appearance or in the Mac window → General; it runs through buttons, rings, the radial menu and the bar. "Flowing background" turns the still gradient into a slowly moving mesh whose hues drift (speed adjustable). Only behind menus and setup, never over the streamed picture.
- **Instant ink:** the stroke appears on the iPad right away as a thin trail in the accent colour and fades after about the measured picture delay – when the Mac's real stroke arrives underneath. Hides most of the stream latency while drawing. iPad → Settings → Pencil.
- **Hover dot:** a small ring under the hovering Pencil tip, drawn on the iPad (the Mac cursor in the video lags behind). Its size (4–40 pt) and an own instant-ink colour can be set in Settings → Pencil.
- **Time-lapse (Mac):** records the streamed picture as an HEVC time-lapse (10×–120×) to Movies → UniversePen. ScreenCaptureKit only delivers frames when the screen changes, so idle time is skipped. Start/stop in the Mac window (Overview or Streaming) or the menu bar panel; a change of picture size (other source/resolution) closes the file. From the iPad: menu → Tools → "Time-lapse".
- **Tablet mode** (like a screenless pen tablet, e.g. for osu! without a tablet): menu → Source → "Tablet mode". The Mac stops capturing; the iPad turns black with a fine dot grid and corner marks for the active area, which maps absolutely onto the whole selected Mac display. Outside the area the cursor stays at the edge. A built-in "Full area" preset (the whole iPad) is the default. Move/resize the area with "Adjust active area" or type width, height and offset in mm (size shown live, saved as named presets for quick switching from the menu → Source – a preset can be bound to a Mac app (e.g. osu!) and is used automatically while that app is in front, optionally locked to the Mac display's aspect ratio). Fingers are off in this mode so the hand can rest on the glass – except on the optional **key pad** (like ExpressKeys): big touch keys at the edge (default Z and X; on any edge – left, right, top or bottom – or each key dragged to any spot in the area editor), held on the Mac as long as a finger rests on them. The area can be **rotated** (degrees, saved with presets), and a **tip threshold** (Settings → Tablet mode) makes light touches stay hover. **osu!:** switch off "High precision mouse" / raw input (Settings → Input → Mouse), otherwise osu! mixes relative and absolute movement and the cursor jumps (confirmed 2026-11-15).
- **Plugins:** small JavaScript plugins run by the Mac app (JavaScriptCore, no file/network access): Pencil filters (smoothing, custom mappings – like OpenTabletDriver), reactions to gestures and the squeeze phases, actions for the iPad (menu → More, squeeze, bar, radial menu), toasts on the iPad and full control via the developer API. Plugins window with switches, editor, log and examples. See [`SDK/plugins`](SDK/plugins/README.md).
- **Profiles:** complete sets of iPad settings plus picture quality (e.g. "Drawing" and "osu!"), switched in Settings → Profiles or the menu → More; changes go into the active profile automatically. Language, colours and pairings stay per device.
- **Pencils without hover** (Apple Pencil 1, USB-C, iPads without hover): "Double-tap to click" – a touch only moves the pointer, touch again at once at the same spot to click or draw; or finger mode "Pointer" (aim with a finger, draw with the Pencil); or the tip threshold (light = pointer, firm = click).
- **Monitor only** (menu → Source → "View only", or Settings, per profile): the iPad just shows the picture – no Pencil, touch, gestures, squeeze or keyboard reach the Mac, so a resting hand can't trigger anything. Switching it on ends a stroke or held keys cleanly.
- **Several iPads:** the first iPad shows the picture; every further iPad that connects becomes a tablet without a picture (tablet mode, its active area mapped onto the selected display) – e.g. one iPad as display and one as pen tablet. A second iPad with its own picture is not supported (it would need a stream and virtual display per iPad).
- **Keep awake & dim:** while connected the iPad never sleeps; optionally it dims after 1–10 minutes without input (not while the picture keeps changing, if you like) and is bright again at the first touch.
- **Share profiles:** export one or all profiles as a `.universepen.json` file (AirDrop, Files, …) and import them on another iPad – e.g. to pass on an osu! area.
- **Clipboard:** menu → Clipboard → "iPad → Mac" / "Mac → iPad" copies text or an image between the two clipboards over the encrypted connection. Only when you tap it, never in the background.
- **Reference picture:** menu → Clipboard → "Reference picture" floats a photo from your library over the picture, on the iPad only (it never goes to the Mac). Drag to move, pinch to scale, slider for transparency; lock it and the Pencil and fingers pass straight through to the Mac, e.g. for tracing.
- **Magnifier follows the pen:** in the "iPad section" mode (Mac window → size slider, now down to 20 %), switch on "Magnifier follows the pen": the zoomed section pans when the pen hovers near the iPad's edge and jumps to the pointer when you move it elsewhere with the trackpad or mouse. It never moves while the tip is down.
- **Ruler:** menu → Tools → "Ruler" lays a ruler over the picture. Move it with one finger, turn it with two (snaps to 0°, 45°, 90° …). Pencil strokes that start on or near it stay on its edge (its label shows the stroke's length in cm on the glass) – straight lines in any Mac app.
- **Laser pointer:** menu → Tools → "Laser": the Pencil draws glowing red marks over the Mac screen that fade after about two seconds, and a red dot follows it. Nothing is clicked or drawn in the app; the marks are a click-through window, so they also show in screen sharing.
- **Screenshot:** menu → Tools → "Shot" takes a picture of exactly what is streamed, at the Mac's full resolution (not the stream size). Drag to crop, then save it to Photos or share it.
- **Local zoom:** iPad → Settings → Zoom → "Only on the iPad": pinching enlarges the picture on the iPad only (up to 800 %), two fingers move it, and Pencil strokes still land in the right place on the Mac. The pill at the top shows the zoom; tap it to reset.
- **Demo mode** (iPad → Settings → Demo, or "Try without a Mac" on the connect screen): runs only on the iPad, clearly labelled – a simulated desktop with a drawing window (your pressure curve, tilt, a pointer following the hovering Pencil, clickable buttons, click ripples) and tablet mode with a small monitor and targets to hit. For showing UniversePen without a Mac.
- **Menu bar (Mac):** connected iPad, path (USB/Wi-Fi), fps and bitrate, iPad battery, source switch, pairing, quit.

## Fingers & multi-touch (like on a pen display)

Confirmed on real hardware (2026-11-15).

- **One finger** (setting "One finger": Mouse / Pen with fixed pressure / Off): tap = click where you touch, tap twice = double-click, drag = click and drag (draws in Affinity without pressure), hold ≈ 0.55 s = right-click.
- **Palm rejection:** fingers do nothing while the Pencil hovers, touches, or was used less than 0.6 s ago, nor with a large contact area (`majorRadius`, adjustable threshold). A second finger cleanly ends a running one-finger action (no stray click before pinch/scroll).
- **Multiple fingers:** two fingers scroll, pinch zooms (method selectable), rotate → shortcuts, two-/three-/four-finger tap and three-finger swipe in all directions are freely assignable (defaults like a Mac trackpad: left/right = switch desktop, up = Mission Control, down = App Exposé; confirmed on real hardware).
- **Zoom or scroll, never both:** each two-finger touch is decided once – a change in finger distance of 6 % means zoom, 14 pt of movement means scroll – and stays that way until the fingers lift. Before, the fingers' small drift while pinching also scrolled, so the Mac picture jumped up and down while zooming.
- iPadOS intercepts four-finger gestures if multitasking gestures are enabled in the iPad settings.
- The Mac can't create real trackpad gestures (magnify/rotate) with public APIs, so zoom works via scroll + modifier.

## Keyboard

- **Hardware keyboard on the iPad** (e.g. Logi Combo Touch): every key is sent to the Mac as a physical key position (USB HID usage → macOS keycode), including ⌘ ⌥ ⌃ ⇧, arrows, F keys. Which character comes out is decided by the **Mac's keyboard layout** – with the same layout on both sides (e.g. German) everything matches, including ä ö ü ß.
- iPadOS keeps some shortcuts for itself (⌘-Tab, ⌘-Space, Globe key, ⌘-H …); those never reach UniversePen.
- Some ISO keyboards report `^` and `<` swapped → Settings → Keyboard → "Swap the ^ and < keys".
- **Trackpad / mouse on the iPad** (confirmed on real hardware, Logi Combo Touch) controls the Mac pointer: absolute position (where the iPad pointer is over the image), click, two-finger click = right-click, double/triple click, drag, two-finger scroll, pinch/rotate like the finger gestures. The iPad pointer is hidden (the Mac cursor is visible in the video) – can be turned off. Keyboard modifiers also apply to clicks (e.g. ⌥-drag).
- **On-screen keyboard** (menu → Clipboard → "Keyboard"): sends typed text as Unicode (independent of the Mac layout), without autocorrect.
- Held keys are released on disconnect and when opening settings, so nothing gets "stuck" on the Mac.

## Other known limits

- **Mirroring, not an extended display**, in all modes except the experimental "Second screen" (see above).
- **Window mode:** the position is tracked every 0.5 s; when the window is resized, the capture restarts at the new shape once the size holds still (about a second, with a short pause in the picture).
- **Tilt direction** hasn't been checked on real hardware → invert switches for X and Y.
- **Zoom mapping in Affinity:** whether ⌘+scroll or ⌥+scroll zooms depends on Affinity's settings → selectable.
- **Latency display:** "RTT" is the real network round-trip time. "Frame" is the age of a frame on arrival (capture + encoding + network), estimated via a clock sync over ping; decoding and display (typically a few ms) are not included.
- **Mouse pointer** is streamed too (helps with hover).
- **Tablet identity:** UniversePen reports its own, made-up vendor ID and doesn't pretend to be Wacom. Apps that only accept certain vendors would then ignore pressure.

---

## Phase 5: Test plan on real hardware

Please go through in order and note each result:

1. **Connection:** pair, connect. Status display (menu → Tools → "Status"): RTT on Wi-Fi typically < 10 ms, 60 fps while moving.
2. **Image:** "iPad region" mode → no black bars, sharp? The encoder line on the Mac should say "Hardware · Low-Latency-RC".
3. **Pen test window** (Mac window → Overview → "Pen Test", move it into the region) – this is the decisive check whether macOS gets the data:
   - hover → `tabletProximity: in`, then `hover` lines
   - draw with varying pressure → `subtype=tabletPoint`, `pressure` changes, line width varies
   - tilt the pen → `tilt` changes; check the direction, use the invert switch if needed
   - roll the Pencil Pro → `rotation` changes
4. **Affinity:** brush with pressure→size (brush dynamics), stroke light → firm. Then tilt/rotation dynamics if the brush uses them.
   - If step 3 shows pressure but Affinity doesn't: Affinity ignores synthetic tablet events → document as a limitation.
5. **Gestures:** pan with two fingers, pinch to zoom (adjust the zoom method), two-/three-finger tap = undo/redo.
6. **Squeeze / double-tap** → the configured action in Affinity (default: double-tap = eraser E, squeeze = radial menu).
7. **Drop case:** turn off Wi-Fi on the iPad mid-stroke → the mouse button on the Mac must not stay "stuck".

## Phase 7: Optimisation ideas (not implemented yet)

- Video over UDP/DTLS instead of TCP (no waiting for lost packets).
- Adapt the bitrate automatically to RTT/backlog.
- Dirty-region detection to save bandwidth on still images (ScreenCaptureKit hardly delivers frames when nothing changes anyway).

## External control & protocol

- **[UniversePen SDK](SDK/README.md) – MIT licence, free for anyone to use:** local developer API (switch it on in the Mac app, `127.0.0.1:47800` only) with an **Input API** (pressure, tilt, rotation, hover, touch, gestures live), a **Display API** (mode, second screen, resolution, frame rate, connection status) and a **Control API** (shortcuts, app profiles, pressure curves, all iPad settings). Swift package `UniversePenKit`, examples in Python, JavaScript and Swift. Tested on real hardware (2026-11-15).
- [`docs/API.md`](docs/API.md): `universepen://…` URLs for Shortcuts, Terminal, Stream Deck (switch mode, pair).
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md): the complete wire protocol – the basis for your own clients/hosts (e.g. Android, Windows).

## Languages & translations

The apps have their own language picker (first step of the setup, later in the settings), independent of the system language. The default is English.

- Texts live in `Packages/TafelKit/Sources/TafelKit/Translations*.swift`; each key is the original German text.
- `python3 Tools/check-l10n.py` lists missing translations.
- **Found a mistake?** Most translations are machine-made. Please open an issue with the "Translation fix" template (language, where in the app, current text, suggestion) – or send a pull request for the matching table directly.

## Licence

Copyright © 2026 Biene

UniversePen is free software under the **GNU General Public License v3.0** (see [`LICENSE`](LICENSE)): you may use, modify and share the code. If you distribute a modified version, you must publish its source code under the GPL-3.0 as well. There is no warranty.

Exception: the [`SDK/`](SDK) folder (developer SDK, examples, API description) is under the **MIT licence** ([`SDK/LICENSE`](SDK/LICENSE)) and may also be used in closed-source programs.
