# UniversePen plugins

**MIT License** (like the rest of `SDK/`). Plugins are small JavaScript files that the Mac app
(UniversePen Host) runs with Äbbl™'s JavaScriptCore. Think OpenTabletDriver plugins, for a tablet
with a screen: filter the Pencil, react to gestures, add actions to the iPad, control UniversePen.

- Folder: `~/Library/Application Support/UniversePen/Plugins/<plugin>/` with `manifest.json` and `main.js`.
- Mac app → **Plugins …** (window or menu bar): switch plugins on/off, edit, save & reload (⌘S), see the log,
  create a new one from a template, or install the [examples](examples).
- Plugins are **off by default** and switched on one by one.

## Safety

A plugin runs on your Mac and can read and change Pencil input, press keys and control UniversePen.
It has **no** file or network access (plain JavaScriptCore – no `fetch`, no `require`, no Node APIs).
Only switch on plugins whose code you know or trust.

Each plugin has its own context and queue. A filter that takes longer than **20 ms** marks its
plugin as stopped (the Pencil keeps working unfiltered); reload it after fixing the code.

## manifest.json

```json
{ "id": "squeeze-scroll", "name": "Squeeze-Scroll", "version": "1.0",
  "description": "What it does", "main": "main.js" }
```

## The `up` object

| Call | What it does |
|---|---|
| `up.filter(fn)` | `fn(sample)` runs for **every Pencil sample** before it reaches the Mac. Return the (changed) sample, `null` to drop it, or an array of samples. Several filters run in plugin-name order. |
| `up.on(event, fn)` | `"pen"` (every sample after filtering), `"gesture"` (`{name, value}`), `"app"` (`{bundleID, name}` when the front app changes), `"connect"` / `"disconnect"` (`{device, link}`) |
| `up.action({id, title, icon}, fn)` | An action for the iPad: appears in the … menu under Plugins and can be put on squeeze, double-tap, finger gestures, shortcut-bar buttons and the radial menu. `icon` is an SF Symbol name. |
| `up.shortcut(key, mods)` | Press a shortcut, e.g. `up.shortcut("n", ["cmd", "shift"])`. Keys: a character or `return tab space delete esc left right up down`; mods: `cmd shift option control`. |
| `up.text(s)` | Types text (Unicode, independent of the keyboard layout). |
| `up.scroll(dx, dy)` | Scrolls by points at the pointer. |
| `up.toast(text, seconds)` | Shows a short message on the iPad. |
| `up.call(method, params)` | Any [developer API](../README.md) method, e.g. `up.call("display.setMode", {mode: "region"})`. Not allowed inside `up.filter` (it would hold up the Pencil). |
| `up.settings.get()` / `up.settings.patch(obj)` | The iPad's settings (pressure curve, smoothing, tablet area, game apps, …). |
| `up.display.get()` / `up.display.setMode(m)` | Source: `display`, `second-screen`, `region`, `window`. |
| `up.frontApp()`, `up.status()` | Front app on the Mac, connection status. |
| `up.profiles.get()` / `up.profiles.activate(idOrName)` | The iPad's settings profiles; switch one (e.g. "osu!" when a game starts). |
| `up.storage.get(k)` / `up.storage.set(k, v)` | Small per-plugin storage (kept across restarts). |
| `up.log(...)`, `console.log(...)` | Log lines in the Plugins window. |
| `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`, `up.now()` | Timers; `up.now()` = milliseconds (monotonic). |

### Pencil samples

```js
{ phase: "hover" | "down" | "move" | "up" | "enter" | "exit" | "cancel",
  x, y,              // 0…1 inside the picture / tablet area (change these to move the point)
  screenX, screenY,  // global Mac points (read only)
  pressure,          // 0…1 (after the iPad's pressure curve)
  tiltX, tiltY,      // −1…1
  rotation,          // degrees (barrel roll)
  time }             // ms
```

### Gestures

`tap2 tap3 tap4`, `swipe3.left/right/up/down`, `pinch` (value = scale step), `rotate` (degrees),
`undoScrub` (steps), `pencil.doubleTap`, `pencil.squeeze` (on release), and the squeeze phases
`pencil.squeezeBegan` / `pencil.squeezeEnded` – e.g. to do something while the squeeze is held.
If the Pencil touched the glass while squeezed, `pencil.squeezeEnded` has `value: 1` and the iPad
does **not** run the squeeze's own action (radial menu, undo, …): the squeeze was used as a modifier.

## Template

[`template/`](template/) is a commented starting point. Copy the folder into your plugins folder, change `id` and `name` in `manifest.json`, then edit `main.js`. It shows the parts most plugins are made of:

1. **Feature switches**: on/off values saved in `up.storage` and read once at start. They keep optional parts of a plugin switchable.
2. **iPad actions** that flip those switches.
3. **A Pencil filter** that uses the switches. It runs for every sample, so it only reads values already in memory.
4. **An app hook** (`up.on("app")`) and a **gesture hook** (`up.on("gesture")`).
5. **A call to the Mac side** (`up.display`, `up.call`) inside try/catch, because errors are thrown.

Before you share a plugin:

- `id` is unique and `main` names the file.
- `up.filter` stays well under 20 ms and never calls `up.call`.
- Storage keys have a prefix (`feature.` or your own) so plugins don't overwrite each other.
- It works with the plugin switched off and on (switch it off and reload to check).

## Plugins and other apps (UniversePhoto)

A plugin runs inside UniversePen Host and has no network access, so it can't reach another app by itself. What exists today:

| Direction | How | Status |
|---|---|---|
| Plugin → UniversePen | `up.*` above | works |
| Other app → UniversePen (requests) | developer API on `127.0.0.1` (see the [SDK README](../README.md)) | works; **off by default**, switch it on in the Mac app |
| Other app → UniversePen (links) | `universepen://…` ([docs/API.md](../../docs/API.md)) | works |
| UniversePhoto → a plugin's switches | none | not built |

**Planned, not built:** a channel that lets a plugin receive events from other apps (for example UniversePhoto) and send its own messages to them. It would be a new interface in UniversePen Host with its own permission switch, off by default. Until it exists, use the developer API or the `universepen://` links above.

**What a plugin cannot do:** it can add actions, filters and workflows, but it cannot lock or unlock UniversePen's own features. A feature switch is only a value stored on the user's Mac, and UniversePen is open source (GPL-3.0), so any check in the app or in a plugin can be removed. If a paid tier or a licence key for UniversePhoto is wanted, that needs its own design (for example a signed licence checked on the Mac). Plugins can't enforce it.

## Examples

- [`squeeze-scroll`](examples/squeeze-scroll/main.js) – hold the squeeze, put the Pencil down and drag to scroll.
- [`smoothing`](examples/smoothing/main.js) – exponential smoothing filter with an on/off action for the iPad.
- [`affinity-actions`](examples/affinity-actions/main.js) – new layer / duplicate / swap colours as iPad actions.
