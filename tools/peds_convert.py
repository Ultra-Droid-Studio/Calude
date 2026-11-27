#!/usr/bin/env python3
"""
peds_convert.py — the user's Microsoft Rocketbox pedestrians (Business_Female_0x / Business_Male_0x .glb, MIT) into ONE
Roblox-ready file of skinned characters: assets/pedestrians/SOLARA_Pedestrians.glb, plus their measurements
(src/ReplicatedStorage/Shared/PedModelData.lua) and a preview (docs/pedestrians_preview.png).

What is kept: the original mesh (every triangle), its skinning, the face/body/hair textures (base colour). What changes:
  * skeleton: the 80 Biped bones -> the 20 the walk animation drives (pelvis, 3 spine, neck, head, clavicles, upper
    arms, forearms, hands, thighs, calves, feet). Finger, toe and face bone weights go to their hand / foot / head, so
    the mesh is unchanged at rest. Bones are named Ped_<Id>_<Bone> (unique per character).
  * one mesh and one texture per character: body, head and hair (alpha) share a 1024 x 1024 atlas (Roblox: one
    MeshPart, one texture, up to 1024 px).
  * axes: Roblox convention, character faces -Z, left = -X, metres, feet on y = 0. The rest pose is the source's bind
    pose (A-pose arms); the game lowers the arms and animates the bones itself (PedAnim + PedRenderer).
The files are meshopt / WebP compressed (tools/gltf_decode.py reads them).

Usage: python3 -I tools/peds_convert.py <folder with Business_*.glb>
Needs numpy, Pillow (WebP) and the meshoptimizer Python package. Only data is read.
"""
import hashlib
import io
import json
import math
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_decode  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "pedestrians")
OUT_GLB = os.path.join(OUT_DIR, "SOLARA_Pedestrians.glb")
OUT_LUA = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "PedModelData.lua")
OUT_PREVIEW = os.path.join(ROOT, "docs", "pedestrians_preview.png")
ATLAS = 1024
HALF = ATLAS // 2

KEEP = {
    "Bip01 Pelvis": "Pelvis", "Bip01 Spine": "Spine", "Bip01 Spine1": "Spine1", "Bip01 Spine2": "Spine2",
    "Bip01 Neck": "Neck", "Bip01 Head": "Head",
    "Bip01 L Clavicle": "LClavicle", "Bip01 L UpperArm": "LUpperArm", "Bip01 L Forearm": "LForearm", "Bip01 L Hand": "LHand",
    "Bip01 R Clavicle": "RClavicle", "Bip01 R UpperArm": "RUpperArm", "Bip01 R Forearm": "RForearm", "Bip01 R Hand": "RHand",
    "Bip01 L Thigh": "LThigh", "Bip01 L Calf": "LCalf", "Bip01 L Foot": "LFoot",
    "Bip01 R Thigh": "RThigh", "Bip01 R Calf": "RCalf", "Bip01 R Foot": "RFoot",
}
FLIP = np.diag([-1.0, 1.0, -1.0, 1.0])  # 180 deg about Y: source faces +Z -> Roblox -Z


def ped_id(fname):
    base = os.path.splitext(fname)[0]  # Business_Female_01
    parts = base.split("_")
    return ("F" if parts[1] == "Female" else "M") + parts[2][:2]


def mat_to_trs(M):
    t = M[:3, 3].copy()
    R = M[:3, :3].copy()
    s = np.linalg.norm(R, axis=0)
    R = R / s
    u, _, vt = np.linalg.svd(R)  # nearest rotation
    R = u @ vt
    w = math.sqrt(max(0.0, 1 + R[0, 0] + R[1, 1] + R[2, 2])) / 2
    if w > 1e-6:
        x = (R[2, 1] - R[1, 2]) / (4 * w)
        y = (R[0, 2] - R[2, 0]) / (4 * w)
        z = (R[1, 0] - R[0, 1]) / (4 * w)
    else:  # 180 deg rotation
        i = int(np.argmax(np.diag(R)))
        q = [0.0, 0.0, 0.0]
        q[i] = math.sqrt(max(0.0, 1 + 2 * R[i, i] - np.trace(R))) / 2
        j, k = (i + 1) % 3, (i + 2) % 3
        q[j] = (R[j, i] + R[i, j]) / (4 * q[i])
        q[k] = (R[k, i] + R[i, k]) / (4 * q[i])
        w = (R[k, j] - R[j, k]) / (4 * q[i])
        x, y, z = q
    return t, [x, y, z, w], s


def load_ped(path):
    g = gltf_decode.load(path)
    j = g.json
    skin = j["skins"][0]
    joints = skin["joints"]
    ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)  # column-major -> row
    world = np.array([g.node_world(n) for n in joints])
    jm = world @ ibm  # skinning matrices at rest
    name_of = {n: j["nodes"][n].get("name", "") for n in range(len(j["nodes"]))}
    par = g.parents()
    # nearest kept ancestor of every joint
    keep_nodes = {n for n in joints if name_of[n] in KEEP}
    assert len(keep_nodes) == len(KEEP), "missing bones: %s" % (set(KEEP) - {name_of[n] for n in keep_nodes})

    def kept(n):
        while n is not None and n not in keep_nodes:
            n = par.get(n)
        return n

    order = [n for n in joints if n in keep_nodes]
    new_index = {n: i for i, n in enumerate(order)}
    pelvis = [n for n in order if name_of[n] == "Bip01 Pelvis"][0]
    joint_map = np.array([new_index[kept(n) or pelvis] for n in joints])  # joints outside the kept tree -> pelvis
    mesh_node = [i for i, n in enumerate(j["nodes"]) if "mesh" in n][0]
    prims = j["meshes"][j["nodes"][mesh_node]["mesh"]]["primitives"]
    pos, nor, uv, jw, faces, mats = [], [], [], [], [], []
    base = 0
    for pi, prim in enumerate(prims):
        p = g.primitive(prim)
        P, N, UV = p["POSITION"], p["NORMAL"], p["TEXCOORD_0"]
        J, Wt = p["JOINTS_0"].astype(int), p["WEIGHTS_0"].astype(float)
        Wt = Wt / np.maximum(Wt.sum(1, keepdims=True), 1e-9)
        # skin to the rest pose
        M = np.einsum("vk,vkij->vij", Wt, jm[J])
        P4 = np.c_[P, np.ones(len(P))]
        Pr = np.einsum("vij,vj->vi", M, P4)[:, :3]
        Nr = np.einsum("vij,vj->vi", M[:, :3, :3], N)
        Nr /= np.maximum(np.linalg.norm(Nr, axis=1, keepdims=True), 1e-9)
        # weights onto the kept bones (top 4, normalised)
        NJ = np.zeros((len(P), 4), int)
        NW = np.zeros((len(P), 4))
        for v in range(len(P)):
            acc = {}
            for k in range(4):
                if Wt[v, k] > 0:
                    b = joint_map[J[v, k]]
                    acc[b] = acc.get(b, 0) + Wt[v, k]
            top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
            s = sum(w for _, w in top)
            for k, (b, w) in enumerate(top):
                NJ[v, k], NW[v, k] = b, w / s
        mat = j["materials"][prim["material"]]
        pos.append(Pr); nor.append(Nr); uv.append(UV); jw.append((NJ, NW))
        faces.append(p["indices"] + base)
        mats.append((mat.get("name", ""), mat, len(P)))
        base += len(P)
    textures = []
    for _, mat, _ in mats:
        tex = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
        textures.append(g.texture_image(tex))
    bones = []
    for n in order:
        parent = kept(par.get(n))
        bones.append({"name": KEEP[name_of[n]], "world": FLIP @ g.node_world(n),
                      "parent": new_index[parent] if parent in new_index else None})
    return {"pos": pos, "nor": nor, "uv": uv, "jw": jw, "faces": faces, "mats": mats, "textures": textures, "bones": bones}


def build_ped(src):
    """merge primitives, atlas the textures, flip axes, feet on y = 0"""
    quadrant = []  # per primitive: (u offset, v offset) in the atlas (glTF UV: v down)
    atlas = Image.new("RGBA", (ATLAS, ATLAS), (128, 128, 128, 255))
    slots = [(0, 0), (HALF, 0), (0, HALF), (HALF, HALF)]
    for i, img in enumerate(src["textures"]):
        x, y = slots[i]
        atlas.paste(img.resize((HALF, HALF), Image.LANCZOS), (x, y))
        quadrant.append((x / ATLAS, y / ATLAS))
    P = np.vstack(src["pos"]) @ FLIP[:3, :3].T
    N = np.vstack(src["nor"]) @ FLIP[:3, :3].T
    UV = []
    for (ou, ov), uv in zip(quadrant, src["uv"]):
        # keep inside the quadrant (a half-texel margin against bleeding)
        u = np.clip(uv[:, 0], 0.001, 0.999) * 0.5 + ou
        v = np.clip(uv[:, 1], 0.001, 0.999) * 0.5 + ov
        UV.append(np.c_[u, v])
    UV = np.vstack(UV)
    J = np.vstack([a for a, _ in src["jw"]])
    W = np.vstack([b for _, b in src["jw"]])
    F = np.vstack(src["faces"])
    floor = P[:, 1].min()
    P[:, 1] -= floor
    bones = []
    for b in src["bones"]:
        w = b["world"].copy()
        w[1, 3] -= floor
        bones.append(dict(b, world=w))
    return {"P": P, "N": N, "UV": UV, "J": J, "W": W, "F": F, "atlas": atlas, "bones": bones}


class Writer:
    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "SOLARA peds_convert.py (Microsoft Rocketbox, MIT)"},
                  "scene": 0, "scenes": [{"name": "SOLARA_Pedestrians", "nodes": []}], "nodes": [], "meshes": [],
                  "materials": [], "textures": [], "images": [], "samplers": [{"magFilter": 9729, "minFilter": 9987}],
                  "skins": [], "accessors": [], "bufferViews": [], "buffers": [{"byteLength": 0}]}
        self.bin = bytearray()

    def view(self, raw, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        bv = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(raw)}
        if target:
            bv["target"] = target
        self.bin += raw
        self.j["bufferViews"].append(bv)
        return len(self.j["bufferViews"]) - 1

    def acc(self, arr, comp, typ, target=34962, bounds=False):
        bv = self.view(arr.tobytes(), target)
        a = {"bufferView": bv, "componentType": comp, "count": len(arr), "type": typ}
        if bounds:
            a["min"] = [float(x) for x in arr.min(0)]
            a["max"] = [float(x) for x in arr.max(0)]
        self.j["accessors"].append(a)
        return len(self.j["accessors"]) - 1

    def node(self, n):
        self.j["nodes"].append(n)
        return len(self.j["nodes"]) - 1

    def add_ped(self, pid, ped):
        pre = "Ped_" + pid
        # bones
        idx = []
        for b in ped["bones"]:
            idx.append(self.node({"name": pre + "_" + b["name"]}))
        for i, b in enumerate(ped["bones"]):
            parent_world = ped["bones"][b["parent"]]["world"] if b["parent"] is not None else np.eye(4)
            local = np.linalg.inv(parent_world) @ b["world"]
            t, r, s = mat_to_trs(local)
            n = self.j["nodes"][idx[i]]
            n["translation"] = [float(x) for x in t]
            n["rotation"] = [float(x) for x in r]
            kids = [idx[k] for k, c in enumerate(ped["bones"]) if c["parent"] == i]
            if kids:
                n["children"] = kids
        roots = [idx[i] for i, b in enumerate(ped["bones"]) if b["parent"] is None]
        ibm = np.array([np.linalg.inv(b["world"]).T for b in ped["bones"]], "<f4")  # column-major
        a_ibm = self.acc(ibm.reshape(-1, 16), 5126, "MAT4", target=None)
        self.j["skins"].append({"name": pre, "joints": idx, "inverseBindMatrices": a_ibm, "skeleton": roots[0]})
        # texture
        buf = io.BytesIO()
        ped["atlas"].save(buf, "PNG", optimize=True)
        img_bv = self.view(buf.getvalue())
        self.j["images"].append({"name": pre + "_Texture", "mimeType": "image/png", "bufferView": img_bv})
        self.j["textures"].append({"sampler": 0, "source": len(self.j["images"]) - 1})
        self.j["materials"].append({"name": pre + "_Material", "alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True,
                                    "pbrMetallicRoughness": {"baseColorTexture": {"index": len(self.j["textures"]) - 1},
                                                             "metallicFactor": 0.0, "roughnessFactor": 0.85}})
        # mesh
        attrs = {
            "POSITION": self.acc(ped["P"].astype("<f4"), 5126, "VEC3", bounds=True),
            "NORMAL": self.acc(ped["N"].astype("<f4"), 5126, "VEC3"),
            "TEXCOORD_0": self.acc(ped["UV"].astype("<f4"), 5126, "VEC2"),
            "JOINTS_0": self.acc(ped["J"].astype("<u2"), 5123, "VEC4"),
            "WEIGHTS_0": self.acc(ped["W"].astype("<f4"), 5126, "VEC4"),
        }
        ind = self.acc(ped["F"].reshape(-1).astype("<u4"), 5125, "SCALAR", target=34963)
        self.j["meshes"].append({"name": pre + "_Body", "primitives": [{"attributes": attrs, "indices": ind,
                                                                         "material": len(self.j["materials"]) - 1}]})
        mesh_node = self.node({"name": pre + "_Body", "mesh": len(self.j["meshes"]) - 1, "skin": len(self.j["skins"]) - 1})
        top = self.node({"name": pre, "children": [mesh_node] + roots})
        self.j["scenes"][0]["nodes"].append(top)

    def write(self, path):
        while len(self.bin) % 4:
            self.bin.append(0)
        self.j["buffers"][0]["byteLength"] = len(self.bin)
        js = json.dumps(self.j, separators=(",", ":")).encode()
        js += b" " * ((4 - len(js) % 4) % 4)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(self.bin)))
            f.write(struct.pack("<I4s", len(js), b"JSON") + js)
            f.write(struct.pack("<I4s", len(self.bin), b"BIN\x00") + bytes(self.bin))


def posed(ped, pose):
    """linear blend skinning with per-bone local rotations (axis-angle in character space at rest) -> vertices"""
    bones = ped["bones"]
    rest = [b["world"] for b in bones]
    cur = [None] * len(bones)

    def depth(i):
        d = 0
        while bones[i]["parent"] is not None:
            i, d = bones[i]["parent"], d + 1
        return d

    for i in sorted(range(len(bones)), key=depth):  # parents first
        b = bones[i]
        R = np.eye(4)
        if b["name"] in pose:
            axis, ang = pose[b["name"]]
            axis = np.array(axis, float) / np.linalg.norm(axis)
            K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
            Rw = np.eye(3) + math.sin(ang) * K + (1 - math.cos(ang)) * K @ K
            Rr = rest[i][:3, :3]
            R[:3, :3] = Rr.T @ Rw @ Rr  # rotation about a character-space axis, in the bone's own frame
        local = (np.linalg.inv(rest[b["parent"]]) @ rest[i]) if b["parent"] is not None else rest[i]
        cur[i] = (cur[b["parent"]] if b["parent"] is not None else np.eye(4)) @ local @ R
    skin = np.array([cur[i] @ np.linalg.inv(rest[i]) for i in range(len(bones))])
    M = np.einsum("vk,vkij->vij", ped["W"], skin[ped["J"]])
    P = np.einsum("vij,vj->vi", M, np.c_[ped["P"], np.ones(len(ped["P"]))])[:, :3]
    return P


def render(ped, P, yaw, size=(260, 420)):
    tex = np.asarray(ped["atlas"]).astype(float)
    img = Image.new("RGB", size, (232, 235, 240))
    d = ImageDraw.Draw(img)
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    eye = np.array([-sy, 0.12, -cy]); eye /= np.linalg.norm(eye)
    f = -eye
    r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    T = P[ped["F"]]
    cam = np.stack([T @ r, T @ u, T @ f], -1)
    uv = ped["UV"][ped["F"]].mean(1)
    cols = tex[np.clip((uv[:, 1] * ATLAS).astype(int), 0, ATLAS - 1), np.clip((uv[:, 0] * ATLAS).astype(int), 0, ATLAS - 1)]
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    L = np.array([0.3, 0.8, -0.5]); L /= np.linalg.norm(L)
    shade = 0.55 + 0.45 * np.clip(np.abs(n @ L), 0, 1)
    lo, hi = cam.reshape(-1, 3).min(0), cam.reshape(-1, 3).max(0)
    s = 0.92 * min(size[0] / (hi[0] - lo[0]), size[1] / (hi[1] - lo[1]))
    o = (hi + lo) / 2
    for k in np.argsort(-cam[:, :, 2].mean(1)):
        if cols[k, 3] < 128:
            continue
        c = tuple(int(x) for x in np.clip(cols[k, :3] * shade[k], 0, 255))
        d.polygon([(size[0] / 2 + (p[0] - o[0]) * s, size[1] / 2 - (p[1] - o[1]) * s) for p in cam[k]], fill=c)
    return img


def main():
    src = sys.argv[1]
    os.makedirs(OUT_DIR, exist_ok=True)
    files = sorted((f for f in os.listdir(src) if f.startswith("Business_") and f.endswith(".glb")), key=lambda f: (len(f), f))
    seen, peds = {}, {}
    for f in files:
        h = hashlib.sha256(open(os.path.join(src, f), "rb").read()).hexdigest()
        if h in seen:
            print("skip duplicate", f, "=", seen[h])
            continue
        pid = ped_id(f)
        if pid in peds:
            print("skip", f, "(id", pid, "taken)")
            continue
        seen[h] = f
        peds[pid] = build_ped(load_ped(os.path.join(src, f)))
    w = Writer()
    data = []
    tiles = []
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    for pid, ped in sorted(peds.items()):
        w.add_ped(pid, ped)
        B = {b["name"]: b["world"][:3, 3] for b in ped["bones"]}
        height = float(ped["P"][:, 1].max())
        leg = float(np.linalg.norm(B["LThigh"] - B["LCalf"]) + np.linalg.norm(B["LCalf"] - B["LFoot"]))
        # checks: faces -Z (nose / head front at -Z), left side at -X, feet at 0
        head_front = ped["P"][ped["P"][:, 1] > height - 0.25]
        assert head_front[:, 2].min() < -0.05, pid + ": should face -Z"
        assert B["LThigh"][0] < 0 < B["RThigh"][0], pid + ": left at -X"
        assert abs(ped["P"][:, 1].min()) < 1e-6
        assert len(ped["F"]) <= 20000, pid + ": too many triangles for one MeshPart"
        data.append((pid, height, leg, float(B["Pelvis"][1]), len(ped["F"])))
        print("%s: %d tris, %d verts, height %.3f m, leg %.3f m, pelvis %.3f m, bones %d" % (
            pid, len(ped["F"]), len(ped["P"]), height, leg, B["Pelvis"][1], len(ped["bones"])))
        # preview: rest pose and a walking pose (arms lowered like the game does)
        rest = render(ped, ped["P"], 0)
        walk = posed(ped, {
            "LUpperArm": ((0, 0, 1), 0.66), "RUpperArm": ((0, 0, 1), -0.66),
            "LThigh": ((1, 0, 0), 0.45), "LCalf": ((1, 0, 0), -0.25),
            "RThigh": ((1, 0, 0), -0.35), "RCalf": ((1, 0, 0), -0.55),
        })
        tile = Image.new("RGB", (520, 440), (232, 235, 240))
        tile.paste(rest, (0, 20))
        tile.paste(render(ped, walk, 35), (260, 20))
        ImageDraw.Draw(tile).text((6, 3), "%s  %d üçgen, %.2f m  (dinlenme / yürüme pozu denemesi)" % (pid, len(ped["F"]), height),
                                  font=font, fill=(20, 20, 20))
        tiles.append(tile)
    w.write(OUT_GLB)
    lines = ["-- PedModelData: tools/peds_convert.py tarafından üretildi (elle değiştirme).",
             "-- Yaya modelleri (Microsoft Rocketbox, MIT): her biri tek deri (skinned) MeshPart + 20 kemik (Ped_<Id>_<Kemik>).",
             "-- Ölçüler metre, dinlenme pozunda (A-pozu kollar): boy, bacak boyu (uyluk + baldır), kalça yüksekliği.",
             "return {",
             "\tBones = { \"Pelvis\", \"Spine\", \"Spine1\", \"Spine2\", \"Neck\", \"Head\", \"LClavicle\", \"LUpperArm\", \"LForearm\",",
             "\t\t\"LHand\", \"RClavicle\", \"RUpperArm\", \"RForearm\", \"RHand\", \"LThigh\", \"LCalf\", \"LFoot\", \"RThigh\", \"RCalf\", \"RFoot\" },",
             "\tPeds = {"]
    for pid, height, leg, pelvis, tris in data:
        lines.append("\t\t{ Id = \"%s\", Female = %s, HeightM = %.3f, LegM = %.3f, PelvisM = %.3f, Triangles = %d }," % (
            pid, "true" if pid[0] == "F" else "false", height, leg, pelvis, tris))
    lines += ["\t},", "}", ""]
    open(OUT_LUA, "w", encoding="utf-8").write("\n".join(lines))
    cols = 2
    sheet = Image.new("RGB", (520 * cols, 440 * math.ceil(len(tiles) / cols)), (232, 235, 240))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * 520, (i // cols) * 440))
    sheet.save(OUT_PREVIEW)
    print("->", OUT_GLB, "(%.1f MB)" % (os.path.getsize(OUT_GLB) / 1e6), OUT_LUA, OUT_PREVIEW)


if __name__ == "__main__":
    main()
