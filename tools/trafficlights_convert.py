#!/usr/bin/env python3
"""
trafficlights_convert.py — the user's Kenney traffic lights (city-builder-bits trafficlight_A / _B / _C, CC0) into ONE
Roblox-ready file: assets/trafficlights/SOLARA_TrafficLights.glb, plus the measurements the game needs
(src/ReplicatedStorage/Shared/TrafficLightData.lua) and a preview (docs/trafficlights_preview.png).

The source files are meshopt-compressed and use a WebP gradient atlas (tools/gltf_decode.py reads them). Every
triangle keeps its geometry and shading normals; its colour comes from the atlas swatch its UVs point at (averaged
per swatch: the swatches are soft vertical gradients). Parts per type (names TL_<Type>_<Role>_<rrggbb>):
  Pole, Housing, Detail (signs, pedestrian box, brackets)
  Red, Yellow, Green   the lenses that face the approaching traffic: the game lights them from the signal state
  Lamp                 type B's street lamp glass (glows at night)
Lenses on the other faces of a two-way head stay unlit (Detail, darkened).

Conventions (Roblox): +Y up; the lit lenses face -Z (= the model's LookVector: CFrame.lookAt(base, base + look) turns
them to the traffic); mast arm / heads reach toward +X (over the road when the pole stands on the right kerb);
origin = centre of the pole's foot. Units: the source's (≈ 1 unit = one city tile); the game scales them
(TrafficLightData.StudsPerUnit).

Usage: python3 -I tools/trafficlights_convert.py <folder with the city-builder-bits-trafficlight_*.glb files>
Needs numpy, Pillow (WebP) and the meshoptimizer Python package. Only data is read.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_decode  # noqa: E402
from cosmo_cars_convert import GlbWriter  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "trafficlights")
OUT_GLB = os.path.join(OUT_DIR, "SOLARA_TrafficLights.glb")
OUT_LUA = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "TrafficLightData.lua")
OUT_PREVIEW = os.path.join(ROOT, "docs", "trafficlights_preview.png")
TYPES = {"A": "city-builder-bits-trafficlight_A.glb", "B": "city-builder-bits-trafficlight_B.glb",
         "C": "city-builder-bits-trafficlight_C.glb"}
STUDS_PER_UNIT = 16.0  # A: 0.73 units -> 11.7 studs (the old procedural light was 12); C's arm reaches 12 studs
# atlas swatch (column, row of the 8 x 4 grid) -> role
CELL_ROLE = {(2, 0): "Pole", (3, 1): "Housing", (4, 1): "Red", (2, 3): "Yellow", (2, 2): "Green"}
LENSES = ("Red", "Yellow", "Green")
LIT = {"Red": (255, 50, 40), "Yellow": (255, 190, 40), "Green": (60, 230, 110), "Lamp": (255, 226, 160)}


def load(path):
    g = gltf_decode.load(path)
    tex = np.asarray(g.texture_image(0))[:, :, :3].astype(float)
    H, W = tex.shape[:2]
    faces = []
    flip = np.diag([-1.0, 1.0, -1.0])  # 180 deg about Y: lenses +Z -> -Z, arm -X -> +X
    for _, mi, M in g.mesh_nodes():
        for prim in g.json["meshes"][mi]["primitives"]:
            p = g.primitive(prim)
            V = (np.c_[p["POSITION"], np.ones(len(p["POSITION"]))] @ M.T)[:, :3] @ flip.T
            nm = np.linalg.inv(M[:3, :3]).T
            N = p["NORMAL"] @ nm.T
            N = (N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)) @ flip.T
            UV = p["TEXCOORD_0"]
            for t in p["indices"]:
                uv = UV[t].mean(0)
                cell = (int(uv[0] % 1 * 8), int(uv[1] % 1 * 4))
                rgb = tex[min(int(uv[1] % 1 * H), H - 1), min(int(uv[0] % 1 * W), W - 1)]
                faces.append({"tri": V[t], "nor": N[t], "cell": cell, "rgb": rgb})
    return faces


def assign(kind, faces):
    def normal(f):
        n = np.cross(f["tri"][1] - f["tri"][0], f["tri"][2] - f["tri"][0])
        return n / max(np.linalg.norm(n), 1e-12)

    pole = [f for f in faces if f["cell"] == (2, 0)]
    foot = np.vstack([f["tri"] for f in pole])
    foot = foot[foot[:, 1] < foot[:, 1].min() + 0.02]
    origin = np.array([(foot[:, 0].min() + foot[:, 0].max()) / 2, foot[:, 1].min(), (foot[:, 2].min() + foot[:, 2].max()) / 2])
    for f in faces:
        f["tri"] = f["tri"] - origin
        role = CELL_ROLE.get(f["cell"], "Detail")
        if role in LENSES and normal(f)[2] > -0.7:
            role = "Side"  # lens on another face of the head (or a green street sign): unlit
        f["role"] = role
    # the lit lenses are the discs of ONE head face: in the column of the red lens that faces the traffic most
    # (two-way heads also have lens rims on their other face that happen to point to -Z)
    red_front = [f for f in faces if f["role"] == "Red"]
    cx = np.median([f["tri"].mean(0)[0] for f in red_front])
    cz = min(f["tri"].mean(0)[2] for f in red_front)
    for f in faces:
        if f["role"] in LENSES:
            c = f["tri"].mean(0)
            if abs(c[0] - cx) > 0.04 or c[2] > cz + 0.03:
                f["role"] = "Side"
    # green that is not in the column of the red lenses is the street-name sign
    red = np.vstack([f["tri"] for f in faces if f["role"] == "Red"])
    lo, hi = red.min(0) - 0.03, red.max(0) + 0.03
    for f in faces:
        if f["role"] in ("Green", "Yellow"):
            c = f["tri"].mean(0)
            if not (lo[0] <= c[0] <= hi[0] and lo[2] <= c[2] <= hi[2] and c[1] < hi[1]):
                f["role"] = "Detail"
        elif f["role"] == "Side" and f["cell"] == (2, 2):
            c = f["tri"].mean(0)
            if not (lo[0] - 0.1 <= c[0] <= hi[0] + 0.1):
                f["role"] = "Detail"  # sign
    if kind == "B":  # the street lamp's glass: housing-coloured faces at the top, under the lamp head
        top = max(f["tri"][:, 1].max() for f in faces)
        for f in faces:
            if f["role"] == "Housing" and f["tri"].mean(0)[1] > top - 0.08:
                f["role"] = "Lamp"
    parts = {}
    for f in faces:
        role = f["role"]
        if role == "Side":
            role = "Detail"
            key = (role, f["cell"], "dim")
        else:
            key = (role, f["cell"], "")
        parts.setdefault(key, []).append(f)
    out = {}
    for (role, cell, dim), fs in parts.items():
        rgb = np.mean([f["rgb"] for f in fs], 0)
        if dim or role in LENSES:
            rgb = rgb * 0.5  # unlit lens
        hexv = "%02x%02x%02x" % tuple(int(round(c)) for c in np.clip(rgb, 0, 255))
        name = "TL_%s_%s_%s" % (kind, role, hexv)
        if name in out:
            out[name]["faces"] += fs
        else:
            out[name] = {"role": role, "rgb": tuple(int(c) for c in hexv_to_rgb(hexv)), "faces": fs}
    return out


def hexv_to_rgb(h):
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def render(parts, state, size=(300, 380), yaw=-25.0, pitch=8.0):
    img = Image.new("RGB", size, (232, 235, 240))
    draw = ImageDraw.Draw(img)
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    eye = np.array([-sy * cp, sp, -cy * cp])
    fwd = -eye
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    light = np.array([0.35, 0.85, -0.4]); light /= np.linalg.norm(light)
    items = []
    for name, p in parts.items():
        role = p["role"]
        lit = role == state or (role == "Lamp" and state == "night")
        col = np.array(LIT[role] if lit else p["rgb"], float)
        for f in p["faces"]:
            T = f["tri"]
            gn = np.cross(T[1] - T[0], T[2] - T[0])
            if np.linalg.norm(gn) < 1e-12:
                continue
            gn /= np.linalg.norm(gn)
            if gn @ fwd > 0.02:
                continue
            nn = f["nor"].mean(0); nn /= max(np.linalg.norm(nn), 1e-9)
            c = col if lit else col * (0.5 + 0.5 * max(0.0, nn @ light))
            cam = np.stack([T @ right, T @ up, T @ fwd], -1)
            items.append((cam[:, 2].mean(), cam, tuple(int(x) for x in np.clip(c, 0, 255))))
    allp = np.vstack([it[1] for it in items])
    lo, hi = allp.min(0), allp.max(0)
    s = 0.9 * min(size[0] / (hi[0] - lo[0]), size[1] / (hi[1] - lo[1]))
    o = (hi + lo) / 2
    for _, cam, c in sorted(items, key=lambda t: -t[0]):
        draw.polygon([(size[0] / 2 + (q[0] - o[0]) * s, size[1] / 2 - (q[1] - o[1]) * s) for q in cam], fill=c)
    return img


def main():
    src = sys.argv[1]
    os.makedirs(OUT_DIR, exist_ok=True)
    w = GlbWriter()
    roots, data, all_parts = [], {}, {}
    for kind, fname in TYPES.items():
        faces = load(os.path.join(src, fname))
        parts = assign(kind, faces)
        all_parts[kind] = parts
        children = [w.mesh_node(name, p["faces"], p["rgb"], np.zeros(3)) for name, p in sorted(parts.items())]
        roots.append(w.group("TrafficLight_" + kind, children))
        pts = np.vstack([f["tri"] for p in parts.values() for f in p["faces"]])
        pole = np.vstack([f["tri"] for p in parts.values() if p["role"] == "Pole" for f in p["faces"]])
        lens = {r: np.vstack([f["tri"] for p in parts.values() if p["role"] == r for f in p["faces"]]) for r in LENSES}
        centre = {}  # bounding-box centre of the Pole / Red / Green PARTS (calibration points for the game)
        for role in ("Pole", "Red", "Green"):
            pp = np.vstack([f["tri"] for p in parts.values() if p["role"] == role for f in p["faces"]])
            centre[role] = (pp.min(0) + pp.max(0)) / 2
        data[kind] = {"Min": pts.min(0), "Max": pts.max(0), "PoleMin": pole.min(0), "PoleMax": pole.max(0),
                      "Lens": {r: v.mean(0) for r, v in lens.items()}, "Centre": centre}
        roles = {}
        for p in parts.values():
            roles[p["role"]] = roles.get(p["role"], 0) + len(p["faces"])
        print("%s: %d tris, %d parts, height %.3f units (%.1f studs), reach +X %.3f, roles %s" % (
            kind, len(faces), len(parts), pts[:, 1].max(), pts[:, 1].max() * STUDS_PER_UNIT, pts[:, 0].max(), roles))
        for r in LENSES:  # lit lenses face -Z and stack red over yellow over green
            assert data[kind]["Lens"][r][2] < 0.2, kind + " lens position"
        L = data[kind]["Lens"]
        assert L["Red"][1] > L["Yellow"][1] > L["Green"][1], kind + ": lens order"
    w.write(OUT_GLB, roots, "SOLARA trafficlights_convert.py (Kenney City Builder Bits, CC0)")

    def v3(v):
        return "{ %.4f, %.4f, %.4f }" % tuple(v)

    lines = [
        "-- TrafficLightData: tools/trafficlights_convert.py tarafından üretildi (elle değiştirme).",
        "-- Trafik ışığı modellerinin (Kenney City Builder Bits, CC0) ölçüleri, kaynak biriminde: direğin ayağı = (0, 0, 0),",
        "-- yanan camlar -Z'ye bakar, kol/başlık +X'e uzanır. Oyun içe aktarılan parçaları bu ölçülerle kalibre eder",
        "-- (içe aktarıcının ölçeği ve konumu önemli değil) ve StudsPerUnit ile büyütür.",
        "return {",
        "\tStudsPerUnit = %.1f," % STUDS_PER_UNIT,
        "\tTypes = {",
    ]
    for kind, d in data.items():
        lines.append("\t\t%s = {" % kind)
        for key in ("Min", "Max", "PoleMin", "PoleMax"):
            lines.append("\t\t\t%s = %s," % (key, v3(d[key])))
        lines.append("\t\t\tLens = { Red = %s, Yellow = %s, Green = %s }," % (v3(d["Lens"]["Red"]), v3(d["Lens"]["Yellow"]),
                                                                          v3(d["Lens"]["Green"])))
        lines.append("\t\t\t-- parçaların sınır kutusu ortaları (kalibrasyon noktaları)")
        lines.append("\t\t\tPoleCenter = %s, RedCenter = %s, GreenCenter = %s," % (
            v3(d["Centre"]["Pole"]), v3(d["Centre"]["Red"]), v3(d["Centre"]["Green"])))
        lines.append("\t\t},")
    lines += ["\t},", "}", ""]
    open(OUT_LUA, "w", encoding="utf-8").write("\n".join(lines))

    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    tiles = []
    for kind, parts in all_parts.items():
        for state in ("Red", "Yellow", "Green", "night"):
            img = render(parts, state)
            ImageDraw.Draw(img).text((6, 4), "%s  %s" % (kind, {"Red": "kırmızı", "Yellow": "sarı", "Green": "yeşil",
                                                                "night": "gece lambası" if kind == "B" else "hepsi sönük"}[state]),
                                     font=font, fill=(20, 20, 20))
            tiles.append(img)
    sheet = Image.new("RGB", (300 * 4, 380 * len(all_parts)), (232, 235, 240))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 4) * 300, (i // 4) * 380))
    sheet.save(OUT_PREVIEW)
    print("->", OUT_GLB, "(%d KB)" % (os.path.getsize(OUT_GLB) // 1024), OUT_LUA, OUT_PREVIEW)


if __name__ == "__main__":
    main()
