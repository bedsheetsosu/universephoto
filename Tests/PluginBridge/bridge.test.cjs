// Run: node Tests/PluginBridge/bridge.test.cjs (no dependencies).
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const actions = new Map(), handlers = new Map(), shortcuts = [], toasts = [];
let app = { bundleID: 'local.universephoto', name: 'UniversePhoto' };
const up = {
  frontApp: () => app,
  action: (spec, callback) => {
    assert(!actions.has(spec.id), 'IDs must be unique');
    assert(spec.title && spec.icon);
    actions.set(spec.id, { spec, callback });
  },
  on: (event, callback) => handlers.set(event, callback),
  shortcut: (key, modifiers) => shortcuts.push({ key, modifiers: Array.from(modifiers) }),
  toast: (...args) => toasts.push(args),
  log: () => {}
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../UniversePhotoBridge/main.js'), 'utf8'), { up });
assert.equal(actions.size, 31);
// Initial app is already UniversePhoto; no app-change event is required.
actions.get('brush').callback();
assert.deepEqual(shortcuts.pop(), { key: 'b', modifiers: [] });
for (const action of actions.values()) action.callback();
assert.equal(shortcuts.length, 31);
assert.deepEqual(shortcuts.find(item => item.key === 'n' && item.modifiers.includes('cmd')), { key: 'n', modifiers: ['cmd', 'shift'] });
assert(!actions.has('addKeyframe'), 'No keyframe action before actual keyframes exist');
// A stale app hook cannot cause keystrokes in another app.
app = { bundleID: 'com.example.other', name: 'UniversePhoto Notes' };
const before = shortcuts.length;
actions.get('newLayer').callback();
assert.equal(shortcuts.length, before);
assert.equal(toasts.at(-1)[0], 'UniversePhoto ist nicht im Vordergrund');
// Return to the app and reconnect without an app event.
app = { bundleID: 'local.universephoto', name: 'UniversePhoto' };
handlers.get('connect')();
actions.get('playPause').callback();
assert.equal(shortcuts.at(-1).key, 'space');
console.log('Bridge tests passed: 31 actions, initial focus, stale focus gate, reconnect, shortcut mappings.');
