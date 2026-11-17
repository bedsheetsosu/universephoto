# UniversePhoto Bridge 0.2

This optional JavaScript plugin adds 31 actions to UniversePen. Assign them to the shortcut bar, radial menu, squeeze, double-tap or finger gestures using UniversePen's existing assignment controls. The plugin does not modify profiles or gesture settings. It has no network or filesystem access.

## Install

1. In Finder, open `~/Library/Application Support/UniversePen/Plugins/`.
2. Copy this folder as `UniversePhotoBridge`. If a folder with that name already exists, preserve it and compare versions before replacing anything.
3. Open UniversePen → Plugins, then enable **UniversePhoto Bridge**.
4. Bring UniversePhoto to the foreground. Actions check the current foreground app before sending a shortcut.

The plugin uses the documented `up.action`, `up.shortcut`, `up.frontApp`, `up.on`, `up.toast` and `up.log` interfaces. No sample filter is installed. UniversePen's Developer API is not required for shortcut actions; Accessibility permission for UniversePen is required by its shortcut injection. The separate optional UniversePhoto input adapter uses the Developer API only after its user-facing toggle is enabled.

## Actions and default shortcuts

| Action | Shortcut |
|---|---|
| Brush / eraser / eyedropper | B / E / I |
| Move / rectangle selection | V / M |
| Fill layer / gradient / text | G / D / T |
| Rectangle / ellipse / hand | R / C / P |
| Brush size increase / decrease | ] / [ |
| Brush opacity increase / decrease | . / , |
| Next palette color | X |
| Undo / redo | Command Z / Command Shift Z |
| New / duplicate layer | Command Shift N / Command J |
| Delete layer | Command Shift Delete |
| Toggle layer visibility | Option H |
| Mirror canvas | H |
| Zoom in / out / fit | Command + / Command - / Command 0 |
| Duplicate frame | Shift F |
| Previous / next frame | Option Left / Option Right |
| Onion skin | Option O |
| Play / pause | Space |

These are keyboard commands, not a state synchronization channel. The plugin cannot read the current brush, layer, color or frame from UniversePhoto. Native and API gesture copies are not replayed by the input adapter, because UniversePen already executes configured gesture actions.

## Validation

Run `node Tests/PluginBridge/bridge.test.cjs` from the project root. It checks action registration, initial focus, stale focus events, reconnection and emitted shortcuts without installing a plugin or altering profiles. Real iPad action delivery still requires a manual hardware check in the actual applications.
