// Squeeze-Scroll: hold the squeeze, put the Pencil on the glass and drag to scroll
// (like dragging a page with a finger). Hovering keeps moving the cursor as usual.
// After a scroll the squeeze's own action (e.g. the radial menu) does not run.

// Points scrolled per full iPad height of Pencil movement (change with up.storage.set("speed", 2000)).
const speed = up.storage.get("speed") || 1500;
let squeezing = false;
let squeezeSince = 0;       // when the squeeze began (a lost "ended" must not leave scroll mode on)
const maxSqueeze = 8000;    // ms; a squeeze held longer than this no longer counts
let scrolling = false;      // the current stroke started while squeezing
let lastX = 0, lastY = 0;

up.on("gesture", g => {
  if (g.name === "pencil.squeezeBegan") { squeezing = true; squeezeSince = Date.now(); }
  if (g.name === "pencil.squeezeEnded") squeezing = false;
});

up.filter(s => {
  if (squeezing && Date.now() - squeezeSince > maxSqueeze) squeezing = false;
  if (s.phase === "down" && squeezing) {
    scrolling = true;
    lastX = s.x; lastY = s.y;
    return null;              // no click on the Mac
  }
  if (!scrolling) return s;
  if (s.phase === "move") {
    up.scroll((s.x - lastX) * speed, (s.y - lastY) * speed);
    lastX = s.x; lastY = s.y;
    return null;
  }
  if (s.phase === "up" || s.phase === "cancel") {
    scrolling = false;        // the whole stroke stays a scroll, even if the squeeze ended first
    return null;
  }
  return s;
});
