#!/usr/bin/env python3
"""test_trafficlights.py — offline check of the 3D traffic lights (assets/trafficlights/SOLARA_TrafficLights.glb) with
the REAL game code: ModelAssetService (ReplicatedStorage.TrafficLightModels) and SignalRenderer (calibration,
placement, signal states), in Lua 5.4 (lupa) with small Roblox stand-ins (tools/roblox_mock.py).

The import is simulated like Roblox does it (one MeshPart per mesh node, Size = mesh box, all in one container) at
several scales, rotations (baked into the meshes or not) and origins. A test junction has two approaches: a one-lane
road and a two-lane road.
  [1] ModelAssetService puts all TL_* parts in ReplicatedStorage.TrafficLightModels (Ready)
  [2] calibration: the placed light is identical for every import transform
  [3] placement: pole foot on the kerb point, lit lenses toward the approaching traffic, red over yellow over green,
      C's arm reaches over the road (away from the kerb), the two-lane road gets C, the one-lane road A or B
  [4] states: only the active lens glows (Neon, signal colour), the others show their own dark colour
  [5] type B's street lamp is tagged NightGlow with a night colour (CityLightsController lights it at night)
  [6] without the model (or while it is being built) the old box light is used
Usage: python3 -I tools/test_trafficlights.py <lupa-site-packages>
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


SERVICES = r"""
RS = new("ReplicatedStorage")
local shared = new("Folder", {Name = "Shared", Parent = RS})
TLD_MARK = new("ModuleScript", {Name = "TrafficLightData", Parent = shared})
WS = new("Workspace")
function WS.Raycast() return nil end
RaycastParams = { new = function() return {} end }
LOADABLE = nil
game = { GetService = function(_, n)
  if n == "ReplicatedStorage" then return RS end
  if n == "Workspace" then return WS end
  if n == "CollectionService" then return CollectionService end
  if n == "InsertService" then return { LoadAsset = function(_, id) LOADED_ID = id; return LOADABLE end } end
  if n == "ServerScriptService" then return { WorldGen = { AssetIds = "__AID" } } end
end }
RS.Modules = { CarModelConfig = "__CMC" }
AID = { Cars = 0, TrafficLights = 0 }
local realRequire = require
require = function(x)
  if x == TLD_MARK then return TLD end
  if x == "__AID" then return AID end
  if x == "__CMC" then return { Folder = "VehicleModels", Models = {} } end
  return realRequire(x)
end
print = function() end
STATE = "R"
TG = { SignalState = function(graph, node, phase, time) return STATE end }
"""

GRAPH = r"""function()
  -- one signalised node, two approaches: a one-lane road from the south (travelling +Z... towards the node at
  -- z = 0) and a two-lane road from the west (travelling +X)
  local function curb(x0, z0, x1, z1)
    local dx, dz = x1 - x0, z1 - z0
    local len = math.sqrt(dx * dx + dz * dz)
    local ux, uz = dx / len, dz / len
    -- right of the travel direction (Roblox: right = forward x up)
    local rx, rz = -uz, ux
    return { X0 = x0, Z0 = z0, X1 = x1, Z1 = z1, Y1 = 0.8, UX = ux, UZ = uz, RX = rx, RZ = rz,
             Length = len, StopS = len - 6, LaneWidth = 12 }
  end
  local south = curb(206, 300, 206, 200)  -- lane travelling -Z (north) towards the node
  local inner = curb(100, 194, 200, 194)
  local outer = curb(100, 206, 200, 206)  -- kerb-side lane of the two-lane road (travelling +X)
  local node = { Id = 7, Control = "Signal", ArmPhase = { [1] = 1, [2] = 2 }, InLanes = {
    { Group = { south }, Edge = 1, From = 3 },
    { Group = { inner, outer }, Edge = 2, From = 4 },
  } }
  return { Nodes = { node }, Meta = { BlockTop = 0.8 } }, south, outer
end"""


def glb_nodes(path):
    data = open(path, "rb").read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + jlen])
    out = []
    for root in gltf["scenes"][0]["nodes"]:
        for ci in gltf["nodes"][root]["children"]:
            n = gltf["nodes"][ci]
            acc = gltf["accessors"][gltf["meshes"][n["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
            out.append((n["name"], acc["min"], acc["max"], n["translation"]))
    return out


NODES = glb_nodes("assets/trafficlights/SOLARA_TrafficLights.glb")
VARIANTS = [(1.0, (0, 0), (0, 0, 0), False), (3.571, (0, 0), (12, 4, -9), False), (2.0, (180, 0), (-3, 0, 5), True),
            (0.5, (90, 0), (1, 2, 3), False), (10.0, (90, 90), (0, 50, 0), True)]


def runtime(variant, ready=True):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(roblox_mock.MOCK + SERVICES)
    g = lua.globals()
    g.TLD = lua.execute(open("src/ReplicatedStorage/Shared/TrafficLightData.lua", encoding="utf-8").read())
    if variant is not None:
        scale, (yaw, pitch), origin, baked = variant
        root = lua.eval("new")("Model", lua.table_from({"Name": "SOLARA_TrafficLights"}))
        mk = lua.eval("""function(root, name, sx, sy, sz, x, y, z, yaw, pitch, ox, oy, oz, baked)
          local rot = CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
          local p
          if baked then
            local s = rot * Vector3.new(sx, sy, sz)
            p = new("MeshPart", {Name = name, Size = Vector3.new(math.abs(s.X), math.abs(s.Y), math.abs(s.Z)),
              CFrame = CFrame.new(ox, oy, oz) * CFrame.new(rot * Vector3.new(x, y, z))})
          else
            p = new("MeshPart", {Name = name, Size = Vector3.new(sx, sy, sz), CFrame = CFrame.new(ox, oy, oz) * rot * CFrame.new(x, y, z)})
          end
          p.Parent = root
        end""")
        for name, mn, mx, t in NODES:
            c = [(mn[i] + mx[i]) / 2 + t[i] for i in range(3)]
            mk(root, name, *[(mx[i] - mn[i]) * scale for i in range(3)], *(v * scale for v in c), yaw, pitch, *origin, baked)
        g.AID.TrafficLights = 55555
        g.LOADABLE = root
    svc = lua.execute(convert(open("src/ServerScriptService/Services/ModelAssetService.lua", encoding="utf-8").read()))
    svc.Init(svc)
    if not ready:
        f = g.RS.FindFirstChild(g.RS, "TrafficLightModels")
        if f:
            f.SetAttribute(f, "Ready", False)
    sr = lua.execute(convert(open("src/StarterPlayer/StarterPlayerScripts/Ambient/SignalRenderer.lua", encoding="utf-8").read()))
    graph, south, outer = lua.eval(GRAPH)()
    sr.Init(graph, g.TG)
    return lua, svc, sr, graph, south, outer


SNAP = r"""function(sr, graph, state)
  STATE = state
  sr.Update(graph, Vector3.new(200, 0, 200), 0, 500)
  local out = {}
  local folder = WS:FindFirstChild("SolaraTrafficLights")
  for _, m in ipairs(folder:GetChildren()) do
    local root = m.PrimaryPart
    local parts = {}
    for _, p in ipairs(m:GetChildren()) do
      if p ~= root then
        local base = root and root.CFrame or CFrame.new()
        local lp = base:PointToObjectSpace(p.CFrame.Position)
        parts[#parts + 1] = { Name = p.Name, X = lp.X, Y = lp.Y, Z = lp.Z, WX = p.CFrame.Position.X, WY = p.CFrame.Position.Y,
          WZ = p.CFrame.Position.Z, SX = p.Size.X, SY = p.Size.Y, SZ = p.Size.Z, Material = p.Material,
          R = p.Color.R, G = p.Color.G, B = p.Color.B, Night = p:GetAttribute("NightColor") ~= nil }
      end
    end
    local rp = root and root.CFrame.Position or Vector3.new()
    local look = root and root.CFrame.LookVector or Vector3.new()
    local right = root and (root.CFrame * Vector3.new(1, 0, 0) - root.CFrame.Position) or Vector3.new()
    out[#out + 1] = { Name = m.Name, Parts = parts, X = rp.X, Y = rp.Y, Z = rp.Z, LX = look.X, LZ = look.Z, RX = right.X, RZ = right.Z }
  end
  return out
end"""

snaps = {}
for vi, variant in enumerate(VARIANTS):
    lua, svc, sr, graph, south, outer = runtime(variant)
    if vi == 0:
        f = lua.globals().RS.FindFirstChild(lua.globals().RS, "TrafficLightModels")
        n = len(f.GetDescendants(f)) if f else 0
        check("[1] TrafficLightModels built (Ready) with every TL_* part", f is not None and f.GetAttribute(f, "Ready") is True
              and n - 1 == len(NODES), f"{n - 1}/{len(NODES)} parts")
        check("[1] no warnings", lua.eval("WARNED") == 0)
    snap = lua.eval(SNAP)
    snaps[vi] = {s.Name: s for s in snap(sr, graph, "R").values()}
    if vi == 0:
        first = (lua, sr, graph, south, outer, snap)

# [2] identical for every import transform
bad = []
for vi in range(1, len(VARIANTS)):
    for name, m in snaps[0].items():
        o = snaps[vi].get(name)
        if not o:
            bad.append(f"v{vi} missing {name}")
            continue
        pa, pb = sorted(m.Parts.values(), key=lambda p: (p.Name, p.Y, p.X)), sorted(o.Parts.values(), key=lambda p: (p.Name, p.Y, p.X))
        for a, b in zip(pa, pb):
            if max(abs(a.X - b.X), abs(a.Y - b.Y), abs(a.Z - b.Z)) > 1e-3 or \
                    max(abs(x - y) for x, y in zip(sorted((a.SX, a.SY, a.SZ)), sorted((b.SX, b.SY, b.SZ)))) > 1e-3:
                bad.append(f"v{vi} {name} {a.Name}")
                break
check("[2] placed lights identical for import scale 1 / 3.57 / 2 / 0.5 / 10, rotated (baked or not), any origin",
      not bad, "; ".join(bad[:4]))

# [3] placement
lua, sr, graph, south, outer, snap = first
models = list(snaps[0].values())
kinds = sorted(m.Name for m in models)
check("[3] one-lane road gets A or B, two-lane road gets C", len(models) == 2 and "TrafficLight_C" in kinds
      and any(k in kinds for k in ("TrafficLight_A", "TrafficLight_B")), ", ".join(kinds))
TLD = lua.globals().TLD
S = TLD.StudsPerUnit
bad = []
for m in models:
    kind = m.Name[-1]
    curb = outer if kind == "C" else south
    t = curb.StopS / curb.Length
    kx = curb.X0 + (curb.X1 - curb.X0) * t + curb.RX * (curb.LaneWidth / 2 + 2.5)
    kz = curb.Z0 + (curb.Z1 - curb.Z0) * t + curb.RZ * (curb.LaneWidth / 2 + 2.5)
    if abs(m.X - kx) > 1e-6 or abs(m.Z - kz) > 1e-6 or abs(m.Y - 0.8) > 1e-6:
        bad.append(f"{kind} foot at ({m.X:.2f},{m.Y:.2f},{m.Z:.2f}) expected ({kx:.2f},0.8,{kz:.2f})")
    if abs(m.LX + curb.UX) > 1e-6 or abs(m.LZ + curb.UZ) > 1e-6:
        bad.append(f"{kind} does not face the traffic")
    lens = {p.Name: p for p in m.Parts.values() if p.Name in ("Red", "Yellow", "Green")}
    if set(lens) != {"Red", "Yellow", "Green"}:
        bad.append(f"{kind} lenses {sorted(lens)}")
        continue
    if not lens["Red"].Y > lens["Yellow"].Y > lens["Green"].Y:
        bad.append(f"{kind} lens order")
    for r, p in lens.items():
        want = [v * S for v in TLD.Types[kind].Lens[r].values()]
        if abs(p.Z) < 0.5 or p.Z > 0:
            bad.append(f"{kind} {r} lens not in front of the pole (z {p.Z:.2f})")
        if abs(p.Y - want[1]) > 0.3:
            bad.append(f"{kind} {r} lens height {p.Y:.2f} vs {want[1]:.2f}")
    # the arm / head reaches toward the road: away from the kerb (opposite to the lane's right vector)
    head = lens["Red"]
    reach = (head.WX - m.X) * curb.RX + (head.WZ - m.Z) * curb.RZ
    if kind == "C" and reach > -8:
        bad.append(f"C head reaches {reach:.2f} studs toward the road (expected < -8)")
    top = max(p.Y + p.SY / 2 for p in m.Parts.values())
    if kind == "A" and not 10 < top < 13 or kind == "C" and not 14 < top < 17 or kind == "B" and not 14 < top < 17:
        bad.append(f"{kind} height {top:.1f}")
check("[3] foot on the kerb point, faces the traffic, lenses in front stacked red/yellow/green, heights, C over the road",
      not bad, "; ".join(bad[:5]))

# [4] states
bad = []
for state, lit in (("R", "Red"), ("Y", "Yellow"), ("G", "Green")):
    for m in snap(sr, graph, state).values():
        for p in m.Parts.values():
            if p.Name in ("Red", "Yellow", "Green"):
                on = p.Name == lit
                if on and (p.Material != "Material.Neon" or p.R + p.G + p.B < 1.2):
                    bad.append(f"{m.Name} {state}: {p.Name} not lit")
                if not on and (p.Material == "Material.Neon" or p.R + p.G + p.B > 1.2):
                    bad.append(f"{m.Name} {state}: {p.Name} lit")
check("[4] only the active lens glows (red / yellow / green cycle)", not bad, "; ".join(bad[:4]))

# [5] lamp of B (the test junction's one-lane approach picks B; otherwise check the model folder)
lua2, svc2, sr2, graph2, _, _ = runtime(VARIANTS[0])
data = lua2.eval(SNAP)(sr2, graph2, "G")
lamps = [p for m in data.values() if m.Name == "TrafficLight_B" for p in m.Parts.values() if p.Name == "Lamp"]
tags = [x[2] for x in lua2.eval("TAGS").values()]
if lamps:
    check("[5] type B street lamp tagged NightGlow with a night colour", len(lamps) == 1 and lamps[0].Night
          and "NightGlow" in tags)
else:
    f = lua2.globals().RS.FindFirstChild(lua2.globals().RS, "TrafficLightModels")
    check("[5] type B has a street lamp glass part in the model",
          len([d for d in f.GetDescendants(f).values() if str(d.Name).startswith("TL_B_Lamp_")]) == 1)

# [6] fallbacks
lua3, _, sr3, graph3, _, _ = runtime(None)
names = sorted(m.Name for m in lua3.eval(SNAP)(sr3, graph3, "R").values())
check("[6] no model → old box lights", names == ["TrafficLight", "TrafficLight"], ", ".join(names))
lua4, _, sr4, graph4, _, _ = runtime(VARIANTS[0], ready=False)
names = sorted(m.Name for m in lua4.eval(SNAP)(sr4, graph4, "R").values())
check("[6] model folder not ready yet → old box lights", names == ["TrafficLight", "TrafficLight"], ", ".join(names))

print("\n%d checks failed" % len(fails) if fails else "\nall checks passed")
sys.exit(1 if fails else 0)
