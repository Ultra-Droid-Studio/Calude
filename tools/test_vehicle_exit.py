#!/usr/bin/env python3
"""test_vehicle_exit.py — getting out of a car always gives the character back (bug: after leaving a car, sometimes at
speed, the car controls stayed on and the character could not move until rejoining).

The REAL VehicleController runs in Lua 5.4 (lupa) with small stand-ins for Roblox and the other controllers.
  [1] normal: sit -> car mode (car keys, car buttons, character controls off, prompts off); stand up -> walking mode
      again (car keys off, on-foot buttons, character controls on, prompts on), Exited fired
  [2] getting out while things break (car parts gone so Car:Release errors, camera errors, mobile layout errors):
      walking mode still comes back fully; the errors are logged
  [3] getting out at speed: the character keeps at most 18 studs/s of horizontal speed (no flying along the road)
  [4] character left in the "seated" state by the server's exit: stood up (GettingUp), Sit cleared
  [5] safety net (every 0.5 s): seat event missed -> leaves the car; car keys / car buttons stuck while on foot ->
      walking mode restored; seated in a car but enter missed -> enters
  [6] safety net leaves alone: the open menu, a non-car seat (bench), a dead character
Usage: python3 -I tools/test_vehicle_exit.py <lupa-site-packages>
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


ENV = r"""
print = function() end
local function Signal()
  local s = { _f = {} }
  function s:Connect(f) local h = { f = f, on = true }; table.insert(self._f, h)
    return { Disconnect = function() h.on = false end } end
  function s:Fire(...) for _, h in ipairs(self._f) do if h.on then h.f(...) end end end
  return s
end
SIGNAL = Signal
DEFERRED = {}
task = {
  spawn = function(f, ...) f(...) end,
  defer = function(f, ...) local a = table.pack(...); table.insert(DEFERRED, function() f(table.unpack(a, 1, a.n)) end) end,
  wait = function() end,
}
function RUN_DEFERRED() local l = DEFERRED; DEFERRED = {}; for _, f in ipairs(l) do f() end end
workspace = new("Workspace")

-- ===== Roblox services
RunService = { PreSimulation = Signal(), Stepped = Signal(), Heartbeat = Signal() }
UIS = { InputChanged = Signal(), InputEnded = Signal() }
PPS = { Enabled = true }
CONTROLS = { enabled = true }
function CONTROLS:Enable() self.enabled = true end
function CONTROLS:Disable() self.enabled = false end
PLAYERMODULE = { GetControls = function() return CONTROLS end }
local playerScripts = { PlayerModule = { _mod = "PlayerModule" } }
function playerScripts:WaitForChild(n) return self[n] end
LOCAL = { PlayerScripts = playerScripts }
function LOCAL:WaitForChild(n) return self[n] end
Players = { LocalPlayer = LOCAL }

-- ===== shared modules
WARNS = {}
LOG = { new = function() return {
  Warn = function(...) local t = {}; for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end; table.insert(WARNS, table.concat(t, " ")) end,
  Info = function() end, Error = function() end,
} end }
MAID = { new = function() local m = { items = {} }
  function m:Give(x) table.insert(self.items, x) end
  function m:Clean() for _, x in ipairs(self.items) do if type(x) == "table" and x.Disconnect then x:Disconnect() end end; self.items = {} end
  return m end }
VD = {
  Get = function(id) return { Type = "Car", MaxSpeed = 80, Travel = 1.2 } end,
  UsesCarPhysics = function() return true end, IsMotorcycle = function() return false end,
  SteerAngleAt = function() return 0.5 end,
}
REMOTES = {}
RR = { Get = function(g, n) local r = REMOTES[n] or { FireServer = function(self, ...) self.fired = (self.fired or 0) + 1 end }
  REMOTES[n] = r; return r end }
CAR_RELEASE_ERROR = false
CARS = {}
CARPHYSICS = { new = function(model, def)
  local car = { Telemetry = { Speed = 0, ForwardSpeed = 0, Gear = "N", Steer = 0 } }
  function car:Step() end
  function car:Release() if CAR_RELEASE_ERROR then error("Wheel_FL is not a valid member of Model") end; self.released = true end
  function car:ConsumeRecoveryRequest() return false end
  function car:IsBraking() return false end
  function car:IsReversing() return false end
  table.insert(CARS, car)
  return car
end }
local shared = { VehicleDefinitions = { _mod = "VD" }, RemoteRegistry = { _mod = "RR" },
  Utilities = { Signal = { _mod = "Signal" }, Maid = { _mod = "Maid" }, Log = { _mod = "Log" } } }
local RS = { Shared = shared }
function RS:WaitForChild(n) return self[n] end
local vehiclesFolder = { CarPhysics = { _mod = "CarPhysics" } }
function vehiclesFolder:WaitForChild(n) return self[n] end
local scriptsRoot = { Vehicles = vehiclesFolder }
function scriptsRoot:WaitForChild(n) return self[n] end
script = { Parent = { Parent = scriptsRoot } }
local MODS = { VD = VD, RR = RR, Signal = { new = Signal }, Maid = MAID, Log = LOG, CarPhysics = CARPHYSICS, PlayerModule = PLAYERMODULE }
local realRequire = require
require = function(x) if type(x) == "table" and x._mod then return MODS[x._mod] end return realRequire(x) end
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService
  elseif n == "UserInputService" then return UIS elseif n == "ProximityPromptService" then return PPS
  elseif n == "ReplicatedStorage" then return RS end
  error("service " .. n)
end }

-- ===== character, humanoid, seats, vehicles
HUMANOID = { Health = 100, Sit = false, SeatPart = nil, State = "HumanoidStateType.Running",
  _seatChanged = Signal(), Died = Signal() }
function HUMANOID:GetPropertyChangedSignal(p) assert(p == "SeatPart"); return self._seatChanged end
function HUMANOID:GetState() return self.State end
function HUMANOID:ChangeState(s) self.State = s; self.changed = s end
ROOT = { AssemblyLinearVelocity = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 3, 0) }
CHARACTER = { Humanoid = HUMANOID }
function CHARACTER:WaitForChild(n) return self[n] end
function SIT(seat, silent) HUMANOID.SeatPart = seat; HUMANOID.Sit = seat ~= nil
  if seat then HUMANOID.State = "HumanoidStateType.Seated" end
  if not silent then HUMANOID._seatChanged:Fire() end end
function UNSEAT_SERVER(silent) -- server destroys the seat weld: SeatPart nil, the state may stay "Seated" here
  HUMANOID.SeatPart = nil
  if not silent then HUMANOID._seatChanged:Fire() end end

function NEW_CAR(id)
  local model = new("Model", { Name = "Car" .. id })
  model:SetAttribute("VehicleId", id)
  model:SetAttribute("DefId", "sedan_vela")
  model.Parent = workspace
  local chassis = new("Part", { Name = "Chassis", CFrame = CFrame.new(0, 2, 0), Size = Vector3.new(6, 1, 12), Parent = model })
  model.PrimaryPart = chassis
  local seat = new("Seat", { Name = "DriverSeat", Parent = model })
  seat:SetAttribute("VehicleSeat", true)
  seat:SetAttribute("DriverSeat", true)
  model.AncestryChanged = Signal()
  model.GetBoundingBox = function() return CFrame.new(0, 3, 0), Vector3.new(6, 5, 12) end
  return model, seat
end
BENCH = new("Seat", { Name = "Bench" })

-- ===== other controllers
CAMERA_ERROR, LAYOUT_ERROR = false, false
local Input = { contexts = {}, ActionBegan = Signal(), ActionEnded = Signal() }
function Input:SetContext(n, on) self.contexts[n] = on or nil end
function Input:IsContextActive(n) return self.contexts[n] == true end
function Input:IsActionActive() return false end
function Input:GetAnalog() return 0 end
local Mobile = { layout = "OnFoot" }
function Mobile:SetLayout(n) self.layout = n; if LAYOUT_ERROR then error("DrivingLayout: bad viewport") end end
function Mobile:GetLayout() return self.layout end
local Camera = { mode = nil }
local function camErr() if CAMERA_ERROR then error("camera: no root part") end end
function Camera:RequestMode(o, m) self.mode = m end
function Camera:Release(o) camErr(); self.mode = nil end
function Camera:SetFollowSubject() camErr() end
function Camera:SetAutoFollowHeading() end
function Camera:SnapBehindCharacter() camErr() end
local Char = { CharacterChanged = Signal() }
function Char:GetCharacter() return CHARACTER end
function Char:GetHumanoid() return HUMANOID end
function Char:GetRootPart() return ROOT end
CONTROLLERS = { InputController = Input, MobileControlsController = Mobile, CameraController = Camera, CharacterController = Char }
EXITED = 0
function STATE()
  return { InVehicle = VC:IsInVehicle(), CarKeys = Input:IsContextActive("Vehicle"), Layout = Mobile:GetLayout(),
    Controls = CONTROLS.enabled, Prompts = PPS.Enabled, Exited = EXITED }
end
function HEARTBEAT(seconds) local t = 0; while t < seconds do RunService.Heartbeat:Fire(0.1); t = t + 0.1 end end
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(roblox_mock.MOCK + ENV)
g = lua.globals()
VC = lua.execute(convert(open("src/StarterPlayer/StarterPlayerScripts/Controllers/VehicleController.lua", encoding="utf-8").read()))
g.VC = VC
VC.Init(VC, g.CONTROLLERS)
VC.Start(VC)
lua.execute("VC.Exited:Connect(function() EXITED = EXITED + 1 end)")
S = g.STATE


def walking(s, exited):
    return (not s.InVehicle and not s.CarKeys and s.Layout == "OnFoot" and s.Controls and s.Prompts
            and s.Exited == exited)


def fmt(s):
    return f"inVehicle={s.InVehicle} carKeys={s.CarKeys} layout={s.Layout} controls={s.Controls} prompts={s.Prompts}"


# [1] normal
model, seat = lua.eval("NEW_CAR")("A")
g.SIT(seat)
s_in = S()
in_ok = s_in.InVehicle and s_in.CarKeys and s_in.Layout == "Car" and not s_in.Controls and not s_in.Prompts
g.SIT(None)
g.RUN_DEFERRED()
s_out = S()
check("[1] normal: sitting gives car mode, standing up gives walking mode back", in_ok and walking(s_out, 1),
      f"in: {fmt(s_in)} | out: {fmt(s_out)}")

# [2] errors while getting out
w0 = len(list(g.WARNS.values()))
g.SIT(seat)
g.CAR_RELEASE_ERROR = True
g.CAMERA_ERROR = True
g.LAYOUT_ERROR = True
lua.execute("for _, car in ipairs(CARS) do end")  # car created lazily on the first physics step
lua.execute("RunService.PreSimulation:Fire(1/60)")
g.SIT(None)
g.RUN_DEFERRED()
g.CAR_RELEASE_ERROR = g.CAMERA_ERROR = g.LAYOUT_ERROR = False
s_err = S()
warns = list(g.WARNS.values())[w0:]
labels = [x for x in ("araç fiziği", "kamera", "mobil düzen") if any(x in w for w in warns)]
check("[2] car parts gone / camera / mobile layout errors while getting out: walking mode still comes back",
      not s_err.InVehicle and not s_err.CarKeys and s_err.Controls and s_err.Prompts and s_err.Exited == 2
      and len(labels) == 3, f"{fmt(s_err)}; logged: {', '.join(labels)}")
# the layout errored after being set: the mobile controller itself still knows "OnFoot"
g.CONTROLLERS.MobileControlsController.layout = "OnFoot"

# [3] at speed
g.SIT(seat)
g.ROOT.AssemblyLinearVelocity = lua.eval("Vector3.new")(48, 2, -36)  # 60 stud/s
g.SIT(None)
g.RUN_DEFERRED()
v = g.ROOT.AssemblyLinearVelocity
flat = (v.X ** 2 + v.Z ** 2) ** 0.5
check("[3] getting out at 60 stud/s: the character keeps at most 18 stud/s (direction kept)",
      abs(flat - 18) < 1e-6 and v.X > 0 and v.Z < 0 and walking(S(), 3), f"{flat:.1f} stud/s")
g.ROOT.AssemblyLinearVelocity = lua.eval("Vector3.new")(3, 0, 0)

# [4] stuck seated state after the server's exit
g.SIT(seat)
g.HUMANOID.changed = None
g.UNSEAT_SERVER()  # SeatPart nil, Sit still true, state still Seated
g.RUN_DEFERRED()
check("[4] left in the 'seated' state by the server: stood up (GettingUp), Sit cleared",
      g.HUMANOID.changed == "HumanoidStateType.GettingUp" and not g.HUMANOID.Sit and walking(S(), 4),
      f"state {g.HUMANOID.State}, Sit {g.HUMANOID.Sit}")
g.HUMANOID.State = "HumanoidStateType.Running"

# [5] safety net
g.SIT(seat)
g.UNSEAT_SERVER(True)  # the seat event never arrives
missed_before = S().InVehicle
g.HEARTBEAT(0.6)
g.RUN_DEFERRED()
a = walking(S(), 5) and missed_before
# keys / buttons stuck while on foot, nothing else wrong
lua.execute('CONTROLLERS.InputController:SetContext("Vehicle", true); CONTROLLERS.MobileControlsController.layout = "Car"; CONTROLS.enabled = false')
g.HEARTBEAT(0.6)
b = walking(S(), 5)
# seated in a car but the enter was missed
g.SIT(seat, True)
g.HEARTBEAT(0.6)
c = S().InVehicle and S().CarKeys
g.SIT(None)
g.RUN_DEFERRED()
check("[5] safety net: missed seat event -> out of the car; stuck car keys/buttons -> walking; missed enter -> in",
      a and b and c and walking(S(), 6), f"missed exit {a}, stuck keys {b}, missed enter {c}")

# [6] safety net leaves alone
g.HUMANOID.State = "HumanoidStateType.Running"
lua.execute('CONTROLLERS.InputController:SetContext("Menu", true); CONTROLLERS.MobileControlsController.layout = "Hidden"; CONTROLS.enabled = false')
g.HEARTBEAT(1.2)
menu_ok = g.CONTROLLERS.MobileControlsController.layout == "Hidden" and not g.CONTROLS.enabled
lua.execute('CONTROLLERS.InputController:SetContext("Menu", false); CONTROLLERS.MobileControlsController.layout = "OnFoot"; CONTROLS.enabled = true')
g.SIT(g.BENCH)
g.HEARTBEAT(1.2)
bench_ok = not S().InVehicle and g.HUMANOID.State == "HumanoidStateType.Seated" and g.HUMANOID.changed != "x"
g.HUMANOID.changed = None
g.HEARTBEAT(0.6)
bench_ok = bench_ok and g.HUMANOID.changed is None
g.SIT(None)
g.HUMANOID.State = "HumanoidStateType.Running"
g.HUMANOID.Health = 0
lua.execute('CONTROLLERS.MobileControlsController.layout = "Car"')
g.HEARTBEAT(0.6)
dead_ok = g.CONTROLLERS.MobileControlsController.layout == "Car"
g.HUMANOID.Health = 100
check("[6] safety net does nothing while the menu is open, on a bench, or when the character is dead",
      menu_ok and bench_ok and dead_ok, f"menu {menu_ok}, bench {bench_ok}, dead {dead_ok}")

print()
print("ALL PASS" if not fails else f"{len(fails)} FAILED: " + "; ".join(fails))
sys.exit(1 if fails else 0)
