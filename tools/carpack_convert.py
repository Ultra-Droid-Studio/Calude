#!/usr/bin/env python3
"""
carpack_convert.py — converts the Quaternius "LowPoly Cars" FBX pack (CC0 1.0) into Roblox-ready .glb files.

For every car it writes assets/carpack/<Car>.glb with ONE node (= one MeshPart after Studio's Import 3D) per
material, so the game can colour each part (random body paint, glass, trim, lights that switch on/off):
  Paint, Paint2 (second body colour), Glass, Dark, Trim, Headlight, TailLight, SirenWhite, SirenBlue
  Wheel_FL_Tire, Wheel_FL_Rim, Wheel_FR_*, Wheel_RL_*, Wheel_RR_*   (the pack's single "BackWheels" mesh is split)
Conventions (Roblox): +Y up, car front = -Z, right = +X, metres, root origin = centre of the four wheel centres
(at wheel-centre height). Faces are flat-shaded (per-triangle normals). Also writes assets/carpack/carpack.json
(per-car dimensions, parts, colours) and docs/carpack_preview.png (software-rendered preview read back from the
.glb files, to verify orientation and colours before importing).

Usage: python3 tools/carpack_convert.py <folder with the pack's .fbx files>
Only reads the FBX data (tools/fbx_reader.py); nothing in the files is executed.
"""
import sys, os, json, struct, math

sys.path.insert(0, os.path.dirname(__file__))
import fbx_reader

OUT = "assets/carpack"
CM = 0.01  # FBX units (cm) -> metres

FIXED_ROLE = {
    "Windows": "Glass", "Headlights": "Headlight", "TailLights": "TailLight",
    "WhiteLights": "SirenWhite", "BlueLights": "SirenBlue", "Black": "Dark", "Grey": "Trim",
}


def to_roblox(v):
    x, y, z = v
    return (x * CM, z * CM, -y * CM)  # FBX Z-up, +Y front  ->  Roblox Y-up, -Z front


def tri_fan(poly):
    return [(poly[0], poly[i], poly[i + 1]) for i in range(1, len(poly) - 1)]


def srgb(c):
    out = []
    for x in c:
        x = max(0.0, min(1.0, x))
        out.append(12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055)
    return [round(v * 255) for v in out]


def load_car(path):
    sc = fbx_reader.scene(path)
    body, wheels = None, {}
    for m in sc["models"].values():
        if not m["geometry"]:
            continue
        key = m["name"].split("_", 1)[1] if "_" in m["name"] else m["name"]
        if "Wheel" in key:
            wheels[key] = m
        else:
            body = m
    parts = {}  # name -> {"tris": [((x,y,z),...)], "color": (r,g,b)}

    def add(name, tri, color):
        p = parts.setdefault(name, {"tris": [], "color": color})
        p["tris"].append(tri)

    # body: per material
    g = body["geometry"]
    mats = body["materials"]
    counts = {}
    for i, poly in enumerate(g["polys"]):
        mi = g["mats"][i] if g["mapping"] == "ByPolygon" else g["mats"][0]
        counts[mi] = counts.get(mi, 0) + 1
    others = sorted([mi for mi in counts if mats[mi]["name"] not in FIXED_ROLE], key=lambda mi: -counts[mi])
    role_of = {}
    for mi in counts:
        name = mats[mi]["name"]
        if name in FIXED_ROLE:
            role_of[mi] = FIXED_ROLE[name]
        else:
            role_of[mi] = "Paint" if mi == others[0] else "Paint2"
    t = body["t"]
    for i, poly in enumerate(g["polys"]):
        mi = g["mats"][i] if g["mapping"] == "ByPolygon" else g["mats"][0]
        for a, b, c in tri_fan(poly):
            tri = tuple(to_roblox(tuple(g["verts"][k][j] + t[j] for j in range(3))) for k in (a, b, c))
            add(role_of[mi], tri, mats[mi]["color"])

    # wheels: tire (Black) / rim (Grey); BackWheels split by side
    for key, m in wheels.items():
        wg, wm, wt = m["geometry"], m["materials"], m["t"]
        for i, poly in enumerate(wg["polys"]):
            mi = wg["mats"][i] if wg["mapping"] == "ByPolygon" else wg["mats"][0]
            kind = "Tire" if wm[mi]["name"] == "Black" else "Rim"
            world = [tuple(wg["verts"][k][j] + wt[j] for j in range(3)) for k in poly]
            if key == "BackWheels":
                cx = sum(v[0] for v in world) / len(world)
                wheel = "RL" if cx < 0 else "RR"
            else:
                wheel = "FL" if "Left" in key else "FR"
            for a, b, c in tri_fan(list(range(len(world)))):
                add("Wheel_%s_%s" % (wheel, kind), tuple(to_roblox(world[k]) for k in (a, b, c)), wm[mi]["color"])
    return parts


def bbox(tris):
    xs = [v[0] for t in tris for v in t]; ys = [v[1] for t in tris for v in t]; zs = [v[2] for t in tris for v in t]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def normal(t):
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
    ux, uy, uz = bx - ax, by - ay, bz - az
    vx, vy, vz = cx - ax, cy - ay, cz - az
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return (nx / l, ny / l, nz / l)


def write_glb(path, car, parts, origin):
    bin_chunks, buffer_views, accessors, meshes, materials, nodes = [], [], [], [], [], []
    offset = 0
    child_ids = []
    for name in sorted(parts):
        p = parts[name]
        lo, hi = bbox(p["tris"])
        center = tuple((lo[i] + hi[i]) / 2 for i in range(3))
        pos, nor = [], []
        for t in p["tris"]:
            n = normal(t)
            for v in t:
                pos.extend(v[i] - center[i] for i in range(3))
                nor.extend(n)
        count = len(pos) // 3
        for data, is_pos in ((pos, True), (nor, False)):
            raw = struct.pack("<%df" % len(data), *data)
            bin_chunks.append(raw)
            buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw), "target": 34962})
            offset += len(raw)
            acc = {"bufferView": len(buffer_views) - 1, "componentType": 5126, "count": count, "type": "VEC3"}
            if is_pos:
                acc["min"] = [min(pos[i::3]) for i in range(3)]
                acc["max"] = [max(pos[i::3]) for i in range(3)]
            accessors.append(acc)
        materials.append({"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": [p["color"][0], p["color"][1], p["color"][2], 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.85}})
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": len(accessors) - 2, "NORMAL": len(accessors) - 1},
                                                      "material": len(materials) - 1, "mode": 4}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1,
                      "translation": [center[i] - origin[i] for i in range(3)]})
        child_ids.append(len(nodes) - 1)
    nodes.append({"name": car, "children": child_ids})
    gltf = {"asset": {"version": "2.0", "generator": "SOLARA carpack_convert.py (Quaternius LowPoly Cars, CC0)"},
            "scene": 0, "scenes": [{"name": car, "nodes": [len(nodes) - 1]}], "nodes": nodes, "meshes": meshes,
            "materials": materials, "accessors": accessors, "bufferViews": buffer_views,
            "buffers": [{"byteLength": offset}]}
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    binary = b"".join(bin_chunks)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(binary), b"BIN\x00") + binary)


def read_glb(path):
    """Reads back our own .glb (for the preview and as a self-check)."""
    data = open(path, "rb").read()
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2 and total == len(data)
    jlen, jtype = struct.unpack_from("<I4s", data, 12)
    gltf = json.loads(data[20:20 + jlen])
    blen, btype = struct.unpack_from("<I4s", data, 20 + jlen)
    binary = data[28 + jlen:28 + jlen + blen]
    out = []
    for node in gltf["nodes"]:
        if "mesh" not in node:
            continue
        prim = gltf["meshes"][node["mesh"]]["primitives"][0]
        acc = gltf["accessors"][prim["attributes"]["POSITION"]]
        bv = gltf["bufferViews"][acc["bufferView"]]
        vals = struct.unpack_from("<%df" % (acc["count"] * 3), binary, bv["byteOffset"])
        tr = node["translation"]
        verts = [(vals[i] + tr[0], vals[i + 1] + tr[1], vals[i + 2] + tr[2]) for i in range(0, len(vals), 3)]
        color = gltf["materials"][prim["material"]]["pbrMetallicRoughness"]["baseColorFactor"][:3]
        out.append((node["name"], [verts[i:i + 3] for i in range(0, len(verts), 3)], color))
    return out


def render(parts, size=(420, 300), yaw=35, pitch=24):
    """Small painter's-algorithm renderer. Camera: in front of the car, to its left, above (car front = -Z)."""
    from PIL import Image, ImageDraw
    img = Image.new("RGB", size, (236, 238, 242))
    draw = ImageDraw.Draw(img)
    cyaw, syaw = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    eye = (-syaw * cp, sp, -cyaw * cp)            # direction from car to camera
    f = (-eye[0], -eye[1], -eye[2])               # camera forward
    r = (f[1] * 0 - f[2] * 1, f[2] * 0 - f[0] * 0, f[0] * 1 - f[1] * 0)  # f x up(0,1,0)
    rl = math.sqrt(sum(c * c for c in r)); r = tuple(c / rl for c in r)
    u = (r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0])  # r x f
    light = (0.35, 0.85, -0.4)
    ll = math.sqrt(sum(c * c for c in light)); light = tuple(c / ll for c in light)
    tris = []
    for name, ts, color in parts:
        rgb = srgb(color)
        for t in ts:
            cam = [(v[0] * r[0] + v[1] * r[1] + v[2] * r[2], v[0] * u[0] + v[1] * u[1] + v[2] * u[2],
                    v[0] * f[0] + v[1] * f[1] + v[2] * f[2]) for v in t]
            n = normal(t)
            if n[0] * f[0] + n[1] * f[1] + n[2] * f[2] > 0.05:
                continue  # arka yüz
            shade = 0.5 + 0.5 * max(0.0, n[0] * light[0] + n[1] * light[1] + n[2] * light[2])
            tris.append((sum(p[2] for p in cam) / 3, cam, tuple(int(c * shade) for c in rgb)))
    xs = [p[0] for _, cam, _ in tris for p in cam]; ys = [p[1] for _, cam, _ in tris for p in cam]
    scale = 0.85 * min(size[0] / (max(xs) - min(xs)), size[1] / (max(ys) - min(ys)))
    ox, oy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    for _, cam, rgb in sorted(tris, key=lambda t: -t[0]):  # uzaktan yakına
        draw.polygon([(size[0] / 2 + (p[0] - ox) * scale, size[1] / 2 - (p[1] - oy) * scale) for p in cam], fill=rgb)
    return img


def main():
    src = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    summary = {}
    previews = []
    for f in sorted(os.listdir(src)):
        if not f.lower().endswith(".fbx"):
            continue
        car = os.path.splitext(f)[0]
        parts = load_car(os.path.join(src, f))
        wheel_centers = {}
        for w in ("FL", "FR", "RL", "RR"):
            lo, hi = bbox(parts["Wheel_%s_Tire" % w]["tris"] + parts["Wheel_%s_Rim" % w]["tris"])
            wheel_centers[w] = tuple((lo[i] + hi[i]) / 2 for i in range(3))
            if w == "FL":
                wheel_radius = (hi[1] - lo[1]) / 2
                wheel_width = hi[0] - lo[0]
        origin = tuple(sum(c[i] for c in wheel_centers.values()) / 4 for i in range(3))
        out_path = os.path.join(OUT, car + ".glb")
        write_glb(out_path, car, parts, origin)
        # self-check: read back, verify triangle counts and orientation
        back = read_glb(out_path)
        tris = sum(len(t) for _, t, _ in back)
        assert tris == sum(len(p["tris"]) for p in parts.values())
        fl, rl = wheel_centers["FL"], wheel_centers["RL"]
        assert fl[2] < rl[2], car + ": front wheels must be at -Z"
        assert wheel_centers["FL"][0] < wheel_centers["FR"][0], car + ": left wheel must be at -X"
        body_lo, body_hi = bbox(parts["Paint"]["tris"])
        assert fl[1] < (body_lo[1] + body_hi[1]) / 2, car + ": wheels must be below the body centre (+Y up)"
        lo, hi = bbox([t for p in parts.values() for t in p["tris"]])
        summary[car] = {
            "Triangles": tris,
            "LengthM": round(hi[2] - lo[2], 3), "WidthM": round(hi[0] - lo[0], 3), "HeightM": round(hi[1] - lo[1], 3),
            "WheelbaseM": round(rl[2] - fl[2], 3), "TrackM": round(wheel_centers["FR"][0] - wheel_centers["FL"][0], 3),
            "WheelRadiusM": round(wheel_radius, 3), "WheelWidthM": round(wheel_width, 3),
            "Parts": {name: {"Triangles": len(p["tris"]), "Srgb": srgb(p["color"])} for name, p in sorted(parts.items())},
        }
        previews.append((car, render(back)))
        print("%-11s %5d tris  L %.2f m  W %.2f m  H %.2f m  wheelbase %.2f m  track %.2f m  wheel r %.3f m  parts %d -> %s" % (
            car, tris, summary[car]["LengthM"], summary[car]["WidthM"], summary[car]["HeightM"], summary[car]["WheelbaseM"],
            summary[car]["TrackM"], wheel_radius, len(parts), out_path))
    json.dump(summary, open(os.path.join(OUT, "carpack.json"), "w"), indent=1)
    from PIL import Image, ImageDraw
    cols = 4
    w, h = previews[0][1].size
    sheet = Image.new("RGB", (cols * w, ((len(previews) + cols - 1) // cols) * (h + 20)), (236, 238, 242))
    d = ImageDraw.Draw(sheet)
    for i, (car, img) in enumerate(previews):
        x, y = (i % cols) * w, (i // cols) * (h + 20)
        sheet.paste(img, (x, y + 20))
        d.text((x + 10, y + 4), car + "   (front = lower left)", fill=(30, 30, 30))
    sheet.save("docs/carpack_preview.png")
    print("preview -> docs/carpack_preview.png")


if __name__ == "__main__":
    main()
