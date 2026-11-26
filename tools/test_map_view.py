"""Offline test: minimap / full map / GPS view stability.

Runs the REAL code with lupa (Lua 5.4):
  * src/ReplicatedStorage/Shared/MapView.lua (as is)
  * MapCanvas:SetView extracted from FrontEnd/Map/MapCanvas.lua (types / if-expressions / generalized for
    converted), with a fake canvas (UIScale, Root, icons, tiles) that records property writes.
The minimap step (MinimapController) is replicated in the harness with the same constants and the same MapView calls.

Drives a 40 s car profile (accelerate, cruise with speed noise, brake) at several map positions and checks that the
point the player arrow sits on (viewport centre) shows the player's real world position:
  rendered player = Root offset + (x + half) * UIScale  ->  must equal viewport/2 within 0.5 px, every frame.
Also counts UIScale / Root / icon writes, and checks heading. With --old <file> it runs an older MapCanvas.lua the
same way for comparison (the old minimap ran at 30 Hz and passed the smoothed scale straight to SetView).

Usage: python3 -I tools/test_map_view.py <lupa-site-packages> [--old old_MapCanvas.lua]
"""
import math
import os
import random
import re
import sys

sys.path.insert(0, sys.argv[1])
from lupa import LuaRuntime  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPVIEW = os.path.join(ROOT, "src/ReplicatedStorage/Shared/MapView.lua")
CANVAS = os.path.join(ROOT, "src/StarterPlayer/StarterPlayerScripts/FrontEnd/Map/MapCanvas.lua")
old_path = sys.argv[sys.argv.index("--old") + 1] if "--old" in sys.argv else None

HALF = 5120.0
SIZE = 240  # desktop minimap (px)
REF = 200
FOOT, SLOW, FAST = 0.34, 0.22, 0.12
ZOOM_STEP = 0.025
MAXSPEED = 120.0
FPS = 60


def extract_setview(src):
    a = src.index("function MapCanvas:SetView")
    b = src.index("\nfunction MapCanvas:", a + 10)
    f = src[a:b]
    f = re.sub(r"\(cx: number, cz: number, scale: number, viewport: Vector2\)", "(cx, cz, scale, viewport)", f)
    f = re.sub(r"\(if (.+?) then (\S+) else (\S+)\)", r"((\1) and \2 or \3)", f)
    f = re.sub(r"for (\w+), (\w+) in (self\.\w+) do", r"for \1, \2 in pairs(\3) do", f)
    return f


HARNESS = r"""
UDim2 = { fromOffset = function(x, y) return { X = x, Y = y } end }
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
MapCanvas = {}
local function partSize() return 0 end
partSize = partSize
local writes = { UIScale = 0, Root = 0, Icons = 0, Tiles = 0 }
function newCanvas()
  local self = setmetatable({}, { __index = MapCanvas })
  self.Half = HALF
  self.Detail = "Mini"
  self.Scale = -1
  self.IconScale = -1
  self.TileRange = ""
  self.Tiles = {}
  self.FixedIcons = {}
  self.RouteSegments = {}
  self.UIScale = setmetatable({}, { __newindex = function(t, k, v) rawset(t, "_" .. k, v); writes.UIScale = writes.UIScale + 1 end,
    __index = function(t, k) return rawget(t, "_" .. k) end })
  self.Root = setmetatable({}, { __newindex = function(t, k, v) rawset(t, "_" .. k, v); writes.Root = writes.Root + 1 end,
    __index = function(t, k) return rawget(t, "_" .. k) end })
  for i = 1, 90 do
    self.FixedIcons[i] = { Pixels = 13, Gui = setmetatable({}, { __newindex = function(t, k, v) if i == 1 then writes.Icons = writes.Icons + 1 end end }) }
  end
  for tx = 0, 9 do for tz = 0, 9 do
    local tile = { a = { TX = tx, TZ = tz } }
    function tile:GetAttribute(k) return self.a[k] end
    self.Tiles[#self.Tiles + 1] = setmetatable(tile, { __newindex = function(t, k, v) rawset(t, k, v); writes.Tiles = writes.Tiles + 1 end })
  end end
  return self
end
function resetWrites() for k in pairs(writes) do writes[k] = 0 end end
function getWrites() return writes end
"""


def load_canvas(lua, src):
    lua.execute("TILE = 1024")
    lua.execute(extract_setview(src))


def make_runtime(canvas_src):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().HALF = HALF
    lua.execute(HARNESS)
    mapview = lua.execute(open(MAPVIEW, encoding="utf-8").read())
    lua.globals().MapView = mapview
    load_canvas(lua, canvas_src)
    return lua, mapview


def speed_profile(t, rng):
    if t < 10:
        return min(MAXSPEED, MAXSPEED / 8 * t)
    if t < 30:
        return MAXSPEED * 0.85 + MAXSPEED * 0.05 * math.sin(t * 2) + rng.uniform(-2, 2)
    return max(0.0, MAXSPEED * 0.9 - MAXSPEED / 4 * (t - 30))


def drive(lua, mapview, x0, z0, new_pipeline):
    """Simulate 40 s of driving east from (x0, z0). Returns (max err px, max err stud, writes/s)."""
    rng = random.Random(1)
    canvas = lua.eval("newCanvas")()
    lua.eval("resetWrites")()
    viewport = lua.table_from({"X": SIZE, "Y": SIZE})
    cur, applied = FOOT, None
    x, z = x0, z0
    dt = 1 / FPS
    acc = 0.0
    worst_px = worst_st = 0.0
    t = 0.0
    frames = 0
    while t < 40:
        v = speed_profile(t, rng)
        x += v * dt
        z += v * 0.3 * dt
        target = SLOW + (FAST - SLOW) * min(max(v / MAXSPEED, 0), 1)
        if new_pipeline:
            cur += (target - cur) * min(dt * 1.5, 1)
            applied = mapview.ZoomStep(applied, cur, ZOOM_STEP)
            scale = applied * SIZE / REF
            canvas.SetView(canvas, x, z, scale, viewport)
        else:
            acc += dt
            if acc >= 1 / 30:
                cur += (target - cur) * min(acc * 1.5, 1)
                acc = 0
                scale = cur * SIZE / REF
                canvas.SetView(canvas, x, z, scale, viewport)
        if canvas.Root.Position is not None:
            ui = canvas.UIScale.Scale
            px = canvas.Root.Position.X + (x + HALF) * ui - SIZE / 2
            py = canvas.Root.Position.Y + (z + HALF) * ui - SIZE / 2
            err = max(abs(px), abs(py))
            worst_px = max(worst_px, err)
            worst_st = max(worst_st, err / ui)
        t += dt
        frames += 1
    w = lua.eval("getWrites")()
    return worst_px, worst_st, {k: w[k] / 40 for k in ("UIScale", "Root", "Icons", "Tiles")}


failures = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        failures.append(name)


cur_src = open(CANVAS, encoding="utf-8").read()
lua, mv = make_runtime(cur_src)

# --- MapView unit checks
ox, oy = mv.RootOffset(100.3, -50.7, 0.1567, 240, 240, HALF)
check("RootOffset is whole units", ox == int(ox) and oy == int(oy), f"{ox}, {oy}")
check("RootOffset centres world point (<=0.5 px)",
      abs(ox + (100.3 + HALF) * 0.1567 - 120) <= 0.5 and abs(oy + (-50.7 + HALF) * 0.1567 - 120) <= 0.5)
check("ZoomStep keeps value inside step", mv.ZoomStep(0.2, 0.2 * 1.02, ZOOM_STEP) == 0.2)
check("ZoomStep jumps to target outside step", abs(mv.ZoomStep(0.2, 0.2 * 1.03, ZOOM_STEP) - 0.206) < 1e-9)
check("ZoomStep initialises from nil", mv.ZoomStep(None, 0.34, ZOOM_STEP) == 0.34)
for (lx, lz, want) in ((0, -1, 0), (1, 0, 90), (0, 1, 180), (-1, 0, -90)):
    got = mv.Heading(lx, lz, 0)
    check(f"Heading look=({lx},{lz})", abs(mv.AngleDelta(got, want)) < 1e-6, f"{got}")
check("Heading keeps last when vehicle is vertical", mv.Heading(0.05, -0.1, 37) == 37)
check("Heading uses flattened look when pitched", abs(mv.Heading(0.5, 0, 0) - 90) < 1e-6)
check("AngleDelta wraps", abs(mv.AngleDelta(179, -179) - (-2)) < 1e-9)

# --- driving simulation with the real SetView
print()
print("Driving 40 s (60 FPS), map size", SIZE, "px")
for (x0, z0) in ((-4600, -4600), (0, 0), (3800, 3800)):
    px, st, w = drive(lua, mv, x0, z0, True)
    check(f"new: start ({x0},{z0}) arrow on true position", px <= 0.5 + 1e-9,
          f"max {px:.2f} px = {st:.2f} stud; writes/s UIScale {w['UIScale']:.1f} Root {w['Root']:.1f} "
          f"icon-resize {w['Icons']:.1f} tiles {w['Tiles']:.1f}")
    check(f"new: start ({x0},{z0}) zoom relayouts <= 6/s", w["UIScale"] <= 6, f"{w['UIScale']:.2f}/s")

if old_path:
    print()
    print("Old MapCanvas.lua, old minimap pipeline (30 Hz, smoothed scale straight to SetView):")
    lua_old, mv_old = make_runtime(open(old_path, encoding="utf-8").read())
    for (x0, z0) in ((-4600, -4600), (0, 0), (3800, 3800)):
        px, st, w = drive(lua_old, mv_old, x0, z0, False)
        print(f"  old: start ({x0},{z0}) max {px:.1f} px = {st:.1f} stud; writes/s UIScale {w['UIScale']:.1f} "
              f"icon-resize {w['Icons']:.1f}")

print()
print("RESULT:", "PASS" if not failures else "FAIL " + ", ".join(failures))
sys.exit(1 if failures else 0)
