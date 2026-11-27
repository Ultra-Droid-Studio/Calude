#!/usr/bin/env python3
"""test_cars.py — offline check of the car models (assets/cars/SOLARA_Cars.glb) with the REAL game code:
ModelAssetService (builds ReplicatedStorage.VehicleModels from the uploaded model), CarModelKit (calibration, dressing,
paint) and CarModelConfig, run in Lua 5.4 (lupa) with small Roblox stand-ins.

The import is simulated the way Roblox does it: one MeshPart per mesh node, Size = the mesh's bounding box,
CFrame = node position; all parts land in one container (the hierarchy does not matter). Tried with several import
scales, rotations and origins:
  [1] ModelAssetService collects all 12 cars by name prefix; folder Ready flag; nothing left over
  [2] calibration (wheelbase / track / wheel radius / length) matches cars.json, for every import transform
  [3] dressing a car on a target frame gives the SAME result for every import transform (part positions and sizes)
  [4] the car stands right: wheels at axle height, body above, headlights at the front (-Z), tail lights at the back
  [5] roles: Paint, Glass, lamps named for the light system (Headlight, TailLight, ...), colours from the part names
  [6] paint: random colour / own colour, police paint fixed, Repaint only touches Paint / Paint2
  [7] Pick: every car definition gets its models; police appears only in traffic (~12 % of sedans)
  [8] without the folder (or while it is being built) the game falls back to the old box cars
Usage: python3 -I tools/test_cars.py <lupa-site-packages>
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
from lupa import LuaRuntime  # noqa: E402
from luau2lua import convert  # noqa: E402
import roblox_mock  # noqa: E402

fails = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        fails.append(name)


MOCK = roblox_mock.MOCK + r"""
RS = new("ReplicatedStorage")
local modules = new("Folder", {Name = "Modules", Parent = RS})
CMC_MARK = new("ModuleScript", {Name = "CarModelConfig", Parent = modules})
LOADABLE = nil
game = { GetService = function(_, n)
  if n == "ReplicatedStorage" then return RS end
  if n == "InsertService" then return { LoadAsset = function(_, id) LOADED_ID = id; return LOADABLE end } end
  if n == "ServerScriptService" then return { WorldGen = { AssetIds = "__AID" } } end
end }
AID = { Cars = 0 }
local realRequire = require
require = function(x)
  if x == CMC_MARK then return CMC end
  if x == "__AID" then return AID end
  return realRequire(x)
end
print = function() end
"""


def glb_nodes(path):
    """(car, part name, local bbox min, max, node translation) for every mesh node of our .glb"""
    data = open(path, "rb").read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + jlen])
    out = []
    for root in gltf["scenes"][0]["nodes"]:
        car = gltf["nodes"][root]
        for ci in car["children"]:
            n = gltf["nodes"][ci]
            acc = gltf["accessors"][gltf["meshes"][n["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
            out.append((car["name"], n["name"], acc["min"], acc["max"], n["translation"]))
    return out


NODES = glb_nodes("assets/cars/SOLARA_Cars.glb")
INFO = json.load(open("assets/cars/cars.json"))
# import variants: (scale, rotation (yaw, pitch) degrees, origin, rotation baked into the meshes?)
VARIANTS = [(1.0, (0, 0), (0, 0, 0), False), (1 / 0.28, (0, 0), (40.5, 3.25, -12.0), False),
            (3.0, (180, 0), (-7, 0, 9), True), (0.5, (90, 0), (1, 2, 3), False), (2.0, (90, 90), (5, -1, 0), True)]


def runtime(variant, with_asset=True):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    g = lua.globals()
    g.CMC = lua.execute(convert(open("src/ReplicatedStorage/Modules/CarModelConfig.lua", encoding="utf-8").read()))
    if variant is not None:
        scale, (yaw, pitch), origin, baked = variant
        root = lua.eval("new")("Model", lua.table_from({"Name": "SOLARA_Cars"}))
        mk = lua.eval("""function(root, name, sx, sy, sz, x, y, z, yaw, pitch, ox, oy, oz, baked)
          local rot = CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
          local p
          if baked then
            -- importer bakes the rotation into the mesh: unrotated part, Size = box of the rotated mesh
            local s = rot * Vector3.new(sx, sy, sz)
            p = new("MeshPart", {Name = name, Size = Vector3.new(math.abs(s.X), math.abs(s.Y), math.abs(s.Z)),
              CFrame = CFrame.new(ox, oy, oz) * CFrame.new(rot * Vector3.new(x, y, z))})
          else
            -- importer keeps the mesh and rotates the part
            p = new("MeshPart", {Name = name, Size = Vector3.new(sx, sy, sz),
              CFrame = CFrame.new(ox, oy, oz) * rot * CFrame.new(x, y, z)})
          end
          p.Parent = root
        end""")
        for car, name, mn, mx, t in NODES:
            c = [(mn[i] + mx[i]) / 2 + t[i] for i in range(3)]
            size = [(mx[i] - mn[i]) * scale for i in range(3)]
            mk(root, name, *size, *(v * scale for v in c), yaw, pitch, *origin, baked)
        if with_asset:
            g.AID.Cars = 987654321
            g.LOADABLE = root
    svc = lua.execute(convert(open("src/ServerScriptService/Services/ModelAssetService.lua", encoding="utf-8").read()))
    kit = lua.execute(convert(open("src/ReplicatedStorage/Shared/CarModelKit.lua", encoding="utf-8").read()))
    return lua, svc, kit


DRESS = r"""function(kit, name, defWheelbase, paint)
  local info = kit.Get(name)
  if not info then return nil end
  local target = CFrame.new(100, 20, -50) * CFrame.Angles(0, math.rad(30), 0)
  local body = new("Part", {Name = "Chassis", CFrame = target, Size = Vector3.new(4, 1, 10)})
  local parent = new("Model")
  local s = defWheelbase / info.Wheelbase
  local res = kit.Build(info, { Frame = target, Scale = s, Parent = parent, Body = body, Paint = paint })
  local out = {}
  for _, p in ipairs(res.Parts) do
    local lp = target:PointToObjectSpace(p.CFrame.Position)
    local look = target.Rotation:ToObjectSpace(p.CFrame.Rotation)
    out[#out + 1] = { Name = p.Name, Role = p:GetAttribute("CarRole"), X = lp.X, Y = lp.Y, Z = lp.Z,
      SX = p.Size.X, SY = p.Size.Y, SZ = p.Size.Z, R = p.Color.R, G = p.Color.G, B = p.Color.B,
      Material = p.Material, Transparency = p.Transparency }
  end
  local spins = {}
  for _, sp in ipairs(res.Spin) do
    local c = target:PointToObjectSpace((sp.Motor.Part0.CFrame * sp.Motor.C0).Position)
    spins[#spins + 1] = { Wheel = sp.Wheel, X = c.X, Y = c.Y, Z = c.Z }
  end
  return { Info = { Wheelbase = info.Wheelbase, Track = info.Track, WheelRadius = info.WheelRadius, Length = info.Length,
    RoofY = info.RoofY, Scale = s }, Parts = out, Spins = spins, Res = res }
end"""

DEF_WB = 8.6
results = {}
for vi, variant in enumerate(VARIANTS):
    lua, svc, kit = runtime(variant)
    svc.Init(svc)
    folder = lua.eval("RS"). FindFirstChild(lua.eval("RS"), "VehicleModels")
    models = [m.Name for m in folder.GetChildren(folder).values()] if folder else []
    leftover = lua.eval("LOADABLE")
    if vi == 0:
        check("[1] ModelAssetService builds VehicleModels with all 12 cars", sorted(models) == sorted(INFO),
              ", ".join(sorted(models)))
        check("[1] folder marked Ready, the loaded asset is cleaned up, LoadAsset used the id",
              folder.GetAttribute(folder, "Ready") is True and leftover._destroyed is True and lua.eval("LOADED_ID") == 987654321)
        check("[1] no warnings", lua.eval("WARNED") == 0, str(lua.eval("WARNED")))
    dress = lua.eval(DRESS)
    results[vi] = {name: dress(kit, name, DEF_WB, None) for name in INFO}

# [2] calibration in model units (metres) after removing the import scale
bad = []
for vi, (scale, _, _, _) in enumerate(VARIANTS):
    for name, r in results[vi].items():
        info = r.Info
        exp = INFO[name]
        for key, val in (("WheelbaseM", info.Wheelbase), ("TrackM", info.Track), ("WheelRadiusM", info.WheelRadius),
                         ("LengthM", info.Length)):
            if abs(val / scale - exp[key]) > 0.01 + 0.002 * exp[key]:
                bad.append(f"{name} v{vi} {key} {val / scale:.3f} vs {exp[key]}")
check("[2] wheelbase / track / wheel radius / length match cars.json for every import transform", not bad, "; ".join(bad[:4]))

# [3] same dressing result for every import transform
bad = []
for name in INFO:
    a = {p.Name + p.Role + str(i): p for i, p in enumerate(results[0][name].Parts.values())}
    for vi in range(1, len(VARIANTS)):
        b = {p.Name + p.Role + str(i): p for i, p in enumerate(results[vi][name].Parts.values())}
        for k, pa in a.items():
            pb = b.get(k)
            if pb is None:
                bad.append(f"{name} v{vi} missing {k}")
                continue
            d = max(abs(pa.X - pb.X), abs(pa.Y - pb.Y), abs(pa.Z - pb.Z))
            sa, sb = sorted((pa.SX, pa.SY, pa.SZ)), sorted((pb.SX, pb.SY, pb.SZ))
            if d > 1e-3 or max(abs(x - y) for x, y in zip(sa, sb)) > 1e-3:
                bad.append(f"{name} v{vi} {k} moved {d:.4f}")
check("[3] dressed car identical for import scale 1 / 3.57 / 3 / 0.5 / 2, rotated (baked or not), any origin",
      not bad, "; ".join(bad[:4]))

# [4] standing right
bad = []
for name, r in results[0].items():
    s = r.Info.Scale
    spins = {sp.Wheel: sp for sp in r.Spins.values()}
    for w, sp in spins.items():  # (front and rear track may differ: check side, symmetry and the mean track)
        ez = -DEF_WB / 2 if w[0] == "F" else DEF_WB / 2
        mirror = spins[w[0] + ("R" if w[1] == "L" else "L")]
        if abs(sp.Z - ez) > 0.05 or abs(sp.Y) > 0.05 or (sp.X < 0) != (w[1] == "L") or abs(sp.X + mirror.X) > 0.05:
            bad.append(f"{name} wheel {w} at ({sp.X:.2f},{sp.Y:.2f},{sp.Z:.2f})")
    mean_track = (spins["FR"].X - spins["FL"].X + spins["RR"].X - spins["RL"].X) / 2
    if abs(mean_track - INFO[name]["TrackM"] * s) > 0.05:
        bad.append(f"{name} track {mean_track:.2f}")
    parts = list(r.Parts.values())
    heads = [p.Z for p in parts if p.Name == "Headlight"]
    tails = [p.Z for p in parts if p.Name == "TailLight"]
    if heads and max(heads) > 0:
        bad.append(f"{name} headlight behind the middle")
    if tails and min(tails) < 0:
        bad.append(f"{name} tail light in front of the middle")
    roof = max(p.Y + p.SY / 2 for p in parts if not p.Name.startswith("CarWheel"))
    if roof < 0.6 * s or r.Info.RoofY <= 0:
        bad.append(f"{name} roof {roof:.2f}")
check("[4] wheels on the axles (front = -Z, left = -X), headlights front, tail lights back, roof up", not bad,
      "; ".join(bad[:4]))

# [5] roles and colours
bad = []
light_names = {"Headlight", "TailLight", "ReverseLight", "IndicatorL", "IndicatorR"}
for name, r in results[0].items():
    parts = list(r.Parts.values())
    roles = {p.Role for p in parts}
    need = {"Paint", "Glass", "Headlight", "Tire", "Rim"} | ({"TailLight"} if name != "Furia" else set())
    if not need <= roles:
        bad.append(f"{name} missing roles {sorted(need - roles)}")
    for p in parts:
        if p.Role in light_names and p.Name != p.Role:
            bad.append(f"{name} lamp {p.Role} named {p.Name}")
        if p.Role == "Glass" and (p.Material != "Material.Glass" or not 0 < p.Transparency < 0.5):
            bad.append(f"{name} glass look")
    for pname in INFO[name]["PartNames"]:
        role = pname.split("_")[1]
        if role in ("Detail", "Glass", "Headlight"):
            hexv = pname.rsplit("_", 1)[1]
            want = tuple(int(hexv[i:i + 2], 16) / 255 for i in (0, 2, 4))
            if not any(p.Role == role and max(abs(p.R - want[0]), abs(p.G - want[1]), abs(p.B - want[2])) < 1e-6 for p in parts):
                bad.append(f"{name} {pname} colour not applied")
    wheels = {p.Name.split("_")[1] for p in parts if p.Name.startswith("CarWheel_")}
    if wheels != {"FL", "FR", "RL", "RR"} or len(r.Spins) != sum(1 for p in parts if p.Name.startswith("CarWheel_")):
        bad.append(f"{name} wheels {wheels}")
check("[5] roles present, lamps named for the light system, glass, colours from the part names, every wheel part spins",
      not bad, "; ".join(bad[:5]))
check("[5] Furia has no tail-lamp geometry in the source model (known)", "TailLight" not in {p.Role for p in results[0]["Furia"].Parts.values()})

# [6] paint
lua, svc, kit = runtime(VARIANTS[0])
svc.Init(svc)
dress = lua.eval(DRESS)
red = lua.eval("Color3.fromRGB(200, 10, 10)")
bad = []
for name in INFO:
    own = INFO[name]["PaintHex"]
    own_rgb = tuple(int(own[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = dress(kit, name, DEF_WB, None)
    b = dress(kit, name, DEF_WB, red)
    pa = [p for p in a.Parts.values() if p.Role == "Paint"]
    pb = [p for p in b.Parts.values() if p.Role == "Paint"]
    if any(max(abs(p.R - own_rgb[0]), abs(p.G - own_rgb[1]), abs(p.B - own_rgb[2])) > 1e-6 for p in pa):
        bad.append(f"{name} own paint")
    fixed = name == "Patrulla"
    want = own_rgb if fixed else (200 / 255, 10 / 255, 10 / 255)
    if any(max(abs(p.R - want[0]), abs(p.G - want[1]), abs(p.B - want[2])) > 1e-6 for p in pb):
        bad.append(f"{name} paint {'should stay fixed' if fixed else 'not applied'}")
    others_same = all((x.R, x.G, x.B) == (y.R, y.G, y.B) for x, y in zip(a.Parts.values(), b.Parts.values())
                      if x.Role not in ("Paint", "Paint2"))
    if not others_same:
        bad.append(f"{name} paint changed other parts")
check("[6] own colour when no paint, given paint applied (police stays black-white), other parts unchanged", not bad,
      "; ".join(bad[:4]))
repaint = lua.eval("""function(kit, res, name)
  kit.Repaint(res.Parts, name, Color3.fromRGB(0, 0, 255))
  local n, other = 0, 0
  for _, p in ipairs(res.Parts) do
    if p:GetAttribute("CarRole") == "Paint" then if p.Color.B > 0.99 and p.Color.R < 0.01 then n = n + 1 end
    elseif p:GetAttribute("CarRole") ~= "Paint2" and p.Color.B > 0.99 and p.Color.R < 0.01 and p.Color.G < 0.01 then other = other + 1 end
  end
  return n, other
end""")
r = dress(kit, "Chispa", DEF_WB, None)
n, other = repaint(kit, r.Res, "Chispa")
check("[6] Repaint recolours the Paint parts only", n > 0 and other == 0, f"paint parts {n}, others {other}")
rnd = lua.eval("""function(kit) local rng = Random.new(7); local own, col = 0, 0
  for i = 1, 2000 do if kit.RandomPaint({Color3.fromRGB(1, 2, 3)}, rng) == nil then own = own + 1 else col = col + 1 end end
  return own, col end""")
own, col = rnd(kit)
check("[6] RandomPaint keeps the model's own colour ~35 % of the time", 0.3 < own / 2000 < 0.4, f"{own / 20:.1f} %")

# [7] Pick
pick = lua.eval("""function(kit, def, traffic) local rng = Random.new(11); local seen = {}
  for i = 1, 3000 do local n = kit.Pick(def, rng, traffic) or "nil"; seen[n] = (seen[n] or 0) + 1 end
  return seen end""")
cfg = lua.eval("CMC")
bad = []
for d, names in cfg.ByDefinition.items():
    seen = dict(pick(kit, d, False))
    if set(seen) != set(names.values()):
        bad.append(f"{d}: {seen}")
sed = dict(pick(kit, "sedan_vela", True))
share = sed.get("Patrulla", 0) / 3000
check("[7] every car definition picks exactly its models (player cars)", not bad, "; ".join(bad))
check("[7] police only in traffic, ~12 % of sedans", "Patrulla" not in dict(pick(kit, "sedan_vela", False)) and 0.09 < share < 0.15,
      f"{share * 100:.1f} %")
check("[7] motorcycles have no car model", dict(pick(kit, "bike_sport_veloz", False)) == {"nil": 3000})

# [8] fallbacks
lua, svc, kit = runtime(None)
svc.Init(svc)
check("[8] no asset id → no folder, Get returns nil (old box cars)", lua.eval("RS").FindFirstChild(lua.eval("RS"), "VehicleModels") is None
      and kit.Get("Chispa") is None)
lua, svc, kit = runtime(VARIANTS[0])
svc.Init(svc)
f = lua.eval("RS").FindFirstChild(lua.eval("RS"), "VehicleModels")
f.SetAttribute(f, "Ready", False)
check("[8] folder still being built (Ready = false) → not used yet", kit.Get("Chispa") is None)
f.SetAttribute(f, "Ready", True)
check("[8] ... and used once ready", kit.Get("Chispa") is not None)

# scale fit report (studs) against the vehicle definitions
defs = {"compact_pico": (7.6, 12), "sedan_vela": (8.6, 14), "sports_rayo": (8.8, 14.4), "suv_terra": (9.2, 15),
        "pickup_mesa": (10.4, 16.5), "van_porter": (10, 16), "utility_brisa": (10.8, 17)}
print("\nsize in the game (studs): definition length vs model length at the definition's wheelbase")
for d, names in cfg.ByDefinition.items():
    wb, length = defs[d]
    row = ", ".join(f"{n} {INFO[n]['LengthM'] * wb / INFO[n]['WheelbaseM']:.1f}" for n in names.values())
    print(f"  {d:14s} def {length:5.1f}: {row}")

print("\n%d checks failed" % len(fails) if fails else "\nall checks passed")
sys.exit(1 if fails else 0)
