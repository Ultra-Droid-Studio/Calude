#!/usr/bin/env python3
"""test_crash.py — after a crash, NPC cars and pedestrians go back into the REAL traffic / pedestrian simulation
(TrafficSim:Rejoin, PedSim:Rejoin) on the REAL map (MapData), headless through lupa.
  [1] a car pushed off its spot (lateral / heading noise) rejoins the nearest lane in its own direction, near where
      it stopped, standing still; then it drives on (moves along the network) without overlapping anyone
  [2] no rejoin: facing against all lanes nearby, far off the road, or the spot on the lane is taken
  [3] a pedestrian that got up rejoins the nearest sidewalk link (never a crossing), near where it stood, keeps its
      look (seed) and walking speed, then walks on
  [4] no pedestrian rejoin far from any sidewalk
Usage: python3 -I tools/test_crash.py <lupa-site-packages>
"""
import math
import os
import re
import sys

sys.path.insert(0, sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
from lupa import LuaRuntime  # noqa: E402
import ambient_data  # noqa: E402

fails = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        fails.append(name)


lua = LuaRuntime(unpack_returned_tuples=True)


def load(p):
    return lua.execute(open(p, encoding="utf-8").read())


TG = load("src/ReplicatedStorage/Shared/Ambient/TrafficGraph.lua")
TS = load("src/ReplicatedStorage/Shared/Ambient/TrafficSim.lua")
PG = load("src/ReplicatedStorage/Shared/Ambient/PedGraph.lua")
PS = load("src/ReplicatedStorage/Shared/Ambient/PedSim.lua")
CFG = load("src/ReplicatedStorage/Modules/AmbientConfig.lua")
T = lua.table_from

vd = open("src/ReplicatedStorage/Shared/VehicleDefinitions.lua", encoding="utf-8").read()
kinds = []
for k in CFG.Traffic.Kinds.values():
    blk = vd[vd.index("\t" + k.Id + " = {"):]
    blk = blk[:blk.index("\n\t},")]
    num = lambda key: float(re.search(r"\b" + key + r" = (-?[\d.]+)", blk).group(1))  # noqa: E731
    kinds.append(T({"Id": k.Id, "Weight": k.Weight, "Length": num("Length"), "Width": num("Width"), "MaxSpeed": num("MaxSpeed")}))
KINDS = T(kinds)

data, raw = ambient_data.load(lua)
g = TG.Build(data, CFG.Traffic)
pg = PG.Build(data, g)

FOCUS = T([T({"X": 80, "Z": -80})])


def ctx(t):
    return T({"Time": t, "Hour": 12, "Focus": FOCUS, "Obstacles": T([]), "MaxVehicles": 40, "MaxPeds": 40, "Density": 1})


traffic = TS.new(g, CFG.Traffic, KINDS, TG, 3)
peds = PS.new(pg, g, traffic, CFG.Pedestrians, PG, TG, 5)
t = 0.0
for _ in range(600):  # 60 s
    traffic.Step(traffic, 0.1, ctx(t))
    peds.Step(peds, 0.1, ctx(t))
    t += 0.1
    traffic.Spawned, traffic.Despawned, peds.Spawned, peds.Despawned = T([]), T([]), T([]), T([])
print(f"warm-up: {len(traffic.Vehicles)} vehicles, {len(peds.Peds)} pedestrians")

lane_of = lua.eval("function(v) return v.Seg, v.OnConn end")


# ---------- [1] cars rejoin
def remove_vehicle(v):
    traffic.Remove(traffic, v, "Kaza")
    traffic.Despawned = T([])


bad, ok_n, moved = [], 0, 0
cands = [v for v in traffic.Vehicles.values() if not v.OnConn and v.State == "Sür"][:12]
rejoined = []
for i, v in enumerate(cands):
    kind, x, z, hx, hz = v.Kind, v.X, v.Z, v.HX, v.HZ
    remove_vehicle(v)
    # pushed: up to 3.5 studs sideways, heading off by up to 25 degrees
    side = (i % 5 - 2) * 1.7
    ang = math.radians((i % 7 - 3) * 8)
    px, pz = x - hz * side, z + hx * side
    nhx, nhz = hx * math.cos(ang) - hz * math.sin(ang), hx * math.sin(ang) + hz * math.cos(ang)
    w = traffic.Rejoin(traffic, kind, px, pz, nhx, nhz, 14)
    if w is None:
        continue  # the spot can be taken (busy street): counted below
    ok_n += 1
    seg, onconn = lane_of(w)
    d = math.hypot(w.X - px, w.Z - pz)
    if onconn or seg.UX * hx + seg.UZ * hz < 0.5:
        bad.append(f"#{i} wrong lane direction")
    if d > 14.5:
        bad.append(f"#{i} rejoined {d:.1f} studs away")
    if w.V != 0:
        bad.append(f"#{i} not standing")
    rejoined.append((w, w.X, w.Z))
check("[1] pushed cars rejoin a lane in their own direction, ≤14 studs away, standing still", ok_n >= 8 and not bad,
      f"{ok_n}/{len(cands)} rejoined; " + "; ".join(bad[:3]))

# drive on: no overlaps on shared lanes, rejoined cars move
overlap = 0
lua_overlap = lua.eval("""function(traffic)
  local n = 0
  for _, a in ipairs(traffic.Vehicles) do
    for _, b in ipairs(traffic.Vehicles) do
      if a ~= b and a.Seg == b.Seg and a.OnConn == b.OnConn and math.abs(a.S - b.S) < (a.Len + b.Len) / 2 - 0.5 then
        n = n + 1
      end
    end
  end
  return n
end""")
for _ in range(300):  # 30 s
    traffic.Step(traffic, 0.1, ctx(t))
    t += 0.1
    overlap += lua_overlap(traffic)
    traffic.Spawned, traffic.Despawned = T([]), T([])
for w, x0, z0 in rejoined:
    if w.Removed or math.hypot(w.X - x0, w.Z - z0) > 20:
        moved += 1
check("[1] rejoined cars drive on (moved > 20 studs or left the area normally) without overlaps",
      moved >= max(1, int(0.75 * len(rejoined))) and overlap == 0, f"{moved}/{len(rejoined)} moved, overlaps {overlap}")

# ---------- [2] no rejoin
v = next(v for v in traffic.Vehicles.values() if not v.OnConn)
kind = v.Kind
check("[2] far off the road (60 studs from any lane): no rejoin",
      traffic.Rejoin(traffic, kind, 5000, 5000, 1, 0, 14) is None)
check("[2] on top of another car on its lane: no rejoin", traffic.Rejoin(traffic, kind, v.X, v.Z, v.HX, v.HZ, 14) is None)
seg, _ = lane_of(v)
lanes_near = list(TG.LanesNear(g, v.X, v.Z, 40).values())
facing_none = None
for ang in range(0, 360, 15):
    hx, hz = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    if all(l.UX * hx + l.UZ * hz <= 0.5 for l in lanes_near):
        facing_none = (hx, hz)
        break
if facing_none:
    check("[2] facing against every lane nearby: no rejoin",
          traffic.Rejoin(traffic, kind, v.X + 1, v.Z + 1, facing_none[0], facing_none[1], 14) is None)
else:
    print("     (every heading has a lane nearby here; facing check skipped)")

# ---------- [3] pedestrians rejoin
bad, n_ok = [], 0
cands = [p for p in peds.Peds.values() if p.Link and not p.Link.Crossing][:10]
start = []
for i, p in enumerate(cands):
    x, z, seed, speed, hx, hz = p.X, p.Z, p.Seed, p.Speed, p.HX, p.HZ
    peds.Remove(peds, p, "Kaza")
    peds.Despawned = T([])
    gx, gz = x + (i % 3 - 1) * 2.5, z + (i % 2) * 2.0  # thrown a little
    q = peds.Rejoin(peds, gx, gz, hx, hz, seed, speed, 18)
    if q is None:
        bad.append(f"#{i} no rejoin")
        continue
    n_ok += 1
    if q.Link.Crossing:
        bad.append(f"#{i} rejoined on a crossing")
    if math.hypot(q.X - gx, q.Z - gz) > 18:
        bad.append(f"#{i} {math.hypot(q.X - gx, q.Z - gz):.1f} studs away")
    if q.Seed != seed or q.Speed != speed:
        bad.append(f"#{i} lost its look / speed")
    start.append((q, q.X, q.Z))
check("[3] pedestrians rejoin a sidewalk link (not a crossing) nearby, same look and speed", n_ok == len(cands) and not bad,
      f"{n_ok}/{len(cands)}; " + "; ".join(bad[:3]))
for _ in range(100):  # 10 s
    traffic.Step(traffic, 0.1, ctx(t))
    peds.Step(peds, 0.1, ctx(t))
    t += 0.1
    traffic.Spawned, traffic.Despawned, peds.Spawned, peds.Despawned = T([]), T([]), T([]), T([])
walked = sum(1 for q, x0, z0 in start if q.Removed or math.hypot(q.X - x0, q.Z - z0) > 3)
check("[3] they walk on", walked >= max(1, int(0.7 * len(start))), f"{walked}/{len(start)} moved > 3 studs in 10 s")

# ---------- [4]
check("[4] far from any sidewalk: no pedestrian rejoin", peds.Rejoin(peds, 5000, 5000, 1, 0, 0.3, 4, 18) is None)

print("\n%d checks failed" % len(fails) if fails else "\nall checks passed")
sys.exit(1 if fails else 0)
