#!/usr/bin/env python3
"""preview_carbody.py — renders the REAL CarBodyKit.lua part recipes (Luau -> Lua via tools/luau2lua.py, run by
lupa) with a small z-buffer rasterizer: every Block / Wedge / Cylinder / Ball as the game builds it, plus the dark
physics tyres. Writes docs/carbody_preview.png (3/4 front, 3/4 rear, side for each style) and prints part counts.

Usage: python3 -I tools/preview_carbody.py <lupa-site-packages> [style ...]
"""
import math
import os
import re
import sys

import numpy as np

sys.path.insert(0, sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
from lupa import LuaRuntime  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402
from luau2lua import convert  # noqa: E402

MOCK = r"""
math.clamp = function(x, a, b) if x < a then return a elseif x > b then return b end return x end
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local V3 = {}
Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3) end
V3.__add = function(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V3.__sub = function(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b) if type(a) == "number" then a, b = b, a end
  if type(b) == "number" then return Vector3.new(a.X*b, a.Y*b, a.Z*b) end
  return Vector3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z) end
local CF = {}
CFrame = {}
local function mk(p, r) return setmetatable({P = p, R = r}, CF) end
local I = {1,0,0, 0,1,0, 0,0,1}
local function mm(a, b) local r = {}
  for i = 0, 2 do for j = 0, 2 do r[i*3+j+1] = a[i*3+1]*b[j+1] + a[i*3+2]*b[3+j+1] + a[i*3+3]*b[6+j+1] end end
  return r end
local function mv(r, v) return Vector3.new(r[1]*v.X+r[2]*v.Y+r[3]*v.Z, r[4]*v.X+r[5]*v.Y+r[6]*v.Z, r[7]*v.X+r[8]*v.Y+r[9]*v.Z) end
function CFrame.new(x, y, z) if type(x) == "table" then return mk(x, I) end return mk(Vector3.new(x or 0, y or 0, z or 0), I) end
function CFrame.Angles(rx, ry, rz)
  local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
  return mk(Vector3.new(0,0,0), mm(mm({1,0,0, 0,cx,-sx, 0,sx,cx}, {cy,0,sy, 0,1,0, -sy,0,cy}), {cz,-sz,0, sz,cz,0, 0,0,1}))
end
CF.__mul = function(a, b) if getmetatable(b) == V3 then return a.P + mv(a.R, b) end return mk(a.P + mv(a.R, b.P), mm(a.R, b.R)) end
CF.__index = function(c, k) if k == "Position" then return c.P end end
Color3 = { fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end }
"""


def load_defs():
    src = open("src/ReplicatedStorage/Shared/VehicleDefinitions.lua", encoding="utf-8").read()
    defs = {}
    for m in re.finditer(r"\n\t(\w+) = \{\n\t\tType = \"Car\"(.*?)\n\t\},", src, re.S):
        body = m.group(2)
        d = {"Id": m.group(1)}
        for key in ("Width", "Length", "CabinHeight", "LowerHeight", "WheelRadius", "WheelWidth", "Wheelbase", "Track",
                    "Clearance"):
            mm = re.search(r"\b" + key + r" = ([\d.]+)", body)
            d[key] = float(mm.group(1))
        d["Style"] = re.search(r'Style = "(\w+)"', body).group(1)
        d["Spoiler"] = "Spoiler = true" in body
        d["Colors"] = [tuple(int(v) for v in c) for c in re.findall(r"rgb\((\d+), (\d+), (\d+)\)", body)]
        defs[d["Id"]] = d
    return defs


def shape_tris(shape, size, R, P, seg=20):
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
    if shape == "Block":
        v = np.array([[x, y, z] for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)])
        f = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4),
             (1, 5, 7), (1, 7, 3)]
    elif shape == "Wedge":
        # bottom 4, top edge at the back (+Z)
        v = np.array([[-sx, -sy, -sz], [sx, -sy, -sz], [sx, -sy, sz], [-sx, -sy, sz], [-sx, sy, sz], [sx, sy, sz]])
        f = [(0, 1, 2), (0, 2, 3), (3, 2, 5), (3, 5, 4), (0, 4, 5), (0, 5, 1), (0, 3, 4), (1, 5, 2)]
    elif shape == "Cylinder":
        a = np.linspace(0, 2 * math.pi, seg, endpoint=False)
        ring = np.c_[np.cos(a) * sy, np.sin(a) * sz]
        v = [[-sx, 0, 0], [sx, 0, 0]] + [[-sx, r[0], r[1]] for r in ring] + [[sx, r[0], r[1]] for r in ring]
        v = np.array(v)
        f = []
        for i in range(seg):
            j = (i + 1) % seg
            a0, a1, b0, b1 = 2 + i, 2 + j, 2 + seg + i, 2 + seg + j
            f += [(0, a1, a0), (1, b0, b1), (a0, a1, b1), (a0, b1, b0)]
    else:  # Ball
        f, v = [], []
        n = 10
        for i in range(n + 1):
            th = math.pi * i / n
            for j in range(seg):
                ph = 2 * math.pi * j / seg
                v.append([sx * math.sin(th) * math.cos(ph), sy * math.cos(th), sz * math.sin(th) * math.sin(ph)])
        v = np.array(v)
        for i in range(n):
            for j in range(seg):
                a, b2 = i * seg + j, i * seg + (j + 1) % seg
                c, d = a + seg, b2 + seg
                f += [(a, b2, d), (a, d, c)]
    return v @ R.T + P, np.array(f)


def render(items, yaw, pitch, size=(620, 360), frame=None):
    W, H = size
    allp = np.vstack([it["v"] for it in items])
    centre = (allp.min(0) + allp.max(0)) / 2 if frame is None else frame[0]
    cy, sy, cp, sp = math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    eye = np.array([sy * cp, sp, -cy * cp])  # yaw 0: camera in front of the car (car front = -Z)
    fwd = -eye
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    light = np.array([0.35, 0.85, -0.4])
    light /= np.linalg.norm(light)
    rel = allp - centre
    span = max(np.abs(rel @ right).max(), np.abs(rel @ up).max() * W / H) if frame is None else frame[1]
    scale = (W * 0.47) / span
    zbuf = np.full((H, W), np.inf)
    img = np.ones((H, W, 3)) * np.array([0.90, 0.92, 0.95])
    # ground shadow-ish line
    for blend in (False, True):
        for it in items:
            if (it["alpha"] < 0.99) != blend:
                continue
            P = it["v"] - centre
            X, Y, Z = W / 2 + (P @ right) * scale, H / 2 - (P @ up) * scale, P @ fwd
            for (a, b, c) in it["f"]:
                n = np.cross(it["v"][b] - it["v"][a], it["v"][c] - it["v"][a])
                ln = np.linalg.norm(n)
                if ln < 1e-12:
                    continue
                n /= ln
                shade = 0.42 + 0.58 * max(0.0, float(n @ light)) + 0.12 * float(abs(n @ fwd))
                col = np.clip(it["c"] * min(shade, 1.15), 0, 1)
                xs, ys = np.array([X[a], X[b], X[c]]), np.array([Y[a], Y[b], Y[c]])
                x0, x1 = max(int(math.floor(xs.min())), 0), min(int(math.ceil(xs.max())), W - 1)
                y0, y1 = max(int(math.floor(ys.min())), 0), min(int(math.ceil(ys.max())), H - 1)
                if x1 < x0 or y1 < y0:
                    continue
                d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
                if abs(d) < 1e-12:
                    continue
                gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
                w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
                w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
                w2 = 1 - w0 - w1
                inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
                z = w0 * Z[a] + w1 * Z[b] + w2 * Z[c]
                zb = zbuf[y0:y1 + 1, x0:x1 + 1]
                ok = inside & (z < zb)
                if not ok.any():
                    continue
                region = img[y0:y1 + 1, x0:x1 + 1]
                if blend:
                    al = it["alpha"]
                    region[ok] = region[ok] * (1 - al) + col * al
                else:
                    region[ok] = col
                    zb[ok] = z[ok]
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)), (centre, span)


def items_for(lua, kit, d, color):
    tbl = lua.table_from({k: v for k, v in d.items() if k != "Colors"})
    paint = lua.eval("function(r,g,b) return Color3.fromRGB(r,g,b) end")(*color)
    specs, prof = kit.Build(tbl, paint, "Full")
    items = []
    count = 0
    for s in specs.values():
        count += 1
        cf = s.CF
        R = np.array([cf.R[i] for i in range(1, 10)]).reshape(3, 3)
        P = np.array([cf.P.X, cf.P.Y, cf.P.Z])
        v, f = shape_tris(s.Shape, (s.Size.X, s.Size.Y, s.Size.Z), R, P)
        c = np.array([s.Color.R, s.Color.G, s.Color.B])
        if s.Material == "Neon":
            c = np.clip(c * 1.2, 0, 1)
        items.append({"v": v, "f": f, "c": c, "alpha": 1 - s.Transparency})
    # physics tyres (dark cylinders) as in the game
    Rw = d["WheelRadius"]
    for sx in (-1, 1):
        for sz in (-1, 1):
            v, f = shape_tris("Cylinder", (d["WheelWidth"], Rw * 2, Rw * 2), np.eye(3),
                              np.array([sx * d["Track"] / 2, 0, sz * d["Wheelbase"] / 2]), seg=28)
            items.append({"v": v, "f": f, "c": np.array([0.11, 0.11, 0.115]), "alpha": 1})
    return items, count


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    kit = lua.execute(convert(open("src/ReplicatedStorage/Shared/CarBodyKit.lua", encoding="utf-8").read()))
    defs = load_defs()
    styles = [a for a in sys.argv[2:]] or ["sedan"]
    chosen = [d for d in defs.values() if d["Style"] in styles]
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
    W, H = 760, 460
    out = Image.new("RGB", (W * 3, (H + 26) * len(chosen)), (255, 255, 255))
    for row, d in enumerate(chosen):
        bright = max(d["Colors"], key=lambda c: (max(c) - min(c), sum(c)))  # most colourful paint for the preview
        items, count = items_for(lua, kit, d, bright)
        print(f"{d['Id']} ({d['Style']}): {count} parts")
        frame = None
        for col, (yaw, pitch) in enumerate(((-38, 18), (145, 16), (-90, 4))):
            img, fr = render(items, yaw, pitch, (W, H), frame)
            frame = frame or fr
            out.paste(img, (col * W, row * (H + 26) + 26))
        ImageDraw.Draw(out).text((8, row * (H + 26) + 4), f"{d['Id']} ({d['Style']}) — {count} parça", font=font, fill=(20, 20, 20))
    path = os.path.join(ROOT, "docs", "carbody_preview.png")
    out.save(path)
    print("wrote", path)


if __name__ == "__main__":
    main()
