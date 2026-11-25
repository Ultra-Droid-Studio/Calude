#!/usr/bin/env python3
"""
test_ambient.py — runs the REAL traffic/pedestrian modules (TrafficGraph, PedGraph, TrafficSim, PedSim, AmbientConfig)
on the REAL MapData through lupa, headless (no Roblox). Checks:
  [1] lane graph: every lane has a successor, connectors join lanes at their node, one-way respected, curves finite
  [2] sidewalk graph: crossings only on intersection pads, walk links never on a road surface, connectivity, idle spots
  [2b] in-game data (current MapDefinitions parser, Sidewalk flag lost): sidewalk graph empty -> 0 pedestrians spawn
  [3] downtown 10 min: no vehicle overlaps, no red-light entries, no pedestrian hit, peds only on sidewalks/crossings,
      no crossing on don't-walk, no reservation leaks, no permanent jams, throughput
  [4] blocked lane (parked player car for 2 min): vehicles stop behind it / change lanes, never drive through it
  [5] player walking across a street: vehicles stop for him
  [6] moving player (driving through town) and two far-apart players: spawn/despawn around each, caps respected
  [7] night vs noon pedestrian density
  [8] cost per simulation step (this Lua runtime, not Luau)
Usage: python3 tools/test_ambient.py <lupa-site-packages>
"""
import sys, math, time, re
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, "tools")
from lupa import LuaRuntime
import ambient_data

lua = LuaRuntime(unpack_returned_tuples=True)
def load(p): return lua.execute(open(p, encoding="utf-8").read())
TG = load("src/ReplicatedStorage/Shared/Ambient/TrafficGraph.lua")
TS = load("src/ReplicatedStorage/Shared/Ambient/TrafficSim.lua")
PG = load("src/ReplicatedStorage/Shared/Ambient/PedGraph.lua")
PS = load("src/ReplicatedStorage/Shared/Ambient/PedSim.lua")
CFG = load("src/ReplicatedStorage/Modules/AmbientConfig.lua")
T = lua.table_from

fail = 0
def check(cond, msg):
    global fail
    if not cond:
        fail += 1
        print("FAIL", msg)

# vehicle kinds from VehicleDefinitions (same ids/weights as AmbientConfig)
vd = open("src/ReplicatedStorage/Shared/VehicleDefinitions.lua", encoding="utf-8").read()
kinds = []
for k in CFG.Traffic.Kinds.values():
    blk = vd[vd.index("\t" + k.Id + " = {"):]
    blk = blk[:blk.index("\n\t},")]
    num = lambda key: float(re.search(r"\b" + key + r" = (-?[\d.]+)", blk).group(1))
    kinds.append(T({"Id": k.Id, "Weight": k.Weight, "Length": num("Length"), "Width": num("Width"), "MaxSpeed": num("MaxSpeed")}))
KINDS = T(kinds)

data, raw = ambient_data.load(lua)
t0 = time.perf_counter()
g = TG.Build(data, CFG.Traffic)
t_build = (time.perf_counter() - t0) * 1000
lanes = list(g.Lanes.values()); conns = list(g.Connectors.values())

# ---------- [1] lane graph
for l in lanes:
    check(len(l.Out) > 0, f"lane {l.Id} (edge {l.Edge}) has no successor")
    check(l.Length > 0.5, f"lane {l.Id} length {l.Length}")
for c in conns:
    check(c.From.To == c.Node and c.To.From == c.Node, f"connector {c.Id} not at its node")
    check(0 < c.Length < 400 and math.isfinite(c.Length), f"connector {c.Id} length {c.Length}")
    check(c.MaxSpeed >= 6, f"connector {c.Id} speed {c.MaxSpeed}")
for e in raw["edges"].values():
    fw = [l for l in lanes if l.Edge == e["Id"] and l.From == e["A"]]
    bw = [l for l in lanes if l.Edge == e["Id"] and l.From == e["B"]]
    check(len(fw) == e["LanesForward"] and len(bw) == e["LanesBackward"], f"edge {e['Id']} lane counts")
sig = [n for n in g.Nodes.values() if n.Control == "Signal"]
for n in sig:
    phases = set(n.ArmPhase.values())
    check(len(phases) == 2 or n.Degree < 3, f"signal node {n.Id} phases {phases}")
print(f"[1] lanes {len(lanes)}, connectors {len(conns)}, signals {len(sig)}, build {t_build:.0f} ms")

# ---------- [2] sidewalk graph
pg = PG.Build(data, g)
pnodes = list(pg.Nodes.values()); plinks = list(pg.Links.values())
cross = [l for l in plinks if l.Crossing]
for l in cross:
    check(g.Pads[l.Node] is not None, f"crossing {l.Id} not on a pad")
onroad = 0
for l in plinks:
    if l.Crossing: continue
    for t in (0.25, 0.5, 0.75):
        x = l.A.X + (l.B.X - l.A.X) * t; z = l.A.Z + (l.B.Z - l.A.Z) * t
        r = PG.OnRoad(data, g, x, z, l.A.Y)
        if (r[0] if isinstance(r, tuple) else r):
            onroad += 1
check(onroad == 0, f"{onroad} sidewalk samples lie on a road")
sizes = sorted(pg.ComponentSizes.values(), reverse=True)
# Semtler arası çevre yollarında haritada kaldırım yok → semt başına bir ağ beklenir; minik kopuk parça olmamalı
check(min(sizes) >= 6, f"tiny sidewalk fragments {sizes}")
check(sum(s for s in sizes if s >= 150) > 0.95 * len(pnodes), f"sidewalk components {sizes}")
print(f"[2] sidewalk nodes {len(pnodes)}, links {len(plinks)}, crossings {len(cross)}, largest component "
      f"{sizes[0]}/{len(pnodes)} (district networks: {sizes}), idle spots {len(pg.Spots)}, walk samples on road: {onroad}")

# ---------- [2b] the game's parser reads the flags column; without sidewalk data no pedestrian may spawn
mapdefs = open("src/ReplicatedStorage/Shared/MapDefinitions.lua", encoding="utf-8").read()
check('local flags = f[11] or ""' in mapdefs and "num(f[12]), num(f[13])" in mapdefs,
      "MapDefinitions does not read edge flags/bridge span from the documented columns")
data_game, _ = ambient_data.load(lua, correct_sidewalks=False)  # = data as read by the OLD parser (no sidewalks)
g_game = TG.Build(data_game, CFG.Traffic)
pg_game = PG.Build(data_game, g_game)
ps_game = PS.new(pg_game, g_game, None, CFG.Pedestrians, PG, TG, 5)
for i in range(50):
    ps_game.Step(ps_game, 0.1, T({"Time": i * 0.1, "Hour": 12, "Focus": T([T({"X": 80, "Z": -80})]), "MaxPeds": 30, "Density": 1}))
check(len(ps_game.Peds) == 0, "pedestrians spawned without a sidewalk graph")
print(f"[2b] MapDefinitions reads flags column: {'f[11]' in mapdefs}; with no sidewalk data: sidewalk links "
      f"{len(pg_game.Links)}, pedestrians spawned {ps_game.Stats.Spawns} (expected 0)")

# ---------- simulation harness
def obb_hit(v, x, z, pad=0.6):
    dx, dz = x - v.X, z - v.Z
    along = dx * v.HX + dz * v.HZ
    side = -dx * v.HZ + dz * v.HX
    return abs(along) < v.Len / 2 + pad and abs(side) < v.Width / 2 + pad

def run(name, seconds, foci_fn, extra_obstacles=lambda t: [], hour=12, max_veh=24, max_peds=32, seed=1, verbose=True,
        check_peds_road=True):
    graph = TG.Build(data, CFG.Traffic)
    pgraph = PG.Build(data, graph)
    ts = TS.new(graph, CFG.Traffic, KINDS, TG, seed)
    ps = PS.new(pgraph, graph, ts, CFG.Pedestrians, PG, TG, seed + 1)
    dt = 1 / CFG.SimRate
    m = dict(overlap=0, pedhit=0, ped_on_road=0, stuck=0, max_veh=0, max_peds=0, t_ts=0, t_ps=0, steps=0,
             leaks=0, obstacle_violations=0, vsum=0, vcount=0)
    still = {}
    steps = int(seconds / dt)
    for i in range(steps):
        t = i * dt
        foci = foci_fn(t)
        extra = extra_obstacles(t)
        obs = [T({"X": f[0], "Y": 1, "Z": f[1], "R": CFG.Traffic.ObstacleRadius.Player, "Kind": "Player"}) for f in foci]
        obs += [T({"X": o[0], "Y": 1, "Z": o[1], "R": o[2], "Kind": o[3]}) for o in extra]
        obs += [T({"X": p.X, "Y": p.Y, "Z": p.Z, "R": CFG.Traffic.ObstacleRadius.Pedestrian, "Kind": "Pedestrian"})
                for p in ps.Peds.values() if p.State == "Geç"]
        ctx = T({"Time": 1000 + t, "Hour": hour, "Focus": T([T({"X": f[0], "Z": f[1]}) for f in foci]),
                 "Obstacles": T(obs), "MaxVehicles": max_veh, "MaxPeds": max_peds,
                 "Density": 1, "DensityAt": None})
        a = time.perf_counter(); ts.Step(ts, dt, ctx); b = time.perf_counter()
        pctx = T({"Time": 1000 + t, "Hour": hour, "Focus": ctx.Focus, "MaxPeds": max_peds,
                  "Density": ps.HourDensity(ps, hour),
                  "Obstacles": T([T({"X": v.X, "Z": v.Z, "R": 3, "Kind": "Vehicle", "Speed": v.V}) for v in ts.Vehicles.values()]
                                 + [T({"X": f[0], "Z": f[1], "R": 2, "Kind": "Player"}) for f in foci])})
        ps.Step(ps, dt, pctx); c = time.perf_counter()
        m["t_ts"] += b - a; m["t_ps"] += c - b; m["steps"] += 1
        vs = list(ts.Vehicles.values()); ped = list(ps.Peds.values())
        m["max_veh"] = max(m["max_veh"], len(vs)); m["max_peds"] = max(m["max_peds"], len(ped))
        # overlaps
        for x in range(len(vs)):
            v = vs[x]
            m["vsum"] += v.V; m["vcount"] += 1
            for y in range(x + 1, len(vs)):
                w = vs[y]
                if abs(v.Y - w.Y) < 4 and (v.X - w.X) ** 2 + (v.Z - w.Z) ** 2 < 60 ** 2:
                    if obb_hit(v, w.X, w.Z, -0.8) or obb_hit(w, v.X, v.Z, -0.8):
                        m["overlap"] += 1
            for p in ped:
                if abs(v.Y - p.Y) < 4 and obb_hit(v, p.X, p.Z, 0.3):
                    m["pedhit"] += 1
            for o in extra:
                if obb_hit(v, o[0], o[1], o[2] * 0.5):
                    m["obstacle_violations"] += 1
            if v.V < 0.1:
                still[v.Id] = still.get(v.Id, 0) + dt
            else:
                still[v.Id] = 0
        if check_peds_road and i % 10 == 0:
            for p in ped:
                if p.State != "Geç" and not (p.Link and p.Link.Crossing):
                    r = PG.OnRoad(data, graph, p.X, p.Z, p.Y)
                    if (r[0] if isinstance(r, tuple) else r):
                        m["ped_on_road"] += 1
        if i % 50 == 0:
            m["leaks"] += ts.CheckReservations(ts)
    m["stuck"] = sum(1 for v in ts.Vehicles.values() if still.get(v.Id, 0) > 90)
    m["positions"] = [(v.X, v.Z) for v in ts.Vehicles.values()]
    # yalnız istatistikleri tut (grafik/simülasyon nesneleri bellekte birikmesin)
    class S: pass
    m["ts"] = S(); m["ts"].Stats = dict(ts.Stats.items()); m["ps"] = S(); m["ps"].Stats = dict(ps.Stats.items())
    for o in (m["ts"], m["ps"]):
        o.Stats = type("St", (), o.Stats)
    del ts, ps, graph, pgraph
    lua.execute("collectgarbage()")
    if verbose:
        st = m["ts"].Stats; pst = m["ps"].Stats
        print(f"    {name}: veh max {m['max_veh']} spawns {st.Spawns} despawns {st.Despawns} entries {st.Entries} "
              f"lane-changes {st.LaneChanges} red-entries {st.RedEntries} | overlaps {m['overlap']} ped-hits {m['pedhit']} "
              f"stuck>90s {m['stuck']} leaks {m['leaks']} avg speed {m['vsum']/max(m['vcount'],1):.1f} | peds max {m['max_peds']} "
              f"crossings {pst.Crossings} cross-on-red {pst.CrossOnRed} gave-up {pst.GaveUp} on-road {m['ped_on_road']} "
              f"| ms/step traffic {m['t_ts']/m['steps']*1000:.2f} peds {m['t_ps']/m['steps']*1000:.2f}")
    return m

def common(m, name, allow_stuck=0):
    check(m["overlap"] == 0, f"{name}: {m['overlap']} vehicle overlaps")
    check(m["pedhit"] == 0, f"{name}: {m['pedhit']} pedestrian hits")
    check(m["ts"].Stats.RedEntries == 0, f"{name}: {m['ts'].Stats.RedEntries} red-light entries")
    check(m["ps"].Stats.CrossOnRed == 0, f"{name}: {m['ps'].Stats.CrossOnRed} crossings on don't-walk")
    check(m["ped_on_road"] == 0, f"{name}: {m['ped_on_road']} pedestrian samples on road outside crossings")
    check(m["leaks"] == 0, f"{name}: {m['leaks']} reservation leaks")
    check(m["stuck"] <= allow_stuck, f"{name}: {m['stuck']} vehicles stuck > 90 s")

DOWNTOWN = (80, -80)
print("[3] downtown, noon, 10 min")
m = run("downtown", 600, lambda t: [DOWNTOWN])
common(m, "downtown")
check(m["ts"].Stats.Entries > 300, f"downtown: low throughput {m['ts'].Stats.Entries}")
check(m["max_veh"] <= 24 + 2 and m["max_peds"] <= 32 + 2, "downtown: caps exceeded")
check(m["ps"].Stats.Crossings > 20, f"downtown: few crossings {m['ps'].Stats.Crossings}")

# [3b] robustness: 5 more random seeds, 4 min each
for seed in (11, 23, 37, 51, 77):
    ms = run(f"seed {seed}", 240, lambda t: [DOWNTOWN], seed=seed, verbose=False, check_peds_road=False)
    common(ms, f"seed {seed}")
    print(f"[3b] seed {seed}: overlaps {ms['overlap']} ped-hits {ms['pedhit']} red {ms['ts'].Stats.RedEntries} "
          f"stuck {ms['stuck']} entries {ms['ts'].Stats.Entries} crossings {ms['ps'].Stats.Crossings}")

# [4] blocked lane: find an avenue lane near downtown, put a parked car in its middle for 120 s
lane = None
for l in lanes:
    if l.Kind == "avenue" and l.Count == 2 and l.Index == 2 and l.Length > 60:
        mx = (l.X0 + l.X1) / 2; mz = (l.Z0 + l.Z1) / 2
        if lane is None or math.hypot(mx - DOWNTOWN[0], mz - DOWNTOWN[1]) < math.hypot((lane.X0 + lane.X1) / 2 - DOWNTOWN[0], (lane.Z0 + lane.Z1) / 2 - DOWNTOWN[1]):
            if math.hypot(mx - DOWNTOWN[0], mz - DOWNTOWN[1]) > 160:
                lane = l
bx, bz = (lane.X0 + lane.X1) / 2, (lane.Z0 + lane.Z1) / 2
print(f"[4] blocked lane {lane.Id} (avenue, curb lane) at ({bx:.0f}, {bz:.0f}) for 120 s")
m = run("blocked", 240, lambda t: [DOWNTOWN], lambda t: [(bx, bz, 4.5, "Vehicle")] if t < 120 else [])
common(m, "blocked")
check(m["obstacle_violations"] == 0, f"blocked: vehicles drove through the parked car ({m['obstacle_violations']})")

# [5] player walking across a street in front of traffic
st = None
for l in lanes:
    if l.Kind == "street" and l.Length > 60:
        mx = (l.X0 + l.X1) / 2; mz = (l.Z0 + l.Z1) / 2
        if 160 < math.hypot(mx - DOWNTOWN[0], mz - DOWNTOWN[1]) < 320:
            st = l; break
cxp, czp = (st.X0 + st.X1) / 2, (st.Z0 + st.Z1) / 2
rx, rz = st.RX, st.RZ
def walker(t):
    k = (t % 20) / 20  # crosses back and forth every 20 s, 30 studs
    off = -15 + 30 * (k if (int(t / 20) % 2 == 0) else 1 - k)
    return [(cxp + rx * off, czp + rz * off, CFG.Traffic.ObstacleRadius.Player, "Player")]
print(f"[5] player crossing street lane {st.Id}")
m = run("jaywalker", 240, lambda t: [DOWNTOWN], walker)
common(m, "jaywalker")
check(m["obstacle_violations"] == 0, f"jaywalker: vehicles hit the walking player ({m['obstacle_violations']})")

# [6] moving player + two players
path = [(80, -80), (600, -80), (600, 500), (80, 500)]
def mover(t):
    seg = (t / 60) % 4; i = int(seg); f = seg - i
    a, b = path[i], path[(i + 1) % 4]
    return [(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)]
print("[6] moving player (square route ~2 km) and two far-apart players")
m = run("moving", 300, mover)
common(m, "moving")
two = [(80, -80), (1200, -300)]
m2 = run("two players", 300, lambda t: two, max_veh=24)
common(m2, "two players")
near = [0, 0]
for (vx, vz) in m2["positions"]:
    d = [math.hypot(vx - f[0], vz - f[1]) for f in two]
    near[d.index(min(d))] += 1
check(near[0] > 0 and near[1] > 0, f"two players: vehicles near each player {near}")
print(f"    vehicles near player 1 / player 2 at end: {near}")

# [7] night vs noon
mn = run("night 02:00", 120, lambda t: [DOWNTOWN], hour=2, verbose=False, check_peds_road=False)
md = run("noon", 120, lambda t: [DOWNTOWN], hour=12, verbose=False, check_peds_road=False)
print(f"[7] pedestrians night max {mn['max_peds']} vs noon max {md['max_peds']}")
check(mn["max_peds"] < md["max_peds"], "night density not lower")

print("RESULT:", "PASS" if fail == 0 else f"FAIL ({fail})")
sys.exit(1 if fail else 0)
