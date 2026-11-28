"""car_inventory/inventory.py — measures the 12 cars in assets/cars/SOLARA_Cars.glb (shading, tyre segments, glass, cabin, sub-objects). Usage: inventory.py <repo> <out.json>
Read-only: reads the model file, writes the given output only. Run with python3 -I."""
import json, math, os, sys
import numpy as np
ROOT = sys.argv[1]
sys.path.insert(0, ROOT + "/tools")
import cosmo_cars_convert as C
cars = C.read_glb(ROOT + "/assets/cars/SOLARA_Cars.glb")
info = json.load(open(ROOT + "/assets/cars/cars.json"))

def role(name):
    r = name.split("_", 1)[1]
    return r.rsplit("_", 1)[0]

def ray_hits(orig, d, tris, maxt):
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2)
    det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-9
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    s = orig - v0
    u = (s * p).sum(1) * inv
    q = np.cross(s, e1)
    v = (q * d).sum(1) * inv
    t = (e2 * q).sum(1) * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-4) & (t < maxt)
    return t[hit]

def components(T):
    # union-find over shared vertex positions
    n = len(T)
    key = {}
    parent = list(range(n))
    def f(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]; a = parent[a]
        return a
    for i, tri in enumerate(T):
        for v in tri:
            k = tuple(np.round(v, 4))
            if k in key:
                ra, rb = f(i), f(key[k])
                if ra != rb: parent[ra] = rb
            else:
                key[k] = i
    groups = {}
    for i in range(n):
        groups.setdefault(f(i), []).append(i)
    return list(groups.values())

out = {}
for car, parts in cars.items():
    j = info[car]
    R = {}
    for name, T, N, rgb in parts:
        R.setdefault(role(name), []).append((name, T, N, rgb))
    body = np.concatenate([T for name, T, N, rgb in parts if not role(name).startswith("Wheel")])
    allv = body.reshape(-1, 3)
    lo, hi = allv.min(0), allv.max(0)
    # shading: per-corner normal vs face normal
    fn = np.cross(body[:, 1] - body[:, 0], body[:, 2] - body[:, 0])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-12
    Nb = np.concatenate([N for name, T, N, rgb in parts if not role(name).startswith("Wheel")])
    ang = np.degrees(np.arccos(np.clip((Nb * fn[:, None, :]).sum(2), -1, 1)))
    smooth_frac = float((ang > 3).mean())
    # wheels
    wheels = {}
    for w in ("FL", "FR", "RL", "RR"):
        tire = np.concatenate([T for name, T, N, rgb in parts if role(name) == f"Wheel_{w}_Tire"])
        rim = np.concatenate([T for name, T, N, rgb in parts if role(name) == f"Wheel_{w}_Rim"])
        v = tire.reshape(-1, 3)
        c = (v.min(0) + v.max(0)) / 2
        r = (v.max(0) - v.min(0))[1] / 2
        rel = v - c
        rad = np.hypot(rel[:, 1], rel[:, 2])
        outer = rel[rad > r * 0.95]
        angs = np.unique(np.round(np.degrees(np.arctan2(outer[:, 1], outer[:, 2])) % 360, 0))
        rv = rim.reshape(-1, 3) - c
        rrad = np.hypot(rv[:, 1], rv[:, 2])
        rimout = rv[rrad > rrad.max() * 0.95]
        rangs = np.unique(np.round(np.degrees(np.arctan2(rimout[:, 1], rimout[:, 2])) % 360, 0))
        # arch: body triangles whose centroid is above the tire, within its x / z footprint
        cen = body.mean(1)
        width_x = v[:, 0].max() - v[:, 0].min()
        sel = (np.abs(cen[:, 0] - c[0]) < width_x / 2 + 0.05) & (np.abs(cen[:, 2] - c[2]) < r * 0.6) & (cen[:, 1] > c[1])
        clear = float((cen[sel][:, 1] - (c[1] + r)).min()) if sel.any() else None
        # body vertices inside the tire cylinder (interpenetration)
        bv = allv - c
        inside = int(((np.hypot(bv[:, 1], bv[:, 2]) < r * 0.98) & (np.abs(bv[:, 0]) < width_x / 2 * 0.98)).sum())
        wheels[w] = dict(radius=round(float(r), 3), tire_segments=len(angs), rim_segments=len(rangs),
                         arch_clear=None if clear is None else round(clear, 3), body_verts_in_tire=inside,
                         center=[round(float(x), 3) for x in c], width=round(float(width_x), 3))
    # glass: what is right behind each glass triangle (inward)
    glass = np.concatenate([T for name, T, N, rgb in parts if role(name) == "Glass"]) if "Glass" in R else np.zeros((0, 3, 3))
    nonglass = np.concatenate([T for name, T, N, rgb in parts if role(name) != "Glass" and not role(name).startswith("Wheel")])
    gc = glass.mean(1)
    gn = np.cross(glass[:, 1] - glass[:, 0], glass[:, 2] - glass[:, 0]); gn /= np.linalg.norm(gn, axis=1, keepdims=True) + 1e-12
    centre = (lo + hi) / 2
    behind, dists = 0, []
    for k in range(len(glass)):
        d = gn[k] if np.dot(gn[k], centre - gc[k]) > 0 else -gn[k]
        t = ray_hits(gc[k], d, nonglass, 3.0)
        if len(t):
            dists.append(float(t.min()))
            if t.min() < 0.03: behind += 1
    glass_area = float(np.linalg.norm(np.cross(glass[:, 1] - glass[:, 0], glass[:, 2] - glass[:, 0]), axis=1).sum() / 2)
    # cabin: inner box under the glass
    gv = glass.reshape(-1, 3)
    if len(gv):
        zlo, zhi = np.percentile(gv[:, 2], 10), np.percentile(gv[:, 2], 90)
        ylo = gv[:, 1].min()
    else:
        zlo, zhi, ylo = lo[2], hi[2], centre[1]
    roof = hi[1]
    cen = nonglass.mean(1)
    half_w = (hi[0] - lo[0]) / 2
    inner = (np.abs(cen[:, 0] - centre[0]) < half_w * 0.6) & (cen[:, 1] > ylo - 0.35) & (cen[:, 1] < roof - 0.12) & (cen[:, 2] > zlo) & (cen[:, 2] < zhi)
    # vertical ray from the cabin middle: what is below/above (floor/roof) and to the side
    mid = np.array([centre[0], (ylo + roof) / 2, (zlo + zhi) / 2])
    hits = {}
    for nm, d in (("down", [0, -1, 0]), ("up", [0, 1, 0]), ("left", [-1, 0, 0]), ("right", [1, 0, 0]), ("front", [0, 0, -1]), ("back", [0, 0, 1])):
        t = ray_hits(mid, np.array(d, float), np.concatenate([nonglass, glass]), 5)
        hits[nm] = len(t)
    # boundary edges of the non-wheel mesh (open holes)
    from collections import Counter
    ec = Counter()
    for tri in body:
        ks = [tuple(np.round(v, 4)) for v in tri]
        for a, b in ((0, 1), (1, 2), (2, 0)):
            ec[tuple(sorted((ks[a], ks[b])))] += 1
    open_edges = sum(1 for e, n in ec.items() if n == 1)
    # sub-objects in Detail / Paint parts
    comps = []
    for name, T, N, rgb in parts:
        rl = role(name)
        if rl.startswith("Wheel"): continue
        for g in components(T):
            sub = T[g].reshape(-1, 3)
            a, b = sub.min(0), sub.max(0)
            comps.append(dict(part=name.split("_", 1)[1], tris=len(g), lo=[round(float(x), 2) for x in a], hi=[round(float(x), 2) for x in b]))
    out[car] = dict(
        dims=[round(float(x), 2) for x in hi - lo], lo=[round(float(x), 2) for x in lo], hi=[round(float(x), 2) for x in hi],
        tris=j["Triangles"], roles={k: j["RoleTriangles"][k] for k in j["RoleTriangles"]},
        smooth_corner_frac=round(smooth_frac, 3), wheels=wheels,
        glass_tris=len(glass), glass_area=round(glass_area, 2), glass_with_body_right_behind=behind,
        glass_inward_hit_median=round(float(np.median(dists)), 3) if dists else None,
        cabin_inner_tris=int(inner.sum()), cabin_rays=hits, open_edges=open_edges, comps=comps,
        cabin_box=dict(z=[round(float(zlo), 2), round(float(zhi), 2)], y=[round(float(ylo), 2), round(float(roof), 2)]),
    )
json.dump(out, open(sys.argv[2], "w"), indent=1)
for car, o in out.items():
    w = o["wheels"]["FL"]
    print(f"{car:9s} tris {o['tris']} dims {o['dims']} smooth {o['smooth_corner_frac']} tireSeg {w['tire_segments']} rimSeg {w['rim_segments']} "
          f"arch {[o['wheels'][k]['arch_clear'] for k in w and o['wheels']]} inTire {[o['wheels'][k]['body_verts_in_tire'] for k in o['wheels']]} "
          f"glass {o['glass_tris']}t {o['glass_area']}m2 behind {o['glass_with_body_right_behind']} med {o['glass_inward_hit_median']} "
          f"cabinTris {o['cabin_inner_tris']} rays {o['cabin_rays']} open {o['open_edges']} comps {len(o['comps'])}")
