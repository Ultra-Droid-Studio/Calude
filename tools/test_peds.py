#!/usr/bin/env python3
"""test_peds.py — offline check of the realistic pedestrians (assets/pedestrians/SOLARA_Pedestrians.glb, Microsoft
Rocketbox) with the REAL game code: ModelAssetService (ReplicatedStorage.PedestrianModels), PedMeshRig (scaling,
calibration, bone poses), PedRenderer (pool, placement) and PedAnim (the walk), in Lua 5.4 (lupa) with small Roblox
stand-ins (tools/roblox_mock.py). The skinned mesh is then deformed in Python with the bone transforms the game set
(linear blend skinning, like Roblox) to check the result and to draw it.

The import is simulated (one MeshPart per character, bones as Bone instances with local CFrames) at several scales,
rotations and origins, with the bones under the mesh, under an own part, or under a foreign "Armature" part.
  [1] ModelAssetService: one Ped_<Id> model per character (10), Ready; bones end up under the character's parts
  [2] standing: feet on the ground, height 5.4-5.9 studs, faces -Z, left side at -X
  [3] neutral arms hang beside the body (upper arm ~7 deg from vertical, hands at hip height), not in A-pose
  [4] leg IK: with PedAnim.LegIK angles the ankle lands where PedAnim wants it (forward d, down h)
  [5] the same character looks the same for every import transform and bone layout
  [6] a full walk cycle (PedAnim.Step) deforms the mesh smoothly: no torn / flung vertices, feet stay planted
  [7] PedRenderer uses the realistic models when present (else the R15 pedestrians), places the root at RootY
Writes docs/pedestrians_walk_preview.png: frames of the walk cycle rendered from the skinned mesh the game would show.
Usage: python3 -I tools/test_peds.py <lupa-site-packages>
"""
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

fails = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        fails.append(name)


SERVICES = r"""
RS = new("ReplicatedStorage")
local shared = new("Folder", {Name = "Shared", Parent = RS})
PMD_MARK = new("ModuleScript", {Name = "PedModelData", Parent = shared})
WS = new("Workspace")
LOADABLE = nil
game = { GetService = function(_, n)
  if n == "ReplicatedStorage" then return RS end
  if n == "Workspace" then return WS end
  if n == "InsertService" then return { LoadAsset = function(_, id) LOADED_ID = id; return LOADABLE end } end
  if n == "ServerScriptService" then return { WorldGen = { AssetIds = "__AID" } } end
end }
RS.Modules = { CarModelConfig = "__CMC" }
AID = { Cars = 0, TrafficLights = 0, Pedestrians = 0 }
AMBIENT = new("Folder", {Name = "Ambient"})
RIG_MARK = new("ModuleScript", {Name = "PedMeshRig", Parent = AMBIENT})
script = { Parent = AMBIENT }
local realRequire = require
require = function(x)
  if x == PMD_MARK then return PMD end
  if x == RIG_MARK then return RIG end
  if x == "__AID" then return AID end
  if x == "__CMC" then return { Folder = "VehicleModels", Models = {} } end
  return realRequire(x)
end
print = function() end
"""


# ---------------------------------------------------------------------------------------------------------------
def read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    g = json.loads(data[20:20 + jlen])
    blen = struct.unpack_from("<I", data, 20 + jlen)[0]
    binary = data[28 + jlen:28 + jlen + blen]

    def acc(i, dtype, width):
        a = g["accessors"][i]
        bv = g["bufferViews"][a["bufferView"]]
        arr = np.frombuffer(binary, dtype, a["count"] * width, bv["byteOffset"])
        return arr.reshape(-1, width) if width > 1 else arr

    def quat(q):
        x, y, z, w = q
        return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])

    def local(n):
        M = np.eye(4)
        M[:3, :3] = quat(n.get("rotation", [0, 0, 0, 1]))
        M[:3, 3] = n.get("translation", [0, 0, 0])
        return M

    peds = {}
    for top in g["scenes"][0]["nodes"]:
        tn = g["nodes"][top]
        mesh_node = [c for c in tn["children"] if "mesh" in g["nodes"][c]][0]
        mn = g["nodes"][mesh_node]
        skin = g["skins"][mn["skin"]]
        prim = g["meshes"][mn["mesh"]]["primitives"][0]
        P = acc(prim["attributes"]["POSITION"], "<f4", 3).astype(float)
        J = acc(prim["attributes"]["JOINTS_0"], "<u2", 4).astype(int)
        W = acc(prim["attributes"]["WEIGHTS_0"], "<f4", 4).astype(float)
        UV = acc(prim["attributes"]["TEXCOORD_0"], "<f4", 2).astype(float)
        F = acc(prim["indices"], "<u4", 1).astype(int).reshape(-1, 3)
        joints = skin["joints"]
        parent = {}
        for i in joints:
            for c in g["nodes"][i].get("children", []):
                parent[c] = i
        world = {}

        def wof(i):
            if i not in world:
                world[i] = (wof(parent[i]) if i in parent else np.eye(4)) @ local(g["nodes"][i])
            return world[i]
        bones = []
        for i in joints:
            bones.append({"name": g["nodes"][i]["name"], "world": wof(i), "local": local(g["nodes"][i]),
                          "parent": joints.index(parent[i]) if i in parent else None})
        peds[tn["name"]] = {"P": P, "J": J, "W": W, "UV": UV, "F": F, "bones": bones}
    return peds


GLB = read_glb("assets/pedestrians/SOLARA_Pedestrians.glb")


def rot(yaw, pitch):
    cy, sy, cp, sp = math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    X = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    Y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    return X @ Y


# (scale, yaw, pitch, origin, bone layout)
VARIANTS = [(1.0, 0, 0, (0, 0, 0), "mesh"), (3.571, 0, 0, (10, 2, -4), "mesh"), (2.0, 180, 0, (-3, 0, 6), "own"),
            (0.5, 90, 0, (1, 2, 3), "foreign"), (10.0, 90, 90, (0, 40, 0), "own")]


def cf_args(M3, p):
    return [float(p[0]), float(p[1]), float(p[2])] + [float(x) for x in M3.reshape(-1)]


def runtime(variant, only=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(roblox_mock.MOCK + SERVICES)
    g = lua.globals()
    g.PMD = lua.execute(open("src/ReplicatedStorage/Shared/PedModelData.lua", encoding="utf-8").read())
    imports = {}
    if variant is not None:
        scale, yaw, pitch, origin, layout = variant
        R = rot(yaw, pitch)
        o = np.array(origin, float)
        mkcf = lua.eval("""function(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9)
          local c = CFrame.fromMatrix(Vector3.new(x, y, z), Vector3.new(r1, r4, r7), Vector3.new(r2, r5, r8))
          return c end""")
        newi = lua.eval("new")
        vec = lua.eval("Vector3.new")
        root = newi("Model", lua.table_from({"Name": "SOLARA_Pedestrians"}))
        armature = None
        if layout == "foreign":
            armature = newi("Part", lua.table_from({"Name": "Armature", "CFrame": mkcf(*cf_args(R, o + R @ np.array([0.3, 0.5, -0.2]) * scale)),
                                                     "Size": vec(1, 1, 1)}))
            armature.Parent = root
        for name, ped in GLB.items():
            if only and name not in only:
                continue
            Pimp = o + (ped["P"] * scale) @ R.T
            lo, hi = Pimp.min(0), Pimp.max(0)
            # mesh part: unrotated if the rotation is baked (yaw multiple of 90 -> axis-aligned box)
            mesh_cf = mkcf(*cf_args(np.eye(3), (lo + hi) / 2))
            mesh = newi("MeshPart", lua.table_from({"Name": name + "_Body", "CFrame": mesh_cf,
                                                    "Size": vec(*(hi - lo))}))
            mesh.Parent = root
            holder = mesh
            if layout == "own":
                holder = newi("Part", lua.table_from({"Name": name, "CFrame": mkcf(*cf_args(np.eye(3), lo)), "Size": vec(0.2, 0.2, 0.2)}))
                holder.Parent = root
            elif layout == "foreign":
                holder = armature
            bone_objs = []
            for b in ped["bones"]:
                bone_objs.append(newi("Bone", lua.table_from({"Name": b["name"]})))
            for b, obj in zip(ped["bones"], bone_objs):
                if b["parent"] is None:
                    Wimp = np.eye(4)
                    Wimp[:3, :3] = R @ b["world"][:3, :3]
                    Wimp[:3, 3] = o + R @ (b["world"][:3, 3] * scale)
                    hc = holder.CFrame
                    obj.Parent = holder
                    obj.CFrame = hc.ToObjectSpace(hc, mkcf(*cf_args(Wimp[:3, :3], Wimp[:3, 3])))
                else:
                    L = b["local"]
                    obj.Parent = bone_objs[b["parent"]]
                    obj.CFrame = mkcf(*cf_args(L[:3, :3], L[:3, 3] * scale))
            imports[name] = {"Pimp": Pimp, "mesh": mesh, "bones": bone_objs}
        g.AID.Pedestrians = 4242
        g.LOADABLE = root
    svc = lua.execute(convert(open("src/ServerScriptService/Services/ModelAssetService.lua", encoding="utf-8").read()))
    svc.Init(svc)
    g.RIG = lua.execute(convert(open("src/StarterPlayer/StarterPlayerScripts/Ambient/PedMeshRig.lua", encoding="utf-8").read()))
    return lua, g.RIG, imports


# skinning: vertices after the game's ScaleTo and bone transforms, in the root's frame
SNAP = r"""function(model, rig, names)
  local root = model.PrimaryPart
  local out = {}
  for _, n in ipairs(names) do
    local b = rig.Drive[n] and rig.Drive[n].Bone
    out[n] = b
  end
  return root
end"""


def skin_state(lua, model, ped_name, imp):
    """returns posed vertices (root frame) and bone positions (root frame) using the Lua bones' rest/transformed CFrames"""
    root = model.PrimaryPart
    bones_lua = {}
    for d in model.GetDescendants(model).values():
        if str(d.ClassName if hasattr(d, "ClassName") else "") == "Bone" or lua.eval("function(d) return d._cls end")(d) == "Bone":
            bones_lua[d.Name] = d
    ped = GLB[ped_name]
    to_np = lua.eval("""function(c) local r = c.R
      return c.P.X, c.P.Y, c.P.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] end""")

    def mat(c):
        v = to_np(c)
        M = np.eye(4)
        M[:3, 3] = v[:3]
        M[:3, :3] = np.array(v[3:]).reshape(3, 3)
        return M
    Rinv = np.linalg.inv(mat(root.CFrame))
    rest = np.array([mat(bones_lua[b["name"]].WorldCFrame) for b in ped["bones"]])
    posed = np.array([mat(bones_lua[b["name"]].TransformedWorldCFrame) for b in ped["bones"]])
    # mesh vertices as the game has them at rest (import + ScaleTo = one similarity transform of the glb model
    # space): fitted from the bind-pose bone positions (glb) to the rest bone positions (game), Umeyama
    bind = np.array([b["world"][:3, 3] for b in ped["bones"]])
    now = rest[:, :3, 3]
    mb, mn = bind.mean(0), now.mean(0)
    H = (bind - mb).T @ (now - mn)
    U, S, Vt = np.linalg.svd(H)
    D = np.diag([1, 1, np.sign(np.linalg.det(Vt.T @ U.T))])
    Rs = Vt.T @ D @ U.T
    sc = np.trace(np.diag(S) @ D) / ((bind - mb) ** 2).sum()
    Vrest = (ped["P"] - mb) @ Rs.T * sc + mn
    skin = posed @ np.linalg.inv(rest)
    M = np.einsum("vk,vkij->vij", ped["W"], skin[ped["J"]])
    Pw = np.einsum("vij,vj->vi", M, np.c_[Vrest, np.ones(len(Vrest))])[:, :3]
    Pr = (np.c_[Pw, np.ones(len(Pw))] @ Rinv.T)[:, :3]
    bonepos = {b["name"].split("_", 2)[2]: (Rinv @ posed[i])[:3, 3] for i, b in enumerate(ped["bones"])}
    restpos = {b["name"].split("_", 2)[2]: (Rinv @ rest[i])[:3, 3] for i, b in enumerate(ped["bones"])}
    return Pr, bonepos, restpos


# ---------------------------------------------------------------------------------------------------------------
PED_NAMES = sorted(GLB)
results = {}
for vi, variant in enumerate(VARIANTS):
    lua, RIG, imports = runtime(variant)
    g = lua.globals()
    folder = g.RS.FindFirstChild(g.RS, "PedestrianModels")
    models = sorted(m.Name for m in folder.GetChildren(folder).values()) if folder else []
    bones_ok = folder is not None and lua.eval("""function(folder)
      -- every bone hangs under a part of its own character model
      for _, m in ipairs(folder:GetChildren()) do
        for _, d in ipairs(m:GetDescendants()) do
          if d._cls == "Bone" then
            local p = d.Parent
            while p and p._cls == "Bone" do p = p.Parent end
            if not p or p.Parent ~= m then return false end
          end
        end
      end
      return true
    end""")(folder)
    check("[1] v%d (%s bones): PedestrianModels has the 10 characters, Ready, bones under their own parts" % (vi, variant[4]),
          models == PED_NAMES and folder.GetAttribute(folder, "Ready") is True and bones_ok and lua.eval("WARNED") == 0,
          "%d models" % len(models))
    rng = lua.eval("Random.new")
    per = {}
    for name in PED_NAMES:
        # build exactly this character: temporarily keep only it in the template list
        pick = lua.eval("""function(RIG, id, seed)
          local rng = Random.new(seed)
          local saved = RIG.Available()
          -- PedMeshRig picks randomly; draw until we get the wanted one
          for i = 1, 400 do
            local m, r = RIG.Build(rng)
            if m and r.Id == id then return m, r end
          end
        end""")
        model, rig = pick(RIG, name[4:], 7)
        per[name] = (model, rig)
    results[vi] = (lua, RIG, per, imports)

# --- [2]..[4] on the first variant
lua, RIG, per, imports = results[0]
PedAnim = lua.execute(convert(open("src/ReplicatedStorage/Shared/Ambient/PedAnim.lua", encoding="utf-8").read()))
pose_of = lua.eval("""function(t) local p = {RootX = 0, RootY = 0, RootYaw = 0, RootRoll = 0, WaistPitch = 0, WaistYaw = 0,
  NeckPitch = 0, NeckYaw = 0, LHip = 0, LKnee = 0, LAnkle = 0, RHip = 0, RKnee = 0, RAnkle = 0, LShoulder = 0,
  LShoulderRoll = 0, RShoulder = 0, RShoulderRoll = 0, LElbow = 0, RElbow = 0}
  for k, v in pairs(t) do p[k] = v end return p end""")
bad2, bad3, bad4 = [], [], []
for name in PED_NAMES:
    model, rig = per[name]
    P, B, _ = skin_state(lua, model, name, imports[name])
    ground = P[:, 1].min()
    height = P[:, 1].max() - ground
    if abs(ground + rig.RootY) > 0.12:
        bad2.append(f"{name} feet at {ground + rig.RootY:+.2f} from the ground")
    if not 5.3 < height < 6.0:
        bad2.append(f"{name} height {height:.2f}")
    head = P[P[:, 1] > P[:, 1].max() - 0.8]
    if not (head[:, 2].min() < B["Head"][2] - 0.2):
        bad2.append(f"{name} does not face -Z")
    if not B["LThigh"][0] < 0 < B["RThigh"][0]:
        bad2.append(f"{name} left/right")
    for side, sx in (("L", -1), ("R", 1)):
        ua = B[side + "Forearm"] - B[side + "UpperArm"]
        ang = math.degrees(math.atan2(abs(ua[0]), -ua[1]))
        if not 4 < ang < 10 or ua[0] * sx < 0:
            bad3.append(f"{name} {side} upper arm {ang:.1f} deg from vertical")
        if B[side + "Hand"][1] > B["Pelvis"][1] + 0.3:
            bad3.append(f"{name} {side} hand above the hip")
    # leg IK
    k = rig.Scale
    for d, h in ((0.6, 2.3), (-0.5, 2.25), (0.9, 2.1)):
        th, ka = PedAnim.LegIK(d, h)
        RIG.Pose(rig, pose_of(lua.table_from({"LHip": th, "LKnee": ka, "RHip": th, "RKnee": ka})))
        _, Bp, _ = skin_state(lua, model, name, imports[name])
        for side in ("L", "R"):
            rel = Bp[side + "Foot"] - Bp[side + "Thigh"]
            if abs(-rel[2] - d * k) > 0.16 * k or abs(-rel[1] - h * k) > 0.16 * k:
                bad4.append(f"{name} {side} d={d} h={h}: ankle fwd {-rel[2] / k:.2f} down {-rel[1] / k:.2f}")
    RIG.Neutral(rig)
check("[2] standing: feet on the ground, 5.3-6.0 studs tall, faces -Z, left at -X", not bad2, "; ".join(bad2[:4]))
check("[3] neutral: arms hang ~7 deg from vertical beside the body (not A-pose)", not bad3, "; ".join(bad3[:4]))
check("[4] leg IK: PedAnim hip/knee angles put the ankle where PedAnim wants it (±0.16 leg units)", not bad4, "; ".join(bad4[:4]))

# --- [5] invariance
bad = []
ref = {}
for name in PED_NAMES:
    model, rig = per[name]
    RIG.Pose(rig, pose_of(lua.table_from({"LHip": 0.4, "LKnee": 0.5, "RShoulder": -0.3, "LElbow": -0.4, "WaistYaw": 0.2})))
    _, Bp, _ = skin_state(lua, model, name, imports[name])
    ref[name] = (Bp, rig.Scale)
for vi in range(1, len(VARIANTS)):
    l2, R2, per2, imp2 = results[vi]
    po = l2.eval("""function(t) local p = {RootX = 0, RootY = 0, RootYaw = 0, RootRoll = 0, WaistPitch = 0, WaistYaw = 0,
      NeckPitch = 0, NeckYaw = 0, LHip = 0, LKnee = 0, LAnkle = 0, RHip = 0, RKnee = 0, RAnkle = 0, LShoulder = 0,
      LShoulderRoll = 0, RShoulder = 0, RShoulderRoll = 0, LElbow = 0, RElbow = 0}
      for k, v in pairs(t) do p[k] = v end return p end""")
    for name in PED_NAMES:
        model, rig = per2[name]
        R2.Pose(rig, po(l2.table_from({"LHip": 0.4, "LKnee": 0.5, "RShoulder": -0.3, "LElbow": -0.4, "WaistYaw": 0.2})))
        _, Bp, _ = skin_state(l2, model, name, imp2[name])
        B0, k0 = ref[name]
        s = rig.Scale / k0  # same random size factor? (same seed -> same draw)
        dev = max(np.linalg.norm(Bp[n] - B0[n] * s) for n in B0)
        if dev > 0.02:
            bad.append(f"v{vi} {name} bones differ by {dev:.3f} studs")
check("[5] same pose for import scale 1 / 3.57 / 2 / 0.5 / 10, rotated, bones under mesh / own part / foreign part",
      not bad, "; ".join(bad[:4]))

# --- [6] walk cycle
frames = []
bad = []
name = "Ped_F03"
model, rig = per[name]
st = PedAnim.new(0.37)
k = rig.Scale
speed = 4.6  # studs/s (AmbientController walking speed range)
dist = 0.0
plant = {}
P0, _, _ = skin_state(lua, model, name, imports[name])
slide = []
for f in range(48):
    dt = 1 / 30
    pose = PedAnim.Step(st, dt, speed / k, 0, 0)
    RIG.Pose(rig, pose)
    dist += speed * dt
    P, Bp, _ = skin_state(lua, model, name, imports[name])
    if not np.isfinite(P).all():
        bad.append(f"frame {f}: NaN")
        break
    move = np.linalg.norm(P - P0, axis=1).max()
    if move > 3.2:
        bad.append(f"frame {f}: a vertex moved {move:.2f} studs")
    # planted foot: world z of the lower foot = root z (-dist forward) + local z; should stay ~constant while planted
    for side in ("L", "R"):
        foot = Bp[side + "Foot"]
        world_z = foot[2] - dist  # the root walks toward -Z by dist
        key = side
        if foot[1] < min(Bp["LFoot"][1], Bp["RFoot"][1]) + 0.02:
            if key in plant:
                slide.append(abs(world_z - plant[key]))
            plant[key] = world_z
        else:
            plant.pop(key, None)
    if f % 4 == 0:
        frames.append(P.copy())
check("[6] walk cycle: mesh stays whole (no torn / flung vertices)", not bad, "; ".join(bad[:3]))
check("[6] planted foot does not slide (frame to frame)", slide and max(slide) < 0.12, "max %.3f studs" % (max(slide) if slide else -1))

# --- [7] PedRenderer
PR_SRC = convert(open("src/StarterPlayer/StarterPlayerScripts/Ambient/PedRenderer.lua", encoding="utf-8").read())
PR = lua.execute(PR_SRC)
PR.Init()
m = PR.Acquire()
mesh_used = lua.eval("function(m) return m.PrimaryPart ~= nil and m.PrimaryPart.Name == 'HumanoidRootPart' and m:FindFirstChild('Head') == nil end")(m)
PR.Place(m, lua.eval("Vector3.new(50, 3, -20)"), 0, -1)
rp = m.PrimaryPart.CFrame.Position
scale = PR.Scale(m)
check("[7] PedRenderer builds realistic pedestrians when the models are there, root at ground + RootY",
      mesh_used and abs(rp.Y - 3) > 2.5 and abs(rp.X - 50) < 1e-6 and scale > 0.9, "root y %.2f, scale %.3f" % (rp.Y, scale))
lua0, RIG0, _ = runtime(None)
PR0 = lua0.execute(PR_SRC)
PR0.Init()
m0 = PR0.Acquire()
check("[7] without the models: the R15 pedestrians", RIG0.Available() is False and m0.FindFirstChild(m0, "Head") is not None)

# --- preview of the walk
try:
    from PIL import Image, ImageDraw, ImageFont
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    ped = GLB[name]
    atlas = None
    data = open("assets/pedestrians/SOLARA_Pedestrians.glb", "rb").read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    gj = json.loads(data[20:20 + jlen])
    binary = data[28 + jlen:]
    img_index = [i for i, im in enumerate(gj["images"]) if im["name"].startswith(name + "_")][0]
    bv = gj["bufferViews"][gj["images"][img_index]["bufferView"]]
    import io
    atlas = np.asarray(Image.open(io.BytesIO(binary[bv["byteOffset"]:bv["byteOffset"] + bv["byteLength"]])).convert("RGBA")).astype(float)
    A = atlas.shape[0]

    def draw(P, yaw, size=(220, 340)):
        img = Image.new("RGB", size, (232, 235, 240))
        d = ImageDraw.Draw(img)
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        eye = np.array([-sy, 0.1, -cy]); eye /= np.linalg.norm(eye)
        fw = -eye
        r = np.cross(fw, [0, 1, 0]); r /= np.linalg.norm(r)
        u = np.cross(r, fw)
        T = P[ped["F"]]
        cam = np.stack([T @ r, T @ u, T @ fw], -1)
        uv = ped["UV"][ped["F"]].mean(1)
        cols = atlas[np.clip((uv[:, 1] * A).astype(int), 0, A - 1), np.clip((uv[:, 0] * A).astype(int), 0, A - 1)]
        n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        L = np.array([0.3, 0.8, -0.5]); L /= np.linalg.norm(L)
        shade = 0.55 + 0.45 * np.abs(n @ L)
        s = size[1] / 6.4
        for kk in np.argsort(-cam[:, :, 2].mean(1)):
            if cols[kk, 3] < 128:
                continue
            c = tuple(int(x) for x in np.clip(cols[kk, :3] * shade[kk], 0, 255))
            d.polygon([(size[0] / 2 + p[0] * s, size[1] * 0.52 - p[1] * s) for p in cam[kk]], fill=c)
        d.line([(0, size[1] * 0.52 + rig.RootY * s), (size[0], size[1] * 0.52 + rig.RootY * s)], fill=(150, 150, 150))
        return img
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    sheet = Image.new("RGB", (220 * 6, 340 * 2 + 24), (232, 235, 240))
    for i, P in enumerate(frames[:6]):
        sheet.paste(draw(P, 90), (i * 220, 24))
        sheet.paste(draw(P, 35), (i * 220, 24 + 340))
    ImageDraw.Draw(sheet).text((6, 4), "Oyundaki kodla (PedAnim + PedMeshRig) üretilen yürüme kareleri — %s, %.1f stud/sn" % (name, speed),
                               font=font, fill=(20, 20, 20))
    sheet.save("docs/pedestrians_walk_preview.png")
    print("preview -> docs/pedestrians_walk_preview.png")
except Exception as e:  # preview is optional
    print("preview skipped:", e)

print("\n%d checks failed" % len(fails) if fails else "\nall checks passed")
sys.exit(1 if fails else 0)
