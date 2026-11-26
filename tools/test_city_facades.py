#!/usr/bin/env python3
"""test_city_facades.py — City expansion stage 3: facades, shop signs, Centro ground-floor shops, billboards, night tags.

Builds EVERY lot of the REAL map with the REAL BuildingBuilder.lua + CityDressing.lua (Luau -> Lua via
tools/luau2lua.py, run by lupa; a recording Kit stores every part) — and the previous BuildingBuilder from git for
comparison. Checks:
  [1] building bodies unchanged: per lot, the parts that are not new dressing are identical to the previous build,
      except the intended changes (old one-style shop sign + awning removed, deco neon strip day/night material,
      front glass of Centro buildings with a ground-floor shop starts above the shop band)
  [2] every business has its sign: a part whose text is the business name, in the business font; signs fit the facade
  [3] nothing new leaves the lot near the ground (< 8 studs; Centro ground-floor shops: <= 0.6 like the existing facade
      glass); higher details stay inside the building's existing envelope
  [4] door corridors (REAL Entrances door formulas) stay free of new collidable parts (floor .. +7.5 studs)
  [5] sidewalk: no new part below 8 studs within 1.0 stud of a pedestrian walking line (REAL PedGraph + Entrances)
  [6] night: every NightGlow / ShopWindow part has a NightColor; counts of signs, windows, billboards
  [7] part budget: total parts before / after, per style, worst building
Writes docs/city3_facades_preview.png (schematic front elevations, day and night) unless --no-preview.
Usage: python3 -I tools/test_city_facades.py <lupa-site-packages> [--no-preview] [--base <git rev>]
"""
import math
import os
import subprocess
import sys

sys.path.insert(0, sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
from lupa import LuaRuntime  # noqa: E402
import ambient_data  # noqa: E402
from luau2lua import convert  # noqa: E402

BB = "src/ServerScriptService/WorldGen/BuildingBuilder.lua"
CD = "src/ServerScriptService/WorldGen/CityDressing.lua"
PREVIEW = "--no-preview" not in sys.argv
fails = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        fails.append(name)


MOCK = r"""
math.clamp = function(x, a, b) if x < a then return a elseif x > b then return b end return x end
local V3 = {}
Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3) end
V3.__index = function(v, k)
  if k == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
end
V3.__add = function(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V3.__sub = function(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V3.__mul = function(a, b) if type(a) == "number" then a, b = b, a end
  if type(b) == "number" then return Vector3.new(a.X*b, a.Y*b, a.Z*b) end
  return Vector3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z) end
V3.__div = function(a, b) return Vector3.new(a.X/b, a.Y/b, a.Z/b) end
V3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
Vector3.zero = Vector3.new(0, 0, 0)

local CF = {}
CF.__index = function(c, k) if k == "Position" then return c.P end end
CFrame = {}
local function mk(p, r) return setmetatable({P = p, R = r}, CF) end
local I = {1,0,0, 0,1,0, 0,0,1}
function CFrame.new(x, y, z)
  if type(x) == "table" then return mk(x, I) end
  return mk(Vector3.new(x or 0, y or 0, z or 0), I)
end
local function mm(a, b)
  local r = {}
  for i = 0, 2 do for j = 0, 2 do
    r[i*3+j+1] = a[i*3+1]*b[j+1] + a[i*3+2]*b[3+j+1] + a[i*3+3]*b[6+j+1]
  end end
  return r
end
local function mv(r, v)
  return Vector3.new(r[1]*v.X + r[2]*v.Y + r[3]*v.Z, r[4]*v.X + r[5]*v.Y + r[6]*v.Z, r[7]*v.X + r[8]*v.Y + r[9]*v.Z)
end
function CFrame.Angles(rx, ry, rz)
  local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
  local X = {1,0,0, 0,cx,-sx, 0,sx,cx}
  local Y = {cy,0,sy, 0,1,0, -sy,0,cy}
  local Z = {cz,-sz,0, sz,cz,0, 0,0,1}
  return mk(Vector3.zero, mm(mm(X, Y), Z))
end
CF.__mul = function(a, b)
  if getmetatable(b) == V3 then return a.P + mv(a.R, b) end
  return mk(a.P + mv(a.R, b.P), mm(a.R, b.R))
end

local C3 = {}
C3.__index = C3
Color3 = {}
function Color3.new(r, g, b) return setmetatable({R = r, G = g, B = b}, C3) end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
function Color3.fromHSV(h, s, v)
  local i = math.floor(h * 6); local f = h * 6 - i
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  i = i % 6
  if i == 0 then return Color3.new(v, t, p) elseif i == 1 then return Color3.new(q, v, p)
  elseif i == 2 then return Color3.new(p, v, t) elseif i == 3 then return Color3.new(p, q, v)
  elseif i == 4 then return Color3.new(t, p, v) end
  return Color3.new(v, p, q)
end
function C3:ToHSV()
  local r, g, b = self.R, self.G, self.B
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h / 6
  end
  return h, (mx > 0) and d / mx or 0, mx
end
function C3:Lerp(o, a) return Color3.new(self.R + (o.R - self.R) * a, self.G + (o.G - self.G) * a, self.B + (o.B - self.B) * a) end

Enum = setmetatable({}, {__index = function(_, k)
  return setmetatable({}, {__index = function(_, j) return k .. "." .. j end}) end})

local RNG = {}
RNG.__index = RNG
Random = {}
function Random.new(seed)
  local s = math.floor(math.abs(seed or 1) * 1000003) % 2147483647
  if s == 0 then s = 1 end
  return setmetatable({s = s}, RNG)
end
function RNG:_next() self.s = (self.s * 48271) % 2147483647; return self.s / 2147483647 end
function RNG:NextNumber(a, b) local u = self:_next(); if a == nil then return u end; return a + (b - a) * u end
function RNG:NextInteger(a, b) return a + math.floor(self:_next() * (b - a + 1)) end

Instance = {}
function Instance.new(cls)
  local o = {ClassName = cls, Attr = {}}
  function o:SetAttribute(k, v) self.Attr[k] = v end
  return o
end
game = { GetService = function(_, name) return { Shared = { MapDefinitions = "__MD" } } end }
script = { Parent = { CityDressing = "__CD" } }

-- recording Kit
REC = {}
KIT = {}
local function record(kind, size, cf, color, material, props)
  local r = { Kind = kind, Size = size, CF = cf, Color = color, Material = material, Name = "", Transparency = 0,
              CanCollide = true, Attr = {}, Tags = {}, Labels = {} }
  if props then
    if props.Name then r.Name = props.Name end
    if props.Transparency then r.Transparency = props.Transparency end
    if props.CanCollide == false then r.CanCollide = false end
  end
  REC[#REC + 1] = r
  local proxy = { _rec = r }
  function proxy:SetAttribute(k, v) self._rec.Attr[k] = v end
  return proxy
end
function KIT:Box(parent, size, cf, color, material, props) return record("Box", size, cf, color, material, props) end
function KIT:Cylinder(parent, height, diameter, cf, color, material, props)
  return record("Cyl", Vector3.new(diameter, height, diameter), cf, color, material, props) end
function KIT:Ball(parent, d, cf, color, material, props) return record("Ball", Vector3.new(d, d, d), cf, color, material, props) end
function KIT:Wedge(parent, size, cf, color, material, props) return record("Wedge", size, cf, color, material, props) end
function KIT:Label(part, face, text, color, glow, font)
  local l = part._rec.Labels; l[#l + 1] = { Face = face, Text = text, Font = font or "", Color = color, Glow = glow and true or false }
end
function KIT:Tag(part, tag) part._rec.Tags[tag] = true end
"""


def load_builder(lua, bb_src, cd_src):
    """Returns the Styles table of the given BuildingBuilder source (CityDressing optional)."""
    cut = bb_src.index("function BuildingBuilder.Build")
    src = bb_src[:cut] + "\nBuildingBuilder._Styles = Styles\nreturn BuildingBuilder\n"
    if cd_src is not None:
        cd = lua.execute(convert(cd_src))
        lua.globals().__CDMOD = cd
    lua.execute("""
local realRequire = require
require = function(x)
  if x == "__MD" then return __MDMOD end
  if x == "__CD" then return __CDMOD end
  return realRequire(x)
end
""")
    return lua.execute(convert(src))._Styles


def build_all(styles_src_pair, data):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    lua.globals().__MDMOD = lua.table_from({"GetData": lua.eval("function() return __DATA end")})
    lua.globals().__DATA = data_for(lua, data)
    styles = load_builder(lua, *styles_src_pair)
    g = lua.globals()
    runner = lua.eval("""
function(styles, lot, poiById)
  REC = {}
  local ctx = {
    Kit = KIT, Model = Instance.new("Model"),
    Base = CFrame.new(lot.Center.X, lot.BaseY or 0, lot.Center.Z) * CFrame.Angles(0, math.rad(lot.Rotation), 0),
    W = lot.Width, D = lot.Depth, H = lot.Height, Rng = Random.new(lot.Seed), Lot = lot,
    Poi = lot.PoiId and poiById[lot.PoiId] or nil,
  }
  local fn = styles[lot.Style]
  if not fn then return nil, "nostyle" end
  local ok, err = pcall(fn, ctx)
  if not ok then return nil, tostring(err) end
  return REC, ""
end""")
    data_l = g.__DATA
    poi_by_id = lua.table_from({p.Id: p for p in data_l.POIs.values()})
    out, errors = {}, []
    for lot in data_l.Lots.values():
        rec, err = runner(styles, lot, poi_by_id)
        if err:
            errors.append((lot.Id, lot.Style, err))
            continue
        out[lot.Id] = [to_py(r) for r in rec.values()]
    return out, errors, data_l


def data_for(lua, _):
    data, _raw = ambient_data.load(lua)
    # Lot fields BuildingBuilder reads; POIById for ctx.Poi
    return data


def to_py(r):
    cf = r.CF
    R = [cf.R[i] for i in range(1, 10)]
    return dict(Kind=r.Kind, Name=r.Name, Size=(r.Size.X, r.Size.Y, r.Size.Z), P=(cf.P.X, cf.P.Y, cf.P.Z), R=R,
                Color=(round(r.Color.R * 255), round(r.Color.G * 255), round(r.Color.B * 255)), Material=r.Material,
                Transparency=r.Transparency, CanCollide=r.CanCollide,
                Attr={k: (_c3(v) if not isinstance(v, (int, float, str, bool)) else v) for k, v in r.Attr.items()},
                Tags=set(r.Tags.keys()),
                Labels=[dict(Face=l.Face, Text=l.Text, Font=l.Font, Color=_c3(l.Color)) for l in r.Labels.values()])


def _c3(c):
    try:
        return (round(c.R * 255), round(c.G * 255), round(c.B * 255))
    except Exception:
        return (255, 255, 255)


def local_box(part, lot):
    """Part corners in lot-local coordinates -> (xmin, xmax, ymin, ymax, zmin, zmax)."""
    th = math.radians(lot.Rotation)
    c, s = math.cos(th), math.sin(th)
    bx, by, bz = lot.Center.X, (lot.BaseY or 0), lot.Center.Z
    sx, sy, sz = (v / 2 for v in part["Size"])
    R, P = part["R"], part["P"]
    xs, ys, zs = [], [], []
    for dx in (-sx, sx):
        for dy in (-sy, sy):
            for dz in (-sz, sz):
                wx = P[0] + R[0] * dx + R[1] * dy + R[2] * dz
                wy = P[1] + R[3] * dx + R[4] * dy + R[5] * dz
                wz = P[2] + R[6] * dx + R[7] * dy + R[8] * dz
                # inverse of Angles(0, th, 0): local = R^T (w - base)
                ox, oz = wx - bx, wz - bz
                xs.append(c * ox - s * oz)
                zs.append(s * ox + c * oz)
                ys.append(wy - by)
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


def world_footprint(part):
    sx, _, sz = (v / 2 for v in part["Size"])
    R, P = part["R"], part["P"]
    pts = []
    for dx, dz in ((-sx, -sz), (sx, -sz), (sx, sz), (-sx, sz)):
        pts.append((P[0] + R[0] * dx + R[2] * dz, P[2] + R[6] * dx + R[8] * dz))
    return pts


def seg_dist(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    L = dx * dx + dz * dz
    t = 0 if L < 1e-12 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L))
    return math.hypot(px - ax - dx * t, pz - az - dz * t)


def poly_seg_distance(poly, a, b):
    # 0 if the segment crosses the polygon; else min corner/endpoint distances (convex quad)
    def inside(p):
        sign = None
        for i in range(4):
            x1, z1 = poly[i]
            x2, z2 = poly[(i + 1) % 4]
            cr = (x2 - x1) * (p[1] - z1) - (z2 - z1) * (p[0] - x1)
            if abs(cr) < 1e-9:
                continue
            if sign is None:
                sign = cr > 0
            elif sign != (cr > 0):
                return False
        return True
    if inside(a) or inside(b):
        return 0.0
    best = min(seg_dist(p[0], p[1], a[0], a[1], b[0], b[1]) for p in poly)
    for i in range(4):
        c1, c2 = poly[i], poly[(i + 1) % 4]
        best = min(best, seg_dist(a[0], a[1], c1[0], c1[1], c2[0], c2[1]), seg_dist(b[0], b[1], c1[0], c1[1], c2[0], c2[1]))
        # proper intersection
        d1 = (b[0] - a[0]) * (c1[1] - a[1]) - (b[1] - a[1]) * (c1[0] - a[0])
        d2 = (b[0] - a[0]) * (c2[1] - a[1]) - (b[1] - a[1]) * (c2[0] - a[0])
        d3 = (c2[0] - c1[0]) * (a[1] - c1[1]) - (c2[1] - c1[1]) * (a[0] - c1[0])
        d4 = (c2[0] - c1[0]) * (b[1] - c1[1]) - (c2[1] - c1[1]) * (b[0] - c1[0])
        if (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0):
            return 0.0
    return best


# ------------------------------------------------------------------ build old and new
new_src = (open(BB, encoding="utf-8").read(), open(CD, encoding="utf-8").read())
# comparison base: the stage-2 commit (before any facade work); override with --base <git revision>
BASE_REV = sys.argv[sys.argv.index("--base") + 1] if "--base" in sys.argv else "13c5a9e"
old_src = (subprocess.run(["git", "show", f"{BASE_REV}:{BB}"], capture_output=True, text=True, check=True).stdout, None)

new_parts, new_err, data = build_all(new_src, None)
old_parts, old_err, _ = build_all(old_src, None)
check("[0] every lot builds (new)", not new_err, str(new_err[:3]))
check("[0] every lot builds (previous, for comparison)", not old_err, str(old_err[:3]))
lots = {l.Id: l for l in data.Lots.values()}

DRESS = {"Sign", "SignFrame", "SignRail", "SignSmall", "Canopy", "Blade", "BladeArm", "Awning", "Planter", "Plant",
         "Fascia", "Vitrine", "VitrineSill", "EntranceFrame", "AC", "ACFan", "TankBase", "Tank", "TankRoof",
         "DecoCorner", "Crown", "NeonFin", "EntryHood", "EntryLamp", "Chimney", "FlowerBox", "Flowers", "Railing",
         "BillboardLeg", "BillboardFrame", "Billboard"}


def key(p):
    return (p["Kind"], tuple(round(v, 2) for v in p["Size"]), tuple(round(v, 2) for v in p["P"]), p["Color"], p["Material"])


# ------------------------------------------------------------------ [1] bodies unchanged
unexpected = []
for lid, parts in new_parts.items():
    lot = lots[lid]
    base_new = [p for p in parts if p["Name"] not in DRESS]
    base_old = old_parts.get(lid, [])
    kn = {}
    for p in base_new:
        kn[key(p)] = kn.get(key(p), 0) + 1
    ko = {}
    for p in base_old:
        ko[key(p)] = ko.get(key(p), 0) + 1
    removed = [k for k in ko if ko[k] > kn.get(k, 0)]
    added = [k for k in kn if kn[k] > ko.get(k, 0)]
    biz = lot.Business
    retail = biz is not None and biz.Unit == "Ground"
    allowed_removed, allowed_added = 0, 0
    if lot.Style in ("storefront", "storefront_plain"):
        allowed_removed = sum(1 for k in removed if k[4] in ("Material.Fabric", "Material.Neon"))
    if lot.Style == "deco_lowrise":
        allowed_removed = sum(1 for k in removed if k[4] == "Material.Neon")
        allowed_added = sum(1 for k in added if k[4] == "Material.SmoothPlastic" and abs(k[1][1] - 0.6) < 1e-6)
    if retail and lot.Style in ("office", "apartment_modern"):
        allowed_removed = sum(1 for k in removed if k[4] == "Material.Glass")
        allowed_added = sum(1 for k in added if k[4] == "Material.Glass")
    if len(removed) != allowed_removed or len(added) != allowed_added:
        unexpected.append((lid, lot.Style, removed[:2], added[:2]))
check("[1] building bodies, colours, sizes unchanged (only intended sign/strip/glass changes)", not unexpected,
      f"{len(unexpected)} lots differ: {unexpected[:2]}")

# ------------------------------------------------------------------ [2] signs
missing_sign, wrong_font, too_wide = [], [], []
for lid, parts in new_parts.items():
    lot = lots[lid]
    b = lot.Business
    if b is None:
        continue
    labels = [(p, l) for p in parts for l in p["Labels"] if l["Text"] == b.Name]
    if not labels:
        missing_sign.append(b.Name)
        continue
    if any(l["Font"] != b.Font for _, l in labels):
        wrong_font.append(b.Name)
    for p, _ in labels:
        x0, x1, *_ = local_box(p, lot)
        if p["Name"] in ("Sign", "SignSmall") and (x0 < -lot.Width / 2 - 0.01 or x1 > lot.Width / 2 + 0.01):
            too_wide.append(b.Name)
check("[2] every business has its sign (name on a part)", not missing_sign, f"missing {missing_sign[:5]}")
check("[2] signs use the business font", not wrong_font, str(wrong_font[:5]))
check("[2] signs fit the facade width", not too_wide, str(too_wide[:5]))
old_style_signs = sum(1 for lid, parts in new_parts.items() if lots[lid].Style in ("storefront", "storefront_plain")
                      for p in parts if p["Material"] == "Material.Neon")
check("[2] no always-on neon left on shop fronts (day/night instead)", old_style_signs == 0, str(old_style_signs))

# ------------------------------------------------------------------ [3] lot bounds / envelope
out_low, out_high = [], []
for lid, parts in new_parts.items():
    lot = lots[lid]
    w, d = lot.Width, lot.Depth
    b = lot.Business
    retail = b is not None and b.Unit == "Ground"
    old_env = [local_box(p, lot) for p in old_parts.get(lid, [])]
    env = (min([e[0] for e in old_env] + [-w / 2]), max([e[1] for e in old_env] + [w / 2]),
           min([e[4] for e in old_env] + [-d / 2]), max([e[5] for e in old_env] + [d / 2]))
    for p in parts:
        if p["Name"] not in DRESS:
            continue
        x0, x1, y0, y1, z0, z1 = local_box(p, lot)
        band = retail and p["Name"] in ("Vitrine", "VitrineSill", "Fascia", "Sign", "SignSmall", "EntranceFrame")
        tol = 0.61 if band else 0.01
        if y0 < 8:
            if x0 < -w / 2 - 0.01 or x1 > w / 2 + 0.01 or z0 < -d / 2 - tol or z1 > d / 2 + 0.01:
                out_low.append((lid, lot.Style, p["Name"], round(z0 + d / 2, 2)))
        else:
            if x0 < env[0] - 0.01 or x1 > env[1] + 0.01 or z0 < min(env[2], -d / 2 - tol + 0.01) - 0.01 or z1 > env[3] + 0.01:
                out_high.append((lid, lot.Style, p["Name"], round(z0 - env[2], 2)))
check("[3] near the ground nothing new leaves the lot (Centro shop band <= 0.6 like the facade glass)", not out_low,
      f"{len(out_low)}: {out_low[:4]}")
check("[3] higher details stay inside the building's existing envelope", not out_high, f"{len(out_high)}: {out_high[:4]}")
if out_high:
    cats = {}
    for lid, st, nm, over in out_high:
        k = (st, nm)
        cats[k] = min(cats.get(k, 0), over)
    print("      by style/part (worst overshoot):", cats)

# ------------------------------------------------------------------ [4] door corridors
EN = LuaRuntime(unpack_returned_tuples=True).execute(open("src/ReplicatedStorage/Shared/Ambient/Entrances.lua", encoding="utf-8").read())
blocked = []
for lid, parts in new_parts.items():
    lot = lots[lid]
    fn = EN.Styles[lot.Style]
    if fn is None:
        continue
    doors, _use = fn(lot.Width, lot.Depth)
    for door in doors.values():
        dx, dz, fy, dw = door[1], door[2], door[3], door[4]
        for p in parts:
            if p["Name"] not in DRESS or not p["CanCollide"]:
                continue
            x0, x1, y0, y1, z0, z1 = local_box(p, lot)
            if x1 > dx - dw / 2 - 0.3 and x0 < dx + dw / 2 + 0.3 and y0 < fy + 7.5 and y1 > fy and \
                    z1 > -lot.Depth / 2 - 4 and z0 < dz - 0.05:
                blocked.append((lid, lot.Style, p["Name"]))
check("[4] door corridors free of new collidable parts", not blocked, f"{len(blocked)}: {blocked[:4]}")

# ------------------------------------------------------------------ [5] sidewalk walking lines
lua2 = LuaRuntime(unpack_returned_tuples=True)
d2, _ = ambient_data.load(lua2)
TG = lua2.execute(open("src/ReplicatedStorage/Shared/Ambient/TrafficGraph.lua", encoding="utf-8").read())
PG = lua2.execute(open("src/ReplicatedStorage/Shared/Ambient/PedGraph.lua", encoding="utf-8").read())
EN2 = lua2.execute(open("src/ReplicatedStorage/Shared/Ambient/Entrances.lua", encoding="utf-8").read())
CFG = lua2.execute(open("src/ReplicatedStorage/Modules/AmbientConfig.lua", encoding="utf-8").read())
tg = TG.Build(d2, CFG.Traffic)
pg = PG.Build(d2, tg)
EN2.Build(d2, pg, PG, tg)
GRID = 64
grid = {}
for ln in pg.Links.values():
    if ln.Crossing or ln.Door or ln.DoorLink:
        continue
    a, b = (ln.A.X, ln.A.Z), (ln.B.X, ln.B.Z)
    for gx in range(int(math.floor(min(a[0], b[0]) / GRID)) - 1, int(math.floor(max(a[0], b[0]) / GRID)) + 2):
        for gz in range(int(math.floor(min(a[1], b[1]) / GRID)) - 1, int(math.floor(max(a[1], b[1]) / GRID)) + 2):
            grid.setdefault((gx, gz), []).append((a, b))
close = []
worst = 99.0
for lid, parts in new_parts.items():
    lot = lots[lid]
    for p in parts:
        if p["Name"] not in DRESS:
            continue
        x0, x1, y0, y1, z0, z1 = local_box(p, lot)
        if y0 >= 8:
            continue
        poly = world_footprint(p)
        cx = sum(q[0] for q in poly) / 4
        cz = sum(q[1] for q in poly) / 4
        for a, b in grid.get((int(math.floor(cx / GRID)), int(math.floor(cz / GRID))), []):
            dd = poly_seg_distance(poly, a, b)
            worst = min(worst, dd)
            if dd < 1.0:
                close.append((lid, lot.Style, p["Name"], round(dd, 2)))
                break
check("[5] no new low part within 1 stud of a pedestrian walking line", not close,
      f"closest {worst:.2f} studs" + (f"; {len(close)}: {close[:4]}" if close else ""))

# ------------------------------------------------------------------ [6] night tags
glow = [p for parts in new_parts.values() for p in parts if "NightGlow" in p["Tags"]]
win = [p for parts in new_parts.values() for p in parts if "ShopWindow" in p["Tags"]]
txt = [p for parts in new_parts.values() for p in parts if "NightText" in p["Tags"]]
no_color = [p["Name"] for p in glow + win if "NightColor" not in p["Attr"]]
boards = [p for parts in new_parts.values() for p in parts if p["Name"] == "Billboard"]
check("[6] every NightGlow / ShopWindow part has a NightColor", not no_color, str(no_color[:4]))
print(f"INFO night: NightGlow {len(glow)}, ShopWindow {len(win)}, NightText {len(txt)}, billboards {len(boards)}")
check("[6] billboards: a few, not everywhere (5..30)", 5 <= len(boards) <= 30, str(len(boards)))

# ------------------------------------------------------------------ [7] budget
n_old = sum(len(v) for v in old_parts.values())
n_new = sum(len(v) for v in new_parts.values())
per_style = {}
for lid, parts in new_parts.items():
    s = lots[lid].Style
    o = len(old_parts.get(lid, []))
    a = per_style.setdefault(s, [0, 0, 0])
    a[0] += 1
    a[1] += o
    a[2] += len(parts)
worst_b = max(new_parts.items(), key=lambda kv: len(kv[1]))
print(f"INFO parts: previous {n_old}, now {n_new} (+{n_new - n_old}, +{100 * (n_new - n_old) / n_old:.1f}%); "
      f"largest building {len(worst_b[1])} parts (lot {worst_b[0]}, {lots[worst_b[0]].Style})")
for s, (n, o, nw) in sorted(per_style.items(), key=lambda kv: -(kv[1][2] - kv[1][1]))[:10]:
    print(f"      {s:18s} {n:4d} lots: {o / n:5.1f} -> {nw / n:5.1f} parts per building")
check("[7] part budget: buildings grow by <= 60% in total", n_new <= n_old * 1.6, f"{n_new / n_old:.2f}x")
check("[7] no building above 150 parts", len(worst_b[1]) <= 150, str(len(worst_b[1])))

# ------------------------------------------------------------------ preview
if PREVIEW:
    import preview_facades
    preview_facades.render(new_parts, lots, os.path.join(ROOT, "docs", "city3_facades_preview.png"))

print()
print("RESULT:", "PASS" if not fails else "FAIL " + "; ".join(fails))
sys.exit(1 if fails else 0)
