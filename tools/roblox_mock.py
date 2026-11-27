"""roblox_mock.py — small Roblox stand-ins (Vector3, CFrame, Color3, Enum, Instance tree, Random) for running the
game's Luau modules offline in Lua 5.4 (lupa) after tools/luau2lua.py. Shared by tools/test_cars.py and
tools/test_trafficlights.py. Only what those modules use is implemented."""

MOCK = r"""
local V3 = {}
Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3) end
V3.__index = function(v, k)
  if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
  if k == "Unit" then local m = math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z); return Vector3.new(v.X/m, v.Y/m, v.Z/m) end
  if k == "Dot" then return function(a, b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
  if k == "Cross" then return function(a, b) return Vector3.new(a.Y*b.Z-a.Z*b.Y, a.Z*b.X-a.X*b.Z, a.X*b.Y-a.Y*b.X) end end
  if k == "Min" then return function(a, b) return Vector3.new(math.min(a.X,b.X), math.min(a.Y,b.Y), math.min(a.Z,b.Z)) end end
  if k == "Max" then return function(a, b) return Vector3.new(math.max(a.X,b.X), math.max(a.Y,b.Y), math.max(a.Z,b.Z)) end end
end
V3.__add = function(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V3.__sub = function(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V3.__div = function(a, b) return Vector3.new(a.X/b, a.Y/b, a.Z/b) end
V3.__mul = function(a, b) if type(a) == "number" then a, b = b, a end
  if type(b) == "number" then return Vector3.new(a.X*b, a.Y*b, a.Z*b) end
  return Vector3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z) end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
local CF = {}
CFrame = {}
local function mk(p, r) return setmetatable({P = p, R = r}, CF) end
local I = {1,0,0, 0,1,0, 0,0,1}
local function mm(a, b) local r = {}
  for i = 0, 2 do for j = 0, 2 do r[i*3+j+1] = a[i*3+1]*b[j+1] + a[i*3+2]*b[3+j+1] + a[i*3+3]*b[6+j+1] end end
  return r end
local function mv(r, v) return Vector3.new(r[1]*v.X+r[2]*v.Y+r[3]*v.Z, r[4]*v.X+r[5]*v.Y+r[6]*v.Z, r[7]*v.X+r[8]*v.Y+r[9]*v.Z) end
local function tr(r) return {r[1],r[4],r[7], r[2],r[5],r[8], r[3],r[6],r[9]} end
function CFrame.new(x, y, z) if type(x) == "table" then return mk(x, I) end return mk(Vector3.new(x or 0, y or 0, z or 0), I) end
function CFrame.fromMatrix(p, rx, ry)
  local rz = rx:Cross(ry)
  return mk(p, {rx.X, ry.X, rz.X, rx.Y, ry.Y, rz.Y, rx.Z, ry.Z, rz.Z})
end
function CFrame.Angles(ax, ay, az)
  local cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
  return mk(Vector3.new(0,0,0), mm(mm({1,0,0, 0,cx,-sx, 0,sx,cx}, {cy,0,sy, 0,1,0, -sy,0,cy}), {cz,-sz,0, sz,cz,0, 0,0,1}))
end
CF.__index = function(c, k)
  if k == "Position" then return c.P end
  if k == "Rotation" then return mk(Vector3.new(0,0,0), c.R) end
  if k == "LookVector" then return Vector3.new(-c.R[3], -c.R[6], -c.R[9]) end
  if k == "ToObjectSpace" then return function(self, o) local it = tr(self.R); return mk(mv(it, o.P - self.P), mm(it, o.R)) end end
  if k == "PointToObjectSpace" then return function(self, v) return mv(tr(self.R), v - self.P) end end
end
CF.__mul = function(a, b) if getmetatable(b) == V3 then return a.P + mv(a.R, b) end return mk(a.P + mv(a.R, b.P), mm(a.R, b.R)) end

local C3 = {}
C3.__index = function(c, k)
  if k == "Lerp" then return function(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end end
end
C3.__eq = function(a, b) return math.abs(a.R-b.R) < 1e-9 and math.abs(a.G-b.G) < 1e-9 and math.abs(a.B-b.B) < 1e-9 end
Color3 = {}
function Color3.new(r, g, b) return setmetatable({R = r, G = g, B = b}, C3) end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
function Color3.fromHex(h) return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)) end
Enum = setmetatable({}, {__index = function(_, k) return setmetatable({}, {__index = function(_, j) return k .. "." .. j end}) end})

-- Instance stand-in: properties, children (also reachable as obj.ChildName), attributes
local Obj = {}
local methods = {}
Obj.__index = function(t, k)
  local m = methods[k]
  if m then return m end
  local v = rawget(t, "_p")[k]
  if v ~= nil then return v end
  if k == "Position" and rawget(t, "_p").CFrame then return rawget(t, "_p").CFrame.Position end
  for _, c in ipairs(rawget(t, "_c")) do if c.Name == k then return c end end
  return nil
end
Obj.__newindex = function(t, k, v)
  local p = rawget(t, "_p")
  if k == "Parent" then
    local old = p.Parent
    if old then local list = rawget(old, "_c"); for i, c in ipairs(list) do if c == t then table.remove(list, i) break end end end
    if v then table.insert(rawget(v, "_c"), t) end
  end
  p[k] = v
end
function new(cls, props)
  local o = setmetatable({_cls = cls, _p = {Name = cls}, _c = {}, _a = {}}, Obj)
  for k, v in pairs(props or {}) do o[k] = v end
  return o
end
function methods.IsA(t, c) return t._cls == c or (c == "BasePart" and (t._cls == "MeshPart" or t._cls == "Part")) end
function methods.GetChildren(t) local out = {}; for i, c in ipairs(t._c) do out[i] = c end; return out end
function methods.GetDescendants(t)
  local out = {}
  local function walk(o) for _, c in ipairs(o._c) do out[#out + 1] = c; walk(c) end end
  walk(t); return out
end
function methods.FindFirstChild(t, n) for _, c in ipairs(t._c) do if c.Name == n then return c end end return nil end
function methods.WaitForChild(t, n) return methods.FindFirstChild(t, n) end
function methods.Destroy(t) t.Parent = nil; t._destroyed = true end
function methods.Clone(t)
  local q = new(t._cls)
  for k, v in pairs(t._p) do if k ~= "Parent" then q._p[k] = v end end
  for k, v in pairs(t._a) do q._a[k] = v end
  for _, c in ipairs(t._c) do local cc = c:Clone(); cc.Parent = q end
  return q
end
function methods.SetAttribute(t, k, v) t._a[k] = v end
function methods.GetAttribute(t, k) return t._a[k] end
Instance = { new = function(cls) return new(cls) end }

-- extras used by SignalRenderer
function CFrame.lookAt(at, target)
  local f = (target - at).Unit
  local r = f:Cross(Vector3.new(0, 1, 0)).Unit
  local u = r:Cross(f)
  return CFrame.fromMatrix(at, r, u)
end
local oldIndex = CF.__index
CF.__index = function(c, k)
  if k == "Inverse" then return function(self) local it = tr(self.R); return mk(-mv(it, self.P), it) end end
  return oldIndex(c, k)
end
function methods.PivotTo(t, target)
  local pp = t.PrimaryPart
  local delta = target * pp.CFrame:Inverse()
  for _, d in ipairs(t:GetDescendants()) do
    if d.CFrame then d.CFrame = delta * d.CFrame end
  end
end
function typeof(v)
  local mt = getmetatable(v)
  if mt == C3 then return "Color3" elseif mt == V3 then return "Vector3" elseif mt == CF then return "CFrame" end
  return type(v)
end
TAGS = {}
CollectionService = { AddTag = function(_, inst, tag) TAGS[#TAGS + 1] = { inst, tag } end }

WARNED = 0
warn = function(...) WARNED = WARNED + 1; print("warn", ...) end

-- Random with a fixed sequence
local RND = {}
RND.__index = RND
function RND:NextNumber() self.s = (self.s * 1103515245 + 12345) % 2147483648; return self.s / 2147483648 end
function RND:NextInteger(a, b) return a + math.floor(self:NextNumber() * (b - a + 1)) end
Random = { new = function(seed) return setmetatable({s = seed or 1}, RND) end }
"""
