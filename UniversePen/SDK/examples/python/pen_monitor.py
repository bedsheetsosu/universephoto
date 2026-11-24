#!/usr/bin/env python3
# UniversePen SDK example (MIT) – prints live Pencil pressure, tilt and gestures.
# Needs: UniversePen Mac app with "Developer API" switched on. No extra packages.
import json, socket

sock = socket.create_connection(("127.0.0.1", 47800))
f = sock.makefile("rw", encoding="utf-8")

def call(method, params=None, _id=[0]):
    _id[0] += 1
    f.write(json.dumps({"id": _id[0], "method": method, "params": params or {}}) + "\n"); f.flush()

call("status.get")
call("subscribe", {"topics": ["input", "gesture"]})
for line in f:
    msg = json.loads(line)
    if msg.get("event") == "pen" and msg["data"]["phase"] in ("down", "move"):
        d = msg["data"]
        bar = "#" * int(d["pressure"] * 40)
        print(f"{d['screenX']:7.1f},{d['screenY']:7.1f}  p={d['pressure']:.2f} {bar:<40} tilt=({d['tiltX']:+.2f},{d['tiltY']:+.2f}) rot={d['rotation']:.0f}°")
    elif msg.get("event") == "gesture":
        print("gesture:", msg["data"])
    elif "result" in msg or "error" in msg:
        print("reply:", msg)
