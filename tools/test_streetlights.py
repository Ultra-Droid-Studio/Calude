#!/usr/bin/env python3
"""test_streetlights.py — 3D street lights (KMB3D, CC-BY-4.0): offline check of the REAL StreetLights.lua placement.

Simulates what Studio's Import 3D produces from assets/streetlights/StreetLights.glb (one MeshPart per node, Size =
mesh bounding box, Position = box centre) at several import scales and origins, then places every lamp of the REAL
map (MapData "X|lamp" rows) with StreetLights.Place and checks:
  [1] the importer scale and origin do not matter (same result for 1 / 3.57 / 0.01 studs per metre, any origin)
  [2] pole base sits exactly on the lamp point (sidewalk height), pole height = 3.5 studs per metre
  [3] arm lamps reach over the road side (local -Z), like the old procedural lamp; others stay above the post
  [4] the lamp glass gets the "StreetLamp" tag (night switching) and a SpotLight on every LampLightEvery-th lamp
  [5] district styles: count per lamp type over the whole map
  [6] without the imported folder Place returns false (old procedural lamp is built)
Usage: python3 -I tools/test_streetlights.py <lupa-site-packages>
"""
import os
import sys

sys.path.insert(0, sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
from lupa import LuaRuntime  # noqa: E402
from luau2lua import convert  # noqa: E402

fails = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        fails.append(name)


MOCK = r"""
local V3 = {}
Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3) end
V3.__index = function(v, k) if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
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
local function tr(r) return {r[1],r[4],r[7], r[2],r[5],r[8], r[3],r[6],r[9]} end
function CFrame.new(x, y, z) if type(x) == "table" then return mk(x, I) end return mk(Vector3.new(x or 0, y or 0, z or 0), I) end
function CFrame.Angles(rx, ry, rz)
  local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
  return mk(Vector3.new(0,0,0), mm(mm({1,0,0, 0,cx,-sx, 0,sx,cx}, {cy,0,sy, 0,1,0, -sy,0,cy}), {cz,-sz,0, sz,cz,0, 0,0,1}))
end
CF.__index = function(c, k)
  if k == "Position" then return c.P end
  if k == "Rotation" then return mk(Vector3.new(0,0,0), c.R) end
  if k == "ToObjectSpace" then return function(self, o) local it = tr(self.R); return mk(mv(it, o.P - self.P), mm(it, o.R)) end end
  if k == "PointToObjectSpace" then return function(self, v) return mv(tr(self.R), v - self.P) end end
end
CF.__mul = function(a, b) if getmetatable(b) == V3 then return a.P + mv(a.R, b) end return mk(a.P + mv(a.R, b.P), mm(a.R, b.R)) end
Color3 = { fromRGB = function(r, g, b) return {R = r, G = g, B = b} end }
Enum = setmetatable({}, {__index = function(_, k) return setmetatable({}, {__index = function(_, j) return k .. "." .. j end}) end})
Instance = { new = function(cls)
  -- parenting a light records it on the part (part.SpotLight)
  return setmetatable({ClassName = cls}, {__newindex = function(t, k, v)
    rawset(t, k, v)
    if k == "Parent" and type(v) == "table" then v[cls] = t end
  end})
end }
warn = function(...) WARNED = (WARNED or 0) + 1; print("warn", ...) end

function MeshPart(name, size, cf)
  local p = {ClassName = "MeshPart", Name = name, Size = size, CFrame = cf, Children = {}}
  function p:IsA(c) return c == "MeshPart" or c == "BasePart" end
  function p:Clone() local q = MeshPart(self.Name, self.Size, self.CFrame); return q end
  return p
end
function Folder(name, parts)
  local f = {Name = name, Parts = parts}
  function f:GetDescendants() return self.Parts end
  return f
end
STORE = {}
game = { GetService = function(_, n)
  if n == "ServerStorage" then return { FindFirstChild = function(_, nm) return STORE[nm] end } end
  return { Shared = { MapDefinitions = "__MD", Config = "__CFG" }, FindFirstChild = function() return nil end }
end }
script = { Parent = { StreetLightData = "__SLD" } }
local realRequire = require
require = function(x)
  if x == "__MD" then return __MD end
  if x == "__CFG" then return { World = { LampLightEvery = 3 } } end
  if x == "__SLD" then return __SLD end
  return realRequire(x)
end
KIT = { Count = 0, Tags = {} }
function KIT:_tick() self.Count = self.Count + 1 end
function KIT:Tag(inst, tag) inst.Tag = tag end
"""


def districts_table(lua):
    rows = []
    for line in open("src/ReplicatedStorage/Shared/MapData.lua", encoding="utf-8"):
        f = line.rstrip("\n").split("|")
        if f[0] == "D":
            rows.append(lua.table_from({"Id": f[1], "Min": lua.table_from({"X": float(f[4]), "Y": float(f[5])}),
                                        "Max": lua.table_from({"X": float(f[6]), "Y": float(f[7])})}))
    data = lua.table_from({"Districts": lua.table_from(rows)})
    return lua.table_from({"GetData": lambda: data})


def lamps():
    out = []
    for line in open("src/ReplicatedStorage/Shared/MapData.lua", encoding="utf-8"):
        f = line.rstrip("\n").split("|")
        if f[0] == "X" and f[1] == "lamp":
            out.append((float(f[2]), float(f[3]), float(f[4]), float(f[5])))
    return out


def build_case(scale, origin):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    lua.execute("""
local oldMeshPart = MeshPart
function MeshPart(name, size, cf)
  local p = oldMeshPart(name, size, cf)
  function p:Clone()
    local q = MeshPart(self.Name, self.Size, self.CFrame)
    CAPTURE[#CAPTURE + 1] = q
    return q
  end
  return p
end
CAPTURE = {}
""")
    lua.globals().__MD = districts_table(lua)
    sld = lua.execute(open("src/ServerScriptService/WorldGen/StreetLightData.lua", encoding="utf-8").read())
    lua.globals().__SLD = sld
    sl = lua.execute(convert(open("src/ServerScriptService/WorldGen/StreetLights.lua", encoding="utf-8").read()))
    if scale is not None:
        mk = lua.eval("function(n, sx, sy, sz, x, y, z) return MeshPart(n, Vector3.new(sx, sy, sz), CFrame.new(x, y, z)) end")
        parts = []
        for key, d in sld.items():
            for role, mn, mx in (("Pole", d.PoleMin, d.PoleMax), ("Lamp", d.LampMin, d.LampMax)):
                size = [(mx[i] - mn[i]) * scale for i in (1, 2, 3)]
                centre = [((mx[i] + mn[i]) / 2 + (d.Offset if i == 1 else 0)) * scale + origin[i - 1] for i in (1, 2, 3)]
                parts.append(mk(f"StreetLight_{key}_{role}", *size, *centre))
        lua.globals().STORE["StreetLightModels"] = lua.eval("Folder")("StreetLightModels", lua.table_from(parts))
    fn = lua.eval("""function(sl, x, y, z, yaw, idx)
      CAPTURE = {}
      local cf = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
      local ok = sl.Place(KIT, {}, cf, { X = x, Z = z }, idx)
      local out = {}
      for _, q in ipairs(CAPTURE) do
        local lp = cf:PointToObjectSpace(q.CFrame.Position)
        out[#out + 1] = { Name = q.Name, SX = q.Size.X, SY = q.Size.Y, SZ = q.Size.Z, LX = lp.X, LY = lp.Y, LZ = lp.Z,
                          Tag = q.Tag, Light = q.SpotLight ~= nil }
      end
      return ok, out, sl.StyleAt(x, z)
    end""")
    return lua, sl, sld, fn


LAMPS = lamps()
print(f"lamps on the map: {len(LAMPS)}")
results = {}
for scale, origin in ((1.0, (0, 0, 0)), (3.57, (120.5, 7.25, -33.0)), (0.01, (-5, 0, 2))):
    lua, sl, sld, fn = build_case(scale, origin)
    res = []
    for i, (x, z, yaw, y) in enumerate(LAMPS):
        ok, out, style = fn(sl, x, y, z, yaw, i + 1)
        res.append((ok, [dict(r) for r in out.values()], style))
    results[scale] = res

base = results[1.0]
same = all(abs(a["LX"] - b["LX"]) < 1e-6 and abs(a["LY"] - b["LY"]) < 1e-6 and abs(a["LZ"] - b["LZ"]) < 1e-6
           and abs(a["SY"] - b["SY"]) < 1e-6
           for s in (3.57, 0.01) for (r1, r2) in zip(base, results[s]) for a, b in zip(r1[1], r2[1]))
check("[1] result independent of import scale (1 / 3.57 / 0.01) and origin", same)
check("[2] every lamp placed with the 3D model", all(ok for ok, _, _ in base), f"{sum(ok for ok, _, _ in base)}/{len(base)}")

S = 3.5
bad_base, bad_height, bad_reach, bad_tag = [], [], [], []
for (ok, parts, style), (x, z, yaw, y) in zip(base, LAMPS):
    d = sld[style]
    pole, head = parts[0], parts[1]  # Place clones the pole first, then the lamp
    bottom = pole["LY"] - pole["SY"] / 2
    if abs(bottom) > 1e-6:
        bad_base.append(bottom)
    if abs(pole["SY"] - (d.PoleMax[2] - d.PoleMin[2]) * S) > 1e-6:
        bad_height.append(pole["SY"])
    if d.Kind == "Arm" and not (head["LZ"] < -3.5):
        bad_reach.append((style, head["LZ"]))
    if d.Kind in ("Post", "Twin") and abs(head["LZ"]) > 3:
        bad_reach.append((style, head["LZ"]))
    if head.get("Tag") != "StreetLamp":
        bad_tag.append(style)
check("[2] pole base exactly on the lamp point (sidewalk height)", not bad_base, str(bad_base[:3]))
check("[2] pole height = 3.5 studs per metre", not bad_height, str(bad_height[:3]))
heights = sorted({round(sld[s].PoleMax[2] * S, 1) for s in sld.keys()})
print(f"      pole heights {heights[0]}..{heights[-1]} studs (old procedural lamp: 18)")
arm_reach = sorted({round(-p[1][1]["LZ"], 1) for p in base if sld[p[2]].Kind == "Arm"})
check("[3] arm lamps reach over the road side (-Z, > 3.5 studs), post/twin lamps stay above the post", not bad_reach,
      f"arm head at {arm_reach} studs (old lamp head centre 3.2)" + (f"; bad {bad_reach[:3]}" if bad_reach else ""))
check("[4] lamp glass tagged StreetLamp", not bad_tag, str(bad_tag[:3]))
light_idx = [i + 1 for i, (ok, parts, style) in enumerate(base) if parts[1]["Light"]]
check("[4] SpotLight on every 3rd lamp (Config.World.LampLightEvery)", light_idx == [i for i in range(1, len(base) + 1) if i % 3 == 0],
      f"{len(light_idx)} lights")

counts = {}
for ok, parts, style in base:
    counts[style] = counts.get(style, 0) + 1
print("INFO lamps per type:", dict(sorted(counts.items(), key=lambda kv: -kv[1])))
tris = sum(sld[s].Triangles * n for s, n in counts.items())
print(f"INFO triangles: {tris} for all {len(base)} lamps (streaming loads only the nearby ones)")

lua, sl, sld, fn = build_case(None, None)
ok, _, _ = fn(sl, 0, 0.8, 0, 0, 1)
check("[6] without StreetLightModels Place returns false (old lamp is built)", ok is False)

print()
print("RESULT:", "PASS" if not fails else "FAIL " + "; ".join(fails))
sys.exit(1 if fails else 0)
