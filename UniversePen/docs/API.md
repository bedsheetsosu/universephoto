# UniversePen – local control API (Mac)

The Mac app can be controlled by other apps and scripts on the same Mac through a URL scheme.
Nothing listens on the network for this; macOS only delivers these URLs from local apps.

| URL | Effect |
|---|---|
| `universepen://mode/display` | Capture the whole display |
| `universepen://mode/second-screen` | Second screen (virtual display, experimental) |
| `universepen://mode/region` | iPad-shaped region |
| `universepen://mode/window` | Single window |
| `universepen://pair` | Show a pairing code |
| `universepen://pair/stop` | Cancel pairing |
| `universepen://show` | Bring the window to the front |
| `universepen://profile/Drawing` | Switch the connected iPad to its profile "Drawing" (name, case-insensitive, or the profile's id; spaces as `%20`) |

`tafel://…` works as an alias for older setups.

## Examples

Terminal / scripts:

```bash
open "universepen://mode/second-screen"
```

- **Shortcuts app:** action “Open URLs” with one of the URLs above.
- **Stream Deck:** “Website” action with the URL (uncheck “open in browser” if offered).
- **AppleScript:** `open location "universepen://mode/display"`

Unknown URLs are ignored and logged (Console, process “UniversePen Host”).
