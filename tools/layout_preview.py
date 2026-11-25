#!/usr/bin/env python3
"""layout_preview.py — writes an HTML diagram of the touch driving layout computed by the REAL
DrivingLayout.lua (via lupa) for several screens. Usage: layout_preview.py <lupa-path> <out.html>"""
import sys
sys.path.insert(0, sys.argv[1])
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
layout = lua.execute(open("src/ReplicatedStorage/Modules/DrivingLayout.lua", encoding="utf-8").read())
SCREENS = [("iPhone 14 landscape · Car · Pad", 750, 390, "Car", "Pad"),
           ("Android 20:9 · Car · Buttons", 800, 360, "Car", "Buttons"),
           ("iPhone SE · Motorcycle · Pad", 667, 375, "Motorcycle", "Pad"),
           ("iPad 4:3 · Car · Pad", 1080, 790, "Car", "Pad")]
COLORS = {"Minimap": "#2a3550", "Hud": "#3b2a50", "Gas": "#ff7a45", "Brake": "#8a8f9e", "Pad": "#40c4d6",
          "Handbrake": "#eb5757", "Horn": "#6b7080", "SteerL": "#40c4d6", "SteerR": "#40c4d6"}
html = ["<html><body style='background:#0b0d12;color:#eee;font-family:sans-serif;margin:16px'>"]
for title, w, h, kind, steering in SCREENS:
    base = layout.ButtonSize(w, h, 1.0)
    rects = layout.Touch(w, h, base, lua.table_from({"Kind": kind, "Steering": steering}))
    html.append(f"<h3 style='margin:12px 0 6px'>{title} — {w}×{h} pt safe area, base {base}px</h3>")
    html.append(f"<div style='position:relative;width:{w}px;height:{h}px;background:linear-gradient(#5b6b86,#2d3341);border:1px solid #556'>")
    for name, r in rects.items():
        c = COLORS.get(name, "#1c1f28")
        html.append(f"<div style='position:absolute;left:{r.X}px;top:{r.Y}px;width:{r.W}px;height:{r.H}px;background:{c};opacity:.88;"
                    f"border-radius:10px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700'>{name}</div>")
    html.append("</div>")
html.append("</body></html>")
open(sys.argv[2], "w").write("\n".join(html))
