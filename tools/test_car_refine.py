#!/usr/bin/env python3
"""test_car_refine.py — checks the stage 2 car refinement (tools/car_refine.py): assets/cars/SOLARA_Cars.glb against
the original assets/cars/SOLARA_Cars_base.glb.
  [1] untouched: every lamp, glass and Detail part (exhausts, grilles, plates, mirror arms, spoilers) is identical
      (positions and normals, triangle by triangle)
  [2] body paint: vertex positions identical (no shape change, nothing can poke through); every normal is unit, on the
      outer side of its face and within the crease angle; corners the original artist had smoothed are unchanged
  [3] design edges stay sharp: two body faces meeting at more than CREASE + 5 degrees never share a normal
  [4] smoother: in every car the body has at least as many smooth-shaded corners as before (and more in total)
  [5] tyres: same outer radius, width and wheel centre as before; 20-sided outline (was 10/12); the dark recess between
      the rim spokes is the original; vertical size = 2 x radius (the game's wheel calibration)
  [6] no holes: rays along the axle through the rim / tyre joint and the sidewall always hit the wheel
  [7] every new triangle's winding agrees with its normals (no inside-out faces)
  [8] triangle budget: at most +700 per car (about +30 %), at most 3700 per car
  [9] cars.json matches the file (triangle counts, part names, wheel radius)
  [10] faces whose winding pointed inward (drawn as small holes in Roblox) are fixed on body paint and rims
Usage: python3 -I tools/test_car_refine.py
"""
import json
import math
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
import cosmo_cars_convert as C  # noqa: E402
import car_refine as R  # noqa: E402

fails = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        fails.append(name)


base_raw = C.read_glb(R.BASE_GLB)
new = C.read_glb(R.OUT_GLB)
# the refiner first flips inside-out body / rim faces ([10] checks that); compare against the base after that step
base = {}
for car, parts in base_raw.items():
    fixed = [[n, T.astype(np.float64).copy(), N.astype(np.float64).copy(), rgb] for n, T, N, rgb in parts]
    R.fix_winding(fixed)
    base[car] = [tuple(p) for p in fixed]
info = json.load(open(R.OUT_JSON))
role = R.role_of


def by_name(parts):
    return {n: (T.astype(np.float64), N.astype(np.float64), rgb) for n, T, N, rgb in parts}


def face_normals(T):
    g = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)


# [1] untouched parts
bad = []
for car in base:
    b, n = by_name(base[car]), by_name(new[car])
    for name, (T, N, rgb) in b.items():
        r = role(name)
        if r in R.SMOOTH_ROLES or r.startswith("Wheel"):
            continue
        if name not in n:
            bad.append(f"{car}: {name} missing")
            continue
        T2, N2, rgb2 = n[name]
        if T2.shape != T.shape or np.abs(T2 - T).max() > 1e-5 or np.abs(N2 - N).max() > 1e-4 or tuple(rgb2) != tuple(rgb):
            bad.append(f"{car}: {name} changed")
check("[1] lamps, glass and Detail parts (exhausts, grilles, plates, trim) unchanged", not bad, "; ".join(bad[:4]))

# [2] body paint
cos_c = math.cos(math.radians(R.CREASE))
cos_flat = math.cos(math.radians(R.FLAT_TOL))
bad, kept_bad = [], []
for car in base:
    b, n = by_name(base[car]), by_name(new[car])
    for name, (T, N, rgb) in b.items():
        if role(name) not in R.SMOOTH_ROLES:
            continue
        T2, N2, _ = n[name]
        if T2.shape != T.shape or np.abs(T2 - T).max() > 1e-5:
            bad.append(f"{car}: {name} moved")
            continue
        fn = face_normals(T)
        area = np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1) / 2
        good = (np.linalg.norm(fn, axis=1) > 0.5) & (area > 1e-6)  # ignore zero-area slivers (no normal at all)
        ln = np.linalg.norm(N2, axis=2)
        d = (N2 * fn[:, None, :]).sum(2)
        No = N / np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-12)
        changed = (np.abs(N2 - No).max(2) > 1e-4) & good[:, None]  # corners the refiner gave a new normal
        if np.abs(ln[good] - 1).max(initial=0) > 1e-3 or (d[changed] < cos_c - 1e-3).any():
            bad.append(f"{car}: {name} new normal off (min dot {d[changed].min(initial=1):.3f})")
        artist = (No * fn[:, None, :]).sum(2) < cos_flat
        artist &= good[:, None]
        if (np.abs(N2 - No)[artist].max(initial=0) > 1e-3):
            kept_bad.append(f"{car}: {name}")
check("[2] body: same vertex positions; new normals unit and within the crease of their face; artist-smoothed corners unchanged",
      not bad and not kept_bad, "; ".join((bad + kept_bad)[:4]))

# [3] sharp design edges stay sharp
bad = []
for car in new:
    body = [(T, N) for nm, T, N, _ in new[car] if role(nm) in R.SMOOTH_ROLES]
    T = np.concatenate([t for t, _ in body]).astype(np.float64)
    N = np.concatenate([nn for _, nn in body]).astype(np.float64)
    fn = face_normals(T)
    keys = np.round(T.reshape(-1, 3), 5)
    _, vid = np.unique(keys, axis=0, return_inverse=True)
    vid = vid.reshape(-1, 3)
    edges = {}
    for f in range(len(T)):
        for k in range(3):
            e = tuple(sorted((int(vid[f, k]), int(vid[f, (k + 1) % 3]))))
            edges.setdefault(e, []).append((f, k))
    lim = math.cos(math.radians(R.CREASE + 5))
    shared_sharp = 0
    for e, lst in edges.items():
        if len(lst) != 2:
            continue
        (f, k), (g, kk) = lst
        if np.dot(fn[f], fn[g]) > lim or np.linalg.norm(fn[f]) < 0.5 or np.linalg.norm(fn[g]) < 0.5:
            continue
        for v in e:
            cf = [i for i in range(3) if vid[f, i] == v][0]
            cg = [i for i in range(3) if vid[g, i] == v][0]
            if np.dot(N[f, cf], N[g, cg]) > 0.9995:
                shared_sharp += 1
    # the original may already have smoothed some sharp edges (artist's choice): only count new ones
    body_b = [(t, nn) for nm, t, nn, _ in base[car] if role(nm) in R.SMOOTH_ROLES]
    Nb = np.concatenate([nn for _, nn in body_b]).astype(np.float64)
    before = 0
    for e, lst in edges.items():
        if len(lst) != 2:
            continue
        (f, k), (g, kk) = lst
        if np.dot(fn[f], fn[g]) > lim or np.linalg.norm(fn[f]) < 0.5 or np.linalg.norm(fn[g]) < 0.5:
            continue
        for v in e:
            cf = [i for i in range(3) if vid[f, i] == v][0]
            cg = [i for i in range(3) if vid[g, i] == v][0]
            if np.dot(Nb[f, cf], Nb[g, cg]) > 0.9995:
                before += 1
    if shared_sharp > before:
        bad.append(f"{car}: {shared_sharp - before} sharp corners smoothed")
check(f"[3] edges sharper than {R.CREASE + 5:.0f}° stay sharp (no new smoothing across them)", not bad, "; ".join(bad[:4]))

# [4] smoother
rows, worse = [], []
tot_b = tot_n = 0
for car in base:
    def smooth_count(parts):
        c = 0
        for nm, T, N, _ in parts:
            if role(nm) not in R.SMOOTH_ROLES:
                continue
            fn = face_normals(T.astype(np.float64))
            Nn = N / np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-12)
            c += int(((Nn * fn[:, None, :]).sum(2) < cos_flat).sum())
        return c
    sb, sn = smooth_count(base[car]), smooth_count(new[car])
    tot_b += sb
    tot_n += sn
    rows.append(f"{car} {sb}->{sn}")
    if sn < sb:
        worse.append(car)
check("[4] body paint has at least as many smooth-shaded corners in every car, more in total",
      not worse and tot_n > tot_b, f"{tot_b} -> {tot_n} corners; " + ", ".join(rows[:6]) + " ...")

# [5] tyres
bad, segs = [], set()
for car in base:
    b, n = by_name(base[car]), by_name(new[car])
    for w in R.WHEELS:
        tb = [v for k, v in b.items() if role(k) == f"Wheel_{w}_Tire"][0]
        rb = [v for k, v in b.items() if role(k) == f"Wheel_{w}_Rim"][0]
        tn = [v for k, v in n.items() if role(k) == f"Wheel_{w}_Tire"][0]
        rn = [v for k, v in n.items() if role(k) == f"Wheel_{w}_Rim"][0]
        vb = np.vstack([tb[0].reshape(-1, 3), rb[0].reshape(-1, 3)])
        vn = np.vstack([tn[0].reshape(-1, 3), rn[0].reshape(-1, 3)])
        cb, cn = (vb.min(0) + vb.max(0)) / 2, (vn.min(0) + vn.max(0)) / 2
        ax_b, r_b, _ = R.radial(tb[0].reshape(-1, 3), cb)
        ax_n, r_n, ang_n = R.radial(tn[0].reshape(-1, 3), cb)
        outer = np.unique(np.round(np.degrees(ang_n[r_n > r_n.max() - 1e-4]) % 360, 1))
        segs.add(len(outer))
        ext = tn[0][:, :, 1].max() - tn[0][:, :, 1].min()
        if np.abs(cb - cn).max() > 1e-4:
            bad.append(f"{car} {w}: centre moved {np.abs(cb - cn).max():.5f}")
        if abs(r_b.max() - r_n.max()) > 1e-3 or abs(np.abs(ax_b).max() - np.abs(ax_n).max()) > 1e-3:
            bad.append(f"{car} {w}: radius/width {r_b.max():.3f}/{np.abs(ax_b).max():.3f} -> {r_n.max():.3f}/{np.abs(ax_n).max():.3f}")
        if len(outer) != R.TIRE_SEGMENTS:
            bad.append(f"{car} {w}: {len(outer)} sides")
        if abs(ext - 2 * r_n.max()) > 1e-3:
            bad.append(f"{car} {w}: height {ext:.3f} vs 2r {2 * r_n.max():.3f}")
        # recess kept: every base tyre face below the rim radius exists in the new tyre
        r_rim = R.radial(rb[0].reshape(-1, 3), cb)[1].max()
        _, rt, _ = R.radial(tb[0], cb)
        recess = tb[0][~((rt.min(1) >= r_rim - 1e-3) & (rt.max(1) > r_rim + 1e-3))]
        flat_new = tn[0].reshape(len(tn[0]), 9)
        missing = sum(1 for t in recess if np.abs(flat_new - t.reshape(9)).max(1).min() > 1e-4)
        if missing:
            bad.append(f"{car} {w}: {missing} recess faces lost")
check("[5] tyres: same radius, width and centre; 20-sided; spoke recess kept; height = 2 x radius",
      not bad and segs == {R.TIRE_SEGMENTS}, "; ".join(bad[:4]) or f"outline sides {sorted(segs)}")

# [6] no holes at the rim / tyre joint and in the sidewall
bad = []
for car in new:
    n = by_name(new[car])
    for w in R.WHEELS:
        wt = np.concatenate([v[0] for k, v in n.items() if role(k).startswith(f"Wheel_{w}_")])
        v = wt.reshape(-1, 3)
        c = (v.min(0) + v.max(0)) / 2
        out = 1.0 if c[0] > 0 else -1.0
        rim = [v2 for k, v2 in n.items() if role(k) == f"Wheel_{w}_Rim"][0][0]
        r_rim = R.radial(rim.reshape(-1, 3), c)[1].max()
        tread = R.radial(wt.reshape(-1, 3), c)[1].max()
        misses = 0
        for a in np.linspace(0, 2 * math.pi, 73)[:-1]:
            for r in np.linspace(r_rim * 0.93, tread * 0.97, 9):
                o = np.array([c[0] + out * 0.6, c[1] + r * math.cos(a), c[2] + r * math.sin(a)])
                if R.first_hit(o, np.array([-out, 0.0, 0.0]), wt, 1.2) is None:
                    misses += 1
        if misses:
            bad.append(f"{car} {w}: {misses} rays through")
check("[6] no see-through gaps at the rim / tyre joint or in the sidewall (648 rays per wheel)", not bad, "; ".join(bad[:4]))

# [7] winding
bad = []
for car in new:
    for nm, T, N, _ in new[car]:
        if not (role(nm).startswith("Wheel") or role(nm) in R.SMOOTH_ROLES):
            continue
        T = T.astype(np.float64)
        g = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        big = np.linalg.norm(g, axis=1) / 2 > 1e-6  # zero-area slivers have no direction
        agree = ((g * N.sum(1)).sum(1) > 0)[big]
        if agree.mean() < 0.999:
            bad.append(f"{car} {nm}: {1 - agree.mean():.1%} inside-out")
check("[7] winding agrees with normals on every changed part", not bad, "; ".join(bad[:4]))

# [8] budget
rows, bad = [], []
for car in new:
    tb = sum(len(T) for _, T, _, _ in base[car])
    tn = sum(len(T) for _, T, _, _ in new[car])
    rows.append(f"{car} +{tn - tb}")
    if tn - tb > 700 or tn > 3700:
        bad.append(f"{car} {tb}->{tn}")
check("[8] triangle budget (+700 / 3700 per car)", not bad, ", ".join(rows))

# [10] winding fixed on body paint and rims (Detail parts left as they were)
rows, bad = [], []
for car in new:
    nb = nn = 0
    for parts, which in ((base_raw[car], "b"), (new[car], "n")):
        for nm, T, N, _ in parts:
            r = role(nm)
            if not (r in R.SMOOTH_ROLES or (r.startswith("Wheel") and r.endswith("_Rim"))):
                continue
            T = T.astype(np.float64)
            g = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
            k = int((((g * N.sum(1)).sum(1) < 0) & (np.linalg.norm(g, axis=1) > 1e-9)).sum())
            if which == "b":
                nb += k
            else:
                nn += k
    if nb:
        rows.append(f"{car} {nb}")
    if nn:
        bad.append(f"{car} {nn} left")
check("[10] inside-out faces on body paint and rims fixed (were drawn as small holes)", not bad,
      "fixed: " + ", ".join(rows) + ("; " + "; ".join(bad) if bad else ""))

# [9] cars.json
bad = []
for car in new:
    j = info[car]
    tn = sum(len(T) for _, T, _, _ in new[car])
    names = sorted(nm for nm, _, _, _ in new[car])
    tire = np.vstack([T.reshape(-1, 3) for nm, T, _, _ in new[car] if role(nm) == "Wheel_FL_Tire"])
    if j["Triangles"] != tn or j["PartNames"] != names or abs(j["WheelRadiusM"] - (tire[:, 1].max() - tire[:, 1].min()) / 2) > 1e-3:
        bad.append(car)
check("[9] cars.json matches the file", not bad, ", ".join(bad))

print()
print("ALL PASS" if not fails else f"{len(fails)} FAILED: " + "; ".join(fails))
sys.exit(1 if fails else 0)
