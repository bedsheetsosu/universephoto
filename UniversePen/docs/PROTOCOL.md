# UniversePen wire protocol (version 2)

Everything needed to write another client (e.g. Android) or host (e.g. Windows) that talks to the
existing apps. All multi-byte numbers are **little-endian**; floats are IEEE 754.

## Discovery

Bonjour (DNS-SD), TCP:

| Service | Purpose | TXT |
|---|---|---|
| `_tafel._tcp` | regular sessions | `id` = host ID (UUID string) |
| `_tafelpair._tcp` | only while the host shows a pairing code | `id` = host ID |

The host advertises on every interface (Wi-Fi, and the iPad's USB-Ethernet link when a cable is
connected). Peer-to-peer Wi-Fi (AWDL) is off unless enabled on both sides.

## Security

TLS 1.2 with a pre-shared key, cipher suite `TLS_PSK_WITH_AES_128_GCM_SHA256` only.

- **Pairing listener:** PSK = HKDF-SHA256(ikm = 12-character code in Crockford Base32 alphabet
  `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (upper case, no dashes), salt = `tafel-pairing-v1`,
  info = `tls-psk`, 32 bytes). PSK identity `tafel-pair`.
- **Session listener:** PSK = the host's 32-byte random key (handed out once during pairing).
  PSK identity `tafel-host`.

A peer without the key cannot finish the handshake. There is no forward secrecy.

## Framing

Every message: `[u8 type][u32 length][payload]`, payload ≤ 64 MiB. Unknown types must be ignored.

Strings in binary payloads: `[u16 length][UTF-8]`. Blobs: `[u32 length][bytes]`.

## Connections and roles

A client opens up to three TLS connections to the session listener; the first frame on each must
be `hello` (otherwise the host drops it, also after 5 s of silence):

1. **control** – opened first. Input to the host; host info, pongs, app info back.
2. **video** – after `hostInfo` arrived. Host → client video.
3. **audio** – optional. Host → client sound.

Video and audio use the same `deviceID` as the control connection. Separate connections keep
large video frames from delaying Pencil input (no head-of-line blocking).

Pairing uses one connection to the pairing listener: client sends `hello` with role `pair`,
host answers `pairGrant` and closes.

## Messages

JSON messages use plain `JSONEncoder` key names (camelCase).

| Type | Name | Dir. | Payload |
|---|---|---|---|
| 0x01 | hello | C→H | JSON `{protocolVersion: 2, role: "control"\|"video"\|"audio"\|"pair", deviceID, deviceName}` |
| 0x02 | hostInfo | H→C | JSON `{hostID, hostName, protocolVersion, sourceDescription, secondary?}` – `secondary: true`: another iPad has the picture, this one is an input-only tablet (it opens no video/audio connection) |
| 0x03 | clientConfig | C→H | JSON `{viewPixelWidth, viewPixelHeight, quality: {codec: "h264"\|"hevc", bitrateMbps, fps, resolutionScale, audio, adaptive, fullSource}, diagnostics?, batteryLevel?, batteryCharging?, tabletMode?, laser?}` – `tabletMode: true`: no video; pen coordinates are normalised to the iPad's active area and map onto the whole selected display. `laser: true`: pen samples only move the pointer and draw fading marks on a click-through overlay (no clicks) |
| 0x04 | pairGrant | H→C | JSON `{hostID, hostName, keyBase64}` (32-byte key) |
| 0x05 | error | H→C | JSON `{message}` |
| 0x06 | appInfo | H→C | JSON `{bundleID, name}` – app in front on the host |
| 0x07 | clientSettings | C→H | JSON `{settings, quality}` – the iPad's settings (for the developer API) |
| 0x08 | settingsPatch | H→C | JSON `{settings?, quality?, removeAppProfiles?}`, deep-merged on the iPad |
| 0x09 | sourceList | H→C | JSON `{mode, modes: [{id, title, available}], displays: [{id, title, available, aspect}], selectedDisplay, windows: [...], selectedWindow}`; mode ids `display`, `second-screen`, `region`, `window`; display/window ids as text |
| 0x0A | selectSource | C→H | JSON `{mode?, display?, window?, refresh?}` – `refresh: true` re-reads the window list first |
| 0x0B | pluginActions | H→C | JSON `[{id: "plugin/action", title, icon?, plugin}]` – actions of running Mac plugins |
| 0x0C | runPluginAction | C→H | JSON `{id}` |
| 0x0D | toast | H→C | JSON `{text, seconds}` – short message shown on the iPad |
| 0x0E | clipboard | both | 1 byte kind (0 empty, 1 UTF-8 text, 2 PNG) + data, max 32 MB – only sent when the user asks |
| 0x0F | requestClipboard | C→H | empty; the Mac answers with `clipboard` |
| 0x16 | requestScreenshot | C→H | empty; the Mac answers with `screenshot` |
| 0x17 | screenshot | H→C | PNG (JPEG if over 24 MB) of the streamed source at full resolution; empty = failed |
| 0x18 | paletteFrame | H→C (video connection) | JPEG of the palette area; empty = no palette |
| 0x19 | paletteMouse | C→H | MouseEvent, x/y 0…1 inside the palette area |
| 0x1A | paletteCommand | C→H | `u8`: 0 remove (forget the area), 1 pick (user drags out an area on the Mac) |
| 0x1B | hostCommand | C→H | `u8`: 0 toggle the time-lapse (the Mac answers with a toast) |
| 0x10 | pen | C→H | `u8 phase, f32 x, f32 y, f32 pressure, f32 tiltX, f32 tiltY, f32 rotation°, f64 timestamp` |
| 0x11 | scroll | C→H | `f32 x, f32 y, f32 dx, f32 dy, u8 modifiers` |
| 0x12 | mouse | C→H | `u8 phase (0 move, 1 down, 2 up, 3 exit), u8 button (0 left, 1 right), f32 x, f32 y` |
| 0x20 | shortcut | C→H | `u8 modifiers, string key` (character, or `return tab space delete esc left right up down`) |
| 0x21 | key | C→H | `u16 HID usage (page 7), bool down` |
| 0x22 | text | C→H | UTF-8 text (typed on an on-screen keyboard) |
| 0x23 | charKey | C→H | JSON `{key, down}` – hold/release a key given as character or special key name (resolved with the Mac's layout; tablet key pad) |
| 0x30 | ping | C→H | `f64 clientTime` (seconds since 1970) |
| 0x31 | pong | H→C | `f64 clientTime, f64 hostTime` |
| 0x40 | videoFormat | H→C | `u8 codec (0 H.264, 1 HEVC), u32 width, u32 height, u8 count, count × blob parameter set, [bool displayP3], [bool sRGBTransfer]` – sRGBTransfer (0.8+): tone curve is sRGB instead of BT.709 |
| 0x41 | videoFrame | H→C | `bool keyframe, f64 captureTime, rest = AVCC/HVCC (4-byte big-endian NAL lengths)` |
| 0x42 | requestKeyframe | C→H | empty |
| 0x50 | audioChunk | H→C | `u32 sampleRate, u8 channels, f64 captureTime, rest = s16 LE interleaved PCM` |

- **Coordinates** (`x`, `y`) are normalised 0…1 over the video image (top-left origin).
- **Pen phases:** 0 hover, 1 down, 2 move, 3 up, 4 enter (proximity in), 5 exit, 6 cancel.
  Pressure 0…1; tilt −1…1 per axis; rotation in degrees (Pencil Pro barrel roll).
- **Modifiers** bit set: 1 ⌘, 2 ⇧, 4 ⌥, 8 ⌃.
- **Scroll** deltas are fractions of the image size; the host scales them to pixels.
- **Video:** the host sends `videoFormat` before every keyframe. A client that missed one sends
  `requestKeyframe`. Frames should be displayed immediately (no buffering).
- **Timing:** ping every 0.5 s. The client treats 2.5 s without a pong as a dead link and
  reconnects (cable first, then Wi-Fi).
- **Backpressure:** the host drops frames *before* encoding while more than ~2 frames are queued on
  the video socket, and (if `adaptive`) lowers the bitrate.

## Versioning

Hosts reject a `hello` with a different `protocolVersion` with an `error` message. Additions that
older peers can ignore (new message types, trailing fields) do not bump the version.
