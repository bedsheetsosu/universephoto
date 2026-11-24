// UniversePen plugin template.
// Copy this folder, give it a new "id" and "name" in manifest.json, then change this file.
// Reference: SDK/plugins/README.md
//
// Plugins run on the Mac inside UniversePen Host (JavaScriptCore): no network, no files,
// no Node APIs. up.filter() runs for every Pencil sample, so keep it fast.

// ---------------------------------------------------------------------------
// 1. Feature switches. Each one is on or off and is saved in this plugin's
//    storage (up.storage), so it survives restarts. Defaults apply until changed.
// ---------------------------------------------------------------------------
const DEFAULTS = {
  "pressure-boost": false,   // used by the Pencil filter in section 3
  "app-hint": true,          // used by the app hook in section 4
};

// Read the saved values once. The filter must not touch storage for every sample.
const flags = {};
for (const name of Object.keys(DEFAULTS)) {
  const saved = up.storage.get("feature." + name);
  flags[name] = typeof saved === "boolean" ? saved : DEFAULTS[name];
}

function setFeature(name, on) {
  if (!(name in DEFAULTS)) { up.log("unknown feature", name); return; }
  flags[name] = !!on;
  up.storage.set("feature." + name, !!on);
  up.log("feature", name, flags[name] ? "on" : "off");
}

// ---------------------------------------------------------------------------
// 2. Actions for the iPad. They appear in the … menu under Plugins and can be
//    put on squeeze, double-tap, finger gestures, the shortcut bar or the radial menu.
// ---------------------------------------------------------------------------
up.action({ id: "toggle-pressure-boost", title: "Pressure boost", icon: "waveform" }, () => {
  setFeature("pressure-boost", !flags["pressure-boost"]);
  up.toast("Pressure boost " + (flags["pressure-boost"] ? "on" : "off"), 2);
});

up.action({ id: "show-features", title: "Features", icon: "checklist" }, () => {
  const lines = Object.keys(flags).map(n => n + ": " + (flags[n] ? "on" : "off"));
  up.toast(lines.join("  ·  "), 4);
});

// ---------------------------------------------------------------------------
// 3. Pencil filter. Gets every sample before it reaches the Mac.
//    Return the sample (changed or not), null to drop it, or an array of samples.
//    x, y are 0…1 inside the picture; pressure 0…1; tiltX/tiltY −1…1.
// ---------------------------------------------------------------------------
up.filter(s => {
  if (flags["pressure-boost"]) s.pressure = Math.min(1, Math.sqrt(s.pressure));
  return s;
});

// ---------------------------------------------------------------------------
// 4. App hook: runs when the front app on the Mac changes.
//    Replace the bundle ID with the app you want to react to.
// ---------------------------------------------------------------------------
const TARGET_APP = "com.example.target-app";   // placeholder, not a real app
up.on("app", app => {
  if (flags["app-hint"] && app.bundleID === TARGET_APP) up.toast("Target app in front", 2);
});

// ---------------------------------------------------------------------------
// 5. Gesture hook: tap2, tap3, tap4, swipe3.left/right/up/down, pinch, rotate,
//    undoScrub, pencil.doubleTap, pencil.squeeze, pencil.squeezeBegan/Ended.
// ---------------------------------------------------------------------------
up.on("gesture", g => {
  if (g.name === "swipe3.up") up.toast("Three fingers up", 1);
});

// ---------------------------------------------------------------------------
// 6. Calls to the Mac side. up.display, up.settings, up.profiles and up.call(method, params)
//    run methods of the developer API. Errors are thrown, so catch them.
//    Not allowed inside up.filter().
// ---------------------------------------------------------------------------
up.action({ id: "full-display", title: "Full display", icon: "display" }, () => {
  try {
    up.display.setMode("display");
  } catch (e) {
    up.log("could not switch the source:", String(e));
  }
});

up.log("template loaded", flags);
