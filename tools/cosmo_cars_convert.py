#!/usr/bin/env python3
"""
cosmo_cars_convert.py — turns the 12 low-poly car FBX files the user supplied (cosmo-art "Low Poly Cars",
itch.io; one palette texture "texture-palette.png") into ONE Roblox-ready file: assets/cars/SOLARA_Cars.glb.

The look stays exactly the source's: same triangles, same shading normals, and every face keeps the colour its
UV points at in the palette texture. Because the palette is a grid of flat colours, faces are grouped by colour into
solid-colour parts (no texture upload needed), and each part gets a ROLE the game understands:

  Paint          the body colour (traffic / player cars are repainted from the vehicle's colour list)
  Glass          windows (game: glass material, slightly see-through)
  Headlight, TailLight, ReverseLight, IndicatorL, IndicatorR
                 lamps: the game's light system switches them (night, brake, reverse, turn signals)
  SirenRed, SirenBlue   police light bar
  Detail         everything else (bumpers, grilles, plates, trim) in its own palette colour
  Wheel_<FL|FR|RL|RR>_<Tire|Rim>   wheel parts (they spin in the game)

Part names: <Car>_<Role>_<rrggbb>  (e.g. Chispa_Paint_fe642e, Chispa_Wheel_FL_Tire_2e2e2e). The colour is in the
name, so the game colours the parts itself (it does not depend on how the importer handles materials); the .glb
materials carry the same colours for Studio's preview.

Conventions (Roblox): +Y up, car front = -Z, right = +X, metres; each car's origin = centre of its four wheel
centres (at wheel-centre height). The game calibrates every model from its own wheels (CarModelKit), so scale and
axes after import do not matter.

Also writes assets/cars/cars.json (dimensions, parts, triangle counts) and docs/cars_preview.png (rendered back
from the written .glb: front and rear view of every car, lamps shown lit).

Usage: python3 -I tools/cosmo_cars_convert.py <folder with the .fbx files and texture-palette.png>
Only reads data (tools/fbx_reader.py); nothing in the files is executed.
"""
import json
import math
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fbx_reader  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "cars")
OUT_GLB = os.path.join(OUT_DIR, "SOLARA_Cars.glb")
OUT_JSON = os.path.join(OUT_DIR, "cars.json")
OUT_PREVIEW = os.path.join(ROOT, "docs", "cars_preview.png")
CM = 0.01  # FBX units (cm) -> metres

# source file -> game model name (invented names; no real makes); "Paint": body colour (palette hex) where the
# automatic choice (largest coloured area) is not the body; "Paint2": second body tone(s); "Sirens": police light bar
CARS = {
    "armor": {"Name": "Bastion"},
    "coupe": {"Name": "Solano", "Paint": "424242"},
    "fenyr": {"Name": "Vortex"},
    "ghini": {"Name": "Strada", "Paint": "585858"},
    "italia": {"Name": "Rossa"},
    "jeep": {"Name": "Cresta"},
    "kamaro": {"Name": "Brava", "Paint2": ["dba901"]},
    "lamb": {"Name": "Furia", "Paint2": ["b40404"]},
    "mobil": {"Name": "Marlin"},
    "police": {"Name": "Patrulla", "Sirens": True},
    "rally": {"Name": "Chispa", "Paint2": ["ff4000"]},
    "van": {"Name": "Mula"},
}


# ----------------------------------------------------------------------------------------------------------------
# FBX helpers
def rot(r):
    rx, ry, rz = [math.radians(a) for a in r]
    X = np.array([[1, 0, 0], [0, math.cos(rx), -math.sin(rx)], [0, math.sin(rx), math.cos(rx)]])
    Y = np.array([[math.cos(ry), 0, math.sin(ry)], [0, 1, 0], [-math.sin(ry), 0, math.cos(ry)]])
    Z = np.array([[math.cos(rz), -math.sin(rz), 0], [math.sin(rz), math.cos(rz), 0], [0, 0, 1]])
    return Z @ Y @ X


def local_matrix(m):
    M = np.eye(4)
    M[:3, :3] = rot(m["pre"]) @ rot(m["r"]) @ np.diag(m["s"])
    M[:3, 3] = m["t"]
    return M


def world_matrix(sc, mid):
    models, parents = sc["models"], sc["parents"]
    M = local_matrix(models[mid])
    p = parents.get(mid)
    while p in models:
        M = local_matrix(models[p]) @ M
        p = parents.get(p)
    return M


def layers(path):
    """geometry name -> {"uv": per-corner UV array, "normal": per-corner normal array} (ByPolygonVertex)"""
    _, root = fbx_reader.read(path)
    out = {}
    for n in root.find("Objects").children:
        if n.name != "Geometry":
            continue
        name = n.props[1].split("\x00")[0]
        idx = n.find("PolygonVertexIndex").props[0]
        cp = [i if i >= 0 else -i - 1 for i in idx]  # control point of each corner
        entry = {}
        for layer_name, data_name, index_name, width, key in (
                ("LayerElementUV", "UV", "UVIndex", 2, "uv"),
                ("LayerElementNormal", "Normals", "NormalsIndex", 3, "normal")):
            layer = n.find(layer_name)
            if layer is None:
                continue
            data = np.array(layer.find(data_name).props[0], float).reshape(-1, width)
            mapping = layer.find("MappingInformationType").props[0]
            reference = layer.find("ReferenceInformationType").props[0]
            index_node = layer.find(index_name)
            if mapping == "ByPolygonVertex":
                ids = np.array(index_node.props[0]) if (reference != "Direct" and index_node) else np.arange(len(cp))
            elif mapping in ("ByVertice", "ByVertex", "ByControlPoint"):
                base = np.array(index_node.props[0]) if (reference != "Direct" and index_node) else np.arange(len(data))
                ids = base[np.array(cp)]
            else:  # AllSame
                ids = np.zeros(len(cp), int)
            entry[key] = data[ids]
        out[name] = entry
    return out


# ----------------------------------------------------------------------------------------------------------------
# colours
def hexof(rgb):
    return "%02x%02x%02x" % tuple(int(c) for c in rgb)


def colour_class(rgb):
    r, g, b = [c / 255 for c in rgb]
    if min(r, g, b) > 0.85:
        return "white"
    if r > 0.6 and g < 0.35 and b < 0.35:
        return "red"
    if r > 0.8 and 0.3 <= g <= 0.75 and b < 0.3:
        return "amber"
    if r > 0.85 and g > 0.75 and b < 0.75:
        return "pale"
    return "other"


def saturation(rgb):
    mx, mn = max(rgb), min(rgb)
    return 0 if mx == 0 else (mx - mn) / mx


def srgb_to_linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# ----------------------------------------------------------------------------------------------------------------
def load_car(path, palette):
    """Returns (faces, wheel_of): faces = list of dict(tri: 3x3 positions, nor: 3x3 normals, mat, rgb, wheel)"""
    sc = fbx_reader.scene(path)
    assert sc["up_axis"] == 1, "expected Y-up FBX"
    lay = layers(path)
    H, W = palette.shape[:2]
    faces = []
    flip = np.diag([-1.0, 1.0, -1.0])  # 180 deg about Y: source front (+Z) -> Roblox front (-Z)
    for mid, m in sc["models"].items():
        g = m["geometry"]
        if not g:
            continue
        M = world_matrix(sc, mid)
        V = (np.c_[np.array(g["verts"], float), np.ones(len(g["verts"]))] @ M.T)[:, :3] * CM
        V = V @ flip.T
        normal_matrix = np.linalg.inv(M[:3, :3]).T
        L = lay[g["name"]]
        UV, NOR = L.get("uv"), L.get("normal")
        mats = m["materials"]
        is_wheel = m["name"].lower().startswith("wheel")
        corner = 0
        for pi, poly in enumerate(g["polys"]):
            mi = 0
            if g["mats"] is not None:
                mi = g["mats"][pi] if g["mapping"] == "ByPolygon" else g["mats"][0]
            ids = list(range(corner, corner + len(poly)))
            corner += len(poly)
            mat = mats[mi]["name"] if mi < len(mats) else "texture"
            # colour: palette at the polygon's mean UV; polygons whose UVs span several cells: most common corner colour
            uv = UV[ids]
            if np.ptp(uv, 0).max() > 0.1:
                samples = [tuple(palette[min(int((1 - v % 1) * H), H - 1), min(int(u % 1 * W), W - 1)]) for u, v in uv]
                rgb = max(set(samples), key=samples.count)
            else:
                u, v = uv.mean(0)
                rgb = tuple(palette[min(int((1 - v % 1) * H), H - 1), min(int(u % 1 * W), W - 1)])
            if NOR is not None:
                n = NOR[ids] @ normal_matrix.T
                n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
                n = n @ flip.T
            else:
                n = None
            P = V[poly]
            for k in range(1, len(poly) - 1):
                sel = [0, k, k + 1]
                faces.append({"tri": P[sel], "nor": None if n is None else n[sel], "mat": mat,
                              "rgb": tuple(int(c) for c in rgb), "wheel": m["name"] if is_wheel else None})
    return faces


def area(tri):
    return float(np.linalg.norm(np.cross(tri[1] - tri[0], tri[2] - tri[0])) / 2)


def assign_roles(car, faces, opts):
    """Returns parts: name -> {"role", "hex", "faces": [...]} and the wheel centres."""
    # wheels: each source wheel object -> FL/FR/RL/RR by its centre (front = -Z, left = -X)
    wheel_objs = {}
    for f in faces:
        if f["wheel"]:
            wheel_objs.setdefault(f["wheel"], []).append(f)
    assert len(wheel_objs) == 4, "%s: expected 4 wheel objects, got %s" % (car, list(wheel_objs))
    centres = {}
    for name, fs in wheel_objs.items():
        pts = np.vstack([f["tri"] for f in fs])
        c = (pts.min(0) + pts.max(0)) / 2
        key = ("F" if c[2] < 0 else "R") + ("L" if c[0] < 0 else "R")
        assert key not in centres, "%s: two wheels at %s" % (car, key)
        centres[key] = c
        tire_rgb = None
        by_colour = {}
        for f in fs:
            by_colour[f["rgb"]] = by_colour.get(f["rgb"], 0) + area(f["tri"])
        tire_rgb = max(by_colour, key=lambda c: by_colour[c] * (1.5 if sum(c) < 200 else 1))  # big + dark = tyre
        for f in fs:
            f["role"] = "Wheel_%s_%s" % (key, "Tire" if f["rgb"] == tire_rgb else "Rim")
            f["wheel_key"] = key
    body = [f for f in faces if not f["wheel"]]
    lo = np.min([f["tri"].min(0) for f in body], 0)
    hi = np.max([f["tri"].max(0) for f in body], 0)
    height = hi[1] - lo[1]

    # body colour (Paint): explicit, or the largest saturated colour group, or the largest colour group
    groups = {}
    for f in body:
        if f["mat"] in ("metallic", "texture"):
            groups[f["rgb"]] = groups.get(f["rgb"], 0) + area(f["tri"])
    if opts.get("Paint"):
        paint = tuple(int(opts["Paint"][i:i + 2], 16) for i in (0, 2, 4))
    else:
        coloured = {c: a for c, a in groups.items() if saturation(c) >= 0.35 and a >= 2.0}
        pool = coloured or groups
        paint = max(pool, key=pool.get)

    for f in body:
        c = f["tri"].mean(0)
        rgb, cls = f["rgb"], colour_class(f["rgb"])
        front = c[2] < 0
        if f["mat"] == "glass":
            f["role"] = "Glass" if sum(rgb) < 300 else "Detail"
        elif opts.get("Sirens") and f["mat"] == "texture" and c[1] > lo[1] + 0.85 * height and cls in ("red", "other") \
                and (cls == "red" or rgb[2] > 200):
            f["role"] = "SirenRed" if cls == "red" else "SirenBlue"
        elif f["mat"] == "light":
            side = "IndicatorL" if c[0] < 0 else "IndicatorR"
            if front:
                f["role"] = {"white": "Headlight", "pale": "Headlight", "amber": side}.get(cls, "Detail")
            else:
                f["role"] = {"red": "TailLight", "pale": "TailLight", "white": "ReverseLight", "amber": side}.get(cls, "Detail")
        elif f["mat"] in ("metallic", "texture") and rgb == paint:
            f["role"] = "Paint"
        elif f["mat"] in ("metallic", "texture") and hexof(rgb) in opts.get("Paint2", ()):
            f["role"] = "Paint2"  # second body tone (mirrors, trims): the game paints it a shade darker than Paint
        else:
            f["role"] = "Detail"
    parts = {}
    for f in faces:
        name = "%s_%s_%s" % (car, f["role"], hexof(f["rgb"]))
        p = parts.setdefault(name, {"role": f["role"], "hex": hexof(f["rgb"]), "faces": []})
        p["faces"].append(f)
    return parts, centres, hexof(paint)


# ----------------------------------------------------------------------------------------------------------------
# glTF writer
class GlbWriter:
    def __init__(self):
        self.bin, self.views, self.accessors, self.meshes, self.materials, self.nodes = [], [], [], [], [], []
        self.offset = 0

    def _add(self, raw, target):
        pad = (4 - len(raw) % 4) % 4
        self.bin.append(raw + b"\x00" * pad)
        self.views.append({"buffer": 0, "byteOffset": self.offset, "byteLength": len(raw), "target": target})
        self.offset += len(raw) + pad
        return len(self.views) - 1

    def mesh_node(self, name, faces, rgb, origin):
        pos, nor = [], []
        for f in faces:
            tri = f["tri"]
            gn = np.cross(tri[1] - tri[0], tri[2] - tri[0])
            gn = gn / max(np.linalg.norm(gn), 1e-12)
            ns = f["nor"] if f["nor"] is not None else np.array([gn, gn, gn])
            for k in range(3):
                pos.append(tri[k])
                nor.append(ns[k])
        pos, nor = np.array(pos), np.array(nor)
        # de-duplicate identical (position, normal) corners
        key = np.round(np.c_[pos, nor], 6)
        uniq, inverse = np.unique(key, axis=0, return_inverse=True)
        inverse = inverse.reshape(-1)
        upos, unor = uniq[:, :3], uniq[:, 3:]
        lo, hi = upos.min(0), upos.max(0)
        centre = (lo + hi) / 2
        local = (upos - centre).astype("<f4")
        unor = unor / np.maximum(np.linalg.norm(unor, axis=1, keepdims=True), 1e-9)
        a_pos = self._accessor(local, "VEC3", 5126, with_bounds=True)
        a_nor = self._accessor(unor.astype("<f4"), "VEC3", 5126)
        index_type = 5123 if len(upos) < 65536 else 5125
        idx = inverse.astype("<u2" if index_type == 5123 else "<u4")
        bv = self._add(idx.tobytes(), 34963)
        self.accessors.append({"bufferView": bv, "componentType": index_type, "count": len(idx), "type": "SCALAR"})
        a_idx = len(self.accessors) - 1
        self.materials.append({"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": [srgb_to_linear(c) for c in rgb] + [1.0], "metallicFactor": 0.0, "roughnessFactor": 0.8}})
        self.meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nor},
                                                          "indices": a_idx, "material": len(self.materials) - 1, "mode": 4}]})
        self.nodes.append({"name": name, "mesh": len(self.meshes) - 1, "translation": [float(x) for x in centre - origin]})
        return len(self.nodes) - 1

    def _accessor(self, arr, typ, comp, with_bounds=False):
        bv = self._add(arr.tobytes(), 34962)
        acc = {"bufferView": bv, "componentType": comp, "count": len(arr), "type": typ}
        if with_bounds:
            acc["min"] = [float(x) for x in arr.min(0)]
            acc["max"] = [float(x) for x in arr.max(0)]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def group(self, name, children):
        self.nodes.append({"name": name, "children": children})
        return len(self.nodes) - 1

    def write(self, path, roots, generator):
        gltf = {"asset": {"version": "2.0", "generator": generator}, "scene": 0,
                "scenes": [{"name": "SOLARA_Cars", "nodes": roots}], "nodes": self.nodes, "meshes": self.meshes,
                "materials": self.materials, "accessors": self.accessors, "bufferViews": self.views,
                "buffers": [{"byteLength": self.offset}]}
        js = json.dumps(gltf, separators=(",", ":")).encode()
        js += b" " * ((4 - len(js) % 4) % 4)
        binary = b"".join(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(binary)))
            f.write(struct.pack("<I4s", len(js), b"JSON") + js)
            f.write(struct.pack("<I4s", len(binary), b"BIN\x00") + binary)


def read_glb(path):
    """Reads our own .glb back: {car: [(part name, triangles (n,3,3) in car space, normals (n,3,3), rgb)]}"""
    data = open(path, "rb").read()
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2 and total == len(data)
    jlen = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + jlen])
    blen = struct.unpack_from("<I", data, 20 + jlen)[0]
    binary = data[28 + jlen:28 + jlen + blen]

    def acc(i, dtype, width):
        a = gltf["accessors"][i]
        bv = gltf["bufferViews"][a["bufferView"]]
        arr = np.frombuffer(binary, dtype, a["count"] * width, bv["byteOffset"])
        return arr.reshape(-1, width) if width > 1 else arr

    cars = {}
    for root in gltf["scenes"][0]["nodes"]:
        node = gltf["nodes"][root]
        parts = []
        for ci in node["children"]:
            child = gltf["nodes"][ci]
            prim = gltf["meshes"][child["mesh"]]["primitives"][0]
            P = acc(prim["attributes"]["POSITION"], "<f4", 3) + np.array(child["translation"])
            N = acc(prim["attributes"]["NORMAL"], "<f4", 3)
            ia = gltf["accessors"][prim["indices"]]
            I = acc(prim["indices"], "<u2" if ia["componentType"] == 5123 else "<u4", 1).reshape(-1, 3)
            lin = gltf["materials"][prim["material"]]["pbrMetallicRoughness"]["baseColorFactor"][:3]
            rgb = [round(255 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055)) for c in lin]
            parts.append((child["name"], P[I], N[I], rgb))
        cars[node["name"]] = parts
    return cars


# ----------------------------------------------------------------------------------------------------------------
# preview (software renderer, painter's algorithm, smooth normals for shading)
LIT = {"Headlight": (255, 246, 200), "TailLight": (255, 40, 40), "ReverseLight": (240, 240, 255),
       "IndicatorL": (255, 170, 40), "IndicatorR": (255, 170, 40), "SirenRed": (255, 30, 30), "SirenBlue": (40, 80, 255)}


def render(parts, size=(440, 280), yaw=35.0, pitch=20.0, lit=True, paint=None, scale=None):
    img = Image.new("RGB", size, (232, 235, 240))
    draw = ImageDraw.Draw(img)
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    eye = np.array([-sy * cp, sp, -cy * cp])  # camera direction from the car (yaw 0 = straight in front)
    fwd = -eye
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    light = np.array([0.35, 0.85, -0.4]); light /= np.linalg.norm(light)
    items = []
    for name, T, N, rgb in parts:
        role = name.split("_")[1]
        col = np.array(rgb, float)
        if paint is not None and role == "Paint":
            col = np.array(paint, float)
        glow = lit and role in LIT
        if glow:
            col = np.array(LIT[role], float)
        cam = np.stack([T @ right, T @ up, T @ fwd], -1)
        gn = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        gn /= np.maximum(np.linalg.norm(gn, axis=1, keepdims=True), 1e-12)
        vis = gn @ fwd < 0.02
        nn = N.mean(1)
        nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-12)
        shade = 0.45 + 0.55 * np.clip(nn @ light, 0, 1) + 0.12 * np.clip(-(nn @ fwd), 0, 1)
        for k in np.nonzero(vis)[0]:
            c = col if glow else np.clip(col * shade[k], 0, 255)
            items.append((cam[k, :, 2].mean(), cam[k], tuple(int(x) for x in c)))
    allp = np.vstack([it[1] for it in items])
    lo, hi = allp.min(0), allp.max(0)
    s = scale or 0.88 * min(size[0] / (hi[0] - lo[0]), size[1] / (hi[1] - lo[1]))
    ox, oy = (hi[0] + lo[0]) / 2, (hi[1] + lo[1]) / 2
    for _, cam, c in sorted(items, key=lambda t: -t[0]):
        draw.polygon([(size[0] / 2 + (p[0] - ox) * s, size[1] / 2 - (p[1] - oy) * s + 10) for p in cam], fill=c)
    return img


# ----------------------------------------------------------------------------------------------------------------
def main():
    src = sys.argv[1]
    palette = np.asarray(Image.open(os.path.join(src, "texture-palette.png")).convert("RGB"))
    os.makedirs(OUT_DIR, exist_ok=True)
    w = GlbWriter()
    roots, summary = [], {}
    for stem, opts in CARS.items():
        car = opts["Name"]
        faces = load_car(os.path.join(src, stem + ".fbx"), palette)
        parts, centres, paint_hex = assign_roles(car, faces, opts)
        origin = sum(centres.values()) / 4
        children = []
        for name in sorted(parts):
            p = parts[name]
            rgb = tuple(int(p["hex"][i:i + 2], 16) for i in (0, 2, 4))
            children.append(w.mesh_node(name, p["faces"], rgb, origin))
        roots.append(w.group(car, children))
        # winding check: geometric normals must agree with the shading normals
        agree = np.mean([np.dot(np.cross(f["tri"][1] - f["tri"][0], f["tri"][2] - f["tri"][0]), f["nor"].sum(0)) > 0
                         for f in faces if f["nor"] is not None and area(f["tri"]) > 1e-8])
        assert agree > 0.95, "%s: face winding disagrees with normals (%.2f)" % (car, agree)
        pts = np.vstack([f["tri"] for f in faces]) - origin
        lo, hi = pts.min(0), pts.max(0)
        fl, fr, rl, rr = centres["FL"], centres["FR"], centres["RL"], centres["RR"]
        tire = np.vstack([f["tri"] for f in faces if f.get("wheel_key") == "FL"])
        roles = {}
        for p in parts.values():
            roles[p["role"]] = roles.get(p["role"], 0) + len(p["faces"])
        summary[car] = {
            "Source": stem + ".fbx", "Triangles": len(faces), "Parts": len(parts), "PaintHex": paint_hex,
            "LengthM": round(float(hi[2] - lo[2]), 3), "WidthM": round(float(hi[0] - lo[0]), 3),
            "HeightM": round(float(hi[1] - lo[1]), 3),
            "WheelbaseM": round(float((rl[2] + rr[2]) / 2 - (fl[2] + fr[2]) / 2), 3),
            "TrackM": round(float((fr[0] + rr[0]) / 2 - (fl[0] + rl[0]) / 2), 3),
            "WheelRadiusM": round(float((tire[:, 1].max() - tire[:, 1].min()) / 2), 3),
            "RoleTriangles": dict(sorted(roles.items())),
            "PartNames": sorted(parts),
        }
        print("%-9s %-8s %5d tris %3d parts  paint %s  L %.2f W %.2f H %.2f  wb %.2f  r %.3f  roles %s" % (
            car, stem, len(faces), len(parts), paint_hex, summary[car]["LengthM"], summary[car]["WidthM"],
            summary[car]["HeightM"], summary[car]["WheelbaseM"], summary[car]["WheelRadiusM"],
            {k: v for k, v in roles.items() if not k.startswith("Wheel")}))
    w.write(OUT_GLB, roots, "SOLARA cosmo_cars_convert.py")
    json.dump(summary, open(OUT_JSON, "w"), indent=1)

    # read back + checks + preview
    back = read_glb(OUT_GLB)
    assert sorted(back) == sorted(summary)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    tiles = []
    for car, parts in back.items():
        tris = sum(len(T) for _, T, _, _ in parts)
        assert tris == summary[car]["Triangles"], car
        wc = {}
        for name, T, _, _ in parts:
            bits = name.split("_")
            if bits[1] == "Wheel":
                wc.setdefault(bits[2], []).append(T.reshape(-1, 3))
        c = {k: (np.vstack(v).min(0) + np.vstack(v).max(0)) / 2 for k, v in wc.items()}
        assert c["FL"][2] < c["RL"][2] and c["FL"][0] < c["FR"][0], car + ": wheel layout"
        assert abs(sum(c.values())[0] / 4) < 0.05 and abs(sum(c.values())[2] / 4) < 0.05, car + ": origin"
        front = render(parts, yaw=35)
        rear = render(parts, yaw=215)
        tile = Image.new("RGB", (880, 300), (232, 235, 240))
        tile.paste(front, (0, 20))
        tile.paste(rear, (440, 20))
        d = ImageDraw.Draw(tile)
        info = summary[car]
        d.text((8, 4), "%s  (%s)  %d üçgen, %d parça, %.1f m" % (car, info["Source"], tris, info["Parts"], info["LengthM"]),
               font=font, fill=(20, 20, 20))
        tiles.append(tile)
    cols = 2
    sheet = Image.new("RGB", (880 * cols, 300 * math.ceil(len(tiles) / cols)), (232, 235, 240))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * 880, (i // cols) * 300))
    sheet.save(OUT_PREVIEW)
    print("->", OUT_GLB, "(%d KB)" % (os.path.getsize(OUT_GLB) // 1024), OUT_JSON, OUT_PREVIEW)


if __name__ == "__main__":
    main()
