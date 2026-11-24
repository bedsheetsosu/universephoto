# UniversePen SDK

**MIT License** (see [`LICENSE`](LICENSE)) – use it in any app, open or closed source. The
UniversePen apps themselves are GPL-3.0; this folder (SDK, examples and this API description) is MIT.

The UniversePen Mac app offers a local developer API. Switch it on in the Mac app
(**Developer API**). It listens **only on `127.0.0.1:47800`** – nothing is reachable from the network.

- **Input API** – live Pencil pressure, tilt, rotation (Pencil Pro barrel roll), hover, finger
  touch, trackpad, keys and gestures.
- **Display API** – mode (whole display, second screen, region, window), virtual second screen,
  resolution, frame rate, bitrate and connection status.
- **Control API** – shortcuts, per-app shortcut bars (app profiles), pressure curves, smoothing and
  every iPad setting.

## Protocol

Plain TCP, one JSON object per line (UTF-8, `\n`). Any language works.

```
→ {"id": 1, "method": "display.get", "params": {}}
← {"id": 1, "result": {…}}            or  {"id": 1, "error": "message"}
← {"event": "pen", "data": {…}}       (after "subscribe")
```

On connect the server sends `{"event": "hello", "data": {"api": 1, "app": "UniversePen"}}`.

### Events (`subscribe` / `unsubscribe` with `{"topics": [...]}`)

| Topic | Event | Data |
|---|---|---|
| `input` | `pen` | `phase` (hover, down, move, up, enter, exit, cancel), `x`, `y` (0…1 over the image), `screenX`, `screenY` (global Mac points, origin top-left of the main display; screens left of / above it give negative values, e.g. the second screen), `pressure` 0…1, `tiltX`, `tiltY` −1…1, `rotation` degrees, `timestamp` |
| `input` | `touch` | one finger / trackpad as pointer: `phase` (move, down, up, exit), `button` (left, right), `x`, `y`, `screenX`, `screenY` |
| `input` | `scroll` | `x`, `y`, `dx`, `dy` (fractions of the image), `modifiers` |
| `input` | `key` | `hidUsage` (USB HID page 7), `down` |
| `input` | `shortcut` | `key`, `modifiers` |
| `gesture` | `gesture` | `name`: tap2, tap3, tap4, swipe3.left/right/up/down, pinch (`value` = scale factor since the last event, sent once it changed ≥ 0.5 %), rotate (`value` = degrees since the last event, sent once ≥ 0.1°), pencil.doubleTap, pencil.squeeze, undoScrub (`value` = undo (−) / redo (+) steps, when the scrub ends) |
| `status` | `status` | every second: `connected`, `device`, `link`, `usb`, `fps`, `mbps`, `targetMbps`, `dropped`, `ipadBattery` (0…1 or null), `ipadCharging` (bool or null) |
| `display` | `display` | same as `display.get`, on every change |
| `app` | `app` | `bundleID`, `name` of the app in front on the Mac |

Gestures still run their configured action; the event is additional.

### Methods

| Method | Params | Result |
|---|---|---|
| `api.info` | – | `api`, `topics` |
| `status.get` | – | status object (see event) |
| `display.get` | – | `mode`, `modes`, `secondScreen` {`available`, `active`, `displayID`, `pixelWidth`, `pixelHeight`}, `stream` {`running`, `encoder`, `width`, `height`, `ipadPixelWidth`, `ipadPixelHeight`, `fps`, `codec`, `bitrateMbps`, `resolutionScale`, `adaptive`, `fullSource`, `audio`} |
| `display.setMode` | `mode`: display \| second-screen \| region \| window | display object |
| `display.setQuality` | any of `fps`, `bitrateMbps`, `resolutionScale`, `adaptive`, `audio`, `codec` | `{sent: true}` (applied on the iPad) |
| `app.get` | – | front app or `null` |
| `control.shortcut` | `key` (character or `return tab space delete esc left right up down`), `modifiers` [cmd, shift, option, control] | `{sent: true}` |
| `control.text` | `text` | types text |
| `control.setPressureCurve` | `points` [[x, y], …] (x = Pencil force, y = output, 0…1, ≥ 2 points) and/or `gamma`, `minimum` | `{sent: true}` |
| `control.setSmoothing` | `stroke`, `pressure` (0…1) | `{sent: true}` |
| `control.setAppProfile` | `bundleID`, `name`, `buttons` [{`title`, `key`, `modifiers`} or {`title`, `hold`: shift\|option\|cmd\|control\|space}] | `{sent: true}` |
| `control.removeAppProfile` | `bundleID` | `{sent: true}` |
| `control.setDefaultBar` | `buttons` (as above) | `{sent: true}` |
| `control.getSettings` | – | `{settings, quality}` exactly as stored on the iPad |
| `control.patchSettings` | `settings` and/or `quality` objects, deep-merged | `{sent: true}` |
| `control.getProfiles` | – | `{profiles: [{id, name, active}], active}` – the iPad's settings profiles |
| `control.activateProfile` | `id` or `name` | profiles object; the iPad switches and shows its "Profile: …" toast |

Settings live on the iPad; Control methods need a connected iPad (error `No iPad connected`).
Per-app Pencil profiles (`settings.appPenProfiles[bundleID]` = {`pressure`, `positionSmoothing`,
`pressureSmoothing`, `doubleTap`, `squeeze`}) and the radial menu items (`settings.radialMenu`, 2…8
buttons) can be set with `control.patchSettings`; an action `{"radialMenu": {}}` opens the radial
menu. `control.removeAppProfile` removes both the app's bar and its Pencil profile.
Shortcuts and text need the Mac app's Accessibility permission.

## Examples

- [`examples/python/pen_monitor.py`](examples/python/pen_monitor.py) – live pressure bar, tilt, gestures.
- [`examples/node/status_and_mode.mjs`](examples/node/status_and_mode.mjs) – status, events, pressure curve.
- [`examples/swift/main.swift`](examples/swift/main.swift) with the Swift package
  [`UniversePenKit`](UniversePenKit) (`.package(path: "…/SDK/UniversePenKit")`).

## Privacy

The API is off by default and loopback-only, but any program on this Mac can connect while it is
on and read Pencil input. Only switch it on when you use a tool that needs it.

The lower-level iPad ↔ Mac protocol is documented in [`../docs/PROTOCOL.md`](../docs/PROTOCOL.md).
