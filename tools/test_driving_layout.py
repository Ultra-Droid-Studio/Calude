#!/usr/bin/env python3
"""
test_driving_layout.py — runs the REAL src/ReplicatedStorage/Modules/DrivingLayout.lua in a Lua
interpreter (lupa) and checks the touch driving layout on many screen sizes / aspect ratios:
  * no two elements overlap (incl. reserved minimap + HUD areas), with a 4 px safety gap
  * nothing leaves the safe area
  * touch targets are at least 44 px
Usage: python3 tools/test_driving_layout.py [path-to-lupa-site-packages]
Screen sizes are Roblox GUI points of the safe area (after notch / top bar insets).
"""
import sys
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])
from lupa import LuaRuntime

SRC = "src/ReplicatedStorage/Modules/DrivingLayout.lua"
lua = LuaRuntime(unpack_returned_tuples=True)
layout = lua.execute(open(SRC, encoding="utf-8").read())

SCREENS = {
    "iPhone SE (landscape)": (667, 375),
    "iPhone 14 (landscape)": (750, 390),
    "iPhone 14 Pro Max (landscape)": (840, 428),
    "Android 20:9 (landscape)": (800, 360),
    "Android 21:9 (landscape)": (840, 360),
    "Small Android 16:9": (640, 360),
    "iPad 9th 4:3": (1080, 790),
    "iPad Pro 12.9": (1366, 1000),
    "Tablet 16:10": (1280, 780),
    "Phone portrait": (390, 800),
}
MIN_TOUCH = 44
failures = 0
checked = 0
for name, (w, h) in SCREENS.items():
    for user_scale in (0.85, 1.0, 1.2):
        base = layout.ButtonSize(w, h, user_scale)
        for kind in ("Car", "Motorcycle", "Passenger"):
            for steering in ("Pad", "Buttons"):
                opts = lua.table_from({"Kind": kind, "Steering": steering})
                rects = layout.Touch(w, h, base, opts)
                checked += 1
                overlaps = list(layout.FindOverlaps(rects, 4).values())
                oob = list(layout.FindOutOfBounds(rects, w, h).values())
                small = [k for k, r in rects.items() if k not in ("Minimap", "Hud", "Guidance") and min(r.W, r.H) < MIN_TOUCH]
                if overlaps or oob or small:
                    failures += 1
                    print(f"FAIL {name} {w}x{h} scale={user_scale} {kind}/{steering} base={base}: "
                          f"overlap={overlaps} out={oob} tooSmall={small}")
# desktop
for name, (w, h) in {"720p": (1280, 684), "1080p": (1920, 1044), "1440p": (2560, 1404), "small window": (1024, 600)}.items():
    d = layout.Desktop(w, h)
    rects = {"Cluster": d.Cluster, "Minimap": d.Minimap, "Guidance": d.Guidance}
    checked += 1
    if list(layout.FindOverlaps(lua.table_from(rects), 4).values()) or list(layout.FindOutOfBounds(lua.table_from(rects), w, h).values()):
        failures += 1
        print(f"FAIL desktop {name}")
print(f"{checked} layouts checked, {failures} failures")
sys.exit(1 if failures else 0)
