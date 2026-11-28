#!/usr/bin/env python3
"""test_npcchat.py — talking to pedestrians (AI chat through Roblox's TextGenerator). The REAL NPCChatService (server)
and the REAL NPCChat panel (client) run together in Lua 5.4 (lupa) with small Roblox stand-ins: TextGenerator,
TextService (filter), TextChatService (chat permission), a mini task scheduler, the REAL MapData districts / POIs.
  Server
  [1] persona from the seed: same seed + gender -> same person; F -> female name, M -> male; many different people
  [2] system prompt: name, age, job, district at the position, nearby places, time of day, the safety rules
  [3] greeting (no message): one TextGenerator per player and pedestrian with the prompt and settings; reply trimmed,
      filtered for the player; conversation token returned
  [4] message: filtered (broadcast) before the model sees it; filtered echo back; token passed on; same generator
  [5] long reply cut to MaxReplyLength; reply filter applied
  [6] bad requests (not a table, no / NaN seed, no position, NaN position, bad message) -> fallback, model not called;
      player too far from the pedestrian -> nothing
  [7] rate limit: 3 quick messages, the 4th is "busy"; refills over time
  [8] accounts without chat permission: canned greeting, no free text, model not called
  [9] model error -> fallback line, token kept, warned once; filter failure -> fallback
  [10] at most MaxGenerators per player (oldest dropped); idle ones cleaned up; all dropped when the player leaves;
       the remote handler never throws
  Client panel (NPCChat) against the server above
  [11] start: panel opens, greeting in the bubble and the log, name / job in the header
  [12] typing + send: filtered "Sen" line, reply, box cleared, token sent back next time
  [13] while waiting: "..." bubble, input locked, a second send ignored; unlocked after the reply
  [14] long typing cut to MaxMessageLength; Enter sends
  [15] no chat permission: input hidden with a note; close button: OnClose, panel hidden; late reply ignored
  [16] remote failure: fallback line, input unlocked; bubble hides after BubbleSeconds
  Pedestrian (PedRenderer)
  [17] Gender from the realistic model id (F / M), "N" for code-built peds; "Konuş" [E] prompt built once, off by
       default, turned off when the ped goes back to the pool
Usage: python3 -I tools/test_npcchat.py <lupa-site-packages>
"""
import os
import sys

sys.path.insert(0, sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
from lupa import LuaRuntime  # noqa: E402
from luau2lua import convert  # noqa: E402
import roblox_mock  # noqa: E402

fails = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        fails.append(name)


def src(path):
    return convert(open(path, encoding="utf-8").read())


# REAL map districts and POIs, shaped like MapDefinitions.GetData() (D and P lines, same fields as MapDefinitions.parse)
def map_data():
    districts, pois = [], []
    for line in open("src/ReplicatedStorage/Shared/MapData.lua", encoding="utf-8").read().split("\n"):
        f = line.split("|")
        if f[0] == "D":
            districts.append(dict(Id=f[1], Name=f[2], MinX=float(f[4]), MinZ=float(f[5]), MaxX=float(f[6]),
                                  MaxZ=float(f[7])))
        elif f[0] == "P":
            pois.append(dict(Id=f[1], Type=f[2], Name=f[3], X=float(f[4]), Z=float(f[5])))
    return districts, pois


ENV = r"""
-- ===== mini scheduler: task.spawn runs now as a coroutine; task.wait yields until the test resumes it
SLEEPING, DELAYED, CLOCK = {}, {}, 1000
os.clock = function() return CLOCK end
task = {}
function task.spawn(f, ...)
  local co = coroutine.create(f)
  local ok, err = coroutine.resume(co, ...)
  if not ok then error(err, 0) end
  return co
end
function task.wait(s)
  local co = coroutine.running()
  SLEEPING[#SLEEPING + 1] = co
  return coroutine.yield()
end
function task.delay(s, f) DELAYED[#DELAYED + 1] = { At = CLOCK + s, F = f } end
function RESUME_ALL()
  local list = SLEEPING; SLEEPING = {}
  local errs = {}
  for _, co in ipairs(list) do
    local ok, err = coroutine.resume(co)
    if not ok then errs[#errs + 1] = tostring(err) end
  end
  return #list, table.concat(errs, "; ")
end
function RUN_DELAYED()
  local keep = {}
  for _, d in ipairs(DELAYED) do if d.At <= CLOCK then d.F() else keep[#keep + 1] = d end end
  DELAYED = keep
end

-- ===== small Roblox pieces the UI uses
Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0 } end }
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2 = { new = function(a, b, c, d) return { X = UDim.new(a, b), Y = UDim.new(c, d) } end,
          fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end, fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end }
local function Signal()
  local s = { _f = {} }
  function s:Connect(f) self._f[#self._f + 1] = f; return { Disconnect = function() end } end
  function s:Fire(...) for _, f in ipairs(self._f) do f(...) end end
  return s
end
SIGNAL = Signal
local baseNew = Instance.new
Instance.new = function(cls)
  local o = baseNew(cls)
  if cls == "TextButton" then o.Activated = Signal() end
  if cls == "TextBox" then
    o.FocusLost = Signal(); o._changed = Signal()
    o.GetPropertyChangedSignal = function(self, prop) return self._changed end
    o.ReleaseFocus = function(self) RELEASED = (RELEASED or 0) + 1 end
  end
  if cls == "TextGenerator" then
    o.Seed = 0; o.Temperature = 0.7; o.TopP = 0.9
    o.GenerateTextAsync = function(self, req)
      GEN_CALLS[#GEN_CALLS + 1] = { Gen = self, UserPrompt = req.UserPrompt, ContextToken = req.ContextToken, MaxTokens = req.MaxTokens }
      return REPLY(self, req)
    end
    GENS[#GENS + 1] = o
  end
  return o
end
GEN_CALLS, GENS = {}, {}
TOK = 0
function DEFAULT_REPLY(self, req)
  TOK = TOK + 1
  return { GeneratedText = "  Merhaba! Bugün hava çok güzel.  ", ContextToken = "ctx" .. TOK, Model = "mock-1" }
end
REPLY = DEFAULT_REPLY

-- ===== services
BAD = { "kotukelime" }
FILTER_FAIL = false
local function hash(text)
  for _, w in ipairs(BAD) do text = string.gsub(text, w, string.rep("#", #w)) end
  return text
end
FILTER_CALLS = {}
TextService = { FilterStringAsync = function(self, text, uid, ctx)
  if FILTER_FAIL then error("filter down") end
  FILTER_CALLS[#FILTER_CALLS + 1] = { Text = text, Uid = uid, Ctx = ctx }
  return {
    GetNonChatStringForBroadcastAsync = function(self) LAST_FILTER_KIND = "broadcast"; return hash(text) end,
    GetNonChatStringForUserAsync = function(self, u) LAST_FILTER_KIND = "user"; return hash(text) end,
  }
end }
CAN_CHAT = {}
TextChatService = { CanUserChatAsync = function(self, uid) CAN_CHAT_ASKED = (CAN_CHAT_ASKED or 0) + 1; return CAN_CHAT[uid] ~= false end }
Lighting = { ClockTime = 15.0 }
PlayersService = { PlayerRemoving = Signal(), LocalPlayer = nil }
SS = new("ServerStorage")
RS = new("ReplicatedStorage")
local shared = new("Folder", { Name = "Shared", Parent = RS })
local modules = new("Folder", { Name = "Modules", Parent = RS })
local util = new("Folder", { Name = "Utilities", Parent = shared })
MARK = {
  RemoteRegistry = new("ModuleScript", { Name = "RemoteRegistry", Parent = shared }),
  MapDefinitions = new("ModuleScript", { Name = "MapDefinitions", Parent = shared }),
  Businesses = new("ModuleScript", { Name = "Businesses", Parent = shared }),
  RateLimiter = new("ModuleScript", { Name = "RateLimiter", Parent = util }),
  Log = new("ModuleScript", { Name = "Log", Parent = util }),
  NPCChatConfig = new("ModuleScript", { Name = "NPCChatConfig", Parent = modules }),
}
MODS = {}
WARNS = {}
MODS.Log = { new = function() return {
  Warn = function(...) WARNS[#WARNS + 1] = table.concat({ tostring(select(1, ...)), tostring(select(2, ...)) }, " ") end,
  Info = function() end, Error = function(...) WARNS[#WARNS + 1] = "E " .. tostring(select(1, ...)) end,
} end }
-- RateLimiter: same token bucket as Shared/Utilities/RateLimiter (its multi-line export type is not convertible here)
MODS.RateLimiter = { new = function(cap, refill)
  local b = {}
  return {
    Check = function(self, key)
      local now = os.clock()
      local s = b[key] or { tokens = cap, last = now }
      b[key] = s
      s.tokens = math.min(cap, s.tokens + (now - s.last) * refill); s.last = now
      if s.tokens >= 1 then s.tokens = s.tokens - 1; return true end
      return false
    end,
    Forget = function(self, key) b[key] = nil end,
  }
end }
REMOTE = new("RemoteFunction", { Name = "Talk" })
MODS.RemoteRegistry = { Get = function(group, name) assert(group == "NPCRemotes" and name == "Talk"); return REMOTE end }
local realRequire = require
require = function(x)
  for k, m in pairs(MARK) do if x == m then return MODS[k] end end
  return realRequire(x)
end
game = { GetService = function(_, n)
  if n == "Players" then return PlayersService elseif n == "ReplicatedStorage" then return RS
  elseif n == "ServerStorage" then return SS elseif n == "TextService" then return TextService
  elseif n == "TextChatService" then return TextChatService elseif n == "Lighting" then return Lighting end
  error("service " .. n)
end }
print = function() end

function PLAYER(uid, x, z)
  local p = new("Player", { Name = "P" .. uid, UserId = uid })
  local char = new("Model", { Name = "Char" })
  new("Part", { Name = "HumanoidRootPart", CFrame = CFrame.new(x, 3, z), Parent = char })
  p.Character = char
  new("PlayerGui", { Name = "PlayerGui", Parent = p })
  p.FindFirstChildOfClass = function(self, cls) for _, c in ipairs(self:GetChildren()) do if c._cls == cls then return c end end end
  return p
end
function REQ(seed, gender, x, z, msg, token) return { Seed = seed, Gender = gender, Position = Vector3.new(x, 0, z), Message = msg, Token = token } end
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(roblox_mock.MOCK + ENV)
g = lua.globals()
districts, pois = map_data()
T = lua.table_from
vec = lua.eval("Vector3.new")
v2 = lua.eval("Vector2.new")
data = T({
    "Districts": T([T({"Id": d["Id"], "Name": d["Name"], "Min": v2(d["MinX"], d["MinZ"]), "Max": v2(d["MaxX"], d["MaxZ"])})
                    for d in districts]),
    "POIs": T([T({"Id": p["Id"], "Type": p["Type"], "Name": p["Name"], "Position": vec(p["X"], 0, p["Z"])}) for p in pois]),
})
g.MODS.MapDefinitions = lua.eval("function(d) return { GetData = function() return d end } end")(data)
g.MODS.Businesses = lua.execute(open("src/ReplicatedStorage/Shared/Businesses.lua", encoding="utf-8").read())
CFG = lua.execute(src("src/ReplicatedStorage/Modules/NPCChatConfig.lua"))
g.MODS.NPCChatConfig = CFG
SVC = lua.execute(src("src/ServerScriptService/Services/NPCChatService.lua"))
SVC.Init(SVC)
SVC.Start(SVC)
cleanup_co = len(list(g.SLEEPING.values()))

# a district with a named POI inside it to stand in
spot = None
for d in districts:
    inside = [p for p in pois if d["MinX"] <= p["X"] <= d["MaxX"] and d["MinZ"] <= p["Z"] <= d["MaxZ"] and p["Name"]]
    if inside:
        spot = (d, inside[0])
        break
D, POI = spot
PX, PZ = POI["X"] + 3, POI["Z"] + 3
smallest = None
for d in districts:
    if d["MinX"] <= PX <= d["MaxX"] and d["MinZ"] <= PZ <= d["MaxZ"]:
        area = (d["MaxX"] - d["MinX"]) * (d["MaxZ"] - d["MinZ"])
        if smallest is None or area < smallest[0]:
            smallest = (area, d["Name"])
DISTRICT_NAME = smallest[1]

# ---------------- [1] persona
persona = SVC.Persona
same = all(persona(s, gd).Name == persona(s, gd).Name and persona(s, gd).Job == persona(s, gd).Job
           for s in (0.123, 0.5, 0.987654) for gd in ("F", "M", "N"))
fem = set(CFG.FemaleNames.values())
mal = set(CFG.MaleNames.values())
fem_ok = all(persona(i / 37.0, "F").First in fem and persona(i / 37.0, "F").Female for i in range(40))
mal_ok = all(persona(i / 37.0, "M").First in mal and not persona(i / 37.0, "M").Female for i in range(40))
names = {persona(i / 41.0, "N").Name for i in range(40)}
jobs = {persona(i / 41.0, "N").Job for i in range(40)}
ages = [persona(i / 41.0, "N").Age for i in range(40)]
check("[1] persona: same seed -> same person; F/M names follow the model; varied people",
      same and fem_ok and mal_ok and len(names) >= 30 and len(jobs) >= 10 and min(ages) >= 22 and max(ages) <= 66,
      f"{len(names)} names, {len(jobs)} jobs in 40 seeds, ages {min(ages)}-{max(ages)}")

# ---------------- [2] system prompt
p0 = persona(0.25, "F")
prompt = SVC.SystemPrompt(p0, vec(PX, 0, PZ))
need = [p0.Name, str(p0.Age), p0.Job, DISTRICT_NAME, POI["Name"], "öğleden sonra", "iki kısa cümle", "Yapay zekâ",
        "Kişisel bilgi", "hangi dilde"]
missing = [n for n in need if n not in prompt]
check("[2] system prompt has the person, district, nearby places, time of day and the rules", not missing and "'sın" not in prompt,
      f"missing {missing}" if missing else f"{len(prompt)} chars, district {DISTRICT_NAME}, place {POI['Name']}")

# ---------------- [3] greeting
P1 = g.PLAYER(101, PX + 2, PZ)
talk = SVC.Talk
r = talk(P1, g.REQ(0.25, "F", PX, PZ, None, None))
calls = list(g.GEN_CALLS.values())
gen = calls[0].Gen if calls else None
check("[3] greeting: one generator with the persona prompt and settings; trimmed reply; token; name and job",
      r.Ok and r.Text == "Merhaba! Bugün hava çok güzel." and r.Token == "ctx1" and r.Name == p0.Name and r.Job == p0.Job
      and len(calls) == 1 and calls[0].ContextToken is None and calls[0].MaxTokens == CFG.MaxTokens
      and "selam" in calls[0].UserPrompt and gen.SystemPrompt == prompt and abs(gen.Temperature - CFG.Temperature) < 1e-9
      and abs(gen.TopP - CFG.TopP) < 1e-9 and gen.Parent is not None and gen.Parent.Name == "NPCChatGenerators"
      and g.LAST_FILTER_KIND == "user",
      f"text {r.Text!r}, token {r.Token}")

# ---------------- [4] message
g.CLOCK = g.CLOCK + 10
r2 = talk(P1, g.REQ(0.25, "F", PX, PZ, "selam kotukelime nasilsin", r.Token))
calls = list(g.GEN_CALLS.values())
check("[4] message filtered before the model, filtered echo, token passed on, same generator",
      r2.Ok and r2.You == "selam ########## nasilsin" and calls[1].UserPrompt == r2.You and calls[1].ContextToken == "ctx1"
      and lua.eval("function(a, b) return a == b end")(calls[1].Gen, gen) and r2.Token == "ctx2" and len(list(g.GENS.values())) == 1,
      f"you {r2.You!r}, model saw {calls[1].UserPrompt!r}")

# ---------------- [5] long reply + reply filter
g.CLOCK = g.CLOCK + 10
lua.execute('REPLY = function() return { GeneratedText = string.rep("çok uzun cevap ", 40) .. " kotukelime", ContextToken = "ctxL" } end')
r3 = talk(P1, g.REQ(0.25, "F", PX, PZ, "anlat", "ctx2"))
n = lua.eval("utf8.len")(r3.Text)
check("[5] long reply cut to MaxReplyLength (+ …); reply filtered for the player",
      r3.Ok and n == CFG.MaxReplyLength + 1 and r3.Text.endswith("…") and g.LAST_FILTER_KIND == "user", f"{n} chars")
lua.execute("REPLY = DEFAULT_REPLY")

# ---------------- [6] bad requests
g.CLOCK = g.CLOCK + 60
before = len(list(g.GEN_CALLS.values()))
bad = lua.eval("""function(talk, P, px, pz)
  local out = {}
  local nan = 0 / 0
  local cases = {
    "hello", {}, { Seed = "1", Position = Vector3.new(px, 0, pz) }, { Seed = nan, Position = Vector3.new(px, 0, pz) },
    { Seed = 1e9, Position = Vector3.new(px, 0, pz) }, { Seed = 0.3 }, { Seed = 0.3, Position = { X = 1, Y = 2, Z = 3 } },
    { Seed = 0.3, Position = Vector3.new(nan, 0, pz) }, { Seed = 0.3, Position = Vector3.new(px, 0, pz), Message = 5 },
    { Seed = 0.3, Position = Vector3.new(px, 0, pz), Message = "" },
    { Seed = 0.3, Position = Vector3.new(px, 0, pz), Message = "\\255\\254" },
  }
  for i, c in ipairs(cases) do
    CLOCK = CLOCK + 10
    local r = talk(P, c)
    out[#out + 1] = (r.Ok and "ok" or "no") .. ":" .. tostring(r.Text ~= nil and r.Text ~= "")
  end
  CLOCK = CLOCK + 10
  local far = talk(P, REQ(0.3, "M", px + 80, pz, "selam"))
  out[#out + 1] = (far.Ok and "ok" or "no") .. ":" .. tostring(far.Text == "")
  return table.concat(out, ",")
end""")(talk, P1, PX, PZ)
after = len(list(g.GEN_CALLS.values()))
check("[6] bad requests -> fallback line without calling the model; too far -> nothing",
      all(x == "no:true" for x in bad.split(",")) and after == before, f"{bad} model calls +{after - before}")

# ---------------- [7] rate limit
g.CLOCK = g.CLOCK + 100
P2 = g.PLAYER(202, PX, PZ + 1)
res = [talk(P2, g.REQ(0.6, "M", PX, PZ, "merhaba")) for _ in range(4)]
g.CLOCK = g.CLOCK + 4.1
res.append(talk(P2, g.REQ(0.6, "M", PX, PZ, "tekrar merhaba")))
check("[7] rate limit: 3 quick messages pass, the 4th is busy, one more after 4 s",
      all(x.Ok for x in res[:3]) and res[3].Busy and not res[3].Ok and res[4].Ok,
      ", ".join("busy" if x.Busy else ("ok" if x.Ok else "no") for x in res))

# ---------------- [8] no chat permission
g.CAN_CHAT[303] = False
P3 = g.PLAYER(303, PX, PZ)
before = len(list(g.GEN_CALLS.values()))
asked0 = g.CAN_CHAT_ASKED or 0
r8 = talk(P3, g.REQ(0.7, "F", PX, PZ, "merhaba"))
r8b = talk(P3, g.REQ(0.7, "F", PX, PZ, "merhaba"))
greet = set(CFG.Greetings.values())
check("[8] no chat permission: canned greeting, no free text, model not called, permission asked once",
      r8.Ok and r8.NoChat and r8.Text in greet and r8.You is None and len(list(g.GEN_CALLS.values())) == before
      and r8b.Text == r8.Text and (g.CAN_CHAT_ASKED or 0) - asked0 == 1,
      r8.Text)

# ---------------- [9] model error, filter failure
g.CLOCK = g.CLOCK + 100
lua.execute('REPLY = function() error("TextGenerator unavailable") end')
w0 = len(list(g.WARNS.values()))
fb = set(CFG.FallbackLines.values())
r9 = talk(P1, g.REQ(0.25, "F", PX, PZ, "hey", "ctx9"))
g.CLOCK = g.CLOCK + 10
r9b = talk(P1, g.REQ(0.25, "F", PX, PZ, "hey", "ctx9"))
w1 = len(list(g.WARNS.values()))
lua.execute("REPLY = DEFAULT_REPLY")
g.FILTER_FAIL = True
g.CLOCK = g.CLOCK + 10
r9c = talk(P1, g.REQ(0.25, "F", PX, PZ, "hey"))
g.FILTER_FAIL = False
check("[9] model error -> fallback, token kept, warned once; filter failure -> fallback",
      not r9.Ok and r9.Text in fb and r9.Token == "ctx9" and r9.You == "hey" and not r9b.Ok and w1 - w0 == 1
      and not r9c.Ok and r9c.Text in fb, f"warnings +{w1 - w0}")

# ---------------- [10] generator cap, idle cleanup, leaving, remote handler
P4 = g.PLAYER(404, PX, PZ)
before = len(list(g.GENS.values()))
for i in range(CFG.MaxGenerators + 3):
    g.CLOCK = g.CLOCK + 5
    talk(P4, g.REQ(0.01 * (i + 1), "N", PX, PZ, None))
mine = [x for x in list(g.GENS.values())[before:]]
alive = [x for x in mine if not x._destroyed]
first_gone = mine[0]._destroyed and mine[1]._destroyed and not mine[-1]._destroyed
# idle cleanup: the server's cleanup loop wakes every 60 s and drops generators unused for GeneratorIdleSeconds
g.CLOCK = g.CLOCK + CFG.GeneratorIdleSeconds + 5
woke, errs = g.RESUME_ALL()
idle_gone = all(x._destroyed for x in list(g.GENS.values()))
# leaving
g.CLOCK = g.CLOCK + 10
talk(P4, g.REQ(0.9, "N", PX, PZ, None))
last = list(g.GENS.values())[-1]
g.PlayersService.PlayerRemoving.Fire(g.PlayersService.PlayerRemoving, P4)
handler = g.REMOTE.OnServerInvoke
g.CLOCK = g.CLOCK + 10
lua.execute('REPLY = function() return { GeneratedText = 42 } end')
h1 = handler(P1, g.REQ(0.25, "F", PX, PZ, "x"))
lua.execute("REPLY = DEFAULT_REPLY")
h2 = handler(P1, None)
check("[10] at most MaxGenerators per player; idle ones cleaned; dropped on leave; remote handler never throws",
      len(alive) == CFG.MaxGenerators and first_gone and cleanup_co == 1 and woke == 1 and not errs and idle_gone
      and last._destroyed and h1 is not None and not h1.Ok and h2 is not None and not h2.Ok,
      f"{len(alive)} kept of {len(mine)}, cleanup loop woke {woke} {errs}")

# ---------------- client panel against the server
LP = g.PLAYER(505, PX + 2, PZ + 1)
g.PlayersService.LocalPlayer = LP
lua.execute("""
REMOTE_MODE = "direct"
PENDING = nil
REMOTE.InvokeServer = function(self, req)
  INVOKES = (INVOKES or 0) + 1
  LAST_REQ = req
  if REMOTE_MODE == "fail" then error("remote down") end
  if REMOTE_MODE == "wait" then
    PENDING = coroutine.running()
    coroutine.yield()
    PENDING = nil
  end
  return REMOTE.OnServerInvoke(INVOKE_AS or PlayersService.LocalPlayer, req)
end
function RESUME_PENDING() local co = PENDING; if co then local ok, err = coroutine.resume(co); if not ok then error(err) end end end
""")
CHAT = lua.execute(src("src/StarterPlayer/StarterPlayerScripts/Ambient/NPCChat.lua"))
CHAT.Init()
ped = lua.eval("""function(x, z)
  local m = new("Model", { Name = "Ped" })
  local root = new("Part", { Name = "HumanoidRootPart", CFrame = CFrame.new(x, 3, z), Parent = m })
  m.PrimaryPart = root
  return m
end""")(PX, PZ)
g.PED = ped
state = lua.eval("""function(LP)
  local gui = LP.PlayerGui:FindFirstChild("SolaraNPCChat")
  local panel = gui and gui.Panel
  local lines = {}
  if panel then
    local kids = panel.Log:GetChildren()
    table.sort(kids, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
    for _, c in ipairs(kids) do if c._cls == "TextLabel" then lines[#lines + 1] = c.Text end end
  end
  local bubble = LP.PlayerGui:FindFirstChild("TalkBubble")
  return {
    Enabled = gui and gui.Enabled, Title = panel and panel.Title.Text,
    Lines = table.concat(lines, " | "), Count = #lines,
    Bubble = bubble and bubble.Enabled and bubble.Box:FindFirstChild("Text").Text or nil,
    OnPed = bubble ~= nil and PED ~= nil and bubble.Adornee == PED.PrimaryPart,
    Editable = panel and panel.Input.TextEditable, SendVisible = panel and panel.Send.Visible,
    Placeholder = panel and panel.Input.PlaceholderText, Box = panel and panel.Input.Text,
  }
end""")
closed = []
info = lua.eval("""function(model, seed, gender, x, z, closed)
  return { Model = model, Seed = seed, Gender = gender, Position = Vector3.new(x, 0, z),
           OnClose = function() closed[#closed + 1] = true end }
end""")
closed_t = lua.table()
g.CLOCK = g.CLOCK + 100
CHAT.Start(info(ped, 0.42, "M", PX, PZ, closed_t))
s = state(LP)
pm = persona(0.42, "M")
title = lua.eval("function(LP) local p = LP.PlayerGui.SolaraNPCChat.Panel; return p.Title.Text, p.Subtitle.Text end")
t1, t2 = title(LP)
check("[11] start: panel open, greeting in bubble + log, persona name and job in the header, bubble on the ped",
      s.Enabled and s.Bubble == "Merhaba! Bugün hava çok güzel." and s.Count == 1 and pm.Name in s.Lines
      and t1 == pm.Name and t2 == pm.Job and s.OnPed and CHAT.IsOpen()
      and g.LAST_REQ.Message is None and g.LAST_REQ.Seed == 0.42 and g.LAST_REQ.Gender == "M",
      f"{t1} / {t2}: {s.Lines}")
tok1 = lua.eval("function() return TOK end")()

box = lua.eval("function(LP) return LP.PlayerGui.SolaraNPCChat.Panel.Input end")(LP)
g.CLOCK = g.CLOCK + 10
box.Text = "  selam kotukelime, buralarda iyi kahve var mi?  "
CHAT.SendTyped()
s = state(LP)
check("[12] send: filtered 'Sen' line, reply line, box cleared, previous token sent back",
      "Sen: selam ##########, buralarda iyi kahve var mi?" in s.Lines and s.Count == 3 and s.Box == ""
      and g.LAST_REQ.Token == f"ctx{tok1}" and g.LAST_REQ.Message == "selam kotukelime, buralarda iyi kahve var mi?",
      s.Lines)

g.REMOTE_MODE = "wait"
g.CLOCK = g.CLOCK + 10
box.Text = "ne iş yapıyorsun?"
CHAT.SendTyped()
s_wait = state(LP)
inv0 = g.INVOKES
box.Text = "ikinci mesaj"
CHAT.SendTyped()
second_ignored = g.INVOKES == inv0
g.RESUME_PENDING()
s_after = state(LP)
g.REMOTE_MODE = "direct"
check("[13] waiting: '...' bubble, input locked, second send ignored; unlocked after the reply",
      s_wait.Bubble == "..." and s_wait.Editable is False and second_ignored and s_after.Editable is True
      and s_after.Bubble == "Merhaba! Bugün hava çok güzel.", f"bubble while waiting {s_wait.Bubble!r}")

box.Text = "ş" * 200
lua.eval("function(b) b._changed:Fire() end")(box)
cut = lua.eval("utf8.len")(box.Text)
g.CLOCK = g.CLOCK + 10
box.Text = "enter ile"
inv0 = g.INVOKES
lua.eval("function(b) b.FocusLost:Fire(true) end")(box)
check("[14] typing longer than MaxMessageLength is cut; Enter sends",
      cut == CFG.MaxMessageLength and g.INVOKES == inv0 + 1 and g.LAST_REQ.Message == "enter ile", f"{cut} chars")

# close while a reply is on the way -> OnClose, hidden, late reply ignored
g.REMOTE_MODE = "wait"
g.CLOCK = g.CLOCK + 10
box.Text = "görüşürüz"
CHAT.SendTyped()
close_btn = lua.eval("function(LP) return LP.PlayerGui.SolaraNPCChat.Panel.Close end")(LP)
lua.eval("function(b) b.Activated:Fire() end")(close_btn)
s_closed = state(LP)
open_after_close = CHAT.IsOpen()
late_ok = True
try:
    g.RESUME_PENDING()
except Exception as e:  # noqa: BLE001
    late_ok = False
s_late = state(LP)
g.REMOTE_MODE = "direct"
# no chat permission account (the server caches permission per player: answer as P3, who has none)
g.INVOKE_AS = P3
g.CLOCK = g.CLOCK + 10
CHAT.Start(info(ped, 0.43, "F", PX, PZ, lua.table()))
s_nochat = state(LP)
g.INVOKE_AS = None
check("[15] close: OnClose called, panel hidden, late reply ignored; no chat permission: input hidden with a note",
      len(list(closed_t.values())) == 1 and s_closed.Enabled is False and open_after_close is False
      and late_ok and s_late.Bubble is None and s_nochat.Enabled and s_nochat.Editable is False
      and s_nochat.SendVisible is False and "izin" in s_nochat.Placeholder and s_nochat.Bubble in greet,
      f"note {s_nochat.Placeholder!r}")
CHAT.Stop()

g.CLOCK = g.CLOCK + 10
CHAT.Start(info(ped, 0.44, "M", PX, PZ, lua.table()))
g.REMOTE_MODE = "fail"
g.CLOCK = g.CLOCK + 10
box.Text = "hey"
CHAT.SendTyped()
s_fail = state(LP)
g.REMOTE_MODE = "direct"
g.CLOCK = g.CLOCK + CFG.BubbleSeconds + 0.5
g.RUN_DELAYED()
s_hidden = state(LP)
idle = CHAT.IdleFor()
check("[16] remote failure: fallback line, input unlocked; bubble hides after BubbleSeconds",
      s_fail.Bubble == CFG.FallbackLines[1] and s_fail.Editable is True and s_hidden.Bubble is None and idle > CFG.BubbleSeconds,
      f"idle {idle:.1f}s")
CHAT.Stop()

# ---------------- [17] PedRenderer.Gender + TalkPrompt (realistic peds built like test_hijack does)
sys.argv = [sys.argv[0], sys.argv[1]]
helpers = open("tools/test_peds.py", encoding="utf-8").read()
helpers = helpers[:helpers.index("# ---------------------------------------------------------------------------------------------------------------\nPED_NAMES")]
ns = {"__name__": "peds_helpers", "__file__": "tools/test_peds.py"}
exec(compile(helpers, "tools/test_peds.py", "exec"), ns)
plua, RIG, imports = ns["runtime"](ns["VARIANTS"][0])
plua.execute("Vector2 = Vector2 or { new = function(x, y) return { X = x or 0, Y = y or 0 } end }")
PR_SRC = convert(open("src/StarterPlayer/StarterPlayerScripts/Ambient/PedRenderer.lua", encoding="utf-8").read())
PR_SRC = PR_SRC.replace("\nreturn PedRenderer", "\nfunction PedRenderer._adopt(m, r) rigOf[m] = r end\nreturn PedRenderer")
PR = plua.execute(PR_SRC)
PR.Init()
probe = plua.eval("""function(PR, RIG)
  local rng = Random.new(7)
  local seen = {}
  for i = 1, 60 do
    local m, rig = RIG.Build(rng)
    if m then PR._adopt(m, rig); seen[rig.Id] = PR.Gender(m) end
  end
  local out = {}
  for id, gd in pairs(seen) do out[#out + 1] = id .. "=" .. gd end
  table.sort(out)
  local cfg = { PromptKey = "KeyCode.E", PromptGamepad = "KeyCode.ButtonX", PromptDistance = 7 }
  local m, rig = RIG.Build(rng)
  PR._adopt(m, rig)
  local a = PR.TalkPrompt(m, cfg)
  local b = PR.TalkPrompt(m, cfg)
  local offByDefault = a.Enabled == false
  a.Enabled = true
  PR.Release(m)
  local n = 0
  for _, c in ipairs(m.PrimaryPart:GetChildren()) do if c.Name == "TalkPrompt" then n = n + 1 end end
  local box = new("Model", { Name = "Box" })
  return table.concat(out, ","), a == b, a.ActionText, a.KeyboardKeyCode, a.GamepadKeyCode, a.MaxActivationDistance,
    a.HoldDuration, a.RequiresLineOfSight, offByDefault, a.Enabled, n, PR.Gender(box), a.Parent == m.PrimaryPart
end""")
genders, same_p, act, key, pad, dist, hold, los, off0, on_after_release, count, unknown, parented = probe(PR, RIG)
ok_g = genders and all((x.split("=")[0][0] == x.split("=")[1]) for x in genders.split(","))
check("[17] Gender from the model id (F/M), 'N' otherwise; 'Konuş' [E]/ButtonX prompt built once, off by default, "
      "off after release",
      ok_g and same_p and act == "Konuş" and key == "KeyCode.E" and pad == "KeyCode.ButtonX" and dist == 7 and hold == 0
      and los is False and off0 and on_after_release is False and count == 1 and unknown == "N" and parented,
      genders)

print()
print("ALL PASS" if not fails else f"{len(fails)} FAILED: " + "; ".join(fails))
sys.exit(1 if fails else 0)
