// UniversePhoto Bridge 0.2 — documented UniversePen JavaScriptCore API only.
// No network, filesystem, profile writes, sample filters, or automatic gesture overrides.
// Assign these up.action entries to the bar, radial menu, squeeze, or double-tap in UniversePen.
const actions = [
  ["brush", "Pinsel", "paintbrush.pointed", "b", []],
  ["eraser", "Radierer", "eraser", "e", []],
  ["eyedropper", "Pipette", "eyedropper", "i", []],
  ["move", "Ebene verschieben", "arrow.up.and.down.and.arrow.left.and.right", "v", []],
  ["selection", "Rechteckauswahl", "rectangle.dashed", "m", []],
  ["fill", "Fläche füllen", "drop.fill", "g", []],
  ["gradient", "Farbverlauf", "rectangle.lefthalf.filled", "d", []],
  ["text", "Text", "textformat", "t", []],
  ["rectangle", "Rechteck", "rectangle", "r", []],
  ["ellipse", "Ellipse", "circle", "c", []],
  ["hand", "Leinwand bewegen", "hand.draw", "p", []],
  ["sizeUp", "Pinselgröße erhöhen", "plus", "]", []],
  ["sizeDown", "Pinselgröße verringern", "minus", "[", []],
  ["opacityUp", "Deckkraft erhöhen", "circle.lefthalf.filled", ".", []],
  ["opacityDown", "Deckkraft verringern", "circle.lefthalf.filled", ",", []],
  ["cycleColor", "Nächste Palettenfarbe", "paintpalette", "x", []],
  ["undo", "Rückgängig", "arrow.uturn.backward", "z", ["cmd"]],
  ["redo", "Wiederholen", "arrow.uturn.forward", "z", ["cmd", "shift"]],
  ["newLayer", "Neue Ebene", "square.stack.3d.up", "n", ["cmd", "shift"]],
  ["duplicateLayer", "Ebene duplizieren", "plus.square.on.square", "j", ["cmd"]],
  ["deleteLayer", "Ebene löschen", "trash", "delete", ["cmd", "shift"]],
  ["toggleVisibility", "Ebenensichtbarkeit wechseln", "eye", "h", ["option"]],
  ["flipCanvas", "Leinwand spiegeln", "arrow.left.and.right", "h", []],
  ["zoomIn", "Vergrößern", "plus.magnifyingglass", "+", ["cmd"]],
  ["zoomOut", "Verkleinern", "minus.magnifyingglass", "-", ["cmd"]],
  ["fitCanvas", "Leinwand einpassen", "arrow.up.left.and.arrow.down.right", "0", ["cmd"]],
  ["newFrame", "Frame duplizieren", "plus.square", "f", ["shift"]],
  ["previousFrame", "Vorheriger Frame", "chevron.left", "left", ["option"]],
  ["nextFrame", "Nächster Frame", "chevron.right", "right", ["option"]],
  ["onionSkin", "Onion-Skinning wechseln", "square.on.square", "o", ["option"]],
  ["playPause", "Wiedergabe / Pause", "playpause", "space", []]
];

function isUniversePhoto(app) {
  return !!app && (app.bundleID === "local.universephoto" || app.name === "UniversePhoto");
}
function frontApp() {
  try { return up.frontApp(); }
  catch (error) { up.log("UniversePhoto Bridge: Vordergrund-App nicht verfügbar", String(error)); return null; }
}
let foreground = isUniversePhoto(frontApp());
actions.forEach(([id, title, icon, key, modifiers]) => {
  up.action({ id, title, icon }, () => {
    // Refresh for every action: the app may have changed before its queued event arrived.
    foreground = isUniversePhoto(frontApp());
    if (!foreground) { up.toast("UniversePhoto ist nicht im Vordergrund", 1.5); return; }
    up.shortcut(key, modifiers);
  });
});
up.on("app", app => {
  const next = isUniversePhoto(app);
  if (next && !foreground) up.toast("UniversePhoto Bridge aktiv", 1);
  foreground = next;
});
up.on("connect", () => { foreground = isUniversePhoto(frontApp()); });
up.on("disconnect", () => { foreground = false; });
up.log("UniversePhoto Bridge: " + actions.length + " Aktionen registriert");
