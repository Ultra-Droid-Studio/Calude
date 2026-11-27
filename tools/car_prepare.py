#!/usr/bin/env python3
"""car_prepare.py — downloaded car models -> Roblox-ready .glb with the ORIGINAL look (textures, materials, colours
kept), fewer triangles, logos/plates removed, wheels as separate parts so they can spin in game.

  Patrol <- "Police car" by Mateusz Woliński (Sketchfab, CC-BY-4.0)
           https://sketchfab.com/3d-models/police-car-9166b13b6ae341f4bfc093edb71d74f4
  Vento  <- "(FREE) Porsche 911 Carrera 4S" by Karol Miklas (Sketchfab, CC-BY-SA-4.0)
           https://sketchfab.com/3d-models/free-porsche-911-carrera-4s-d01b254483794de3819786d93e0e1ebf
           (this modified model is shared under CC-BY-SA-4.0 as well, see assets/cars/LICENSE.txt)

What is changed and why:
  * triangles reduced with texture-aware quadric edge collapse (MeshLab / pymeshlab): flat areas lose triangles,
    curves, edges and texture seams are kept; UVs travel with the vertices, so textures stay where they were
  * hidden parts removed: Vento's transparent clear-coat shell (177k triangles, an exact copy over the paint) and
    the baked ground-shadow plane
  * brand marks removed: Vento crest, "PORSCHE" / "911" lettering (geometry and texture), licence plates;
    Patrol: the badge oval on the grille texture is covered with grille pattern
  * Vento's wheel meshes hold a whole axle: split into left / right wheels
  * part names: Wheel_<FL|FR|RL|RR>_<Tire|Rim|...> (wheels, spin in game), Paint (Vento body paint, takes the
    car colour in game), Keep_<original name> (everything else, kept exactly as imported)
  Every mesh stays under Roblox's 20 000-triangle limit. Coordinates, units and orientation are the original ones
  (the game measures the wheels to place the model).

Usage: python3 -I tools/car_prepare.py <dir with pymeshlab> <police_car.glb> <porsche.glb>
Writes assets/cars/<Name>.glb, assets/cars/cars.json, assets/cars/compare_<Name>.png (left: source after removing
the parts above, right: the written file read back; same textures, same light).
Only glTF JSON, buffers and textures are read; nothing in the model files is executed.
"""
import io
import json
import math
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from streetlights_convert import accessor, node_matrix, read_glb  # noqa: E402

for _p in [a for a in sys.argv[1:] if os.path.isdir(a)]:
    sys.path.insert(0, _p)
import pymeshlab  # noqa: E402
from PIL import Image  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cars")
MAX_TRIS = 20000


# =============================================================================================== loading
def load(path):
    js, binary = read_glb(path)
    prims = []

    def walk(ni, parent):
        n = js["nodes"][ni]
        M = parent @ node_matrix(n)
        if "mesh" in n:
            for k, p in enumerate(js["meshes"][n["mesh"]]["primitives"]):
                a = p["attributes"]
                pos = accessor(js, binary, a["POSITION"]).astype(float)
                idx = (accessor(js, binary, p["indices"]).astype(np.int64).reshape(-1, 3) if "indices" in p
                       else np.arange(len(pos)).reshape(-1, 3))
                uv = accessor(js, binary, a["TEXCOORD_0"]).astype(float) if "TEXCOORD_0" in a else None
                world = (np.c_[pos, np.ones(len(pos))] @ M.T)[:, :3]
                nrm = None
                if "NORMAL" in a:
                    nrm = accessor(js, binary, a["NORMAL"]).astype(float) @ np.linalg.inv(M[:3, :3])
                    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-20
                prims.append(dict(node=n.get("name", ""), sub=k, mat=p.get("material", 0), pos=world, idx=idx, uv=uv,
                                  nrm=nrm))
        for c in n.get("children", []):
            walk(c, M)

    for r in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(r, np.eye(4))
    return js, binary, prims


def image_bytes(js, binary, image_index):
    im = js["images"][image_index]
    bv = js["bufferViews"][im["bufferView"]]
    return binary[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]], im.get("mimeType", "image/png")


def material_texture(js, mat):
    tex = js["materials"][mat].get("pbrMetallicRoughness", {}).get("baseColorTexture")
    return None if tex is None else js["textures"][tex["index"]]["source"]


# =============================================================================================== decimation
def weld(pos, idx, tol=1e-6):
    key = np.round(pos / tol).astype(np.int64)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return pos[first], inverse.reshape(-1)[idx]


_TMP = os.path.join(os.environ.get("TMPDIR", "/tmp"), "solara_car_prepare")


def _textured_obj(pos, faces, wedge):
    os.makedirs(_TMP, exist_ok=True)
    tex = os.path.join(_TMP, "t.png")
    if not os.path.exists(tex):
        Image.new("RGB", (4, 4), (255, 255, 255)).save(tex)
    with open(os.path.join(_TMP, "m.mtl"), "w") as f:
        f.write("newmtl m\nmap_Kd t.png\n")
    path = os.path.join(_TMP, "m.obj")
    with open(path, "w") as f:
        f.write("mtllib m.mtl\n")
        f.write("".join("v %.8f %.8f %.8f\n" % tuple(v) for v in pos))
        f.write("".join("vt %.8f %.8f\n" % (u, 1.0 - v) for u, v in wedge))  # OBJ: v up
        f.write("usemtl m\n")
        f.write("".join("f %d/%d %d/%d %d/%d\n" % (a + 1, 3 * i + 1, b + 1, 3 * i + 2, c + 1, 3 * i + 3)
                        for i, (a, b, c) in enumerate(faces)))
    return path


def decimate(pos, idx, uv, target):
    """-> (positions, faces, wedge_uv (F*3x2) or None). Texture-aware when uv is given."""
    wedge = uv[idx].reshape(-1, 2) if uv is not None else None
    if len(idx) <= target:
        return pos, idx, wedge
    wpos, widx = weld(pos, idx)
    ms = pymeshlab.MeshSet()
    if wedge is not None:
        # MeshLab needs a texture index on every wedge: load through an OBJ with one textured material
        ms.load_new_mesh(_textured_obj(wpos, widx, wedge))
    else:
        ms.add_mesh(pymeshlab.Mesh(vertex_matrix=wpos, face_matrix=widx.astype(np.int32)))
    common = dict(targetfacenum=int(target), qualitythr=0.5, preserveboundary=True, boundaryweight=2.0,
                  optimalplacement=True, preservenormal=True, planarquadric=True)
    if wedge is not None:
        ms.meshing_decimation_quadric_edge_collapse_with_texture(extratcoordw=3.0, **common)
    else:
        ms.meshing_decimation_quadric_edge_collapse(preservetopology=False, autoclean=True, **common)
    m = ms.current_mesh()
    f = m.face_matrix().astype(np.int64)
    w = None
    if wedge is not None:
        w = m.wedge_tex_coord_matrix().copy()
        w[:, 1] = 1.0 - w[:, 1]  # back from OBJ (v up) to glTF (v down)
    return m.vertex_matrix().astype(float), f, w


# =============================================================================================== normals + vertex split
def corner_normals(pos, faces, crease_deg=40.0):
    """Smooth normals that stay sharp across edges bent more than crease_deg (per face corner)."""
    v0, v1, v2 = pos[faces[:, 0]], pos[faces[:, 1]], pos[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    unit = fn / (np.linalg.norm(fn, axis=1, keepdims=True) + 1e-20)
    cos_t = math.cos(math.radians(crease_deg))
    nv = len(pos)
    adj = [[] for _ in range(nv)]
    for fi, (a, b, c) in enumerate(faces):
        adj[a].append(fi)
        adj[b].append(fi)
        adj[c].append(fi)
    out = np.zeros((len(faces), 3, 3))
    for fi in range(len(faces)):
        uf = unit[fi]
        for k in range(3):
            near = adj[faces[fi, k]]
            sel = [g for g in near if unit[g] @ uf > cos_t]
            n = fn[sel].sum(axis=0)
            ln = np.linalg.norm(n)
            out[fi, k] = n / ln if ln > 1e-20 else uf
    return out


def transfer_normals(src_pos, src_nrm, pos, faces):
    """Corner normals taken from the ORIGINAL dense mesh (smooth like the source): for every corner the source
    vertex nearest to it, and among the source normals at that spot the one closest to the new face's normal
    (keeps the source's hard edges hard)."""
    key = np.round(src_pos / 1e-6).astype(np.int64)
    uniq, inverse = np.unique(key, axis=0, return_inverse=True)
    inverse = inverse.reshape(-1)
    upos = np.zeros((len(uniq), 3))
    upos[inverse] = src_pos
    normals_at = [[] for _ in range(len(uniq))]
    for i, u in enumerate(inverse):
        normals_at[u].append(i)
    span = (src_pos.max(0) - src_pos.min(0)).max()
    cell = max(span / 150.0, 1e-4)
    grid = {}
    for i, c in enumerate(map(tuple, np.floor(upos / cell).astype(np.int64))):
        grid.setdefault(c, []).append(i)
    # every new vertex: the source normals around it (nearest source spot, plus every source spot not much further away)
    around = []
    for p in pos:
        c = np.floor(p / cell).astype(np.int64)
        found = None
        for r in (1, 2, 4, 8):
            cand = []
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    for dz in range(-r, r + 1):
                        cand.extend(grid.get((c[0] + dx, c[1] + dy, c[2] + dz), ()))
            if cand:
                found = np.array(cand)
                break
        if found is None:
            found = np.arange(len(upos))
        d = np.sqrt(((upos[found] - p) ** 2).sum(axis=1))
        keep = found[d <= d.min() * 1.5 + cell * 0.5]
        dist = np.sqrt(((upos[keep] - p) ** 2).sum(axis=1))
        idxs = np.concatenate([normals_at[u] for u in keep])
        wts = np.concatenate([np.full(len(normals_at[u]), 1.0 / (dd + cell * 0.05)) for u, dd in zip(keep, dist)])
        around.append((idxs, wts))
    v0, v1, v2 = pos[faces[:, 0]], pos[faces[:, 1]], pos[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-20
    out = np.zeros((len(faces), 3, 3))
    for fi in range(len(faces)):
        for k in range(3):
            idxs, wts = around[faces[fi, k]]
            cands = src_nrm[idxs]
            dots = cands @ fn[fi]
            ok = dots > 0.5  # same side of the surface as this face (not a panel-gap flange or a back face)
            if ok.any():
                n = (cands[ok] * wts[ok, None]).sum(axis=0)
            else:
                n = cands[int(dots.argmax())]
            ln = np.linalg.norm(n)
            out[fi, k] = n / ln if ln > 1e-12 else fn[fi]
    return out


def to_indexed(pos, faces, wedge_uv, normals=None):
    """Wedge data -> glTF vertices (unique position + uv + normal). normals: per corner (F,3,3) or None."""
    if normals is None:
        normals = corner_normals(pos, faces)
    P = pos[faces].reshape(-1, 3)
    N = normals.reshape(-1, 3)
    U = wedge_uv if wedge_uv is not None else np.zeros((len(P), 2))
    key = np.c_[np.round(P, 6), np.round(U, 5), np.round(N, 3)]
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return P[first], N[first], U[first], inverse.reshape(-1, 3)


# =============================================================================================== texture edits
def paint_rect(img, box, src_dx=0, color=None):
    """Cover a texture rectangle: copy from src_dx pixels to the right (pattern) or fill with a colour."""
    x0, y0, x1, y1 = box
    a = np.array(img)
    if color is not None:
        a[y0:y1, x0:x1] = color
    else:
        a[y0:y1, x0:x1] = a[y0:y1, x0 + src_dx:x1 + src_dx]
    return Image.fromarray(a)


def uv_hits(prims, image_index_of, image_index, boxes, size):
    """Triangles (of kept parts) whose UV centroid falls in one of the boxes of the given image -> count per part."""
    hits = {}
    w, h = size
    for p in prims:
        if p["uv"] is None or image_index_of(p) != image_index:
            continue
        c = p["uv"][p["idx"]].mean(axis=1)
        x, y = np.mod(c[:, 0], 1) * w, np.mod(c[:, 1], 1) * h
        n = 0
        for (x0, y0, x1, y1) in boxes:
            n += int(((x >= x0) & (x < x1) & (y >= y0) & (y < y1)).sum())
        if n:
            hits[p["node"]] = n
    return hits


# =============================================================================================== cars
def prepare_patrol(path):
    js, binary, prims = load(path)
    edits = {}
    # badge oval on the grille: cover with the grille pattern next to it (texture 0 = body, 1024 px)
    body_img = material_texture(js, 0)
    data, _ = image_bytes(js, binary, body_img)
    img = Image.open(io.BytesIO(data)).convert("RGB")
    edits[body_img] = paint_rect(img, (74, 458, 118, 484), src_dx=46)
    wheel_names = {"CrownVic.Wheel.Ft.L": "FL", "CrownVic.Wheel.Ft.R": "FR", "CrownVic.Wheel.Bk.L": "RL",
                   "CrownVic.Wheel.Bk.R": "RR"}
    parts = []
    for p in prims:
        base = p["node"].rsplit("_", 1)[0]
        if base in wheel_names:
            name, target = f"Wheel_{wheel_names[base]}_Tire", 1800  # whole wheel (textured tyre + rim): spins
        elif base == "CrownVic.Body":
            name, target = "Keep_Body", 19500
        elif base == "Roof light bar":
            name, target = "Keep_LightBar", 2200
        elif base == "roof lights":
            name, target = "Keep_RoofLights", 800
        elif base == "windows glass":
            name, target = "Keep_Glass", 1500
        else:
            name, target = "Keep_" + base.replace(" ", "").replace(".", ""), 1500
        parts.append(dict(p, out=name, target=target))
    return js, binary, parts, edits


VENTO_DROP_NODES = {
    "Plane.002_0", "Plane.003_0", "Plane.004_0",  # "PORSCHE" / model lettering (geometry)
    "boot.003_0",                                 # lettering panel in the rear light band (texture)
    "boot.007_0",                                 # crest on the bonnet
    "Plane.005_0", "Plane.006_0",                 # licence plates
    "Plane_0",                                    # baked ground shadow
}
VENTO_DROP_MATS = {1}  # transparent clear-coat shell over the paint (copy of the body, 177k triangles)
# texture 6 ("tex_shiny", 1024 px): crest and lettering panel are covered (lights on the same sheet stay)
VENTO_TEX_BOXES = [(400, 60, 640, 340), (85, 400, 955, 625)]
VENTO_TEX_FILL = [(0, 0, 0, 255), (0, 0, 0, 0)]  # each box gets its own background (black / transparent)


def prepare_vento(path):
    js, binary, prims = load(path)
    edits = {}
    shiny = js["textures"][6]["source"]
    data, _ = image_bytes(js, binary, shiny)
    img = Image.open(io.BytesIO(data)).convert("RGBA")
    for box, fill in zip(VENTO_TEX_BOXES, VENTO_TEX_FILL):
        img = paint_rect(img, box, color=fill)
    edits[shiny] = img
    kept = [p for p in prims if p["node"] not in VENTO_DROP_NODES and p["mat"] not in VENTO_DROP_MATS]
    hits = uv_hits(kept, lambda p: material_texture(js, p["mat"]), shiny, VENTO_TEX_BOXES, (1024, 1024))
    if hits:
        print("  NOTE: kept parts still map into the covered crest/lettering area:", hits)
    parts = []
    for p in kept:
        node, mat = p["node"], p["mat"]
        if node.startswith("Cylinder.000") or node.startswith("Cylinder.001"):
            axle = "F" if node.startswith("Cylinder.001") else "R"   # front axle at +Z (bumper_front side)
            kind = {3: "Rim", 2: "RimDark", 7: "Tire", 8: None}[mat]
            if kind is None:   # brake calipers do not turn with the wheel: static part
                parts.append(dict(p, out=f"Keep_Caliper{axle}", target=1600))
                continue
            cent = p["pos"][p["idx"]].mean(axis=1)
            for side, sel in (("L", cent[:, 0] > 0), ("R", cent[:, 0] <= 0)):  # car faces +Z: left = +X
                q = dict(p, idx=p["idx"][sel])
                target = {"Rim": 1300, "RimDark": 700, "Tire": 500}[kind]
                parts.append(dict(q, out=f"Wheel_{axle}{side}_{kind}", target=target))
            continue
        name = "Paint" if mat == 4 else "Keep_" + node.replace(".", "")
        tris = len(p["idx"])
        if mat == 4:
            target = max(int(tris * 0.10), 300)          # smooth body panels
        elif mat in (9, 11, 12, 10):
            target = max(int(tris * 0.18), 200)          # glass / light lenses
        elif node.startswith(("Cube.00", "boot.006")):
            target = max(int(tris * 0.08), 150)          # interior, mostly hidden behind tinted glass
        else:
            target = max(int(tris * 0.10), 200)
        parts.append(dict(p, out=name, target=target))
    return js, binary, parts, edits


# =============================================================================================== output
def build(car, js, binary, parts, edits):
    """Decimate every part, merge parts with the same output name + material, write the .glb."""
    groups = {}
    report = {}
    for p in parts:
        pos, faces, wuv = decimate(p["pos"], p["idx"], p["uv"], p["target"])
        if p.get("nrm") is not None:
            used = np.unique(p["idx"])
            cn = transfer_normals(p["pos"][used], p["nrm"][used], pos, faces)
        else:
            cn = corner_normals(pos, faces)
        groups.setdefault((p["out"], p["mat"]), []).append((pos, faces, wuv, cn))
        r = report.setdefault(p["out"], [0, 0])
        r[0] += len(p["idx"])
        r[1] += len(faces)
    meshes = []
    for (name, mat), items in groups.items():
        P, F, W, NN, off = [], [], [], [], 0
        for pos, faces, wuv, cn in items:
            P.append(pos)
            F.append(faces + off)
            W.append(wuv if wuv is not None else np.zeros((len(faces) * 3, 2)))
            NN.append(cn)
            off += len(pos)
        pos, faces, wuv, cnorm = np.vstack(P), np.vstack(F), np.vstack(W), np.vstack(NN)
        # Roblox: at most 20 000 triangles per MeshPart -> split long meshes into chunks
        for c in range(0, len(faces), MAX_TRIS):
            fsel = slice(c, c + MAX_TRIS)
            vpos, vnrm, vuv, vidx = to_indexed(pos, faces[fsel], wuv[c * 3:(c + MAX_TRIS) * 3], cnorm[fsel])
            suffix = "" if len(faces) <= MAX_TRIS else f"_{c // MAX_TRIS + 1}"
            meshes.append(dict(name=name + suffix, mat=mat, pos=vpos, nrm=vnrm, uv=vuv, idx=vidx))
    path = os.path.join(OUT, f"{car}.glb")
    write_glb(path, car, js, binary, meshes, edits)
    return path, report


def write_glb(path, car, js, binary, meshes, edits):
    blob = bytearray()
    views, accs, out_meshes, nodes, materials, textures, images = [], [], [], [], [], [], []
    image_map, mat_map = {}, {}

    def view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def image_index(src):
        if src not in image_map:
            if src in edits:
                buf = io.BytesIO()
                edits[src].save(buf, format="PNG")
                data, mime = buf.getvalue(), "image/png"
            else:
                data, mime = image_bytes(js, binary, src)
            images.append({"bufferView": view(data), "mimeType": mime})
            textures.append({"source": len(images) - 1})
            image_map[src] = len(textures) - 1
        return image_map[src]

    def material_index(mi):
        if mi not in mat_map:
            m = js["materials"][mi]
            pbr = m.get("pbrMetallicRoughness", {})
            out = {"name": m.get("name", f"m{mi}"), "pbrMetallicRoughness": {
                "baseColorFactor": pbr.get("baseColorFactor", [1, 1, 1, 1]),
                "metallicFactor": pbr.get("metallicFactor", 0.0), "roughnessFactor": pbr.get("roughnessFactor", 0.6)}}
            src = material_texture(js, mi)
            if src is not None:
                out["pbrMetallicRoughness"]["baseColorTexture"] = {"index": image_index(src)}
            if m.get("alphaMode"):
                out["alphaMode"] = m["alphaMode"]
            if m.get("doubleSided"):
                out["doubleSided"] = True
            materials.append(out)
            mat_map[mi] = len(materials) - 1
        return mat_map[mi]

    for m in meshes:
        attrs = {}
        pv = view(m["pos"].astype(np.float32).tobytes(), 34962)
        accs.append({"bufferView": pv, "componentType": 5126, "count": len(m["pos"]), "type": "VEC3",
                     "min": m["pos"].min(0).tolist(), "max": m["pos"].max(0).tolist()})
        attrs["POSITION"] = len(accs) - 1
        nv = view(m["nrm"].astype(np.float32).tobytes(), 34962)
        accs.append({"bufferView": nv, "componentType": 5126, "count": len(m["nrm"]), "type": "VEC3"})
        attrs["NORMAL"] = len(accs) - 1
        if material_texture(js, m["mat"]) is not None:
            tv = view(m["uv"].astype(np.float32).tobytes(), 34962)
            accs.append({"bufferView": tv, "componentType": 5126, "count": len(m["uv"]), "type": "VEC2"})
            attrs["TEXCOORD_0"] = len(accs) - 1
        iv = view(m["idx"].astype(np.uint32).tobytes(), 34963)
        accs.append({"bufferView": iv, "componentType": 5125, "count": m["idx"].size, "type": "SCALAR"})
        out_meshes.append({"name": m["name"], "primitives": [{"attributes": attrs, "indices": len(accs) - 1,
                                                              "material": material_index(m["mat"])}]})
        nodes.append({"name": m["name"], "mesh": len(out_meshes) - 1})
    nodes.append({"name": car, "children": list(range(len(nodes)))})
    src_asset = js.get("asset", {}).get("extras", {})
    gltf = {
        "asset": {"version": "2.0", "generator": "SOLARA car_prepare.py",
                  "extras": {"author": src_asset.get("author"), "license": src_asset.get("license"),
                             "source": src_asset.get("source"), "title": src_asset.get("title"),
                             "modified": "fewer triangles, brand marks and plates removed, wheels split"}},
        "scene": 0, "scenes": [{"name": car, "nodes": [len(nodes) - 1]}], "nodes": nodes, "meshes": out_meshes,
        "materials": materials, "textures": textures, "images": images, "samplers": [],
        "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(blob)}],
    }
    if not gltf["samplers"]:
        del gltf["samplers"]
    if not textures:
        for k in ("textures", "images"):
            del gltf[k]
    jb = json.dumps(gltf, separators=(",", ":")).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    while len(blob) % 4:
        blob.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(jb) + 8 + len(blob)))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


# =============================================================================================== textured preview
def linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def scene_from_glb(path):
    """Renderable triangles from a .glb (any of ours or the source): list of dict(pos, idx, uv, nrm, color, tex, alpha)."""
    js, binary, prims = load(path)
    return scene_from(js, binary, prims, {})


def scene_from(js, binary, prims, edits):
    cache = {}
    out = []
    for p in prims:
        m = js["materials"][p["mat"]]
        pbr = m.get("pbrMetallicRoughness", {})
        bcf = np.array(pbr.get("baseColorFactor", [1, 1, 1, 1]), dtype=float)
        src = material_texture(js, p["mat"])
        tex = None
        if src is not None and p["uv"] is not None:
            if src not in cache:
                if src in edits:
                    cache[src] = np.asarray(edits[src].convert("RGBA"), dtype=float) / 255.0
                else:
                    data, _ = image_bytes(js, binary, src)
                    cache[src] = np.asarray(Image.open(io.BytesIO(data)).convert("RGBA"), dtype=float) / 255.0
            tex = cache[src]
        alpha = float(bcf[3]) if m.get("alphaMode") == "BLEND" else 1.0
        out.append(dict(pos=p["pos"], idx=p["idx"], uv=p["uv"], nrm=p.get("nrm"), color=linear_to_srgb(bcf[:3]),
                        tex=tex, alpha=alpha, blend=m.get("alphaMode") == "BLEND"))
    return out


def render(scene, yaw, pitch=20, size=(560, 360), frame=None):
    W, H = size
    allp = np.vstack([s["pos"] for s in scene])
    centre = (allp.min(0) + allp.max(0)) / 2 if frame is None else frame[0]
    cy, sy, cp, sp = math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    fwd = -np.array([sy * cp, sp, cy * cp])          # camera looks along fwd (from the eye towards the car)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    light = np.array([0.4, 0.8, 0.45])
    light /= np.linalg.norm(light)
    rel = allp - centre
    span = max(np.abs(rel @ right).max(), np.abs(rel @ up).max() * W / H) if frame is None else frame[1]
    scale = (W * 0.46) / span
    zbuf = np.full((H, W), np.inf)
    img = np.ones((H, W, 3)) * np.array([0.92, 0.93, 0.95])
    transparent = []
    for pass_blend in (False, True):
        for s in scene:
            if s["blend"] != pass_blend:
                continue
            P = (s["pos"] - centre)
            X = W / 2 + (P @ right) * scale
            Y = H / 2 - (P @ up) * scale
            Z = P @ fwd
            idx = s["idx"]
            v0, v1, v2 = s["pos"][idx[:, 0]], s["pos"][idx[:, 1]], s["pos"][idx[:, 2]]
            fn = np.cross(v1 - v0, v2 - v0)
            fn /= (np.linalg.norm(fn, axis=1, keepdims=True) + 1e-20)
            facing = fn @ fwd
            shade = 0.5 + 0.5 * np.abs(fn @ light)
            for t in range(len(idx)):
                a, b, c = idx[t]
                xs, ys = np.array([X[a], X[b], X[c]]), np.array([Y[a], Y[b], Y[c]])
                x0, x1 = max(int(math.floor(xs.min())), 0), min(int(math.ceil(xs.max())), W - 1)
                y0, y1 = max(int(math.floor(ys.min())), 0), min(int(math.ceil(ys.max())), H - 1)
                if x1 < x0 or y1 < y0:
                    continue
                gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
                d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
                if abs(d) < 1e-12:
                    continue
                w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
                w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
                w2 = 1 - w0 - w1
                inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
                if not inside.any():
                    continue
                z = w0 * Z[a] + w1 * Z[b] + w2 * Z[c]
                zb = zbuf[y0:y1 + 1, x0:x1 + 1]
                ok = inside & (z < zb)
                if not ok.any():
                    continue
                col = np.broadcast_to(s["color"], ok.shape + (3,)).copy()
                alpha = np.full(ok.shape, s["alpha"])
                if s["tex"] is not None:
                    uv = s["uv"]
                    u = w0 * uv[a, 0] + w1 * uv[b, 0] + w2 * uv[c, 0]
                    v = w0 * uv[a, 1] + w1 * uv[b, 1] + w2 * uv[c, 1]
                    th, tw = s["tex"].shape[:2]
                    tx = np.clip((np.mod(u, 1) * tw).astype(int), 0, tw - 1)
                    ty = np.clip((np.mod(v, 1) * th).astype(int), 0, th - 1)
                    texel = s["tex"][ty, tx]
                    col = col * texel[..., :3]
                    if s["blend"]:
                        alpha = alpha * texel[..., 3] if s["alpha"] < 1 else texel[..., 3]
                if s.get("nrm") is not None:
                    # smooth shading from the vertex normals (what Roblox does with the mesh normals)
                    nm = s["nrm"]
                    n = w0[..., None] * nm[a] + w1[..., None] * nm[b] + w2[..., None] * nm[c]
                    n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-20
                    col = col * (0.5 + 0.5 * np.abs(n @ light))[..., None]
                else:
                    col = col * shade[t]
                region = img[y0:y1 + 1, x0:x1 + 1]
                if pass_blend:
                    al = alpha[..., None]
                    region[ok] = (region * (1 - al) + col * al)[ok]
                else:
                    region[ok] = col[ok]
                    zb[ok] = z[ok]
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)), (centre, span)


def compare(car, before_scene, after_path):
    after = scene_from_glb(after_path)
    tiles = []
    for yaw in (35, 150):
        a, frame = render(before_scene, yaw)
        b, _ = render(after, yaw, frame=frame)
        tiles.append((a, b))
    W, H = tiles[0][0].size
    from PIL import ImageDraw, ImageFont
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    img = Image.new("RGB", (W * 2, H * 2 + 34), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.text((10, 8), f"{car}: sol = kaynak (logo/plaka/görünmez parça çıkarılmış), sağ = hazırlanan dosya", font=font, fill=(20, 20, 20))
    for i, (a, b) in enumerate(tiles):
        img.paste(a, (0, 34 + i * H))
        img.paste(b, (W, 34 + i * H))
    out = os.path.join(OUT, f"compare_{car}.png")
    img.save(out)
    return out


def main():
    files = [a for a in sys.argv[1:] if a.endswith(".glb")]
    if len(files) != 2:
        raise SystemExit(__doc__)
    os.makedirs(OUT, exist_ok=True)
    results = {}
    for car, fn, path in (("Patrol", prepare_patrol, files[0]), ("Vento", prepare_vento, files[1])):
        print(car)
        js, binary, parts, edits = fn(path)
        before_tris = sum(len(p["idx"]) for p in parts)
        out_path, report = build(car, js, binary, parts, edits)
        after = scene_from_glb(out_path)
        after_tris = sum(len(s["idx"]) for s in after)
        biggest = max(len(s["idx"]) for s in after)
        print(f"  {before_tris} -> {after_tris} triangles (largest mesh {biggest}); {os.path.getsize(out_path) / 1e6:.1f} MB")
        for name, (b, a) in sorted(report.items()):
            print(f"    {name:22s} {b:7d} -> {a:6d}")
        before_scene = scene_from(js, binary, [{k: v for k, v in p.items()} for p in parts], edits)
        print("  wrote", compare(car, before_scene, out_path))
        results[car] = {"SourceTriangles": before_tris, "Triangles": after_tris, "LargestMesh": biggest,
                        "Parts": {k: v[1] for k, v in report.items()}}
    json.dump(results, open(os.path.join(OUT, "cars.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
