#!/usr/bin/env python3
"""
test_road_surface.py — runs the REAL ServerScriptService/WorldGen/RoadBuilder.lua (Luau, converted on the fly to
Lua 5.4 for this file only) on the REAL MapData with small Vector3/Vector2/CFrame stand-ins and a recording kit, then
drives virtual wheels along every lane: samples the top of the collidable driving surface every 0.25 studs from each
node outwards and reports steps (height jumps not explained by the slope) and gaps (no surface under the lane).

Vehicle stability fix (2025): lane lines / crosswalk stripes must not collide, roads must meet junction pads and
freeway decks without a step, corner discs must be flush.

Usage: python3 tools/test_road_surface.py <lupa-site-packages> [RoadBuilder.lua path]
"""
import sys, re, math
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, "tools")
from lupa import LuaRuntime
import ambient_data

ROAD = sys.argv[2] if len(sys.argv) > 2 else "src/ServerScriptService/WorldGen/RoadBuilder.lua"
STEP_LIMIT = 0.025   # studs: a step bigger than this hits the wheel (lines were 0.03, ramps 0.2–1.3)


def convert(src):
    """Luau -> Lua 5.4 for RoadBuilder only (types, casts, if-expressions, continue, generalized for)."""
    out = []
    for line in src.split("\n"):
        if re.match(r"\s*type \w+ =", line):
            continue
        line = re.sub(r" :: \w+", "", line)
        if "function" in line:
            line = re.sub(r"\)\s*:\s*[^\n]*$", ")", line)                 # return type
            line = re.sub(r"(\w+)\s*:\s*[A-Za-z][\w\.\?]*", r"\1", line)  # parameter types
        m = re.match(r"(\s*local \w+)\s*:\s*.+?(=.*)$", line)
        if m:
            line = m.group(1) + " " + m.group(2)
        m = re.match(r"(\s*for [\w, ]+ in )(\{[^}]*\}|[\w\.\[\]]+)( do.*)$", line)
        if m and not m.group(2).startswith(("pairs", "ipairs")):
            line = m.group(1) + "pairs(" + m.group(2) + ")" + m.group(3)
        line = line.replace("continue", "goto continue") if re.match(r"\s*continue\b", line) else line
        out.append(line)
    text = "\n".join(out)

    # if-expressions -> immediately invoked functions
    def conv_ifexpr(t):
        i = 0
        res = []
        while True:
            m = re.search(r"(=\s*|\(\s*|,\s*)if ", t[i:])
            if not m:
                res.append(t[i:])
                break
            start = i + m.end() - 3
            res.append(t[i:start])
            # parse until end of expression: depth-0 ',' or ')' or newline
            j = start
            depth = 0
            while j < len(t):
                c = t[j]
                if c in "([{":
                    depth += 1
                elif c in ")]}":
                    if depth == 0:
                        break
                    depth -= 1
                elif c == "," and depth == 0:
                    break
                elif c == "\n":
                    break
                j += 1
            expr = t[start:j].strip()
            parts = re.split(r"\b(then|elseif|else)\b", expr[3:])
            body = "if " + parts[0].strip() + " then return " + parts[2].strip()
            k = 3
            while k < len(parts):
                kw = parts[k]
                if kw == "elseif":
                    body += " elseif " + parts[k + 1].strip() + " then return " + parts[k + 3].strip()
                    k += 4
                else:
                    body += " else return " + parts[k + 1].strip()
                    k += 2
            res.append("(function() " + body + " end end)()")
            i = j
        return "".join(res)
    text = conv_ifexpr(text)
    # 'continue' label at the end of the node loop in planNodes
    lines = text.split("\n")
    for idx, l in enumerate(lines):
        if l.startswith("\tfor _, node in pairs(data.NodeList) do") or l.startswith("\tfor _, node in data.NodeList do"):
            for k in range(idx + 1, len(lines)):
                if lines[k] == "\tend":
                    lines.insert(k, "\t\t::continue::")
                    break
            break
    return "\n".join(lines)


MOCK = r"""
math.clamp = function(x, a, b) if x < a then return a elseif x > b then return b end return x end
math.sign = function(x) if x > 0 then return 1 elseif x < 0 then return -1 end return 0 end
local V3 = {}
V3.__index = function(v, k)
  if k == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
  if k == "Unit" then local m = math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z); return Vector3.new(v.X/m, v.Y/m, v.Z/m) end
  return V3[k]
end
Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3) end
V3.__add = function(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V3.__sub = function(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V3.__mul = function(a, b) if type(a) == "number" then a, b = b, a end
  if type(b) == "number" then return Vector3.new(a.X*b, a.Y*b, a.Z*b) end
  return Vector3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z) end
V3.__div = function(a, b) return Vector3.new(a.X/b, a.Y/b, a.Z/b) end
V3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
function V3.Lerp(a, b, t) return a + (b - a) * t end
function V3.Dot(a, b) return a.X*b.X + a.Y*b.Y + a.Z*b.Z end
function V3.Cross(a, b) return Vector3.new(a.Y*b.Z - a.Z*b.Y, a.Z*b.X - a.X*b.Z, a.X*b.Y - a.Y*b.X) end
local V2 = {}
V2.__index = function(v, k)
  if k == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y) end
  if k == "Unit" then local m = math.sqrt(v.X*v.X + v.Y*v.Y); return Vector2.new(v.X/m, v.Y/m) end
  return V2[k]
end
Vector2 = {}
function Vector2.new(x, y) return setmetatable({X = x or 0, Y = y or 0}, V2) end
function V2.Dot(a, b) return a.X*b.X + a.Y*b.Y end
-- CFrame: position P, rotation columns R (right), U (up), B (back)
local CF = {}
CF.__index = function(c, k)
  if k == "Position" then return c.P end
  if k == "UpVector" then return c.U end
  if k == "RightVector" then return c.R end
  if k == "LookVector" then return -c.B end
  return CF[k]
end
CFrame = {}
local function mk(p, r, u, b) return setmetatable({P = p, R = r, U = u, B = b}, CF) end
function CFrame.new(x, y, z)
  local p = (type(x) == "table") and x or Vector3.new(x, y, z)
  return mk(p, Vector3.new(1,0,0), Vector3.new(0,1,0), Vector3.new(0,0,1))
end
function CFrame.lookAt(at, target)
  local look = (target - at).Unit
  local right = look:Cross(Vector3.new(0,1,0))
  if right.Magnitude < 1e-6 then right = Vector3.new(1,0,0) else right = right.Unit end
  local up = right:Cross(look)
  return mk(at, right, up, -look)
end
function CFrame.Angles(x, y, z) return CFrame.new(0,0,0) end -- (kit kayıtçısında kullanılmıyor)
local function apply(c, v) return c.P + c.R * v.X + c.U * v.Y + c.B * v.Z end
local function rot(c, v) return c.R * v.X + c.U * v.Y + c.B * v.Z end
CF.__mul = function(a, b)
  if getmetatable(b) == V3 then return apply(a, b) end
  return mk(apply(a, b.P), rot(a, b.R), rot(a, b.U), rot(a, b.B))
end
Enum = setmetatable({}, {__index = function(_, k) return setmetatable({}, {__index = function(_, j) return k .. "." .. j end}) end})
"""

KIT = r"""
local parts = {}
local kit = {}
kit.Colors = setmetatable({}, {__index = function(_, k) return k end})
function kit.StripCFrame(a, b, thickness, lateral)
  local mid = (a + b) / 2
  local length = (b - a).Magnitude
  local cf
  if length < 1e-3 then cf = CFrame.new(mid) else cf = CFrame.lookAt(mid, b) end
  return cf * CFrame.new(lateral or 0, -thickness / 2, 0), length
end
function kit:Folder(parent, name) return { Name = name, Parent = parent } end
local function record(kind, parent, size, cf, props, extra)
  local collide = true
  if props and props.CanCollide == false then collide = false end
  local p = { Kind = kind, Folder = parent.Name, Size = size, CF = cf, Collide = collide, Diameter = extra }
  parts[#parts + 1] = p
  return setmetatable({ SetAttribute = function() end }, { __newindex = function(t, k, v) rawset(t, k, v) end })
end
function kit:Box(parent, size, cf, color, material, props) return record("Box", parent, size, cf, props) end
function kit:Cylinder(parent, height, diameter, cf, color, material, props)
  return record("Disc", parent, Vector3.new(height, diameter, diameter), cf, props, diameter)
end
function kit:Wedge(parent, size, cf, color, material, props) return record("Wedge", parent, size, cf, props) end
return kit, parts
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
data, raw = ambient_data.load(lua)
# Position tables -> Vector3
lua.execute("""
return function(data)
  for _, n in pairs(data.Nodes) do n.Position = Vector3.new(n.Position.X, n.Position.Y, n.Position.Z) end
end
""")(data)
kit, parts = lua.execute(KIT)
lua.globals().__MAPDEFS = lua.table_from({"GetData": lua.eval("function() return __DATA end")})
lua.globals().__DATA = data
lua.execute("""
game = { GetService = function(_, name) return { Shared = { MapDefinitions = '__MD' } } end }
local realRequire = require
require = function(x) if x == '__MD' then return __MAPDEFS end return realRequire(x) end
""")
src = convert(open(ROAD, encoding="utf-8").read())
RB = lua.execute(src)
RB.Build(kit, lua.table_from({"Name": "World"}))

# ---- index collidable driving surfaces (road strips + junction pads + fillers)
lua_parts = list(parts.values())
surf = []
markings_collide = 0
markings_total = 0
for p in lua_parts:
    if p.Folder == "Markings" and p.Size.Y <= 0.07:
        markings_total += 1
        if p.Collide:
            markings_collide += 1
    if p.Folder not in ("Surfaces", "Intersections") or not p.Collide:
        continue
    cf = p.CF
    if p.Kind == "Disc":
        surf.append(("disc", cf.P.X, cf.P.Y + p.Size.X / 2, cf.P.Z, p.Diameter / 2))
    else:
        surf.append(("box", cf.P.X, cf.P.Y, cf.P.Z, (cf.R.X, cf.R.Y, cf.R.Z), (cf.U.X, cf.U.Y, cf.U.Z),
                     (cf.B.X, cf.B.Y, cf.B.Z), p.Size.X / 2, p.Size.Y / 2, p.Size.Z / 2))
GRID = 32.0
grid = {}
for s in surf:
    if s[0] == "disc":
        r = s[4]; x0, x1, z0, z1 = s[1] - r, s[1] + r, s[3] - r, s[3] + r
    else:
        ext = abs(s[4][0]) * s[7] + abs(s[6][0]) * s[9] + abs(s[5][0]) * s[8]
        ezt = abs(s[4][2]) * s[7] + abs(s[6][2]) * s[9] + abs(s[5][2]) * s[8]
        x0, x1, z0, z1 = s[1] - ext, s[1] + ext, s[3] - ezt, s[3] + ezt
    for i in range(int(math.floor(x0 / GRID)), int(math.floor(x1 / GRID)) + 1):
        for j in range(int(math.floor(z0 / GRID)), int(math.floor(z1 / GRID)) + 1):
            grid.setdefault((i, j), []).append(s)


def top_at(x, z, near_y):
    best = None
    for s in grid.get((int(math.floor(x / GRID)), int(math.floor(z / GRID))), ()):
        if s[0] == "disc":
            if (x - s[1]) ** 2 + (z - s[3]) ** 2 <= s[4] ** 2 + 1e-6:
                h = s[2]
            else:
                continue
        else:
            _, px, py, pz, R, U, B, hx, hy, hz = s
            if abs(U[1]) < 1e-6:
                continue
            # height where the point lies on the top face (local y = +hy)
            y = py + (hy - U[0] * (x - px) - U[2] * (z - pz)) / U[1]
            dx, dy, dz = x - px, y - py, z - pz
            lx = R[0] * dx + R[1] * dy + R[2] * dz
            lz = B[0] * dx + B[1] * dy + B[2] * dz
            if abs(lx) > hx + 1e-4 or abs(lz) > hz + 1e-4:
                continue
            h = y
        if abs(h - near_y) > 6:
            continue  # other level (bridge above / road below)
        if best is None or h > best:
            best = h
    return best


steps, gaps, samples = [], 0, 0
gap_where = []
nodes, edges = raw["nodes"], raw["edges"]
for eid, e in edges.items():
    A, B = nodes[e["A"]]["Position"], nodes[e["B"]]["Position"]
    dx, dz = B.X - A.X, B.Z - A.Z
    L = math.hypot(dx, dz)
    if L < 4:
        continue
    ux, uz = dx / L, dz / L
    rx, rz = -uz, ux
    lanes = [0.0, e["Width"] / 4, -e["Width"] / 4]
    for end, (P, sign) in enumerate(((A, 1), (B, -1))):
        for off in lanes:
            prev = None
            dist = 0.0
            reach = min(45.0, L / 2)
            while dist <= reach:
                t = dist / L if sign == 1 else 1 - dist / L
                x = A.X + dx * t + rx * off
                z = A.Z + dz * t + rz * off
                ny = A.Y + (B.Y - A.Y) * t
                h = top_at(x, z, ny)
                samples += 1
                if h is None:
                    gaps += 1
                    gap_where.append((e["Kind"], eid, (e["A"], e["B"])[end], len(nodes[(e["A"], e["B"])[end]]["Edges"]), round(dist, 2), off))
                    prev = None
                else:
                    if prev is not None:
                        slope = (B.Y - A.Y) / L * 0.25
                        jump = abs((h - prev[0]) - slope * (1 if sign == 1 else -1))
                        if jump > STEP_LIMIT:
                            # gerçek basamak mı (süreksizlik) yoksa eğim kırılması mı? 0.01 aralıkla yeniden ölç
                            def at(dd):
                                tt = dd / L if sign == 1 else 1 - dd / L
                                return top_at(A.X + dx * tt + rx * off, A.Z + dz * tt + rz * off, A.Y + (B.Y - A.Y) * tt)
                            worst = 0.0
                            k = dist - 0.25
                            while k < dist:
                                h1, h2 = at(k), at(k + 0.01)
                                if h1 is not None and h2 is not None:
                                    worst = max(worst, abs(h2 - h1))
                                k += 0.01
                            if worst > STEP_LIMIT:
                                steps.append((round(worst, 3), e["Kind"], eid, (e["A"], e["B"])[end], round(dist, 1), off))
                    prev = (h,)
                dist += 0.25

steps.sort(reverse=True)
print(f"road builder: {ROAD}")
print(f"surfaces {len(surf)}, lane samples {samples}, no-surface samples {gaps}")
import collections as _c
print("no-surface by (kind, node degree):", dict(_c.Counter((g[0], g[3]) for g in gap_where)), "max dist from node:", max([g[4] for g in gap_where] or [0]))
print(f"thin markings {markings_total}, collidable {markings_collide}")
print(f"steps > {STEP_LIMIT} along lanes: {len(steps)}" + (f", largest {steps[0][0]}" if steps else ""))
import collections
c = collections.Counter((s[1], round(s[0], 2)) for s in steps)
for k, v in c.most_common(12):
    print(f"   {v:4d} x {k}")
for st in steps[:6]:
    print("   e.g. step %.3f on %s edge %d near node %d at %.1f studs, lane offset %.1f" % st)
fail = 0
if markings_collide:
    print("FAIL collidable thin markings:", markings_collide); fail += 1
if steps:
    print("FAIL steps on lanes:", len(steps)); fail += 1
print("RESULT:", "PASS" if fail == 0 else f"FAIL ({fail})")
sys.exit(1 if fail else 0)
