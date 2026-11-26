#!/usr/bin/env python3
"""
test_navigation.py — runs the REAL src/ReplicatedStorage/Shared/Navigation.lua (via lupa) against the
REAL MapData (same field layout as MapDefinitions) and checks:
  1. routes from all spawn points to all POIs exist, follow allowed road arcs (one-way respected),
     are never shorter than the straight line, and finish near the destination
  2. snapping in every district / region (incl. far off-road points and under elevated roads)
  3. unreachable destinations are reported, not crashed (synthetic disconnected graph)
  4. simulated driving: progress is monotonic, remaining distance shrinks, maneuvers come in order,
     arrival is reached; deviating triggers a reroute that starts at the new position; destination change
  5. performance (average / worst route time in this Lua runtime)
Usage: python3 tools/test_navigation.py <lupa-site-packages>
"""
import sys, math, random, time
sys.path.insert(0, sys.argv[1])
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
Nav = lua.execute(open("src/ReplicatedStorage/Shared/Navigation.lua", encoding="utf-8").read())
lines = open("src/ReplicatedStorage/Shared/MapData.lua", encoding="utf-8").read().split("\n")

def P(x, y, z): return lua.table_from({"X": x, "Y": y, "Z": z})
nodes, edges, pois, spawns, districts = {}, [], [], [], []
for l in lines:
    f = l.split("|")
    if f[0] == "N":
        nodes[int(f[1])] = (float(f[2]), float(f[3]), float(f[4]))
    elif f[0] == "E":  # same indices as MapDefinitions (Lua f[2..10] = python 1..9)
        edges.append(dict(Id=int(f[1]), A=int(f[2]), B=int(f[3]), Kind=f[4], Width=float(f[5]),
                          LanesForward=int(float(f[6])), LanesBackward=int(float(f[7])), Speed=float(f[8]), Name=f[9]))
    elif f[0] == "P":
        pois.append((f[1], float(f[6]), float(f[7])))  # entrance
    elif f[0] == "S":
        spawns.append((f[1], float(f[2]), float(f[3])))
    elif f[0] == "D":
        districts.append((f[1], float(f[4]), float(f[5]), float(f[6]), float(f[7])))
# City expansion stage 2: new businesses are POIs in the game too (MapDefinitions -> Businesses.Apply)
sys.path.insert(0, "tools")
import ambient_data  # noqa: E402
_known = {pid for pid, _, _ in pois}
for _p in ambient_data.load(LuaRuntime(unpack_returned_tuples=True))[0].POIs.values():
    if _p.Id not in _known:
        pois.append((_p.Id, _p.Entrance.X, _p.Entrance.Z))

def build(nodes, edges):
    lnodes = lua.table_from({k: lua.table_from({"Position": P(*v)}) for k, v in nodes.items()})
    ledges = lua.table_from([lua.table_from(e) for e in edges])
    return Nav.new(lua.table_from({"Nodes": lnodes, "EdgeList": ledges}))

def find(n, a, b):
    """FindRoute returns route OR (nil, reason); lupa gives a bare value for single returns."""
    r = n.FindRoute(n, a, b)
    if isinstance(r, tuple):
        return r[0], (r[1] if len(r) > 1 else None)
    return r, None

nav = build(nodes, edges)
allowed = set()
for e in edges:
    if e["LanesForward"] > 0: allowed.add((e["A"], e["B"]))
    if e["LanesBackward"] > 0: allowed.add((e["B"], e["A"]))
node_at = {(round(v[0], 3), round(v[2], 3), round(v[1], 3)): k for k, v in nodes.items()}

fail = 0
def check(cond, msg):
    global fail
    if not cond:
        fail += 1
        print("FAIL", msg)

def pts(route):
    return [(p.X, p.Y, p.Z) for p in route.Points.values()]

# ---- 1. spawn -> POI matrix
times, count, offroad = [], 0, 0
for sname, sx, sz in spawns:
    for pid, px, pz in pois:
        t0 = time.perf_counter()
        route, reason = find(nav, P(sx, 0.5, sz), P(px, 0.5, pz))
        times.append(time.perf_counter() - t0)
        count += 1
        check(route is not None, f"no route {sname}->{pid}: {reason}")
        if route is None: continue
        ps = pts(route)
        ids = [node_at.get((round(x, 3), round(z, 3), round(y, 3))) for x, y, z in ps[1:-1]]
        ids = [i for i in ids if i is not None]
        for a, b in zip(ids, ids[1:]):
            check((a, b) in allowed, f"illegal arc {a}->{b} on {sname}->{pid}")
        straight = math.hypot(ps[-1][0] - ps[0][0], ps[-1][2] - ps[0][2])
        check(route.Length + 1e-6 >= straight * 0.999, f"route shorter than straight line {sname}->{pid}")
        end_gap = math.hypot(ps[-1][0] - px, ps[-1][2] - pz)
        if route.Offroad: offroad += 1
        else: check(end_gap <= Nav.OffroadDistance, f"route ends {end_gap:.0f} from {pid}")
        m = list(route.Maneuvers.values())
        check(m[-1].Type == "Arrive", "last maneuver not Arrive")
        check(all(m[i].Distance <= m[i + 1].Distance for i in range(len(m) - 1)), "maneuvers out of order")
print(f"[1] {count} spawn→POI routes, offroad-finish {offroad}, avg {1000*sum(times)/len(times):.2f} ms, worst {1000*max(times):.2f} ms")

# ---- 2. snapping across regions
random.seed(7)
snapped = 0
for did, x0, z0, x1, z1 in districts:
    for _ in range(6):
        x, z = random.uniform(x0, x1), random.uniform(z0, z1)
        s = nav.Snap(nav, P(x, 0.5, z))
        check(s is not None, f"no road near {did} ({x:.0f},{z:.0f})")
        if s is not None: snapped += 1
far = nav.Snap(nav, P(5000, 0, 5000))  # bay corner
print(f"[2] {snapped} district points snapped; far bay point snaps at {far.Horizontal:.0f} studs" if far else "[2] far point: no road")
# elevated: a ground point under an elevated road must snap to a GROUND road whenever one exists
# within 90 studs (the freeway deck above cannot be reached from there)
elev = [e for e in edges if nodes[e["A"]][1] > 8 and nodes[e["B"]][1] > 8]
ground = [e for e in edges if nodes[e["A"]][1] < 4 and nodes[e["B"]][1] < 4]
def seg_dist(px, pz, a, b):
    dx, dz = b[0] - a[0], b[2] - a[2]; l2 = dx * dx + dz * dz
    t = 0 if l2 < 1e-9 else max(0, min(1, ((px - a[0]) * dx + (pz - a[2]) * dz) / l2))
    return math.hypot(px - (a[0] + dx * t), pz - (a[2] + dz * t))
checked_under = 0
for e in elev:
    a, b = nodes[e["A"]], nodes[e["B"]]
    mx, mz = (a[0] + b[0]) / 2, (a[2] + b[2]) / 2
    near_ground = min(seg_dist(mx, mz, nodes[g["A"]], nodes[g["B"]]) for g in ground)
    s = nav.Snap(nav, P(mx, 0.5, mz))
    if near_ground < 90:
        checked_under += 1
        check(s.Y < 4, f"ground point under elevated edge {e['Id']} snapped to Y={s.Y:.1f} (ground road {near_ground:.0f} away)")
    # and on the deck itself the freeway must win
    sd = nav.Snap(nav, P(mx, (a[1] + b[1]) / 2 + 1, mz))
    check(sd.Y > 8, f"point ON elevated edge {e['Id']} snapped down to Y={sd.Y:.1f}")
print(f"[2b] {len(elev)} elevated edges: on-deck stays on deck; {checked_under} ground points with a nearby ground road snap to it")

# ---- 3. unreachable (two islands, one one-way bridge)
iso_nodes = {1: (0, 0, 0), 2: (100, 0, 0), 3: (1000, 0, 0), 4: (1100, 0, 0)}
iso_edges = [dict(Id=1, A=1, B=2, Kind="street", Width=20, LanesForward=1, LanesBackward=1, Speed=50, Name="A St"),
             dict(Id=2, A=3, B=4, Kind="street", Width=20, LanesForward=1, LanesBackward=1, Speed=50, Name="B St")]
iso = build(iso_nodes, iso_edges)
r, reason = find(iso, P(10, 0, 0), P(1050, 0, 0))
check(r is None and reason == "Unreachable", f"islands should be unreachable, got {reason}")
one = build({1: (0, 0, 0), 2: (300, 0, 0)}, [dict(Id=1, A=1, B=2, Kind="ramp", Width=20, LanesForward=1, LanesBackward=0, Speed=60, Name="Ramp")])
r1, _ = find(one, P(20, 0, 0), P(250, 0, 0))
r2, reason2 = find(one, P(250, 0, 0), P(20, 0, 0))
check(r1 is not None and r2 is None and reason2 == "Unreachable", "one-way ramp must not be driven backwards")
print(f"[3] disconnected → {reason}; one-way backwards → {reason2}")

# ---- 4. simulated drives
def drive(route, start_offset=(0, 0), speed=30.0, dt=0.1, deviate_at=None):
    ps = pts(route)
    seg, along_prev, remaining_prev = None, -1, 1e9
    t, i, pos = 0.0, 0, list(ps[0])
    announced = []
    while i < len(ps) - 1 and t < 600:
        a, b = ps[i], ps[i + 1]
        dx, dy, dz = b[0] - pos[0], b[1] - pos[1], b[2] - pos[2]
        d = math.sqrt(dx * dx + dy * dy + dz * dz)
        step = speed * dt
        if d <= step: pos = list(b); i += 1
        else: pos = [pos[0] + dx / d * step, pos[1] + dy / d * step, pos[2] + dz / d * step]
        t += dt
        probe = pos
        if deviate_at is not None and t >= deviate_at:
            return pos
        pr = Nav.Progress(route, P(*probe), seg)
        seg = pr.Segment
        check(pr.Along + 0.5 >= along_prev, f"progress went backwards ({pr.Along:.1f} < {along_prev:.1f})")
        check(pr.Remaining <= remaining_prev + 0.5, "remaining grew")
        check(pr.Deviation < 2.0, f"on-route deviation {pr.Deviation:.2f}")
        along_prev, remaining_prev = pr.Along, pr.Remaining
        if not announced or announced[-1] != pr.Next.Index: announced.append(pr.Next.Index)
    return announced, remaining_prev

drives = 0
for k in range(12):
    s = spawns[k % len(spawns)]; p = pois[(k * 7) % len(pois)]
    route, _ = find(nav, P(s[1], 0.5, s[2]), P(p[1], 0.5, p[2]))
    announced, remaining = drive(route)
    check(announced == sorted(announced), "maneuvers announced out of order")
    check(remaining < 1.0, f"did not arrive (remaining {remaining:.1f})")
    drives += 1
# deviation → reroute from the new position
route, _ = find(nav, P(spawns[0][1], 0.5, spawns[0][2]), P(pois[40][1], 0.5, pois[40][2]))
pos = drive(route, deviate_at=6.0)
off = P(pos[0] + 90, pos[1], pos[2] + 90)
pr = Nav.Progress(route, off, None)
check(pr.Deviation > 35, "deviation not detected")
re, _ = find(nav, off, route.Destination)
check(re is not None, "reroute failed")
first = re.Points[1]
check(math.hypot(first.X - (pos[0] + 90), first.Z - (pos[2] + 90)) < 200, "reroute does not start near player")
# destination change
alt, _ = find(nav, off, P(pois[3][1], 0.5, pois[3][2]))
check(alt is not None and abs(alt.Destination.X - pois[3][1]) < 1e-6, "destination change failed")
print(f"[4] {drives} simulated drives arrived; deviation {pr.Deviation:.0f} studs → reroute ok; destination change ok")

print("RESULT:", "PASS" if fail == 0 else f"{fail} FAILURES")
sys.exit(1 if fail else 0)
