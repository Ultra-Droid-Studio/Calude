#!/usr/bin/env python3
"""
preview_ped.py — draws the NPC R15 rig (same part sizes/joints as PedRenderer.lua) in poses produced by the REAL
PedAnim.lua (lupa), using Roblox's Motor6D rule Part1 = Part0 * C0 * Transform * C1^-1. Side view (walk cycle) and
3/4 views. Output: docs/livingcity_ped_preview.png. Checks orientation: feet on the ground, legs swing forward/back,
knees bend backward, arms swing opposite to legs.
Usage: python3 tools/preview_ped.py <lupa-site-packages>
"""
import sys, math
sys.path.insert(0, sys.argv[1])
import numpy as np
from PIL import Image, ImageDraw
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
A = lua.execute(open("src/ReplicatedStorage/Shared/Ambient/PedAnim.lua", encoding="utf-8").read())

def T(x, y, z):
    m = np.eye(4); m[:3, 3] = (x, y, z); return m
def Rx(a):
    c, s = math.cos(a), math.sin(a); m = np.eye(4); m[1, 1] = c; m[1, 2] = -s; m[2, 1] = s; m[2, 2] = c; return m
def Ry(a):
    c, s = math.cos(a), math.sin(a); m = np.eye(4); m[0, 0] = c; m[0, 2] = s; m[2, 0] = -s; m[2, 2] = c; return m
def Rz(a):
    c, s = math.cos(a), math.sin(a); m = np.eye(4); m[0, 0] = c; m[0, 1] = -s; m[1, 0] = s; m[1, 1] = c; return m
def ang(x, y, z):  # CFrame.Angles(x, y, z) = Rx * Ry * Rz
    return Rx(x) @ Ry(y) @ Rz(z)

W = 1.0
tw = 2.0 * W; ax = tw / 2 + 0.48
parts = {  # name: (size, rest center)
    "HumanoidRootPart": ((2, 2, 1), (0, 2.95, 0)), "LowerTorso": ((1.9, 0.6, 1.0), (0, 2.95, 0)),
    "UpperTorso": ((tw, 1.5, 1.0), (0, 4.0, 0)), "Head": ((1.15, 1.2, 1.15), (0, 5.35, 0)),
}
for side, sx in (("Left", -1), ("Right", 1)):
    parts[side + "UpperArm"] = ((0.95, 1.2, 0.95), (sx * ax, 4.15, 0))
    parts[side + "LowerArm"] = ((0.9, 1.05, 0.9), (sx * ax, 3.0, 0))
    parts[side + "Hand"] = ((0.8, 0.45, 0.8), (sx * ax, 2.25, 0))
    parts[side + "UpperLeg"] = ((0.95, 1.2, 0.95), (sx * 0.5, 2.1, 0))
    parts[side + "LowerLeg"] = ((0.9, 1.2, 0.9), (sx * 0.5, 0.9, 0))
    parts[side + "Foot"] = ((0.9, 0.3, 1.25), (sx * 0.5, 0.15, -0.15))
joints = [("Root", "HumanoidRootPart", "LowerTorso", (0, 2.95, 0)), ("Waist", "LowerTorso", "UpperTorso", (0, 3.25, 0)),
          ("Neck", "UpperTorso", "Head", (0, 4.75, 0))]
for side, sx in (("Left", -1), ("Right", 1)):
    joints += [(side + "Shoulder", "UpperTorso", side + "UpperArm", (sx * ax, 4.6, 0)),
               (side + "Elbow", side + "UpperArm", side + "LowerArm", (sx * ax, 3.55, 0)),
               (side + "Wrist", side + "LowerArm", side + "Hand", (sx * ax, 2.475, 0)),
               (side + "Hip", "LowerTorso", side + "UpperLeg", (sx * 0.5, 2.7, 0)),
               (side + "Knee", side + "UpperLeg", side + "LowerLeg", (sx * 0.5, 1.5, 0)),
               (side + "Ankle", side + "LowerLeg", side + "Foot", (sx * 0.5, 0.3, 0))]
rest = {n: T(*c) for n, (sz, c) in parts.items()}
C = {}
for jn, p0, p1, at in joints:
    C[jn] = (np.linalg.inv(rest[p0]) @ T(*at), np.linalg.inv(rest[p1]) @ T(*at), p0, p1)

def transforms(pose):
    if pose is None:
        return {}
    return {
        "Root": T(pose.RootX, pose.RootY, 0) @ ang(0, pose.RootYaw, pose.RootRoll),
        "Waist": ang(pose.WaistPitch, pose.WaistYaw, 0), "Neck": ang(pose.NeckPitch, pose.NeckYaw, 0),
        "LeftHip": ang(pose.LHip, 0, 0), "LeftKnee": ang(-pose.LKnee, 0, 0), "LeftAnkle": ang(pose.LAnkle, 0, 0),
        "RightHip": ang(pose.RHip, 0, 0), "RightKnee": ang(-pose.RKnee, 0, 0), "RightAnkle": ang(pose.RAnkle, 0, 0),
        "LeftShoulder": ang(pose.LShoulder, 0, pose.LShoulderRoll), "RightShoulder": ang(pose.RShoulder, 0, pose.RShoulderRoll),
        "LeftElbow": ang(pose.LElbow, 0, 0), "RightElbow": ang(pose.RElbow, 0, 0),
    }

def solve(pose, rootCF):
    tr = transforms(pose)
    cf = {"HumanoidRootPart": rootCF}
    for jn, p0, p1, at in joints:
        c0, c1, _, _ = C[jn]
        cf[p1] = cf[p0] @ c0 @ tr.get(jn, np.eye(4)) @ np.linalg.inv(c1)
    return cf

COLORS = {"Head": (240, 200, 164), "UpperTorso": (58, 104, 172), "LowerTorso": (42, 54, 86)}
def color(n):
    if n in COLORS: return COLORS[n]
    if "Arm" in n: return (58, 104, 172) if "Upper" in n else (240, 200, 164)
    if "Hand" in n: return (240, 200, 164)
    if "Leg" in n: return (42, 54, 86)
    if "Foot" in n: return (28, 28, 30)
    return (200, 200, 200)

def boxes(cf):
    out = []
    for n, (sz, c) in parts.items():
        if n == "HumanoidRootPart": continue
        m = cf[n]; hx, hy, hz = sz[0] / 2, sz[1] / 2, sz[2] / 2
        corners = [m @ np.array([sx * hx, sy * hy, sz_ * hz, 1]) for sx in (-1, 1) for sy in (-1, 1) for sz_ in (-1, 1)]
        out.append((n, np.array(corners)[:, :3]))
    return out

FACES = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
def draw(dr, cf, ox, oy, scale, view):
    # view: rotation applied to world for the camera (looking along -z of view)
    polys = []
    for n, pts in boxes(cf):
        P = (view @ np.c_[pts, np.ones(8)].T).T[:, :3]
        for f in FACES:
            q = P[list(f)]
            polys.append((q[:, 2].mean(), n, q))
    polys.sort(key=lambda t: t[0])  # far (more negative z) first
    for depth, n, q in polys:
        base = np.array(color(n), dtype=float)
        nrm = np.cross(q[1] - q[0], q[2] - q[0]); nl = np.linalg.norm(nrm)
        shade = 0.55 + 0.45 * abs(nrm[2] / nl) if nl > 1e-9 else 0.6
        col = tuple(int(min(255, c * shade)) for c in base)
        dr.polygon([(ox + x * scale, oy - y * scale) for x, y, _ in q], fill=col, outline=(20, 20, 20))

img = Image.new("RGB", (1500, 760), (236, 240, 244))
dr = ImageDraw.Draw(img)
# side view: camera looks along +X (person walks toward -Z = to the left in image)
side = Ry(math.pi / 2)
st = A.new(3); dt = 1 / 30; v = 5.0
poses = []
for i in range(int(2.0 / dt)):
    poses.append(A.Step(st, dt, v, 0, 0))
cycle = poses[-int(1 / A.Cadence(v) * 2 / dt):]
n = 8
for k in range(n):
    p = cycle[int(k * len(cycle) / n)]
    cf = solve(p, T(0, 2.95, 0))
    draw(dr, cf, 90 + k * 170, 330, 45, side)
    dr.line([(20, 330), (1480, 330)], fill=(120, 120, 120), width=2)
dr.text((20, 10), "Living City NPC (R15 rig built in code) - PedAnim walk cycle at 5 studs/s, side view (walking left)", fill=(20, 20, 20))
# 3/4 views: idle, walk, door reach, turn lean
views = []
st2 = A.new(5)
for i in range(60): idle = A.Step(st2, dt, 0, 0, 0)
st3 = A.new(6)
for i in range(60): walk = A.Step(st3, dt, 5, 0, 0)
st4 = A.new(8)
for i in range(60): reach = A.Step(st4, dt, 0.8, 0, 1)
st5 = A.new(9)
for i in range(60): turn = A.Step(st5, dt, 4.5, 1.5, 0)
labels = ["Idle", "Walk", "Door (push)", "Turn left (lean)", "Rest pose"]
three = Rx(math.radians(-12)) @ Ry(math.radians(35))
for k, p in enumerate([idle, walk, reach, turn, None]):
    cf = solve(p, T(0, 2.95, 0))
    draw(dr, cf, 150 + k * 290, 700, 48, three)
    dr.text((80 + k * 290, 715), labels[k], fill=(20, 20, 20))
img.save("docs/livingcity_ped_preview.png")
# sanity: feet heights and orientation in the side cycle
for p in cycle[:: max(1, len(cycle) // 4)]:
    cf = solve(p, T(0, 2.95, 0))
    lf = cf["LeftFoot"][:3, 3]; rf = cf["RightFoot"][:3, 3]; head = cf["Head"][:3, 3]
    print("feet y %.2f %.2f (sole = y-0.15), feet z %.2f %.2f, head y %.2f" % (lf[1], rf[1], lf[2], rf[2], head[1]))
print("saved docs/livingcity_ped_preview.png")
