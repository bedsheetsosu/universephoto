// Affinity actions: shows up on the iPad (… menu → Plugins) and can be put on squeeze,
// double-tap, the shortcut bar or the radial menu.
up.action({ id: "new-layer", title: "New layer", icon: "square.stack.3d.up" }, () => {
  up.shortcut("n", ["cmd", "shift"]);
  up.toast("New layer");
});

up.action({ id: "duplicate", title: "Duplicate layer", icon: "plus.square.on.square" }, () => {
  up.shortcut("j", ["cmd"]);
  up.toast("Duplicated");
});

up.action({ id: "swap-colours", title: "Swap colours", icon: "arrow.left.arrow.right" }, () => {
  up.shortcut("x");
});

up.on("app", app => {
  if (app.name && app.name.toLowerCase().includes("affinity")) up.toast(`${app.name} ✓`, 1.2);
});
