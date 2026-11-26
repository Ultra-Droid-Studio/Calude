#!/usr/bin/env python3
"""
test_ambient.py — runs the REAL traffic/pedestrian modules (TrafficGraph, PedGraph, TrafficSim, PedSim, AmbientConfig)
on the REAL MapData through lupa, headless (no Roblox). Checks:
  [1] lane graph: every lane has a successor, connectors join lanes at their node, one-way respected, curves finite
  [2] sidewalk graph: crossings only on intersection pads, walk links never on a road surface, connectivity, idle spots
  [2b] in-game data (current MapDefinitions parser, Sidewalk flag lost): sidewalk graph empty -> 0 pedestrians spawn
  [3] downtown 10 min: no vehicle overlaps, no red-light entries, no pedestrian hit, peds only on sidewalks/crossings,
      no crossing on don't-walk, no reservation leaks, no permanent jams, no vehicle removed while visible, throughput,
      Living City flow metrics (speed, stopped share + reasons, restart delay, stop-go, density by road class)
  [4] blocked lane (parked player car for 2 min): vehicles stop behind it / change lanes, never drive through it
  [4b] closed intersection exit (player car parked right after a signal): nobody blocks the box, vehicles turn elsewhere
  [5] player walking across a street: vehicles stop for him
  [6] moving player (driving through town) and two far-apart players: spawn/despawn around each, caps respected
  [7] night vs noon pedestrian density
  [8] density presets Low/Normal/High (device budgets) and caps
  [9] signal plans: main road longer green, never two phases green/yellow at once, cycle length
  [10] building entrances: doors on verified facades, walkway to the sidewalk off the road and outside other lots,
       door nodes are dead ends; in the downtown run pedestrians enter and leave buildings only through doors
  [11] procedural walk (PedAnim): planted foot never slides, sole on the ground in stance, swing foot above ground,
       joint limits, neutral idle
  cost per simulation step is printed with every run (this Lua runtime, not Luau)
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
EN = load("src/ReplicatedStorage/Shared/Ambient/Entrances.lua")
PA = load("src/ReplicatedStorage/Shared/Ambient/PedAnim.lua")
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

# ---------- simulation harness (per-step checks run in Lua: fast with 60+ vehicles)
H = lua.execute(r"""
local H = {}
local sqrt, abs, cos, sin = math.sqrt, math.abs, math.cos, math.sin
-- kamera görüş konisi (her odak için): yön ang, yarım açı half, menzil maxd. Engelleme (bina) yok = en kötü durum
function H.vis(foci, angs, half, maxd)
  local c = cos(half)
  return function(x, y, z, d)
    for i = 1, #foci do
      local f = foci[i]
      local dx, dz = x - f.X, z - f.Z
      local dd = sqrt(dx * dx + dz * dz)
      if dd < 2 then return true end
      if dd <= maxd and (dx * cos(angs[i]) + dz * sin(angs[i])) / dd > c then return true end
    end
    return false
  end
end
function H.canSpawn(vis, visibleMin)
  return function(x, y, z, d)
    if d >= visibleMin then return true end
    return not vis(x, y, z, d)
  end
end
function H.new()
  return { overlap = 0, pedhit = 0, obsv = 0, vsum = 0, vcount = 0, stopped = 0, reasons = {}, cls = {},
    restartSum = 0, restartN = 0, restarts = {}, waiting = {}, greenStart = {}, greenSum = 0, greenN = 0, greens = {},
    prevState = {}, still = {}, maxStill = {}, visDespawn = 0, despawn = {}, boxHold = {}, boxBlock = 0,
    dens = {}, densN = 0, move = {}, goAt = {}, stopgo = 0, starts = 0, stopgoWhy = {}, obsStill = 0, badEnter = 0,
    pedN = 0, pedWait = 0, pedPrev = {}, pedTurnMax = 0, pedAccMax = 0, pedVisDespawn = 0, pedDespawn = {} }
end
local function hit(v, x, z, p)
  local dx, dz = x - v.X, z - v.Z
  local along = dx * v.HX + dz * v.HZ
  local side = -dx * v.HZ + dz * v.HX
  return abs(along) < v.Len / 2 + p and abs(side) < v.Width / 2 + p
end
local function nearest(foci, x, z)
  local b = math.huge
  for i = 1, #foci do local f = foci[i]; local d = (f.X - x) ^ 2 + (f.Z - z) ^ 2; if d < b then b = d end end
  return sqrt(b)
end
function H.step(m, ts, ps, extra, dt, t, vis, hard, foci, ringMin, ringMax, pedHard)
  local vs = ts.Vehicles
  local peds = ps.Peds
  for i = 1, #vs do
    local v = vs[i]
    for j = i + 1, #vs do
      local w = vs[j]
      if abs(v.Y - w.Y) < 4 and (v.X - w.X) ^ 2 + (v.Z - w.Z) ^ 2 < 3600 then
        if hit(v, w.X, w.Z, -0.8) or hit(w, v.X, v.Z, -0.8) then m.overlap = m.overlap + 1 end
      end
    end
    for k = 1, #peds do local p = peds[k]; if abs(v.Y - p.Y) < 4 and hit(v, p.X, p.Z, 0.3) then m.pedhit = m.pedhit + 1 end end
    -- engel ihlali: HAREKET EDEN araç engelin (park etmiş araç / yürüyen oyuncu) içine girdi. Duran araca senaryodaki
    -- oyuncunun kendisinin yürümesi ayrı sayılır (araç kıpırdamıyor, kaçınamaz).
    for k = 1, #extra do
      local o = extra[k]
      if hit(v, o[1], o[2], o[3] * 0.5) then
        if v.V > 0.5 then m.obsv = m.obsv + 1 else m.obsStill = m.obsStill + 1 end
      end
    end
    m.vsum = m.vsum + v.V; m.vcount = m.vcount + 1
    local cl = v.OnConn and "junction" or v.Seg.Kind
    local c = m.cls[cl]; if not c then c = { n = 0, sum = 0, mn = 0, msum = 0 }; m.cls[cl] = c end
    c.n = c.n + 1; c.sum = c.sum + v.V
    if v.V >= 0.5 then c.mn = c.mn + 1; c.msum = c.msum + v.V end
    if v.V < 0.5 then
      m.stopped = m.stopped + 1
      m.reasons[v.State] = (m.reasons[v.State] or 0) + 1
    end
    -- kalkış gecikmesi: öndeki araç kalktıktan (V>1) sonra arkadaki duran aracın V>=1 olması
    local lb = v.LimitBy
    if v.V < 0.3 and type(lb) == "table" then
      if lb.V > 1 then m.waiting[v] = m.waiting[v] or t else m.waiting[v] = nil end
    elseif v.V < 0.3 then
      m.waiting[v] = nil -- artık başka bir sebeple (çizgi, yaya) bekliyor: takip kalkışı değil
    elseif v.V >= 1 and m.waiting[v] then
      local d = t - m.waiting[v]; m.waiting[v] = nil
      m.restartSum = m.restartSum + d; m.restartN = m.restartN + 1; m.restarts[#m.restarts + 1] = d
    end
    -- yeşilde kalkış: kırmızıda bekleyen ilk aracın izin aldıktan sonra V>=1 olması
    if m.prevState[v] == "Kırmızı" and v.Reserve and v.V < 0.5 then m.greenStart[v] = t end
    if v.V >= 1 and m.greenStart[v] then
      local d = t - m.greenStart[v]; m.greenStart[v] = nil
      m.greenSum = m.greenSum + d; m.greenN = m.greenN + 1; m.greens[#m.greens + 1] = d
    end
    m.prevState[v] = v.State
    -- dur-kalk titremesi: kalktıktan sonra 2.5 sn içinde yeniden duran araç (kısa kalk-dur döngüsü)
    if v.V >= 1 and m.move[v] ~= "go" then
      if m.move[v] == "stop" then m.starts = m.starts + 1; m.goAt[v] = t end
      m.move[v] = "go"
    elseif v.V < 0.3 and m.move[v] ~= "stop" then
      if m.move[v] == "go" and m.goAt[v] and t - m.goAt[v] < 2.5 then
        m.stopgo = m.stopgo + 1
        local why = (type(v.LimitBy) == "table") and "leader" or tostring(v.LimitBy) .. ":" .. tostring(v.State)
        m.stopgoWhy[why] = (m.stopgoWhy[why] or 0) + 1
      end
      m.move[v] = "stop"
    end
    if v.V < 0.1 then m.still[v] = (m.still[v] or 0) + dt else m.still[v] = 0 end
    if (m.still[v] or 0) > (m.maxStill[v] or 0) then m.maxStill[v] = m.still[v] end
    -- kavşak içinde (bağlantı üstünde) uzun süre duran = kavşağı tıkayan (yayaya yol vermek için bekleme hariç)
    if v.OnConn and v.V < 0.3 and v.LimitBy ~= "pedestrian" then
      m.boxHold[v] = (m.boxHold[v] or 0) + dt
      if m.boxHold[v] > 10 and m.boxHold[v] - dt <= 10 then m.boxBlock = m.boxBlock + 1 end
    else m.boxHold[v] = 0 end
    -- yoğunluk: halka içindeki araçlar sınıfa göre
    if not v.OnConn then
      local d = nearest(foci, v.X, v.Z)
      if d >= ringMin and d <= ringMax then m.dens[v.Seg.Kind] = (m.dens[v.Seg.Kind] or 0) + 1 end
    end
  end
  m.densN = m.densN + 1
  pedHard = pedHard or 1e9
  -- yayalar: geçitte bekleme payı, tik başına en büyük yön değişimi ve hız değişimi
  for k = 1, #peds do
    local p = peds[k]
    m.pedN = m.pedN + 1
    if p.State == "Bekle" then m.pedWait = m.pedWait + 1 end
    local pr = m.pedPrev[p]
    local sp = p.CurSpeed or 0
    if pr and p.HX and pr[1] then
      local dot = math.max(-1, math.min(1, pr[1] * p.HX + pr[2] * p.HZ))
      local ang = math.deg(math.acos(dot))
      if ang > m.pedTurnMax then m.pedTurnMax = ang end
      local acc = math.abs(sp - pr[3]) / dt
      if acc > m.pedAccMax and sp > 0 then m.pedAccMax = acc end
    end
    m.pedPrev[p] = { p.HX, p.HZ, sp }
  end
  for _, p in ipairs(ps.Despawned) do
    local r = p.RemoveReason or "?"
    m.pedDespawn[r] = (m.pedDespawn[r] or 0) + 1
    if r == "Bina" then
      -- binaya giren yaya kapı boşluğunun içinde kaybolmalı (duvarın içinde değil)
      local e = p.Door
      local d = e and math.sqrt((p.X - (e.X - e.NX * 1.8)) ^ 2 + (p.Z - (e.Z - e.NZ * 1.8)) ^ 2) or 99
      if d > 0.6 then m.badEnter = m.badEnter + 1 end
    end
    if vis and r ~= "Kaza" and r ~= "Kapat" and r ~= "Bina" then
      local d = nearest(foci, p.X, p.Z)
      if d < pedHard and vis(p.X, p.Y, p.Z, d) then m.pedVisDespawn = m.pedVisDespawn + 1 end
    end
    m.pedPrev[p] = nil
  end
  for _, v in ipairs(ts.Despawned) do
    local r = v.RemoveReason or "?"
    m.despawn[r] = (m.despawn[r] or 0) + 1
    if vis and r ~= "Kaza" and r ~= "Kapat" then
      local d = nearest(foci, v.X, v.Z)
      if d < hard and vis(v.X, v.Y, v.Z, d) then m.visDespawn = m.visDespawn + 1 end
    end
    m.move[v] = nil; m.goAt[v] = nil
    m.still[v] = nil; m.waiting[v] = nil; m.greenStart[v] = nil; m.prevState[v] = nil; m.boxHold[v] = nil
  end
end
-- 'limit' sn'den uzun hiç kıpırdamayan araç. Yolda duran oyuncunun dibinde (30 stud) onu bekleyen araç sayılmaz:
-- bu doğru davranış (oyuncuyu ezmez, korna çalar gibi bekler).
function H.stuck(m, ts, limit, foci)
  local n = 0
  for _, v in ipairs(ts.Vehicles) do
    if (m.still[v] or 0) > limit and not (v.LimitBy == "obstacle" and foci and nearest(foci, v.X, v.Z) < 30) then n = n + 1 end
  end
  return n
end
return H
""")

def lane_len_in_ring(graph, foci, rmin, rmax):
    out = {}
    for l in graph.Lanes.values():
        mx, mz = (l.X0 + l.X1) / 2, (l.Z0 + l.Z1) / 2
        d = min(math.hypot(mx - f[0], mz - f[1]) for f in foci)
        if rmin <= d <= rmax:
            out[l.Kind] = out.get(l.Kind, 0) + l.Length
    return out

def pct(lst, q):
    lst = sorted(lst)
    return lst[min(len(lst) - 1, int(len(lst) * q))] if lst else 0

def run(name, seconds, foci_fn, extra_obstacles=lambda t: [], hour=12, max_veh=None, max_peds=None, seed=1, verbose=True,
        check_peds_road=True, cfg_traffic=None, camera=True, doors=True):
    tcfg = cfg_traffic or CFG.Traffic
    if max_veh is None:
        max_veh = CFG.Traffic.MaxVehicles.Desktop.Normal
    if max_peds is None:
        max_peds = CFG.Pedestrians.MaxPedestrians.Desktop.Normal
    graph = TG.Build(data, tcfg)
    pgraph = PG.Build(data, graph)
    pgraph.Entrances = EN.Build(data, pgraph, PG, graph) if doors else None
    ts = TS.new(graph, tcfg, KINDS, TG, seed)
    ps = PS.new(pgraph, graph, ts, CFG.Pedestrians, PG, TG, seed + 1)
    dt = 1 / CFG.SimRate
    hm = H.new()
    m = dict(ped_on_road=0, max_veh=0, max_peds=0, t_ts=0, t_ps=0, steps=0, leaks=0)
    steps = int(seconds / dt)
    ring = (tcfg.SpawnMin, tcfg.SpawnMax)
    for i in range(steps):
        t = i * dt
        foci = foci_fn(t)
        extra = extra_obstacles(t)
        # oyuncu/engel hızları (sonlu fark): araçlar yola doğru yürüyen insanı önceden görür
        foci2, extra2 = foci_fn(t + dt), extra_obstacles(t + dt)
        def vel(a, b2):
            return ((b2[0] - a[0]) / dt, (b2[1] - a[1]) / dt) if b2 is not None else (0, 0)
        obs = []
        for k, f in enumerate(foci):
            vx, vz = vel(f, foci2[k] if k < len(foci2) else None)
            obs.append(T({"X": f[0], "Y": 1, "Z": f[1], "R": tcfg.ObstacleRadius.Player, "Kind": "Player", "VX": vx, "VZ": vz}))
        for k, o in enumerate(extra):
            vx, vz = vel(o, extra2[k] if k < len(extra2) else None)
            obs.append(T({"X": o[0], "Y": 1, "Z": o[1], "R": o[2], "Kind": o[3], "VX": vx, "VZ": vz}))
        obs += [T({"X": p.X, "Y": p.Y, "Z": p.Z, "R": tcfg.ObstacleRadius.Pedestrian, "Kind": "Pedestrian",
                   "VX": (p.HX or 0) * (p.CurSpeed or 0), "VZ": (p.HZ or 0) * (p.CurSpeed or 0)})
                for p in ps.Peds.values() if p.State == "Geç"]
        lfoci = T([T({"X": f[0], "Z": f[1]}) for f in foci])
        vis = H.vis(lfoci, T([0.21 * t + k for k in range(len(foci))]), math.radians(40), 900) if camera else None
        ctx = T({"Time": 1000 + t, "Hour": hour, "Focus": lfoci,
                 "Obstacles": T(obs), "MaxVehicles": max_veh, "MaxPeds": max_peds,
                 "Density": 1, "DensityAt": None, "IsVisible": vis,
                 "CanSpawn": H.canSpawn(vis, tcfg.SpawnVisibleMin) if camera else None})
        a = time.perf_counter(); ts.Step(ts, dt, ctx); b = time.perf_counter()
        pctx = T({"Time": 1000 + t, "Hour": hour, "Focus": ctx.Focus, "MaxPeds": max_peds,
                  "Density": ps.HourDensity(ps, hour), "IsVisible": vis,
                  "CanSpawn": H.canSpawn(vis, CFG.Pedestrians.SpawnVisibleMin) if camera else None,
                  "Obstacles": T([T({"X": v.X, "Z": v.Z, "R": 3, "Kind": "Vehicle", "Speed": v.V}) for v in ts.Vehicles.values()]
                                 + [T({"X": f[0], "Z": f[1], "R": 2, "Kind": "Player"}) for f in foci])})
        ps.Step(ps, dt, pctx); c = time.perf_counter()
        m["t_ts"] += b - a; m["t_ps"] += c - b; m["steps"] += 1
        H.step(hm, ts, ps, T([T([o[0], o[1], o[2]]) for o in extra]), dt, t, vis,
               tcfg.HardDespawnRadius or 1e9, lfoci, ring[0], ring[1], CFG.Pedestrians.HardDespawnRadius or 1e9)
        nv, npd = len(ts.Vehicles), len(ps.Peds)
        m["max_veh"] = max(m["max_veh"], nv); m["max_peds"] = max(m["max_peds"], npd)
        if check_peds_road and i % 10 == 0:
            for p in ps.Peds.values():
                if p.State != "Geç" and not (p.Link and p.Link.Crossing):
                    r = PG.OnRoad(data, graph, p.X, p.Z, p.Y)
                    if (r[0] if isinstance(r, tuple) else r):
                        m["ped_on_road"] += 1
        if i % 50 == 0:
            m["leaks"] += ts.CheckReservations(ts)
    m["stuck"] = H.stuck(hm, ts, 90, T([T({"X": f[0], "Z": f[1]}) for f in foci_fn(seconds)]))
    m["positions"] = [(v.X, v.Z) for v in ts.Vehicles.values()]
    lens = lane_len_in_ring(graph, foci_fn(seconds), ring[0], ring[1])
    # yalnız sayıları tut (grafik/simülasyon nesneleri bellekte birikmesin)
    for k in ("overlap", "pedhit", "obsv", "vsum", "vcount", "stopped", "restartSum", "restartN", "greenSum", "greenN",
              "visDespawn", "boxBlock", "densN", "stopgo", "starts", "pedN", "pedWait", "pedTurnMax", "pedAccMax", "obsStill",
              "badEnter",
              "pedVisDespawn"):
        m[k] = hm[k]
    m["obstacle_violations"] = hm.obsv
    m["reasons"] = dict(hm.reasons.items())
    m["despawn"] = dict(hm.despawn.items())
    m["pedDespawn"] = dict(hm.pedDespawn.items())
    m["stopgoWhy"] = dict(hm.stopgoWhy.items())
    m["cls"] = {k: dict(n=c.n, sum=c.sum, mn=c.mn, msum=c.msum) for k, c in hm.cls.items()}
    m["restarts"] = list(hm.restarts.values()); m["greens"] = list(hm.greens.values())
    m["density"] = {k: (hm.dens[k] or 0) / max(hm.densN, 1) / (L / 100) for k, L in lens.items() if L > 0 and hm.dens[k]}
    m["avg_speed"] = hm.vsum / max(hm.vcount, 1)
    m["stopped_share"] = hm.stopped / max(hm.vcount, 1)
    m["restart"] = hm.restartSum / max(hm.restartN, 1)
    m["green"] = hm.greenSum / max(hm.greenN, 1)
    class S: pass
    m["ts"] = S(); m["ps"] = S()
    m["ts"].Stats = type("St", (), dict(ts.Stats.items())); m["ps"].Stats = type("St", (), dict(ps.Stats.items()))
    del ts, ps, graph, pgraph, hm
    lua.execute("collectgarbage()")
    if verbose:
        st = m["ts"].Stats; pst = m["ps"].Stats
        print(f"    {name}: veh max {m['max_veh']} spawns {st.Spawns} despawns {st.Despawns} entries {st.Entries} "
              f"lane-changes {st.LaneChanges} reroutes {st.Reroutes} red-entries {st.RedEntries} | overlaps {m['overlap']} "
              f"ped-hits {m['pedhit']} stuck>90s {m['stuck']} box-block>10s {m['boxBlock']} leaks {m['leaks']} "
              f"visible-despawns {m['visDespawn']} | peds max {m['max_peds']} crossings {pst.Crossings} "
              f"cross-on-red {pst.CrossOnRed} gave-up {pst.GaveUp} on-road {m['ped_on_road']} "
              f"| ms/step traffic {m['t_ts']/m['steps']*1000:.2f} peds {m['t_ps']/m['steps']*1000:.2f}")
    return m

def report_flow(m, name):
    tot = sum(m["reasons"].values()) or 1
    reasons = ", ".join(f"{k} {100*v/tot:.0f}%" for k, v in sorted(m["reasons"].items(), key=lambda kv: -kv[1])[:6])
    cls = "  ".join(f"{k}: avg {c['sum']/c['n']:.1f} moving {c['msum']/max(c['mn'],1):.1f} ({100*c['n']/max(m['vcount'],1):.0f}%)"
                    for k, c in sorted(m["cls"].items(), key=lambda kv: -kv[1]["n"]))
    dens = ", ".join(f"{k} {v:.2f}" for k, v in sorted(m["density"].items(), key=lambda kv: -kv[1]))
    print(f"    {name} flow: avg speed {m['avg_speed']:.1f}, stopped {100*m['stopped_share']:.0f}% ({reasons})")
    print(f"      by road: {cls}")
    print(f"      restart after leader {m['restart']:.2f} s (p90 {pct(m['restarts'], 0.9):.2f}, n={len(m['restarts'])}); "
          f"start on green {m['green']:.2f} s (p90 {pct(m['greens'], 0.9):.2f}, n={len(m['greens'])})")
    print(f"      vehicles per 100 studs of lane in spawn ring: {dens}; despawn reasons {m['despawn']}")
    print(f"      pedestrians: waiting at crossings {100*m['pedWait']/max(m['pedN'],1):.0f}% of time, max turn per tick "
          f"{m['pedTurnMax']:.0f} deg, max speed change {m['pedAccMax']:.1f} studs/s2, despawn reasons {m['pedDespawn']}")
    print(f"      stop-go (re-stop within 2.5 s of starting): {m['stopgo']} of {m['starts']} starts "
          f"({100*m['stopgo']/max(m['starts'],1):.1f}%, causes {m['stopgoWhy']}); box-blocking >10 s: {m['boxBlock']}")

def common(m, name, allow_stuck=0):
    check(m["overlap"] == 0, f"{name}: {m['overlap']} vehicle overlaps")
    check(m["pedhit"] == 0, f"{name}: {m['pedhit']} pedestrian hits")
    check(m["ts"].Stats.RedEntries == 0, f"{name}: {m['ts'].Stats.RedEntries} red-light entries")
    check(m["ps"].Stats.CrossOnRed == 0, f"{name}: {m['ps'].Stats.CrossOnRed} crossings on don't-walk")
    check(m["ped_on_road"] == 0, f"{name}: {m['ped_on_road']} pedestrian samples on road outside crossings")
    check(m["leaks"] == 0, f"{name}: {m['leaks']} reservation leaks")
    check(m["stuck"] <= allow_stuck, f"{name}: {m['stuck']} vehicles stuck > 90 s")
    check(m["visDespawn"] == 0, f"{name}: {m['visDespawn']} vehicles removed while visible")
    check(m["pedVisDespawn"] == 0, f"{name}: {m['pedVisDespawn']} pedestrians removed while visible")
    # bekçi (75 sn hiç kıpırdamayan aracı kaldırır) kilitlenmeyi gizlemesin: devreye girmesi hata sayılır
    check(m["ts"].Stats.Watchdog == 0, f"{name}: idle watchdog removed {m['ts'].Stats.Watchdog} vehicles (deadlock)")
    check(m["ts"].Stats.Locked == 0, f"{name}: {m['ts'].Stats.Locked} vehicles removed as locked in a junction")

DOWNTOWN = (80, -80)
BUDGET = CFG.Traffic.MaxVehicles.Desktop.Normal
print(f"[3] downtown, noon, 10 min (vehicle budget {BUDGET}, desktop/Normal)")
m = run("downtown", 600, lambda t: [DOWNTOWN])
report_flow(m, "downtown")
common(m, "downtown")
check(m["ts"].Stats.Entries > 2000, f"downtown: low throughput {m['ts'].Stats.Entries}")
PBUDGET = CFG.Pedestrians.MaxPedestrians.Desktop.Normal
check(m["max_veh"] <= BUDGET + 2 and m["max_peds"] <= PBUDGET + 2, "downtown: caps exceeded")
# yaya hedefleri (eski sistem: geçitte bekleme ~%30, köşede tik başına 180° ani dönme, hız anında 0 ↔ tam)
pw = m["pedWait"] / max(m["pedN"], 1)
check(pw <= 0.25, f"downtown: pedestrians wait at crossings {100*pw:.0f}% of the time")
check(m["pedTurnMax"] <= 40, f"downtown: pedestrian turned {m['pedTurnMax']:.0f} deg in one tick")
check(m["pedAccMax"] <= CFG.Pedestrians.WalkDecel + 0.5, f"downtown: pedestrian speed jump {m['pedAccMax']:.1f}")
check(m["max_peds"] >= 0.9 * PBUDGET, f"downtown: only {m['max_peds']} pedestrians (budget {PBUDGET})")
pst = m["ps"].Stats
check(pst.Entered > 20 and pst.Exited > 20, f"downtown: few building entries/exits ({pst.Entered}/{pst.Exited})")
check(m["badEnter"] == 0, f"downtown: {m['badEnter']} pedestrians vanished away from a doorway")
print(f"    doors: entered {pst.Entered}, exited {pst.Exited}, door goals {pst.DoorGoals}, vanished off-door {m['badEnter']}")
check(m["ps"].Stats.Crossings > 20, f"downtown: few crossings {m['ps'].Stats.Crossings}")
# Yaşayan Şehir hedefleri (eski sistem aynı ölçümle: ort. hız 10.7–12.1, kalkış 0.68–0.71 sn, 24 araçta yoğunluk ~0.1)
check(m["avg_speed"] >= 11.5, f"downtown: average speed {m['avg_speed']:.1f} < 11.5")
check(m["restart"] <= 0.35, f"downtown: restart delay {m['restart']:.2f} s > 0.35")
# titreme = yayaya yol verme ve kuyrukta çizgiye ilerleme DIŞINDAKİ kısa kalk-dur (öndeki araç / engel)
jitter = sum(n for k, n in m["stopgoWhy"].items() if not (k.startswith("pedestrian") or k.startswith("stop:")))
check(jitter <= 0.015 * max(m["starts"], 1), f"downtown: stop-go jitter {jitter}/{m['starts']} {m['stopgoWhy']}")
check(m["boxBlock"] == 0, f"downtown: {m['boxBlock']} vehicles blocked an intersection > 10 s")
dav, dst = m["density"].get("avenue", 0), m["density"].get("street", 0)
check(dav > 1.5 * dst, f"downtown: avenues not denser than streets ({dav:.2f} vs {dst:.2f})")
check(dav >= 0.3, f"downtown: avenue density {dav:.2f} < 0.3 vehicles / 100 studs")

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

# [4b] closed exit: player car parked on the first studs of an avenue out-lane right after a signalized junction
exit_lane = None
for l in lanes:
    n = g.Nodes[l.From]
    if l.Kind == "avenue" and n.Control == "Signal" and n.Degree == 4 and l.Length > 60:
        d = math.hypot(n.X - DOWNTOWN[0], n.Z - DOWNTOWN[1])
        if 120 < d < 300 and (exit_lane is None or d < exit_lane[1]):
            exit_lane = (l, d)
el = exit_lane[0]
ex, ez = el.X0 + el.UX * 7, el.Z0 + el.UZ * 7
print(f"[4b] closed exit: lane {el.Id} (avenue) right after signal node {el.From}, parked car at ({ex:.0f}, {ez:.0f}) for 150 s")
m = run("closed exit", 200, lambda t: [DOWNTOWN], lambda t: [(ex, ez, 4.5, "Vehicle")] if t < 150 else [])
common(m, "closed exit")
check(m["obstacle_violations"] == 0, f"closed exit: vehicles drove through the parked car ({m['obstacle_violations']})")
check(m["boxBlock"] == 0, f"closed exit: {m['boxBlock']} vehicles blocked the intersection > 10 s")
check(m["ts"].Stats.Reroutes > 0, "closed exit: no vehicle chose another direction")
print(f"    closed exit: reroutes {m['ts'].Stats.Reroutes}, lane changes {m['ts'].Stats.LaneChanges}, box-block {m['boxBlock']}")

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
print(f"    jaywalker: moving vehicle inside the walking player 0 required -> {m['obstacle_violations']}; "
      f"player walked into a stopped vehicle (scripted walker, no avoidance): {m['obsStill']} ticks")

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
m2 = run("two players", 300, lambda t: two)
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

# [8] density presets (desktop budgets): count follows the preset, never above the cap
counts = {}
for preset in ("Low", "Normal", "High"):
    cap = CFG.Traffic.MaxVehicles.Desktop[preset]
    mp = run(f"preset {preset}", 120, lambda t: [DOWNTOWN], max_veh=cap, verbose=False, check_peds_road=False)
    common(mp, f"preset {preset}")
    check(mp["max_veh"] <= cap + 2, f"preset {preset}: {mp['max_veh']} vehicles > cap {cap}")
    counts[preset] = (mp["vcount"] / max(mp["densN"], 1), cap)
print("[8] density presets (desktop): " + ", ".join(f"{k} cap {c} -> mean {n:.0f} vehicles" for k, (n, c) in counts.items())
      + "; tablet " + str(dict(CFG.Traffic.MaxVehicles.Tablet.items())) + ", mobile " + str(dict(CFG.Traffic.MaxVehicles.Mobile.items())))
check(counts["Low"][0] < counts["Normal"][0] < counts["High"][0], f"presets not ordered {counts}")

# [9] signal plans
S = CFG.Traffic.Signal
both, mains, wrong_cycle = 0, 0, 0
for n in sig:
    g1, g2 = n.Greens[1], n.Greens[2]
    if g1 != g2:
        mains += 1
    if abs(n.Cycle - (g1 + g2 + 2 * (S.Yellow + S.AllRed))) > 1e-6:
        wrong_cycle += 1
    tt = 0.0
    while tt < n.Cycle:
        a = TG.SignalState(g, n, 1, 1000 + tt)[0]; b = TG.SignalState(g, n, 2, 1000 + tt)[0]
        if a != "R" and b != "R":
            both += 1
        tt += 0.25
check(both == 0, f"signals: {both} samples with both phases green/yellow")
check(wrong_cycle == 0, f"signals: {wrong_cycle} nodes with wrong cycle length")
check(mains > 0, "signals: no main/side road plans")
print(f"[9] signals: {len(sig)} nodes, {mains} with main-road priority ({S.MainGreen}/{S.SideGreen} s), "
      f"others {S.Green}/{S.Green} s, green wave {S.WaveSpeed} studs/s; conflicting-green samples {both}")

# [10] building entrances
g10 = TG.Build(data, CFG.Traffic); pg10 = PG.Build(data, g10)
nlinks0 = len(pg10.Links)
reg = EN.Build(data, pg10, PG, g10)
ents = list(reg.List.values())
lots = {l["Id"]: l for l in raw["lots"]}
bad_face = bad_road = bad_lot = bad_dead = 0
import collections
by_style = collections.Counter()
for e in ents:
    by_style[e.Style] += 1
    lot = lots[e.LotId]
    th = math.radians(lot["Rotation"]); c, s_ = math.cos(th), math.sin(th)
    dx, dz = e.X - lot["Center"].X, e.Z - lot["Center"].Z
    lx, lz = dx * c - dz * s_, dx * s_ + dz * c
    # kapı cephede: lotun içinde ya da en fazla 5.5 stud önünde (saçak/cam giriş), yanlarda taşma yok
    if not (abs(lx) <= lot["Width"] / 2 and -lot["Depth"] / 2 - 5.5 <= lz <= lot["Depth"] / 2):
        bad_face += 1
    a, b = e.Walk, e.Node
    near_lots = [T(o) for o in raw["lots"] if o["Id"] != e.LotId and abs(o["Center"].X - e.X) < 90 and abs(o["Center"].Z - e.Z) < 90]
    for k in range(0, 11):
        f = k / 10
        x, z = a.X + (b.X - a.X) * f, a.Z + (b.Z - a.Z) * f
        r = PG.OnRoad(data, g10, x, z, pg10.Top)
        if (r[0] if isinstance(r, tuple) else r):
            bad_road += 1; break
        if any(EN.InLot(o, x, z, 0.5) for o in near_lots):
            bad_lot += 1; break
    if len(list(b.Links.values())) != 1:
        bad_dead += 1
check(len(ents) >= 1000, f"entrances: only {len(ents)}")
check(bad_face == 0, f"entrances: {bad_face} doors not on their building front")
check(bad_road == 0, f"entrances: {bad_road} door walkways on a road")
check(bad_lot == 0, f"entrances: {bad_lot} door walkways through another lot")
check(bad_dead == 0, f"entrances: {bad_dead} door nodes are not dead ends")
print(f"[10] entrances {len(ents)} (rejected {dict(reg.Rejected.items())}), sidewalk links {nlinks0} -> {len(pg10.Links)}; "
      f"by style {dict(by_style.most_common(8))}; off-facade {bad_face}, on-road {bad_road}, through-lot {bad_lot}")

# [11] procedural walk
def walk_check(speeds_fn, seconds, dt=1 / 60):
    st = PA.new(7); x = 0.0; plant = {"L": None, "R": None}; drift = ground = 0.0; clear = 1e9
    knee = hip = (0, 0); v = 0.0
    for i in range(int(seconds / dt)):
        v = speeds_fn(i * dt, v, dt)
        p = PA.Step(st, dt, v, 0, 0)
        x += v * dt
        for side in ("L", "R"):
            th, k = (p.LHip, p.LKnee) if side == "L" else (p.RHip, p.RKnee)
            knee = (min(knee[0], k), max(knee[1], k)); hip = (min(hip[0], th), max(hip[1], th))
            kx, ky, ax, ay = PA.LegFK(th, k)
            wx, wy = x + ax, p.HipH + ay - PA.ANKLE_Y
            if (p.LStance if side == "L" else p.RStance) and v > 0.8:
                ground = max(ground, abs(wy))
                if plant[side] is None: plant[side] = wx
                drift = max(drift, abs(wx - plant[side]))
            else:
                plant[side] = None
                if v > 0.8: clear = min(clear, wy)
    return drift, ground, clear, knee, hip, p
res = []
for vv in (2.0, 4.2, 5.0, 5.8):
    res.append((vv,) + walk_check(lambda t, v, dt, vv=vv: vv, 6)[:5])
def ramp(t, v, dt):
    target = 5.0 if 1 < t < 4.5 else 0.0
    return min(target, v + 6 * dt) if target > v else max(target, v - 8 * dt)
rd, rg, rc, rk, rh, last = walk_check(ramp, 8)
for vv, d, gr, cl, kn, hp in res + [("ramp", rd, rg, rc, rk, rh)]:
    check(d < 0.15, f"walk {vv}: planted foot slides {d:.3f} studs")
    check(gr < 0.02, f"walk {vv}: stance sole off the ground {gr:.3f}")
    check(cl > -0.02, f"walk {vv}: swing foot below ground {cl:.3f}")
    check(0 <= kn[0] and kn[1] < 2.3 and -1.0 < hp[0] and hp[1] < 1.2, f"walk {vv}: joint limits knee {kn} hip {hp}")
check(abs(last.LFootD) < 0.05 and abs(last.RFootD) < 0.05, "walk: idle feet not under the body")
print("[11] procedural walk: " + "; ".join(f"v={vv}: drift {d:.3f}, sole {gr:.3f}, swing min {cl:.2f}" for vv, d, gr, cl, kn, hp in res)
      + f"; start/stop ramps drift {rd:.3f}; idle feet {abs(last.LFootD):.2f}/{abs(last.RFootD):.2f}")

print("RESULT:", "PASS" if fail == 0 else f"FAIL ({fail})")
sys.exit(1 if fail else 0)
