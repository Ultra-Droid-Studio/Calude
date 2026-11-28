#!/usr/bin/env python3
"""
car_refine.py — Car pack stage 2: smoother look for the 12 cars WITHOUT changing their shape or their details.

Input : assets/cars/SOLARA_Cars_base.glb  (the original look, written by cosmo_cars_convert.py)
Output: assets/cars/SOLARA_Cars.glb       (what the game uploads), assets/cars/cars.json (updated),
        docs/cars_refine_preview.png      (before / after, smooth-shaded software render)

What changes
  * Body paint (roles Paint, Paint2): new shading normals with a crease angle. Faces meeting at less than CREASE
    degrees are shaded as one smooth surface; sharper edges stay sharp (design lines, window frames, box shapes).
    Vertex positions are NOT touched: the silhouette and every joint with the other parts stay exactly as they were.
  * Tyres: the outer tyre (rim joint -> sidewall -> shoulder -> tread) is rebuilt as a surface of revolution with
    TIRE_SEGMENTS segments (was 10, Brava 12) from each car's own tyre profile (same radius, width, colour), with smooth
    normals over the shoulder. The dark recess between the rim spokes (part of the tyre mesh) is kept as it was.
  * Rims: the original rim is kept; a thin round lip (same colour) on the outer face hides its 10-sided outline.
  * Wheel arches: where a car has no wheel well (the body above the tyre is the back of the outer shell), a dark
    liner is added inside the arch, shaped from rays against the car's own body so that it always stays inside it.
    All 12 current cars already have wheel wells, so none is added today.
  * Winding fix: body / rim faces whose triangle winding points inward while their normals point outward were not
    drawn from outside in Roblox (small holes on roof-rack slats and wheel-arch edges): their winding is flipped.
What does NOT change (byte for byte): lamps (head, tail, reverse, indicators, sirens), glass, every "Detail" part
(exhausts, grilles, plates, mirror arms, spoilers, trim), part names of existing parts, wheel centres.

Usage: python3 -I tools/car_refine.py
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cosmo_cars_convert as C  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE_GLB = os.path.join(ROOT, "assets", "cars", "SOLARA_Cars_base.glb")
OUT_GLB = os.path.join(ROOT, "assets", "cars", "SOLARA_Cars.glb")
OUT_JSON = os.path.join(ROOT, "assets", "cars", "cars.json")
OUT_PREVIEW = os.path.join(ROOT, "docs", "cars_refine_preview.png")

CREASE = 50.0  # degrees: flat body corners are smoothed with neighbours closer than this (box edges stay sharp)
FLAT_TOL = 2.0  # degrees: a corner whose normal is within this of its face normal is flat (gets smoothed)
SNAP = 12.0  # degrees: a new normal this close to a neighbouring smooth group joins it
TIRE_SEGMENTS = 20
TIRE_CREASE = 55.0  # degrees: tyre profile corners below this are shaded round (shoulder chamfer ~45°)
ARCH_GAP = 0.02  # m: liner at least this far above the tyre
LINER_HEX = "1a1a1a"
LIP_PROUD = 0.004  # m: rim lip in front of the rim face (no z-fighting)
SMOOTH_ROLES = ("Paint", "Paint2")
AVERAGE_ROLES = ("Paint", "Paint2", "Detail")  # faces that may take part in a body vertex's average
WHEELS = ("FL", "FR", "RL", "RR")


def role_of(name):
    return name.split("_", 1)[1].rsplit("_", 1)[0]


def unit(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


# ---------------------------------------------------------------------------------------------------------------
# body: crease-angle smooth normals
def smooth_body(parts):
    """parts: list of [name, T, N, rgb] (mutable). Rewrites N of Paint / Paint2 parts in place."""
    faces = []  # (part index, face index)
    for pi, (name, T, N, rgb) in enumerate(parts):
        if role_of(name) in AVERAGE_ROLES:
            for fi in range(len(T)):
                faces.append((pi, fi))
    tri = np.array([parts[pi][1][fi] for pi, fi in faces], dtype=np.float64)
    cr = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    area2 = np.linalg.norm(cr, axis=1)
    fn = cr / np.maximum(area2, 1e-12)[:, None]
    valid = area2 > 1e-10
    # corner angles (weights)
    ang = np.zeros((len(tri), 3))
    for k in range(3):
        a = tri[:, (k + 1) % 3] - tri[:, k]
        b = tri[:, (k + 2) % 3] - tri[:, k]
        ang[:, k] = np.arccos(np.clip((unit(a) * unit(b)).sum(1), -1, 1))
    # weld by position
    keys = np.round(tri.reshape(-1, 3), 5)
    _, vid = np.unique(keys, axis=0, return_inverse=True)
    vid = vid.reshape(-1, 3)
    incident = {}
    for f in range(len(tri)):
        if not valid[f]:
            continue
        for k in range(3):
            incident.setdefault(int(vid[f, k]), []).append((f, k))
    cos_c = math.cos(math.radians(CREASE))
    cos_flat = math.cos(math.radians(FLAT_TOL))
    cos_snap = math.cos(math.radians(SNAP))
    orig = {}
    for f, (pi, fi) in enumerate(faces):
        N = parts[pi][2]
        for k in range(3):
            orig[(f, k)] = N[fi, k] / max(np.linalg.norm(N[fi, k]), 1e-12)
    changed = kept = 0
    for f, (pi, fi) in enumerate(faces):
        name, T, N, rgb = parts[pi]
        if role_of(name) not in SMOOTH_ROLES or not valid[f]:
            continue
        for k in range(3):
            o = orig[(f, k)]
            if np.dot(o, fn[f]) < cos_flat:
                kept += 1  # the artist already smoothed this corner: keep exactly
                continue
            incident_here = incident[int(vid[f, k])]
            acc = np.zeros(3)
            for g, kk in incident_here:
                if np.dot(fn[f], fn[g]) >= cos_c:
                    acc += fn[g] * ang[g, kk]
            n = acc / max(np.linalg.norm(acc), 1e-12)
            # join a neighbouring smooth group (artist's) when it is close: no new seam next to it
            best, best_dot = None, cos_snap
            for g, kk in incident_here:
                if g == f or role_of(parts[faces[g][0]][0]) not in SMOOTH_ROLES:
                    continue
                og = orig[(g, kk)]
                if np.dot(og, fn[g]) < cos_flat and np.dot(og, n) >= best_dot and np.dot(og, fn[f]) >= cos_c:
                    best, best_dot = og, float(np.dot(og, n))
            if best is not None:
                n = best
            if np.dot(n, o) < 1 - 1e-9:
                changed += 1
            N[fi, k] = n
    return changed, kept


# ---------------------------------------------------------------------------------------------------------------
# tyres
def wheel_frame(parts, w):
    tire_i = [i for i, p in enumerate(parts) if role_of(p[0]) == f"Wheel_{w}_Tire"][0]
    rim_i = [i for i, p in enumerate(parts) if role_of(p[0]) == f"Wheel_{w}_Rim"][0]
    v = np.vstack([parts[tire_i][1].reshape(-1, 3), parts[rim_i][1].reshape(-1, 3)])
    centre = (v.min(0) + v.max(0)) / 2
    return tire_i, rim_i, centre


def radial(P, c):
    rel = P - c
    return rel[..., 0], np.hypot(rel[..., 1], rel[..., 2]), np.arctan2(rel[..., 1], rel[..., 2])


def tire_profile(T, c, r_rim):
    """outer profile of the tyre on one side: list of (axial >= 0, radius) from the rim joint to the tread centre"""
    ax, r, _ = radial(T.reshape(-1, 3), c)
    pts = sorted({(round(abs(float(a)), 4), round(float(b), 4)) for a, b in zip(ax, r) if b >= r_rim - 1e-3})
    pts.sort(key=lambda p: (p[1], -p[0]))
    clean = []
    for p in pts:
        if clean and abs(p[0] - clean[-1][0]) < 0.003 and abs(p[1] - clean[-1][1]) < 0.003:
            continue
        clean.append(p)
    # the tread: keep only its outermost axial point (flat tread, one segment across)
    r_max = max(p[1] for p in clean)
    tread = [p for p in clean if p[1] > r_max - 1e-3]
    side = [p for p in clean if p[1] <= r_max - 1e-3]
    edge = max(tread, key=lambda p: p[0])
    return side + [edge]


def revolve(profile_side, c, segments, r_start_outer, r_start_inner, outer_sign):
    """Full tyre surface: outer side profile -> tread -> inner side profile, revolved. profile_side: (axial, radius)
    from the rim joint to the tread edge. The first ring starts at r_start_* (outer / inner face). Returns (T, N)."""
    # one cross-section from the outer rim joint over the tread to the inner rim joint (axial signed, outer = +)
    sec = [(a, r) for a, r in profile_side]
    outer = [(a, r) for a, r in sec]
    outer[0] = (outer[0][0], r_start_outer)
    inner = [(-a, r) for a, r in reversed(sec)]
    inner[-1] = (inner[-1][0], r_start_inner)
    line = outer + inner  # outer joint ... outer tread edge, inner tread edge ... inner joint
    # per-point normals in the (axial, radial) plane, crease-aware: each segment's outward normal
    segs = []
    for i in range(len(line) - 1):
        (a0, r0), (a1, r1) = line[i], line[i + 1]
        t = np.array([a1 - a0, r1 - r0])
        t /= max(np.linalg.norm(t), 1e-12)
        segs.append(np.array([t[1], -t[0]]))  # one of the two in-plane normals; oriented below
    # make every segment normal point outward of the tyre body: away from the tyre's mid-surface (0, r_mid)
    r_mid = (min(r for _, r in line) + max(r for _, r in line)) / 2
    for i in range(len(segs)):
        (a0, r0), (a1, r1) = line[i], line[i + 1]
        mid = np.array([(a0 + a1) / 2, (r0 + r1) / 2])
        if np.dot(segs[i], mid - np.array([0.0, r_mid])) < 0:
            segs[i] = -segs[i]
    cos_t = math.cos(math.radians(TIRE_CREASE))

    def point_normal(i, seg):
        """normal of profile point i as seen from segment seg (smoothed with the neighbour if below the crease)"""
        other = seg - 1 if i == seg else seg + 1
        n = segs[seg]
        if 0 <= other < len(segs) and np.dot(segs[seg], segs[other]) >= cos_t:
            n = unit(segs[seg] + segs[other])
        return n

    th = np.linspace(0, 2 * math.pi, segments, endpoint=False)  # 0 = top (vertex at top and bottom: even count)
    T, N = [], []
    for s in range(len(line) - 1):
        for j in range(segments):
            q = []
            for (i, tj) in ((s, j), (s + 1, j), (s + 1, (j + 1) % segments), (s, (j + 1) % segments)):
                a, r = line[i]
                ang = th[tj]
                dirv = np.array([0.0, math.cos(ang), math.sin(ang)])
                p = c + np.array([a * outer_sign, 0, 0]) + dirv * r
                nn = point_normal(i, s)
                n3 = np.array([nn[0] * outer_sign, 0, 0]) + dirv * nn[1]
                q.append((p, unit(n3)))
            for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                P = np.array([x[0] for x in tri])
                Nn = np.array([x[1] for x in tri])
                gn = np.cross(P[1] - P[0], P[2] - P[0])
                if np.linalg.norm(gn) < 1e-12:
                    continue
                if np.dot(gn, Nn.sum(0)) < 0:
                    P, Nn = P[[0, 2, 1]], Nn[[0, 2, 1]]
                T.append(P)
                N.append(Nn)
    return np.array(T), np.array(N)


def rim_lip(c, outer_sign, x_face, r_in, r_out, segments, proud=LIP_PROUD):
    th = np.linspace(0, 2 * math.pi, segments, endpoint=False)
    x = c[0] + outer_sign * (x_face + proud)
    n = np.array([outer_sign, 0.0, 0.0])
    T, N = [], []
    for j in range(segments):
        a0, a1 = th[j], th[(j + 1) % segments]
        d0 = np.array([0, math.cos(a0), math.sin(a0)])
        d1 = np.array([0, math.cos(a1), math.sin(a1)])
        base = np.array([x, c[1], c[2]])
        q = [base + d0 * r_in, base + d0 * r_out, base + d1 * r_out, base + d1 * r_in]
        for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
            P = np.array(tri)
            if np.dot(np.cross(P[1] - P[0], P[2] - P[0]), n) < 0:
                P = P[[0, 2, 1]]
            T.append(P)
            N.append(np.array([n, n, n]))
    return np.array(T), np.array(N)


def refine_wheel(parts, w, segments):
    tire_i, rim_i, c = wheel_frame(parts, w)
    name_t, Tt, Nt, rgb_t = parts[tire_i]
    name_r, Tr, Nr, rgb_r = parts[rim_i]
    _, r_rim_all, _ = radial(Tr.reshape(-1, 3), c)
    r_rim = float(r_rim_all.max())
    ax_r, _, ang_r = radial(Tr.reshape(-1, 3), c)
    n_rim = len(np.unique(np.round(np.degrees(ang_r[r_rim_all > r_rim * 0.97]) % 360, 0)))
    outer_sign = 1.0 if c[0] > 0 else -1.0
    _, rt, _ = radial(Tt, c)  # (n, 3) radii per corner
    outer_face = (rt.min(1) >= r_rim - 1e-3) & (rt.max(1) > r_rim + 1e-3)
    keep_T, keep_N = Tt[~outer_face], Nt[~outer_face]
    prof = tire_profile(Tt[outer_face], c, r_rim)
    joint_axial = prof[0][0]
    inscribed = r_rim * math.cos(math.pi / max(n_rim, 3)) * 0.985
    newT, newN = revolve(prof, c, segments, r_rim, inscribed, outer_sign)
    half_w = max(a for a, _ in prof)
    proud = min(LIP_PROUD, max((half_w - joint_axial) / 2, 0.0))  # never wider than the tyre (wheel centre stays)
    lipT, lipN = rim_lip(c, outer_sign, joint_axial, inscribed, r_rim, segments, proud)
    parts[tire_i] = [name_t, np.concatenate([keep_T, newT]), np.concatenate([keep_N, newN]), rgb_t]
    parts[rim_i] = [name_r, np.concatenate([Tr, lipT]), np.concatenate([Nr, lipN]), rgb_r]
    tread = max(r for _, r in prof)
    return dict(centre=c, tread=tread, half_width=half_w, rim=r_rim, rim_segments=n_rim, joint=joint_axial,
                inscribed=inscribed, outer_sign=outer_sign, kept=int((~outer_face).sum()), profile=prof)


# ---------------------------------------------------------------------------------------------------------------
# wheel arch liners
def ray_hits(orig, d, tris, maxt):
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2)
    det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    s = orig - v0
    u = (s * p).sum(1) * inv
    q = np.cross(s, e1)
    v = (q * d).sum(1) * inv
    t = (e2 * q).sum(1) * inv
    hit = ok & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t > 1e-5) & (t < maxt)
    return t[hit]


def first_hit(orig, d, tris, maxt):
    t = ray_hits(orig, d, tris, maxt)
    return float(t.min()) if len(t) else None


def first_hit_facing(orig, d, tris, maxt):
    """(distance, True if the hit face looks back at the ray origin = a visible surface, not the back of a shell)"""
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2)
    det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    s = orig - v0
    u = (s * p).sum(1) * inv
    q = np.cross(s, e1)
    v = (q * d).sum(1) * inv
    t = (e2 * q).sum(1) * inv
    hit = ok & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t > 1e-5) & (t < maxt)
    if not hit.any():
        return None, False
    i = np.nonzero(hit)[0][np.argmin(t[hit])]
    gn = np.cross(e1[i], e2[i])
    return float(t[i]), bool(np.dot(gn, d) < 0)


def arch_liner(body_tris, wheel, segments_deg=10, max_deg=100):
    c, R, hw, out = wheel["centre"], wheel["tread"], wheel["half_width"], wheel["outer_sign"]
    # the model may already have a wheel well (a surface above the tyre facing it): then nothing to add
    _, facing = first_hit_facing(np.array([c[0], c[1], c[2]]), np.array([0.0, 1.0, 0.0]), body_tris, 2.5 * R)
    if facing:
        return None
    xs = [c[0] - out * (hw + 0.03) + out * k * (2 * hw + 0.03) / 4 for k in range(5)]
    angles = list(range(-max_deg, max_deg + 1, segments_deg))
    rho = {}
    for a in angles:
        th = math.radians(a)
        d = np.array([0.0, math.cos(th), -math.sin(th)])  # a > 0: toward the front (-Z)
        dists = []
        for x in xs:
            t = first_hit(np.array([x, c[1], c[2]]), d, body_tris, 2.5 * R)
            dists.append(t)
        if any(t is None for t in dists):
            rho[a] = None
            continue
        r = min(dists) - 0.012
        rho[a] = r if r >= R + ARCH_GAP else None
    if rho.get(0) is None:
        return None
    lo = 0
    while lo - segments_deg in rho and rho[lo - segments_deg] is not None:
        lo -= segments_deg
    hi = 0
    while hi + segments_deg in rho and rho[hi + segments_deg] is not None:
        hi += segments_deg
    run = list(range(lo, hi + 1, segments_deg))
    if len(run) < 3:
        return None

    def point(x, a, r):
        th = math.radians(a)
        return np.array([x, c[1] + r * math.cos(th), c[2] - r * math.sin(th)])

    # outer edge: as far out as still under the body (ray along the radial direction hits the body shortly)
    x_in = c[0] - out * (hw + 0.03)
    x_out = c[0] + out * hw
    for e in (0.10, 0.06, 0.03, 0.0):
        x = c[0] + out * (hw + e)
        ok = True
        for a in run:
            th = math.radians(a)
            d = np.array([0.0, math.cos(th), -math.sin(th)])
            t = first_hit(point(x, a, rho[a] - 0.002), d, body_tris, 0.3)
            if t is None:
                ok = False
                break
        if ok:
            x_out = x
            break
    T, N = [], []
    for i in range(len(run) - 1):
        a0, a1 = run[i], run[i + 1]
        q = [point(x_in, a0, rho[a0]), point(x_out, a0, rho[a0]), point(x_out, a1, rho[a1]), point(x_in, a1, rho[a1])]
        nq = []
        for a in (a0, a0, a1, a1):
            th = math.radians(a)
            nq.append(-np.array([0.0, math.cos(th), -math.sin(th)]))  # faces the wheel
        for idx in ((0, 1, 2), (0, 2, 3)):
            P = np.array([q[k] for k in idx])
            Nn = np.array([nq[k] for k in idx])
            if np.dot(np.cross(P[1] - P[0], P[2] - P[0]), Nn.sum(0)) < 0:
                P, Nn = P[[0, 2, 1]], Nn[[0, 2, 1]]
            T.append(P)
            N.append(Nn)
    return dict(T=np.array(T), N=np.array(N), run=(lo, hi), x_in=x_in, x_out=x_out,
                rho_min=min(rho[a] for a in run), R=R)


# ---------------------------------------------------------------------------------------------------------------
def fix_winding(parts):
    """Faces whose winding is opposite to their (correct, outward) shading normals are culled from the side they are
    seen from in Roblox: small holes (roof-rack slats, arch edges). Flip their winding on body paint and rims."""
    flipped = 0
    for p in parts:
        name, T, N, rgb = p
        r = role_of(name)
        if not (r in SMOOTH_ROLES or (r.startswith("Wheel") and r.endswith("_Rim"))):
            continue
        g = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        bad = ((g * N.sum(1)).sum(1) < 0) & (np.linalg.norm(g, axis=1) > 1e-10)
        if bad.any():
            T[bad] = T[bad][:, [0, 2, 1]]
            N[bad] = N[bad][:, [0, 2, 1]]
            flipped += int(bad.sum())
    return flipped


def refine_car(parts):
    parts = [[n, T.astype(np.float64).copy(), N.astype(np.float64).copy(), rgb] for n, T, N, rgb in parts]
    flipped = fix_winding(parts)
    changed, kept = smooth_body(parts)
    report = {"smoothed_corners": changed, "kept_original": kept, "flipped": flipped, "wheels": {}, "liners": {}}
    for w in WHEELS:
        report["wheels"][w] = refine_wheel(parts, w, TIRE_SEGMENTS)
    body = np.concatenate([T for n, T, N, rgb in parts if role_of(n) in AVERAGE_ROLES])
    liners_T, liners_N = [], []
    for w in WHEELS:
        lin = arch_liner(body, report["wheels"][w])
        report["liners"][w] = None if lin is None else {k: v for k, v in lin.items() if k not in ("T", "N")}
        if lin is not None:
            liners_T.append(lin["T"])
            liners_N.append(lin["N"])
    if liners_T:
        car = parts[0][0].split("_", 1)[0]
        lname = f"{car}_Detail_{LINER_HEX}"
        rgb = tuple(int(LINER_HEX[i:i + 2], 16) for i in (0, 2, 4))
        existing = [p for p in parts if p[0] == lname]
        if existing:
            existing[0][1] = np.concatenate([existing[0][1]] + liners_T)
            existing[0][2] = np.concatenate([existing[0][2]] + liners_N)
        else:
            parts.append([lname, np.concatenate(liners_T), np.concatenate(liners_N), rgb])
    return parts, report


# ---------------------------------------------------------------------------------------------------------------
# preview: z-buffer, per-pixel interpolated normals (shows smooth shading)
def render_smooth(parts, size=(360, 220), yaw=35.0, pitch=14.0, focus=None, zoom=1.0):
    W, H = size
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    eye = np.array([-sy * cp, sp, -cy * cp])
    fwd = -eye
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    light = unit(np.array([0.35, 0.85, -0.4]))
    allP = np.vstack([T.reshape(-1, 3) for _, T, _, _ in parts])
    cam_all = np.stack([allP @ right, allP @ up], -1)
    if focus is not None:
        fc = np.array([focus @ right, focus @ up])
        span = 1.2 / zoom
        lo2, hi2 = fc - span, fc + span
    else:
        lo2, hi2 = cam_all.min(0), cam_all.max(0)
    s = 0.9 * min(W / (hi2[0] - lo2[0]), H / (hi2[1] - lo2[1]))
    o = (lo2 + hi2) / 2
    img = np.full((H, W, 3), (232, 235, 240), np.float64)
    zb = np.full((H, W), np.inf)
    for name, T, N, rgb in parts:
        role = role_of(name)
        col = np.array(rgb, float)
        lit = role in C.LIT
        if lit:
            col = np.array(C.LIT[role], float)
        glass = role == "Glass"
        for k in range(len(T)):
            P = T[k]
            gn = np.cross(P[1] - P[0], P[2] - P[0])
            if np.dot(gn, fwd) >= 0:
                continue
            x = (P @ right - o[0]) * s + W / 2
            y = H / 2 - (P @ up - o[1]) * s
            z = P @ fwd
            x0, x1 = int(max(math.floor(x.min()), 0)), int(min(math.ceil(x.max()), W - 1))
            y0, y1 = int(max(math.floor(y.min()), 0)), int(min(math.ceil(y.max()), H - 1))
            if x0 > x1 or y0 > y1:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            den = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2])
            if abs(den) < 1e-12:
                continue
            l0 = ((y[1] - y[2]) * (gx - x[2]) + (x[2] - x[1]) * (gy - y[2])) / den
            l1 = ((y[2] - y[0]) * (gx - x[2]) + (x[0] - x[2]) * (gy - y[2])) / den
            l2 = 1 - l0 - l1
            m = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
            if not m.any():
                continue
            zz = l0 * z[0] + l1 * z[1] + l2 * z[2]
            sub = zb[y0:y1 + 1, x0:x1 + 1]
            m &= zz < sub
            if not m.any():
                continue
            n = l0[..., None] * N[k][0] + l1[..., None] * N[k][1] + l2[..., None] * N[k][2]
            n = unit(n)
            diff = np.clip(n @ light, 0, 1)
            spec = np.clip(n @ unit(light - fwd), 0, 1) ** 24
            if lit:
                c = np.broadcast_to(col, n.shape)
            elif glass:
                c = col * (0.5 + 0.5 * diff)[..., None] + 40 * spec[..., None]
            else:
                c = col * (0.38 + 0.62 * diff)[..., None] + 70 * spec[..., None] + 10 * np.clip(-(n @ fwd), 0, 1)[..., None]
            region = img[y0:y1 + 1, x0:x1 + 1]
            region[m] = np.clip(c, 0, 255)[m]
            sub[m] = zz[m]
    return Image.fromarray(img.astype(np.uint8))


def main():
    base = C.read_glb(BASE_GLB)
    info = json.load(open(OUT_JSON))
    w = C.GlbWriter()
    roots, reports, refined = [], {}, {}
    for car, parts in base.items():
        new_parts, rep = refine_car(parts)
        refined[car] = new_parts
        reports[car] = rep
        children = []
        for name, T, N, rgb in sorted(new_parts, key=lambda p: p[0]):
            faces = [{"tri": T[i], "nor": N[i]} for i in range(len(T))]
            children.append(w.mesh_node(name, faces, rgb, np.zeros(3)))
        roots.append(w.group(car, children))
    w.write(OUT_GLB, roots, "SOLARA car_refine.py (from cosmo_cars_convert.py)")
    back = C.read_glb(OUT_GLB)
    for car, parts in back.items():
        j = info[car]
        roles = {}
        for name, T, _, _ in parts:
            r = role_of(name)
            roles[r] = roles.get(r, 0) + len(T)
        tire = np.vstack([T.reshape(-1, 3) for n, T, _, _ in parts if role_of(n) == "Wheel_FL_Tire"])
        base_tris = sum(len(T) for _, T, _, _ in base[car])
        j["BaseTriangles"] = j.get("BaseTriangles", base_tris)
        j["Triangles"] = sum(len(T) for _, T, _, _ in parts)
        j["Parts"] = len(parts)
        j["RoleTriangles"] = dict(sorted(roles.items()))
        j["PartNames"] = sorted(n for n, _, _, _ in parts)
        j["WheelRadiusM"] = round(float((tire[:, 1].max() - tire[:, 1].min()) / 2), 3)
        rep = reports[car]
        j["Refine"] = {
            "Crease": CREASE, "TireSegments": TIRE_SEGMENTS, "SmoothedCorners": rep["smoothed_corners"],
            "KeptOriginalCorners": rep["kept_original"], "FlippedFaces": rep["flipped"],
            "Liners": [k for k, v in rep["liners"].items() if v is not None],
        }
        print("%-9s %5d -> %5d tris  wheels r=%.3f  liners %s  new normals %d, original kept %d, flipped %d" % (
            car, j["BaseTriangles"], j["Triangles"], j["WheelRadiusM"], ",".join(j["Refine"]["Liners"]) or "-",
            rep["smoothed_corners"], rep["kept_original"], rep["flipped"]))
    json.dump(info, open(OUT_JSON, "w"), indent=1)

    # preview: per car, before | after (3/4 front), before | after (front wheel close-up)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    tw, th = 330, 200
    sheet = Image.new("RGB", (tw * 4, (th + 18) * len(base)), (232, 235, 240))
    d = ImageDraw.Draw(sheet)
    for i, car in enumerate(base):
        before = [(n, T.astype(np.float64), N.astype(np.float64), rgb) for n, T, N, rgb in base[car]]
        after = back[car]
        wc = reports[car]["wheels"]["FL"]["centre"]
        imgs = [render_smooth(before, (tw, th)), render_smooth(after, (tw, th)),
                render_smooth(before, (tw, th), yaw=70, pitch=6, focus=wc, zoom=1.9),
                render_smooth(after, (tw, th), yaw=70, pitch=6, focus=wc, zoom=1.9)]
        y = i * (th + 18)
        d.text((6, y + 2), f"{car}: önce | sonra   —   ön teker: önce | sonra   ({info[car]['BaseTriangles']} -> {info[car]['Triangles']} üçgen)",
               font=font, fill=(20, 20, 20))
        for k, im in enumerate(imgs):
            sheet.paste(im, (k * tw, y + 18))
    sheet.save(OUT_PREVIEW)
    print("->", OUT_GLB, "(%d KB)" % (os.path.getsize(OUT_GLB) // 1024), OUT_JSON, OUT_PREVIEW)


if __name__ == "__main__":
    main()
