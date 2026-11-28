#!/usr/bin/env python3
"""test_hijack.py — car hijacking (NPC driver in traffic cars, "Steal" prompt) with the REAL TrafficRenderer and
PedRenderer / PedMeshRig in Lua 5.4 (lupa) with small Roblox stand-ins (tools/roblox_mock.py).
  [1] every traffic car model (12 cars on their vehicle definitions + the box fallback) gets a driver seat on the left,
      inside the body, low enough for a seated adult, and a door point outside the driver door with an "Çal" (F) prompt
  [2] a realistic pedestrian seated there (PedRenderer.SitIn) fits: head under the roof, body inside the car's width,
      hips at the seat, thighs forward, hands forward; welded to the car root; LeaveSeat frees it
  [3] HijackInfo gives what the server needs: definition, model name, paint (nil = the model's own colour)
Writes docs/hijack_preview.png: the seated drivers inside the cars (glass left out so they are visible).
Usage: python3 -I tools/test_hijack.py <lupa-site-packages>
"""
import io
import json
import math
import os
import struct
import sys

import numpy as np

sys.path.insert(0, sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
from lupa import LuaRuntime  # noqa: E402
from luau2lua import convert  # noqa: E402
import roblox_mock  # noqa: E402
import cosmo_cars_convert  # noqa: E402

fails = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        fails.append(name)


SERVICES = r"""
RS = new("ReplicatedStorage")
local modules = new("Folder", {Name = "Modules", Parent = RS})
CMC_MARK = new("ModuleScript", {Name = "CarModelConfig", Parent = modules})
local shared = new("Folder", {Name = "Shared", Parent = RS})
VD_MARK = new("ModuleScript", {Name = "VehicleDefinitions", Parent = shared})
KIT_MARK = new("ModuleScript", {Name = "CarModelKit", Parent = shared})
PMD_MARK = new("ModuleScript", {Name = "PedModelData", Parent = shared})
WS = new("Workspace")
AMBIENT = new("Folder", {Name = "Ambient"})
RIG_MARK = new("ModuleScript", {Name = "PedMeshRig", Parent = AMBIENT})
script = { Parent = AMBIENT }
game = { GetService = function(_, n)
  if n == "ReplicatedStorage" then return RS end
  if n == "Workspace" then return WS end
end }
local realRequire = require
require = function(x)
  if x == CMC_MARK then return CMC end
  if x == VD_MARK then return VD end
  if x == KIT_MARK then return KIT end
  if x == PMD_MARK then return PMD end
  if x == RIG_MARK then return RIG end
  return realRequire(x)
end
print = function() end
"""

CARS = cosmo_cars_convert.read_glb("assets/cars/SOLARA_Cars.glb")
INFO = json.load(open("assets/cars/cars.json"))


def glb_nodes(path):
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


lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(roblox_mock.MOCK + SERVICES)
g = lua.globals()
g.CMC = lua.execute(convert(open("src/ReplicatedStorage/Modules/CarModelConfig.lua", encoding="utf-8").read()))
g.VD = lua.execute(convert(open("src/ReplicatedStorage/Shared/VehicleDefinitions.lua", encoding="utf-8").read()))
g.PMD = lua.execute(open("src/ReplicatedStorage/Shared/PedModelData.lua", encoding="utf-8").read())
# the uploaded car models, as ModelAssetService leaves them (one Model per car, MeshParts at their node positions)
newi = lua.eval("new")
vec = lua.eval("Vector3.new")
cfn = lua.eval("CFrame.new")
folder = newi("Folder", lua.table_from({"Name": "VehicleModels", "Parent": g.RS}))
models = {}
for car, name, mn, mx, t in glb_nodes("assets/cars/SOLARA_Cars.glb"):
    if car not in models:
        models[car] = newi("Model", lua.table_from({"Name": car, "Parent": folder}))
    c = [(mn[i] + mx[i]) / 2 + t[i] for i in range(3)]
    newi("MeshPart", lua.table_from({"Name": name, "Size": vec(*[mx[i] - mn[i] for i in range(3)]), "CFrame": cfn(*c),
                                     "Parent": models[car]}))
g.KIT = lua.execute(convert(open("src/ReplicatedStorage/Shared/CarModelKit.lua", encoding="utf-8").read()))
TR = lua.execute(convert(open("src/StarterPlayer/StarterPlayerScripts/Ambient/TrafficRenderer.lua", encoding="utf-8").read()))
TR.Init()

acquire = lua.eval("""function(TR, defId, name)
  CMC.ByDefinition[defId] = { name }
  CMC.TrafficVariants[defId] = nil
  local m = TR.Acquire(defId, false, 0)
  local seat, door, def, body, paint = TR.HijackInfo(m)
  local prompt = TR.HijackPrompt(m)
  local lo, hi = Vector3.new(1e9, 1e9, 1e9), Vector3.new(-1e9, -1e9, -1e9)
  for _, p in ipairs(m:GetChildren()) do
    if p.Size and p.Name ~= "Root" and p.Name ~= "Hull" and string.sub(p.Name, 1, 8) ~= "CarWheel" and p.Name ~= "Wheel" then
      local h = p.Size / 2
      for _, sx in ipairs({-1, 1}) do for _, sy in ipairs({-1, 1}) do for _, sz in ipairs({-1, 1}) do
        local c = m.PrimaryPart.CFrame:PointToObjectSpace(p.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
        lo, hi = lo:Min(c), hi:Max(c)
      end end end
    end
  end
  return { Model = m, Seat = seat.Position, Door = door, Def = def, Body = body, Paint = paint, Lo = lo, Hi = hi,
           Prompt = prompt and prompt.KeyboardKeyCode, Action = prompt and prompt.ActionText }
end""")

cases = []
for d, names in g.CMC.ByDefinition.items():
    for n in list(names.values()):
        cases.append((d, n))
cases.append(("sedan_vela", "Patrulla"))
bad, results = [], {}
for defId, name in cases:
    r = acquire(TR, defId, name)
    results[name] = (defId, r)
    s, lo, hi, door = r.Seat, r.Lo, r.Hi, r.Door
    width = hi.X - lo.X
    if not (s.X < -0.4 and s.X > lo.X + 0.7):
        bad.append(f"{name}: seat x {s.X:.2f} (body {lo.X:.2f}..{hi.X:.2f})")
    if not (s.Y < hi.Y - 2.8 and s.Y > 0.5):
        bad.append(f"{name}: seat y {s.Y:.2f} roof {hi.Y:.2f}")
    if not (lo.Z < s.Z < hi.Z):
        bad.append(f"{name}: seat z {s.Z:.2f}")
    if not (door.X < lo.X - 0.8 and abs(door.Z - s.Z) < 0.01 and abs(door.Y) < 0.01):
        bad.append(f"{name}: door {door.X:.2f},{door.Y:.2f},{door.Z:.2f}")
    if r.Action != "Çal" or str(r.Prompt) != "KeyCode.F":
        bad.append(f"{name}: prompt {r.Action} {r.Prompt}")
check("[1] every traffic car: driver seat left, inside, low enough; door point outside the driver door; 'Çal' [F] prompt",
      not bad, "; ".join(bad[:4]))
name_box, has = lua.eval("""function(TR)
  CMC.ByDefinition.van_porter = {}
  local m = TR.Acquire("van_porter", false, 0)
  return m.Name, TR.HijackInfo(m) ~= nil
end""")(TR)
check("[1] box fallback car (no 3D model) has the driver seat too", has and name_box == "NPC_van_porter", name_box)
bad = []
for name, (defId, r) in results.items():
    if r.Def != defId or r.Body != name:
        bad.append(f"{name}: {r.Def} {r.Body}")
own = [n for n, (d, r) in results.items() if r.Paint is None]
check("[3] HijackInfo: definition and model name for the server, paint colour or nil (own colour)", not bad,
      f"own colour this run: {', '.join(own) or '-'}")

# ---------------- seated pedestrians (PedRenderer + PedMeshRig) in a second runtime
sys.argv = [sys.argv[0], sys.argv[1]]
src = open("tools/test_peds.py", encoding="utf-8").read()
src = src[:src.index("# ---------------------------------------------------------------------------------------------------------------\nPED_NAMES")]
ns = {"__name__": "peds_helpers", "__file__": "tools/test_peds.py"}
exec(compile(src, "tools/test_peds.py", "exec"), ns)
plua, RIG, imports = ns["runtime"](ns["VARIANTS"][0])
sit = plua.eval("""function(PR, RIG, id, sx, sy, sz, seed)
  local rng = Random.new(seed)
  local m, rig
  for i = 1, 400 do
    m, rig = RIG.Build(rng)
    if m and rig.Id == id then break end
  end
  -- hand the built model to PedRenderer like Acquire would
  local car = new("Part", {Name = "Root", CFrame = CFrame.new(), Size = Vector3.new(6, 0.2, 14)})
  PR._adopt(m, rig)
  PR.SitIn(m, car, CFrame.new(sx, sy, sz))
  -- Roblox: parts welded to the root move with it (the stand-in does not simulate welds)
  for _, p in ipairs(rig.Parts) do p.CFrame = m.PrimaryPart.CFrame * rig.PartOffset[p] end
  local weld = m.PrimaryPart:FindFirstChild("SeatWeld")
  return m, rig, weld ~= nil and weld.Part0 == car and m.PrimaryPart.Anchored == false
end""")
# PedRenderer keeps its rigs private; give the test a door in (only used here)
PR_SRC = convert(open("src/StarterPlayer/StarterPlayerScripts/Ambient/PedRenderer.lua", encoding="utf-8").read())
PR_SRC = PR_SRC.replace("\nreturn PedRenderer", "\nfunction PedRenderer._adopt(m, r) rigOf[m] = r end\nreturn PedRenderer")
PR = plua.execute(PR_SRC)
PR.Init()

bad, scenes = [], []
for i, name in enumerate(["Solano", "Bastion", "Chispa", "Brava", "Mula", "Patrulla"]):
    defId, r = results[name]
    pid = ["F01", "M02", "F03", "M05", "M01", "M04"][i]
    m, rig, welded = sit(PR, RIG, pid, r.Seat.X, r.Seat.Y, r.Seat.Z, 3 + i)
    P, B, _ = ns["skin_state"](plua, m, "Ped_" + pid, imports["Ped_" + pid])
    # skin_state returns the ped's root frame; the root sits at the seat (identity rotation) -> car root space
    P = P + np.array([r.Seat.X, r.Seat.Y, r.Seat.Z])
    B = {k: v + np.array([r.Seat.X, r.Seat.Y, r.Seat.Z]) for k, v in B.items()}
    lo, hi = r.Lo, r.Hi
    if P[:, 1].max() > hi.Y - 0.15:
        bad.append(f"{name}/{pid}: head {P[:, 1].max():.2f} above roof {hi.Y:.2f}")
    if P[:, 0].min() < lo.X - 0.1:
        bad.append(f"{name}/{pid}: sticks out of the side")
    if not welded:
        bad.append(f"{name}/{pid}: not welded to the car root")
    knee_fwd = B["Pelvis"][2] - B["LCalf"][2]
    hand_fwd = B["Pelvis"][2] - B["LHand"][2]
    if knee_fwd < 1.0 or hand_fwd < 0.8:
        bad.append(f"{name}/{pid}: knees {knee_fwd:.2f} / hands {hand_fwd:.2f} not forward")
    if abs(B["Pelvis"][1] - r.Seat.Y) > 0.05:
        bad.append(f"{name}/{pid}: hips not at the seat")
    scenes.append((name, pid, defId, P, m))
check("[2] seated driver fits: head under the roof, inside the body, hips on the seat, knees and hands forward, welded",
      not bad, "; ".join(bad[:4]))
leave = plua.eval("""function(PR, m)
  PR.LeaveSeat(m)
  return m.PrimaryPart:FindFirstChild("SeatWeld") == nil and m.PrimaryPart.Anchored == true
end""")
check("[2] LeaveSeat frees the driver (weld gone, root anchored)", leave(PR, scenes[0][4]))

# ---------------- preview
try:
    from PIL import Image, ImageDraw, ImageFont
    data = open("assets/pedestrians/SOLARA_Pedestrians.glb", "rb").read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    gj = json.loads(data[20:20 + jlen])
    binary = data[28 + jlen:]
    GLBP = ns["GLB"]

    def atlas(pid):
        idx = [i for i, im in enumerate(gj["images"]) if im["name"].startswith("Ped_" + pid + "_")][0]
        bv = gj["bufferViews"][gj["images"][idx]["bufferView"]]
        return np.asarray(Image.open(io.BytesIO(binary[bv["byteOffset"]:bv["byteOffset"] + bv["byteLength"]])).convert("RGBA")).astype(float)

    def draw(items, yaw, size=(420, 300)):
        img = Image.new("RGB", size, (232, 235, 240))
        d = ImageDraw.Draw(img)
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        eye = np.array([-sy * 0.95, 0.3, -cy * 0.95]); eye /= np.linalg.norm(eye)
        fw = -eye
        rt = np.cross(fw, [0, 1, 0]); rt /= np.linalg.norm(rt)
        up = np.cross(rt, fw)
        L = np.array([0.3, 0.8, -0.5]); L /= np.linalg.norm(L)
        tris = []
        allp = []
        for T, cols in items:
            cam = np.stack([T @ rt, T @ up, T @ fw], -1)
            n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
            sh = 0.55 + 0.45 * np.abs(n @ L)
            for k in range(len(T)):
                if cols[k] is None:
                    continue
                tris.append((cam[k, :, 2].mean(), cam[k], tuple(int(c) for c in np.clip(np.array(cols[k]) * sh[k], 0, 255))))
            allp.append(cam.reshape(-1, 3))
        allp = np.vstack(allp)
        lo, hi = allp.min(0), allp.max(0)
        s = 0.9 * min(size[0] / (hi[0] - lo[0]), size[1] / (hi[1] - lo[1]))
        o = (hi + lo) / 2
        for _, cam, c in sorted(tris, key=lambda t: -t[0]):
            d.polygon([(size[0] / 2 + (p[0] - o[0]) * s, size[1] / 2 - (p[1] - o[1]) * s) for p in cam], fill=c)
        return img

    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    tiles = []
    for name, pid, defId, P, m in scenes:
        defs = g.VD.Catalog[defId]
        sm = defs.Wheelbase / INFO[name]["WheelbaseM"]
        rad = INFO[name]["WheelRadiusM"] * sm
        car_tris, car_cols = [], []
        for pname, T, N, rgb in CARS[name]:
            role = pname.split("_")[1]
            if role == "Glass":
                continue  # see-through: the driver is visible
            TT = T * sm + np.array([0, rad, 0])
            car_tris.append(TT)
            car_cols += [rgb] * len(TT)
        car_T = np.vstack(car_tris)
        ped = GLBP["Ped_" + pid]
        A = atlas(pid)
        uv = ped["UV"][ped["F"]].mean(1)
        pc = A[np.clip((uv[:, 1] * 1024).astype(int), 0, 1023), np.clip((uv[:, 0] * 1024).astype(int), 0, 1023)]
        ped_cols = [tuple(c[:3]) if c[3] > 127 else None for c in pc]
        items = [(car_T, car_cols), (P[ped["F"]], ped_cols)]
        tile = Image.new("RGB", (840, 320), (232, 235, 240))
        tile.paste(draw(items, -60), (0, 20))
        tile.paste(draw(items, -110), (420, 20))
        ImageDraw.Draw(tile).text((6, 3), f"{name}: sürücü koltuğunda {pid} (camlar çizilmedi)", font=font, fill=(20, 20, 20))
        tiles.append(tile)
    sheet = Image.new("RGB", (840 * 2, 320 * math.ceil(len(tiles) / 2)), (232, 235, 240))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 2) * 840, (i // 2) * 320))
    sheet.save("docs/hijack_preview.png")
    print("preview -> docs/hijack_preview.png")
except Exception as e:  # preview is optional
    import traceback
    traceback.print_exc()
    print("preview skipped:", e)

print("\n%d checks failed" % len(fails) if fails else "\nall checks passed")
sys.exit(1 if fails else 0)
