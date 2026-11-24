// UniversePen SDK example (MIT) – shows status, switches to the second screen, sets a pressure curve.
// Run: node status_and_mode.mjs   (Node 18+, no packages needed)
import net from "node:net";
import readline from "node:readline";

const sock = net.connect(47800, "127.0.0.1");
const lines = readline.createInterface({ input: sock });
let id = 0;
const pending = new Map();
const call = (method, params = {}) =>
  new Promise((resolve, reject) => {
    pending.set(++id, { resolve, reject });
    sock.write(JSON.stringify({ id, method, params }) + "\n");
  });
lines.on("line", (l) => {
  const m = JSON.parse(l);
  if (m.event) return console.log("event", m.event, m.data);
  const p = pending.get(m.id); pending.delete(m.id);
  m.error ? p.reject(new Error(m.error)) : p.resolve(m.result);
});

sock.on("connect", async () => {
  console.log("status", await call("status.get"));
  console.log("display", await call("display.get"));
  await call("subscribe", { topics: ["status", "display", "app"] });
  // Softer start of the pressure curve:
  try { await call("control.setPressureCurve", { points: [[0, 0], [0.3, 0.5], [1, 1]] }); } catch (e) { console.log(e.message); }
});
