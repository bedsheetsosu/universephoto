// Smoothing: exponential moving average on the Pencil position (adds a little lag, removes jitter).
// Change the strength: up.storage.set("strength", 0.6) and reload.
const strength = Math.min(Math.max(up.storage.get("strength") ?? 0.5, 0), 0.95);
let enabled = !(up.storage.get("off") ?? false);
let sx = null, sy = null;

up.filter(s => {
  if (!enabled) return s;
  if (s.phase === "down" || s.phase === "enter" || sx === null) {
    sx = s.x; sy = s.y;
    return s;
  }
  sx += (s.x - sx) * (1 - strength);
  sy += (s.y - sy) * (1 - strength);
  s.x = sx; s.y = sy;
  if (s.phase === "exit" || s.phase === "cancel") sx = sy = null;
  return s;
});

// Put this on squeeze / the bar on the iPad to switch it quickly.
up.action({ id: "toggle", title: "Smoothing on/off", icon: "scribble" }, () => {
  enabled = !enabled;
  up.storage.set("off", !enabled);
  sx = sy = null;
  up.toast(enabled ? "Smoothing on" : "Smoothing off");
});
