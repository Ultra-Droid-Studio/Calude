#!/usr/bin/env python3
"""streetlights_convert.py — "Various Low-Poly Street Lights" by KMB3D (Sketchfab, CC-BY-4.0) -> Roblox-ready .glb.

Source: https://sketchfab.com/3d-models/various-low-poly-street-lights-1173b0c4d9b0400bbeaafbee0e94ca59
License: CC-BY-4.0 — credit "KMB3D" (in-game credits + docs/CREDITS.md). Changes: split into separate lamps,
re-centred, rotated so the arm points to the road (-Z), unused material extensions dropped.

The source holds 8 lamps, each = a "metal" mesh (pole) + a "light" mesh (lamp glass). For every lamp this writes
two nodes into assets/streetlights/StreetLights.glb, named StreetLight_<Key>_Pole and StreetLight_<Key>_Lamp
(-> two MeshParts after Studio's Import 3D; the game finds them by name, the hierarchy does not matter).
Conventions (Roblox): +Y up, metres, pole base centre = lamp origin, arm/lantern towards -Z (the road side of a
sidewalk lamp in PropBuilder). In the file the lamps stand in a row 3 m apart along X (so the import does not
overlap); the game re-places every lamp from the measured sizes in StreetLightData.lua (also written here).
Also writes assets/streetlights/preview.png (silhouettes from the written file: front and side views).

Usage: python3 -I tools/streetlights_convert.py <various_low-poly_street_lights.glb>
Only the glTF JSON and binary buffers are read; nothing in the file is executed.
"""
import json
import math
import os
import struct
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "streetlights")
OUT_GLB = os.path.join(OUT_DIR, "StreetLights.glb")
OUT_LUA = os.path.join(ROOT, "src", "ServerScriptService", "WorldGen", "StreetLightData.lua")
SPACING = 3.0

# source mesh prefix -> (key, kind, rotation about Y in degrees so the arm points to -Z)
#   Arm: single arm over the road; Double: two arms (road + sidewalk); Twin: two lamps on a crossbar (parallel to
#   the kerb); Post: lantern / globe on top of the post
LAMPS = {
    "polySurface102": ("Arm", "Arm", 180),     # arm along +Z in the source
    "polySurface60": ("Lantern", "Arm", -90),  # hanging lantern on an arm along -X
    "polySurface109": ("Double", "Double", 0),
    "polySurface77": ("TwinBar", "Twin", 0),
    "polySurface69": ("Twin", "Twin", 0),
    "polySurface88": ("Crook", "Twin", 0),
    "polySurface59": ("Globe", "Post", 0),
    "polySurface68": ("Classic", "Post", 0),
}


def read_glb(path):
    data = open(path, "rb").read()
    magic, _ver, _len = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise SystemExit("not a glb")
    clen, _ = struct.unpack("<II", data[12:20])
    js = json.loads(data[20:20 + clen])
    off = 20 + clen
    blen, _ = struct.unpack("<II", data[off:off + 8])
    return js, data[off + 8:off + 8 + blen]


def accessor(js, binary, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    comp = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    size = np.dtype(comp).itemsize
    if stride and stride != n * size:
        raw = np.frombuffer(binary[start:start + stride * a["count"]], dtype=np.uint8).reshape(a["count"], stride)
        return raw[:, :n * size].copy().view(comp).reshape(a["count"], n)
    return np.frombuffer(binary, dtype=comp, count=a["count"] * n, offset=start).reshape(a["count"], n)


def node_matrix(n):
    if "matrix" in n:
        return np.array(n["matrix"], dtype=float).reshape(4, 4).T
    t = n.get("translation", [0, 0, 0])
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    s = n.get("scale", [1, 1, 1])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M = np.eye(4)
    M[:3, :3] = R * np.array(s)
    M[:3, 3] = t
    return M


def collect(js, binary):
    meshes = {}  # source node prefix -> {"metal"|"light": (pos, nrm, idx)}

    def walk(ni, parent):
        n = js["nodes"][ni]
        M = parent @ node_matrix(n)
        if "mesh" in n:
            name = n.get("name", "")
            prefix = name.split("_")[0]
            role = "light" if "_light" in name else "metal"
            P, N, I = [], [], []
            base = 0
            for prim in js["meshes"][n["mesh"]]["primitives"]:
                pos = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
                nrm = accessor(js, binary, prim["attributes"]["NORMAL"]).astype(float) if "NORMAL" in prim["attributes"] else None
                idx = accessor(js, binary, prim["indices"]).astype(np.int64).reshape(-1) if "indices" in prim else np.arange(len(pos))
                P.append((np.c_[pos, np.ones(len(pos))] @ M.T)[:, :3])
                if nrm is not None:
                    nn = nrm @ np.linalg.inv(M[:3, :3]).T
                    nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-12
                    N.append(nn)
                I.append(idx + base)
                base += len(pos)
            meshes.setdefault(prefix, {})[role] = (np.vstack(P), np.vstack(N) if N else None, np.concatenate(I))
        for c in n.get("children", []):
            walk(c, M)

    for r in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(r, np.eye(4))
    return meshes


def rot_y(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def flat_normals(P, I):
    tri = I.reshape(-1, 3)
    N = np.zeros_like(P)
    fn = np.cross(P[tri[:, 1]] - P[tri[:, 0]], P[tri[:, 2]] - P[tri[:, 0]])
    for k in range(3):
        np.add.at(N, tri[:, k], fn)
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
    return N


def main():
    src = sys.argv[1]
    js, binary = read_glb(src)
    extras = js.get("asset", {}).get("extras", {})
    if "CC-BY-4.0" not in str(extras.get("license", "")):
        raise SystemExit("unexpected license: " + str(extras.get("license")))
    meshes = collect(js, binary)
    os.makedirs(OUT_DIR, exist_ok=True)

    out_nodes, out_meshes, out_acc, out_views = [], [], [], []
    blob = bytearray()
    lamps = []

    def add_view(arr, target):
        nonlocal blob
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        b = arr.tobytes()
        blob.extend(b)
        out_views.append({"buffer": 0, "byteOffset": off, "byteLength": len(b), "target": target})
        return len(out_views) - 1

    def add_mesh(name, P, N, I, material, offset_x):
        P2 = P + np.array([offset_x, 0, 0])
        pv = add_view(P2.astype(np.float32), 34962)
        out_acc.append({"bufferView": pv, "componentType": 5126, "count": len(P2), "type": "VEC3",
                        "min": P2.min(0).tolist(), "max": P2.max(0).tolist()})
        pa = len(out_acc) - 1
        nv = add_view(N.astype(np.float32), 34962)
        out_acc.append({"bufferView": nv, "componentType": 5126, "count": len(N), "type": "VEC3"})
        na = len(out_acc) - 1
        iv = add_view(I.astype(np.uint32), 34963)
        out_acc.append({"bufferView": iv, "componentType": 5125, "count": len(I), "type": "SCALAR"})
        ia = len(out_acc) - 1
        out_meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": pa, "NORMAL": na},
                                                          "indices": ia, "material": material}]})
        out_nodes.append({"name": name, "mesh": len(out_meshes) - 1})
        return len(out_nodes) - 1

    order = sorted(LAMPS, key=lambda k: LAMPS[k][0])
    for i, prefix in enumerate(order):
        key, kind, rot = LAMPS[prefix]
        metal = meshes[prefix]["metal"]
        light = meshes[prefix]["light"]
        P = metal[0]
        low = P[P[:, 1] < 0.25]
        axis = np.array([(low[:, 0].min() + low[:, 0].max()) / 2, P[:, 1].min(), (low[:, 2].min() + low[:, 2].max()) / 2])
        R = rot_y(rot)
        parts = {}
        for role, (pos, nrm, idx) in (("Pole", metal), ("Lamp", light)):
            p = (pos - axis) @ R.T
            n = (nrm @ R.T) if nrm is not None else flat_normals(p, idx)
            parts[role] = (p, n, idx)
        offset_x = i * SPACING
        nodes = []
        for role, mat in (("Pole", 0), ("Lamp", 1)):
            p, n, idx = parts[role]
            nodes.append(add_mesh(f"StreetLight_{key}_{role}", p, n, idx, mat, offset_x))
        pole_p, lamp_p = parts["Pole"][0], parts["Lamp"][0]
        lamps.append(dict(Key=key, Kind=kind, Prefix=prefix, Offset=offset_x,
                          PoleMin=pole_p.min(0).tolist(), PoleMax=pole_p.max(0).tolist(),
                          LampMin=lamp_p.min(0).tolist(), LampMax=lamp_p.max(0).tolist(),
                          Triangles=int((len(parts["Pole"][2]) + len(parts["Lamp"][2])) // 3)))

    gltf = {
        "asset": {"version": "2.0", "generator": "SOLARA streetlights_convert.py",
                  "copyright": "KMB3D, CC-BY-4.0 (modified: split, re-centred, rotated)",
                  "extras": {"author": extras.get("author"), "license": extras.get("license"), "source": extras.get("source"),
                             "title": extras.get("title")}},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(out_nodes)))}],
        "nodes": out_nodes,
        "meshes": out_meshes,
        "materials": [
            {"name": "Metal", "pbrMetallicRoughness": {"baseColorFactor": [0.16, 0.17, 0.18, 1], "metallicFactor": 0.6,
                                                      "roughnessFactor": 0.45}},
            {"name": "LampGlass", "pbrMetallicRoughness": {"baseColorFactor": [0.85, 0.82, 0.74, 1], "metallicFactor": 0.0,
                                                          "roughnessFactor": 0.3}},
        ],
        "accessors": out_acc,
        "bufferViews": out_views,
        "buffers": [{"byteLength": len(blob)}],
    }
    jb = json.dumps(gltf, separators=(",", ":")).encode()
    while len(jb) % 4:
        jb += b" "
    while len(blob) % 4:
        blob.append(0)
    total = 12 + 8 + len(jb) + 8 + len(blob)
    with open(OUT_GLB, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A))
        f.write(jb)
        f.write(struct.pack("<II", len(blob), 0x004E4942))
        f.write(blob)

    def v(t):
        return "{ %.4f, %.4f, %.4f }" % tuple(t)

    lines = [
        "-- StreetLightData: ÜRETİLDİ — tools/streetlights_convert.py. Elle değiştirme; aracı yeniden çalıştır.",
        "-- Kaynak: \"Various Low-Poly Street Lights\" — KMB3D, CC-BY-4.0 (" + str(extras.get("source")) + ")",
        "-- Değişiklik: lambalara ayrıldı, ortalandı, kol yola (−Z) bakacak şekilde döndürüldü.",
        "-- Birim: metre; köken = direğin taban merkezi. PoleMin/Max, LampMin/Max: MeshPart sınır kutuları (köken göreli).",
        "-- Offset: .glb dosyasında lambanın X kaydırması (içe aktarmada üst üste binmesinler diye).",
        "return {",
    ]
    for L in lamps:
        lines.append(f"\t{L['Key']} = {{ Kind = \"{L['Kind']}\", Offset = {L['Offset']:.1f}, Triangles = {L['Triangles']},")
        lines.append(f"\t\tPoleMin = {v(L['PoleMin'])}, PoleMax = {v(L['PoleMax'])},")
        lines.append(f"\t\tLampMin = {v(L['LampMin'])}, LampMax = {v(L['LampMax'])} }},")
    lines.append("}")
    open(OUT_LUA, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("wrote", OUT_GLB, f"{os.path.getsize(OUT_GLB) / 1e3:.0f} kB", "and", OUT_LUA)
    for L in lamps:
        print(f"  {L['Key']:8s} {L['Kind']:6s} height {L['PoleMax'][1]:.2f} m, arm/lamp z {L['LampMin'][2]:+.2f}..{L['LampMax'][2]:+.2f}, "
              f"{L['Triangles']} triangles")
    preview(OUT_GLB, lamps)


def preview(path, lamps):
    """Silhouettes read back from the written .glb: front (X-Y) and side (Z-Y, road = left)."""
    from PIL import Image, ImageDraw, ImageFont
    js, binary = read_glb(path)
    scale = 70  # px per metre
    W = len(lamps) * 2 * 3.2 * scale
    img = Image.new("RGB", (int(W), int(6.6 * scale + 60)), (236, 240, 244))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    byname = {n["name"]: n for n in js["nodes"]}
    ground = 6.1 * scale + 30
    for i, L in enumerate(lamps):
        for view in (0, 1):
            cx = (i * 2 + view) * 3.2 * scale + 1.6 * scale
            d.line([(cx - 1.4 * scale, ground), (cx + 1.4 * scale, ground)], fill=(150, 150, 150), width=2)
            for role, col in (("Pole", (40, 42, 46)), ("Lamp", (240, 180, 60))):
                n = byname[f"StreetLight_{L['Key']}_{role}"]
                prim = js["meshes"][n["mesh"]]["primitives"][0]
                P = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
                I = accessor(js, binary, prim["indices"]).reshape(-1, 3)
                P = P - np.array([L["Offset"], 0, 0])
                hx = P[:, 0] if view == 0 else P[:, 2]
                for t in I:
                    pts = [(cx + hx[k] * scale, ground - P[k, 1] * scale) for k in t]
                    d.polygon(pts, fill=col)
            d.text((cx, 12), f"{L['Key']} ({'ön' if view == 0 else 'yan, yol solda'})", font=font, fill=(20, 20, 20), anchor="mt")
    out = os.path.join(OUT_DIR, "preview.png")
    img.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
