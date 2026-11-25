# SOLARA — Phase 0: Complete Source Code Audit

**Source audited:** `SOLARA_Phase3.rbxlx` (Config.Version `0.3.0-phase3`)
**Audit date:** 2026-11-25
**Type:** Analysis only. No scripts, objects or systems were changed.

---

## 0. Scope, method and limits

- The `.rbxlx` was parsed as XML. All **42 scripts** were extracted with their full Explorer paths and read line by line. That is about 7,450 lines of Luau, plus `MapData` (9,771 lines / 348 KB of generated map data).
- `MapData` was also parsed with an offline script to measure road geometry: slopes, the height steps where roads meet junctions, vehicle spot spacing and signal/stop flags.
- **Line references** use the form `Path/Script.lua:line`. The path is the script's Explorer path, and the line number is inside that script's `Source`, which matches Studio's script editor.
- **Limits:**
  - This is **static analysis**. Roblox can't be run in this environment. Findings tagged **VERIFY** depend on engine behaviour and must be confirmed in Studio; each one includes a concrete test.
  - **`SOLARA_PROJECT_CONTEXT.md` was not part of the upload.** Only the `.rbxlx` arrived. The code refers to spec sections ("Bölüm 8", "Bölüm 19"…) that could not be cross-checked.
  - The `tools/mapgen.py` generator that `MapData` was produced by is **not** in the place file or in the git repository.
  - `REALISTIC.html` in the repo is an unrelated three.js web demo ("Büyük Şehir 3D"), not part of the Roblox project.

---

## 1. Executive summary

The codebase is **well structured for its stage**:

- One server entry point and one client entry point, with Priority-ordered `Init`/`Start` and pcall isolation.
- A single remote registry, rate-limited and validated remotes, and Maid/Signal utilities.
- A camera controller that owns all camera writes.
- A data-driven vehicle catalogue and a data-driven world.

No crash-level defect was found by reading. The core loop (spawn → walk → enter car → drive → exit) is coherent.

The weaknesses are concentrated in **vehicle physics fidelity**, **multiplayer authority**, **road geometry**, and in large **missing product layers**: menu, persistence, AI, navigation and audio assets.

**Top 10 by impact**

| # | Finding | Sev. | Prio. |
|---|---|---|---|
| 1 | Sloped roads meet flat junction pads with **vertical steps of up to 1.30 studs** (33 transitions > 0.5 studs). Vehicles hit a wall at ramp ends. | High | P0 |
| 2 | Parked vehicles are unanchored **without `SetNetworkOwner(nil)`**, so nearby clients get automatic physics ownership (fling/teleport exploit, desync). Vehicle speed/teleport checks only log. | High | P0 |
| 3 | Motorcycle lean is **kinematic** (input × speed). It forces the whole physics assembly, including the cylindrical wheels, onto their edges. The lean is ~3× too much at low speed, and pitch is damped by the align target. | High | P1 |
| 4 | Vehicle camera **pivot lag grows with speed** (≈9–12.5 studs at top speed) and the camera isn't scaled to vehicle size. At minimum zoom it ends up inside the van's rear glass; at default zoom it sits at or below the roof line of the van, SUV and pickup. | High | P1 |
| 5 | Mobile vehicle steering is **binary (◀ ▶)**. Whether the Roblox jump button stays usable while seated is unconfirmed (VERIFY). If it does, jumping unseats the driver. | High (mobile) | P1 |
| 6 | **No persistence at all.** No `DataStoreService` anywhere; settings live in memory. | High | P1 |
| 7 | **No main menu or loading flow.** The world builds at runtime after join, with a spawn race on ground. | High | P1 |
| 8 | **No traffic/pedestrian AI, GPS or minimap.** The data foundations are good: road graph with lanes/speeds/one-way, plus 211 signal, 235 stop and 181 crosswalk nodes. | High (feature) | P2 |
| 9 | Handbrake-exit leaves the **rear-wheel grip permanently reduced** on that client. Its cache flag resets on re-entry, but the parts don't. | Medium | P0 |
| 10 | Lane lines and crosswalk stripes are **collidable and stick out 0.03 studs**, causing micro-bumps at every lane change or crossing. | Medium | P0 |

---

## 2. Architecture inventory

### 2.1 Place structure (as saved)

```
Workspace            StreamingEnabled = true, NO children (world is generated at runtime, not baked)
Players              CharacterAutoLoads = true
ReplicatedStorage
  Modules/           AnimationConfig, AudioConfig, CameraConfig, InputConfig, UIConfig
  Shared/            Config, Constants, MapData, MapDefinitions, RemoteRegistry, Types, VehicleDefinitions
    Utilities/       Log, Maid, MathUtil, RateLimiter, Signal
ServerScriptService
  ServerBootstrap    (Script)
  Services/          CharacterService, MovementValidationService, PlayerService,
                     VehicleService, WeatherService, WorldService
  Vehicles/          VehicleFactory
  WorldGen/          BuildingBuilder, Kit, LandBuilder, PropBuilder, RoadBuilder, WorldBuilder
StarterPlayer/StarterPlayerScripts
  ClientBootstrap    (LocalScript)
  Controllers/       AnimationController, AudioController, CameraController, CharacterController,
                     DebugHUDController, InputController, MobileControlsController,
                     SettingsController, VehicleController, VehicleHUDController
```

These are **not present** in the file: `StarterGui`, `ReplicatedFirst`, `ServerStorage`, `Lighting`, `SoundService`, `Teams` and `Terrain` content. All lighting and terrain are created by code.

### 2.2 Server

| Module | Prio | Responsibility | Status |
|---|---|---|---|
| `ServerBootstrap` | — | `RemoteRegistry.Build()`, requires `Services/*`, `Init` then `Start` by Priority, pcall per service | Implemented |
| `WorldService` | 1 | Creates `Workspace.World/*` folders; if not `Baked`, runs `WorldBuilder.Build` **asynchronously**; fires `WorldReady` | Implemented |
| `PlayerService` | 5 | Sessions, game mode (Normal/Sandbox), `ClientReady` → `SessionInfo` | Implemented (no data) |
| `CharacterService` | 20 | Avatar-preserving spawn, ground raycast, rig/eye-height attributes, forces `CharacterAutoLoads` | Implemented |
| `WeatherService` | 30 | Day/night clock, lighting/atmosphere/post-FX, street lamps, `IsNight` attribute | Implemented (no weather) |
| `MovementValidationService` | 40 | Horizontal speed sampling at 2 Hz; **log only** | Partial |
| `VehicleService` | 50 | Parked spawns, enter/exit, ownership, lights/indicators/horn, flip, freeze/reset loop, speed log | Implemented (gaps below) |
| `Vehicles/VehicleFactory` | — | Builds a physical vehicle from a definition: chassis, knuckles, constraints, body, seats, prompts, sounds, mass-based tuning | Implemented |
| `WorldGen/*` | — | Ground, terrain water/hills, coast, roads/sidewalks/junctions/markings/bridges, 40+ building styles, 14 prop kinds, POI zones, spawns; `Bake()`/`Clear()` tooling | Implemented |

### 2.3 Client

| Controller | Prio | Responsibility | Status |
|---|---|---|---|
| `SettingsController` | 1 | In-memory settings with validators | Partial (no UI, no persistence) |
| `InputController` | 2 | Device detection; action-based input through ContextActionService; contexts (OnFoot/Vehicle) | Implemented |
| `CharacterController` | 3 | Character tracking; Walk/Run/Sprint; movement locks | Implemented |
| `AnimationController` | 4 | Custom action animations by rig | Implemented but **unused** (all IDs empty, no callers) |
| `CameraController` | 5 | The only writer of `Camera.CFrame`; follow/scripted modes, overrides, collision, safety net | Implemented |
| `VehicleController` | 6 | Seat detection, client-side driving (motors, servos, lean), state push | Implemented |
| `MobileControlsController` | 8 | Touch buttons for on-foot and vehicle layouts | Implemented (digital) |
| `VehicleHUDController` | 9 | Speed, gear, indicator/light/handbrake icons | Implemented |
| `DebugHUDController` | 9 | F3 debug panel | Implemented |
| `AudioController` | 10 | Engine pitch from speed | Implemented but **inert** (no sound assets) |

### 2.4 Shared modules and configuration

- `Config` (frozen): movement speeds, spawn, world build, environment clock, debug flags.
- `Constants` (frozen): attribute keys, camera modes (including unused `Menu` and `Cinematic`), world folder names (including empty `TrafficNodes` and `PedestrianNodes`).
- `VehicleDefinitions`: 7 cars and 5 motorcycles; `DriveSign`, `SteerAngleAt`, `ToKmh` (0.28 m/stud).
- `MapDefinitions` / `MapData`: one parser for the generated map.
  - 19 districts, 549 nodes, 919 edges (588 street, 214 avenue, 48 one-way ramp, 40 country, 19 freeway, 10 highway).
  - 1,333 lots, 90 POIs, 5,826 props (3,037 trees, 2,367 lamps), 108 vehicle spots (88 cars, 20 bikes), 14 spawns.
  - The map is 10,240 × 10,240 studs.
- `RemoteRegistry`: the only remote definition point; the server builds, the client waits.
- `CameraConfig`: vehicle profiles are explicitly marked **temporary** (`CameraConfig.lua:51`).
- `AudioConfig` and `AnimationConfig`: **every asset ID is an empty string.**

### 2.5 Initialization order and dependencies

**Server:** `RemoteRegistry.Build` → require Services → `Init` in this order: World(1) → Player(5) → Character(20) → Weather(30) → MovementValidation(40) → Vehicle(50). `Start` runs in the same order.

- `WorldService:Start` uses `task.spawn` to start the build. Spawn points and the first ~350 ground parts exist when `Start` returns; the rest is built over many frames (Kit yields every 350 parts, `Kit.lua:17-22`).
- `CharacterService:Start` can place characters **before** blocks and ground are complete (finding M7).
- `VehicleService` correctly waits for `WorldReady` before spawning vehicles (`VehicleService.lua:596-617`).

**Client:** Settings(1) → Input(2) → Character(3) → Animation(4) → Camera(5) → Vehicle(6) → MobileControls(8) → VehicleHUD(9) and DebugHUD(9) (tie; order follows `GetChildren`, which is harmless) → Audio(10). After that, the client listens for `SessionInfo` and fires `ClientReady`.

- `Start`-time dependencies all point to lower priorities, so they are safe.
- Runtime calls from `VehicleController` into `CameraController`, `MobileControlsController` and `InputController` happen after `Start`, so they are also safe.

### 2.6 Network surface

| Remote | Dir | Validation | Notes |
|---|---|---|---|
| `PlayerRemotes.ClientReady` | C2S | RateLimiter(3, 0.2/s); string ≤ 24 | OK |
| `PlayerRemotes.SessionInfo` | S2C | — | OK |
| `PlayerRemotes.Notify` | S2C | — | **Defined, never fired** |
| `VehicleRemotes.RequestExit` | C2S | RateLimiter(3, 1/s); must be seated in a registered seat | OK |
| `VehicleRemotes.DriveState` | C2S | RateLimiter(20, 15/s); driver only; field types and enums checked | OK |
| `VehicleRemotes.RequestFlip` | C2S | RateLimiter(1, 0.33/s); vehicle stopped and tilted | OK |
| Enter (ProximityPrompt `Triggered`) | C2S (engine) | Rate limit, alive, seat free, ≤ 14 studs | **Bypassable by Seat touch-sit** (M9) |
| `NPC/Shop/Inventory/Trade/MultiplayerRemotes` | — | — | Empty folders |

**Physics authority:** the driver's client owns the vehicle assemblies, which is correct for responsive driving. The server never validates the vehicle's **position**; it only logs speed (H2).

### 2.7 Prepared but unused extension points

Several hooks are already in place for later phases, which is good:

- **Signals fired with no listeners:** `VehicleEntered`/`VehicleExited`, `SessionStarted`/`SessionEnded`, `NightChanged`, `CharacterReady`, `MovementStateChanged`.
- **Unused APIs:** `CameraController:RequestScripted`/`PlayCinematic` (meant for the menu and cinematics), `CharacterController:SetMovementLocked`, the `"Hidden"` mobile layout, and the `ServerTeleportAt` grace attribute (meant for GPS fast travel).

---

## 3. Vehicle lifecycle trace (cars)

| Stage | Where | What happens | Assessment |
|---|---|---|---|
| **Definition** | `VehicleDefinitions.lua:14-78` | Dimensions, mass, top speed, acceleration, braking, steering range, grip, drive layout, seats, colours | Clean, data-driven |
| **Spawn (parked)** | `VehicleService.lua:596-617` → `SpawnAtGround` `374-387` → `SpawnVehicle` `360-371` | Waits for `WorldReady`; for each of the 108 spots, raycasts ground from y=400, computes ride height, builds the vehicle **anchored** | Ride-height formula duplicated from the factory (L8) |
| **Build** | `VehicleFactory.lua:398-590` | Chassis (all of the mass) + per wheel: Knuckle ⟂ `CylindricalConstraint` (suspension slide + steering servo), `SpringConstraint`, `HingeConstraint` motor → Wheel (cylinder). Body parts are massless and welded. Seats are `Seat` (not `VehicleSeat`) with attributes and a `ProximityPrompt` each. Spring stiffness gives 0.6×travel sag; damping ratio 0.45; torques are mass-scaled | Sound physical design; see M3/M10 |
| **Registration** | `VehicleService.lua:313-357` | Listens for seat `Occupant` changes and prompt `Triggered`; collects light parts; `Destroying` cleanup | Cleanup incomplete (M11) |
| **Activation / freeze** | `VehicleService.lua:622-660` | Every 1 s: unanchor if a player is within 220 studs; anchor if nobody is within 320 and speed < 1; reset if Y < -60; idle reset after 300 s if far away and moved > 25 studs | **Unanchor never sets server ownership** (H2) |
| **Enter** | Prompt (F / ButtonY, 10 studs driver, 8 passenger) → `_tryEnter` `410-429` → `seat:Sit` → `onSeated` `238-268` | Server checks rate, alive, seat free, not already seated, ≤ 14 studs. Then: unanchor, character massless, prompt off. Driver only: hand IK (R15), `DriverUserId`, **`SetNetworkOwner(player)`**, auto headlights at night, engine `Play` | Good validation; touch-sit bypass (M9) |
| **Client entry** | `VehicleController.lua:365-391` → `enter` `245-307` | `SeatPart` change → collect motors, steer servos, rear wheels and bike align; camera override `Vehicle`/`Motorcycle` (prio 20) following the chassis; disables PlayerModule controls and all ProximityPrompts; enables the Vehicle input context; mobile layout; `driveStep` on Heartbeat for the driver | Collects descendants once (M6) |
| **Driver/passenger detection** | `VehicleFactory.lua:478` (`DriverSeat` attribute); `VehicleService.lua:241`; `VehicleController.lua:258` | Only the driver seat grants ownership and driving; passengers get camera + exit only | Correct |
| **Throttle** | `VehicleController.lua:154-163` | Driven motors target `MaxSpeed/R`. Torque = drive × (1−(v/vmax)²) clamped to ≥ 0.12, × throttle; undriven wheels spin freely | Hard speed cap through the motor target; arcade, acceptable |
| **Steering** | `VehicleController.lua:139-145` | Input slew of 3.2/s (4.5/s when returning to centre); max angle interpolated linearly from `MaxSteer` to `MinSteer` by v/vmax; same angle on both front wheels | No Ackermann (M10) |
| **Braking** | `VehicleController.lua:164-168, 176-188` | Brake = motor target 0 with `brakeTorque` × input on all wheels | No ABS or brake bias (M10) |
| **Reversing** | `VehicleController.lua:169-173` | Below 2 studs/s, the brake input becomes reverse at 0.6× torque | OK |
| **Handbrake** | `VehicleController.lua:178-180, 189` | Rear wheels locked + rear friction × 0.45 above 8 studs/s | **Grip state bug** (M1) |
| **Idle with driver** | `VehicleController.lua:152` | Only `coastTorque` (≈4 studs/s² of deceleration) | **Rolls on slopes** (M4) |
| **Lights/indicators/horn** | Client `pushState` `97-113` → `DriveState` → server `518-554` → attributes → `applyLights`; blinking loop `662-675` | Server-side validated. Blinking is done on the server (L2) | OK / perf |
| **Auto flip** | `VehicleController.lua:203-212` → `RequestFlip` → server `556-593` | Cars only: upright vector Y < 0.3 for 2.5 s → server re-orients if stopped | OK |
| **Exit** | VehExit → `RequestExit` → `ExitVehicle` `467-489` → `findExitCFrame` `432-465` | Destroy `SeatWeld`, `Sit=false`, deferred `PivotTo` to the first clear side/front/back spot (roof as a last resort) | **No speed gate; velocity kept** (M5) |
| **Unseat** | `onUnseated` `270-311` | Prompt back on, massless restored, IK removed, `ServerTeleportAt` grace; driver: clear state, stop sounds, then **0.3 s later** ownership → server + parking brake | Client keeps the last motor commands for 0.3 s (M4) |
| **Client exit** | `leave` `225-243` | Release camera, restore controls/prompts/context/layout | Doesn't restore local wheel grip (M1) |
| **Parking / reset** | `applyParkingBrake` `145-158`; `ResetToSpot` `400-408` | All motors brake, steering centred, bikes upright | OK |
| **Network ownership** | `VehicleFactory.lua:601-609` | Per physical part with pcall | Set to the player on driver entry; set to the server only after a driver exits |
| **Destruction / cleanup** | `VehicleService.lua:348-355`; `VehicleController.lua:301-305` | **There is no destroy/despawn API.** Vehicles live forever. `Destroying` only clears `records`/`seatRecords` (not `lastSpeedWarn`, occupants, IK or massless state); the client leaves if the model is removed | Gap (M11) |

---

## 4. Motorcycle analysis

**Catalogue:** Veloz R (sport), Tango (street), Dune Cruiser, Zip (scooter), Ruta (standard). Mass 18–30, wheel radius 0.9–1.3, top speed 75–160 studs/s, MaxLean 28–40°. 20 of the 108 spots are bikes.

**Build differences** (`VehicleFactory.lua`):

- Chassis is an invisible 0.9 × 0.9 × (0.7·wheelbase) box (`411-412`).
- Front knuckle is the only steered one; rear is driven (`440-441`).
- Fork, handlebar (with `HandL`/`HandR` IK targets), headlight, front indicators and fender are welded to the **front knuckle**, so they turn with steering (`251-264`).
- The seat is visible and exposed (`468-473`).
- An `AlignOrientation "Upright"` (PrimaryAxisParallel, Responsiveness 30, MaxTorque = mass·g·60, `499-510, 569`) is enabled.

**Riding** (`VehicleController.lua:191-201`): every Heartbeat, the align target becomes the up-vector perpendicular to the current forward direction, rotated toward the right by `lean = steer × clamp(v/25, 0, 1) × MaxLean`.

| Aspect | Status | Detail |
|---|---|---|
| Stays upright | Implemented, too strong | The align torque is large enough that a bike **can never fall, crash, wheelie or stoppie**. All of its dynamics are masked. |
| Lean | Partial / physically wrong | Lean comes from **input**, not physics. Veloz R example, using the same physics model: at 25 studs/s with full steer, the code leans **40°** where cornering physics needs ~13°; at 10 studs/s, 16° vs ~2°; at 160 studs/s (4° steer), 40° vs the ~59° that the turn would need (and that turn is already beyond grip). |
| Lean mechanism | Problematic | The **whole physics assembly** is rotated about the chassis centre of mass. The cylindrical wheels then touch the road on their **rim edges**: sharp-edge contact, grip that changes with lean, chatter, and sideways scrub because the rotation pivot isn't the contact patch. |
| Pitch | Partial | Pitch is free in principle (the target follows the current forward vector), but the target updates at 60 Hz while physics runs at 240 Hz, so the align **damps pitch rate**. This affects crests, jumps and the junction steps (H1). |
| Parked on a slope | Bug-prone | `applyParkingBrake` forces the axis to world up (`VehicleService.lua:153-156`). On the 8–12% ramps the bike is held level, so one wheel hovers or loads unevenly. |
| Steering | OK | Speed-sensitive range (`MaxSteer`→`MinSteer`); no counter-steer. That is fine for arcade feel, but lean and steer are decoupled. |
| Suspension | OK | Same strut design as cars, with travel 0.7–1.0. |
| Camera | Partial | Separate `Motorcycle` profile; no roll/lean follow; same speed-proportional pivot lag (H4). |
| Mobile | Partial | Same binary steering; **no Flip button** for bikes (the keyboard `R` flip still works); no handbrake button (Space still works on PC). |
| Rider | Partial | Default Roblox sit pose; R15 hand IK to the handlebar works and follows steering; R6 has no IK; `BikeRide`/`BikeLean*` animations are empty and never called. |
| Exit | OK | Side offset uses half-width 1.2 (`VehicleService.lua:435`). |
| Touch-sit | Bug | The exposed bike seat auto-sits anyone who walks or jumps into it, bypassing the prompt (M9). |
| Small-wheel risk | High | The scooter has R = 0.9. A 0.66–1.30-stud junction step (H1) is 73–144% of its wheel radius. |

**Recommended motorcycle model** (decision for Phase 1):

1. Keep the physics chassis **upright in roll**. Use a roll-only stabiliser (a torque from roll error, or an align on a vehicle-local axis that leaves pitch to ground contact) and let pitch follow wheel contact.
2. Compute lean as `atan(v·yawRate / g)`, clamped to `MaxLean` and smoothed.
3. Apply lean **visually only**: the body and the rider's seat weld are rotated through a `Motor6D` about the contact line, client-side. Other clients get it through a replicated attribute or the network-owner CFrame.
4. If physical lean is ever kept, switch the bike wheels to `Ball` shapes so contact stays round.

---

## 5. Feature status matrix

| Area | Implemented | Partial | Absent |
|---|---|---|---|
| Architecture | Bootstraps, service/controller contract, RemoteRegistry, Maid/Signal/RateLimiter/Log | — | Automated tests |
| Character | Avatar-preserving spawn, eye height, Walk/Run/Sprint | Movement validation (log only) | — |
| World | Procedural city, terrain, coast, roads, buildings, props, POIs, day/night, lamps, Bake tool | Traffic signal/stop **data** only | Traffic lights / stop signs geometry; weather (rain/clouds) |
| Vehicles (cars) | 7 models, physical suspension/steering/drive, parked spawns, enter/exit, ownership, lights, indicators, flip, reset/freeze, HUD | Handling model (arcade), anti-cheat (log), audio (no assets) | Player spawn/despawn API, ownership/locking, damage, fuel, garages/dealership logic |
| Motorcycles | 5 models, drivable, upright, IK hands | Lean model, pitch, mobile layout | Crash/fall, rider animations |
| Camera | Unified controller, 3 player modes, vehicle/bike follow, collision, cinematic API | Vehicle profiles (temporary values) | Speed FOV, size-aware distance, look-back, hood cam |
| Input | Action map, contexts, gamepad, touch layouts | Analog throttle (defeated), mobile steering (digital) | Rebinding UI |
| UI | Vehicle HUD, debug HUD, mobile buttons | — | **Main menu, loading screen, settings UI**, notifications (`Notify` unused) |
| Data | — | Session/game mode only | **DataStore persistence, settings persistence** |
| AI | Road graph, district densities, `IsNight` | — | **Traffic AI, pedestrian AI** |
| Navigation | `WorldToMap`/`MapToWorld`, neighbours, nearest node | — | **Pathfinding, minimap, full map, GPS route, waypoints** |
| Audio | Engine pitch controller, sound spawning | — | **All audio assets**, SoundGroups, volume settings |
| Animation | Controller and config | — | **All animation assets**; no vehicle hooks |

---

## 6. Findings (ranked)

**Severity:** High = breaks a core experience or opens an exploit; Medium = clearly degrades quality or a likely bug; Low = hygiene/performance/polish.
**Priority:** P0 = fix before any new feature (stabilisation); P1 = next phase; P2 = feature phase; P3 = later.
**Status:** CONFIRMED = follows directly from the code; VERIFY = depends on engine behaviour, confirm in Studio.

### HIGH

#### H1 · Vertical steps where sloped roads meet junction pads — P0 · CONFIRMED (geometry computed from MapData)

- **Location:** `ServerScriptService/WorldGen/RoadBuilder.lua:134-147` (`trimmedEnds`), `77-128` (pads in `planNodes`, flat at node Y), `247-256` (pad boxes), `171-178` (road strips).
- **Problem:**
  - Every road strip is trimmed back to the pad edge by interpolating **along the 3D edge**, so a sloped strip ends `grade × trim` above or below the node height.
  - The junction pad is a flat box whose top is at node Y. The result is a vertical lip at every sloped-edge/pad interface.
  - Measured: **33 interfaces > 0.5 studs, 49 > 0.1**. The worst is **1.30 studs** (freeway edge 594 at node 348, grade 11.8%). Sixteen ramp ends are at **0.66 studs**.
  - Wheel radii are 0.9–1.75. Suspension limits use `Restitution = 0` hard stops. Vehicles bottom out, get launched or stop dead. Bikes (strong align) bounce; the scooter may be unable to climb.
  - These are exactly the freeway and ramp routes that future GPS and traffic will use.
- **Replace/improve:**
  - Generate sloped strips so the end at the pad edge is **at node Y**. Split each sloped edge into a short flat apron (pad edge → apron end at node Y) plus the slope, or recompute the strip from the pad-edge point at node Y to the far trimmed point.
  - Alternatively, tilt the pad, or add a transition `WedgePart`.
  - Add a **geometry validation pass**, in `mapgen.py` or an editor command, that fails the build if any discontinuity exceeds 0.05 studs.
- **Dependents:** VehicleFactory suspension tuning, VehicleController, future TrafficService, GPS routes, bake output.
- **Test:**
  1. Editor script that raycasts down every 0.5 studs along each edge centre-line and across pads, and reports height jumps > 0.05 (expected 0).
  2. Drive each listed ramp at 30/60/100 km/h with every vehicle class, logging peak chassis vertical acceleration and suspension-limit contacts.

#### H2 · Physics authority: parked vehicles under automatic ownership; vehicle position not validated — P0 · CONFIRMED (ownership path) / VERIFY (exploitability)

- **Location:**
  - `VehicleService.lua:649-650`: unanchor without an ownership call.
  - `VehicleService.lua:160-166`: `setAnchored`.
  - The only `SetNetworkOwner(nil)` is at `VehicleService.lua:303`, after a driver exits.
  - `VehicleService.lua:636-645`: speed is logged only.
  - `MovementValidationService.lua:18, 39-42`: `LogOnly`, and seated characters are skipped.
- **Problem:**
  - A server-created assembly that is unanchored with no explicit owner uses **automatic ownership**, so the nearest client simulates it. Most of the 108 parked vehicles have never had an owner set.
  - Any client near them can move or fling them, and ownership flips between players as they walk around, causing stutter.
  - While driving, the driver's client can teleport the car with its passengers; the server only compares velocity against a generous limit and prints a warning.
- **Replace/improve:**
  - Centralise in `setAnchored`: after unanchoring an **unoccupied** vehicle, call `SetNetworkOwner(nil)` on every physical part.
  - Add a server-side position-delta check per driven vehicle: allowed distance ≈ (`MaxSpeed` × 1.3 + slack) × dt, with a grace for flips/resets/exits. On repeated violation, revoke ownership, `ResetToSpot` or eject.
  - Promote `MovementValidationService` to its rubber-band policy after calibration.
- **Dependents:** `_tryEnter`, `onSeated` (sets the driver as owner), `ResetToSpot`, `RequestFlip`, any future traffic AI (AI cars must also be server-owned).
- **Test:**
  1. Studio → Test → Local Server with 2 clients. Walk player 2 next to a parked car and print `GetNetworkOwner()` for its chassis on the server (expected `nil`).
  2. From player 2's client, set the car's `AssemblyLinearVelocity`; it must not move on the server.
  3. While driving, teleport the chassis 200 studs on the client; the server must detect it within one sample window.

#### H3 · Motorcycle lean/stability model — P1 · CONFIRMED (math) / VERIFY (edge-contact chatter magnitude)

- **Location:** `VehicleController.lua:191-201`; `VehicleFactory.lua:330-345` (cylinder wheels), `499-510`, `569`; `VehicleService.lua:153-156`.
- **Problem:** see §4. Lean is input-driven and ~3× too strong at urban speeds. The whole assembly is tilted, so the wheels ride on their edges. Pitch is damped. Parked bikes are forced level. The align torque is so large that no fall or crash is possible.
- **Replace/improve:** the model in §4 (roll stabiliser, physics-derived lean, visual-only lean rig, optional Ball wheels). Expose `LeanSharpness`, `MaxLean` and `RollStiffness` in `VehicleDefinitions`.
- **Dependents:** VehicleFactory bike styles (welds to the chassis/knuckle must move to a lean pivot), hand IK targets, Motorcycle camera profile, `AnimationConfig.BikeLean*`, mobile layout.
- **Test:** figure-8 and constant-radius runs at 20/60/120 km/h, logging commanded lean, `atan(a_lat/g)`, wheel contact (downward raycast per wheel per frame), chassis vertical jitter (RMS) and lateral slip. Accept if lean error < 5° and there is no edge-contact chatter.

#### H4 · Vehicle camera: speed-proportional lag and size-unaware framing — P1 · CONFIRMED

- **Location:** `CameraController.lua:359-369` (exponential pivot smoothing), `339-351` (auto-heading), `396-406` (distance), `422-428` (FOV only for Sprint); `CameraConfig.lua:51-79` (marked temporary).
- **Problem:**
  - Exponential smoothing of a moving target lags by `v / FollowSharpness`: Vehicle (k=12) ≈ **9.2 studs at 110 studs/s** and **12.5 at 150**; Motorcycle (k=14) ≈ **11.4 at 160**. The effective distance nearly **doubles** at top speed and snaps back under braking (rubber-banding). The lag also appears sideways in corners.
  - One profile serves every car, from the 12-stud Pico to the 17-stud Brisa. The camera collision filter excludes the **own** vehicle (`refreshFilter`, lines 109-121), so nothing stops the camera entering its own body. At `MinDistance` = 7 (≈6.85 studs back, 4.06 up) the camera ends up **inside the Porter van's rear glass wedge**, and at rear-quarter angles it clips the other long vehicles.
  - At the default distance the camera is ~5.1 studs above the chassis centre. That is below the van's roof (5.8) and at about the SUV's (5.25) and pickup's (5.15) roof line, so tall vehicles block the forward view.
  - There is no speed FOV, shake, look-back or hood camera.
- **Replace/improve:**
  - Velocity-compensated follow: smooth the **offset** relative to the subject (or predict `target + v·dt`), using a critically damped spring.
  - Per-vehicle framing from `VehicleDefinitions` (Length, CabinHeight): `Distance = k1·Length + k2`, `MinDistance ≥ Length/2 + margin`, height above the roof line.
  - Speed-based FOV (+0…+10) and subtle high-speed shake (accessibility toggle). Look-back key. Optional roll follow for bikes.
- **Dependents:** VehicleController (`RequestMode`, `SetFollowSubject`), CameraConfig, SettingsController (camera options), the future GPS 3D route view.
- **Test:** log `distance(camera, chassis)` vs speed on a straight 0→max→0 run (target ±1 stud of profile distance). Zoom fully in on each vehicle; the camera must never be inside its bounding box. Do a 1-hour mobile soak for errors (safety-net counter stays 0).

#### H5 · Mobile vehicle controls — P1 · CONFIRMED (binary) / VERIFY (jump button)

- **Location:** `MobileControlsController.lua:31-41` (buttons), `117-162` (layout), comment at `140`; `VehicleController.lua:58-69, 291` (`controls:Disable()`).
- **Problem:**
  - Steering is **on/off**, slewed at 3.2/s, so you can't hold a gentle curve. Throttle and brake are on/off too.
  - The layout assumes "Roblox joystick/jump are hidden in vehicles". `ControlModule:Disable()` disables the movement controller, but whether the **TouchJump button** is hidden or inert while seated depends on the PlayerModule version (**VERIFY**). If it stays active, pressing it makes the humanoid jump, which **unseats the driver**, and it sits under the `GAZ` button area.
  - There are no indicator buttons, no Flip for bikes, and no camera reset or look-back.
- **Replace/improve:**
  - An analog steering control: a horizontal drag pad or virtual wheel on the left, outputting −1…1 through `InputController` as an analog channel; optional tilt steering.
  - Optional pressure/drag throttle.
  - Explicitly hide or disable `TouchGui.JumpButton` while seated (or set `Humanoid` jump to disabled while in a vehicle).
  - Add indicator buttons; add Flip for bikes.
- **Dependents:** InputController (needs analog actions, not just booleans), VehicleController `readInputs`, HUD positioning, the future minimap slot (bottom-left is reserved).
- **Test:** Studio device emulator (iPhone SE, iPhone 15, iPad, Pixel). Multi-touch gas + steer + camera drag; a lane-change accuracy test; confirm the jump button isn't visible or usable while seated (tap the area 20× and stay seated).

#### H6 · No persistence (player data or settings) — P1 · CONFIRMED (absent)

- **Location:** no `DataStoreService` anywhere; `PlayerService.lua:2` ("DataService in Phase 7"); `SettingsController.lua:1-3, 17-24, 48` (in-memory only).
- **Problem:** every setting (camera mode, sensitivity, invert, FOV, shoulder, smoothing) resets each session. There is no foundation for owned vehicles, money, progress or sandbox permissions.
- **Replace/improve:**
  - A `DataService` with session locking (ProfileStore-style), schema version + migrations, retry/backoff, autosave, `BindToClose`, and a Studio mock store.
  - A `SettingsRemotes` group (`GetSettings` / `SaveSettings`) validated with the **same validators** as `SettingsController` (move them to a Shared module).
  - A Settings UI.
- **Dependents:** CameraController, SettingsController, PlayerService (load before `SessionReady`), the future main menu, vehicle ownership/garage, economy.
- **Test:** with API Services enabled, change settings, rejoin, and confirm they're restored. Simulate DataStore errors (injected failures) and confirm defaults are used with no overwrite of good data. Two-server session-lock test. A shutdown save test with `BindToClose`.

#### H7 · No main menu, loading screen or controlled spawn flow — P1 · CONFIRMED (absent)

- **Location:**
  - The place has no `ReplicatedFirst` or `StarterGui`. `Players.CharacterAutoLoads = true` is in the place and is also **forced** by `CharacterService.lua:44-47`.
  - Ready but unused: `Constants.CameraModes.Menu`, `CameraController:RequestScripted`/`PlayCinematic`, and the mobile `"Hidden"` layout.
- **Problem:** players drop straight into a world that is still building (pop-in). There is no mode choice (Normal/Sandbox), settings entry point, news or credits.
- **Replace/improve:**
  - A `ReplicatedFirst` loading screen that waits for `WorldReady` + `ContentProvider` on essentials.
  - A `MainMenuController` using a scripted Menu camera, with Play, Settings and Mode.
  - Switch to `CharacterAutoLoads = false`, with the server calling `LoadCharacter` after a validated `RequestSpawn`. `CharacterService.checkAvatarPolicy` must be changed **together** with this, or it will turn auto-load back on.
- **Dependents:** CharacterService, PlayerService (`SessionReady`), CameraController, MobileControls (`Hidden`), DataService (settings before the menu), the spawn race (M7).
- **Test:** cold join on PC, mobile and console. The menu camera animates, the cursor is free, and no gameplay input leaks through. Play → spawn on ground. Re-open the menu mid-game → camera and controls restore. 20 join/leave cycles with no errors.

#### H8 · No traffic or pedestrian AI (and no signal geometry) — P2 · CONFIRMED (absent)

- **Location:** no traffic or NPC services; empty `NPCRemotes`; empty `TrafficNodes`/`PedestrianNodes` folders (`Constants.lua:44-54`). Map data has 211 signal, 235 stop and 181 crosswalk nodes, but `RoadBuilder` builds **no traffic lights or stop signs** (only crosswalk stripes).
- **What exists to build on:** the road graph with lanes forward/backward, speed and one-way edges; `GetNeighbors` with `CanTravel`; district `DayDensity`/`NightDensity`; the `IsNight` attribute; `WeatherService.NightChanged`.
- **Replace/improve:**
  - `TrafficService` (server): a lane model derived from edges (lane offsets from `Width` and lane counts), intersection controllers (signal phases and stop yielding), and **kinematic** AI cars that move along splines with server CFrame updates or client-interpolated replication. They switch to physics only on collision.
  - A spawn/despawn budget in a ring around players, scaled by district density and time of day, with LOD (simplified models far away).
  - Traffic light and stop-sign props built from node flags.
  - `PedestrianService` using sidewalks and crosswalks, with the same budget and LOD approach.
- **Dependents:** H1 (geometry must be clean), H2 (AI must be server-owned), RoadBuilder, MapDefinitions, VehicleFactory (lightweight AI variants), performance budget (L3).
- **Test:** a headless simulation in Studio with 0 players at the 4 city centres (no deadlocks at intersections for 30 minutes); a server heartbeat budget below 2 ms per 50 AI cars; a collision response test; a mobile client FPS test downtown at peak density.

#### H9 · No GPS, minimap or full map — P2 · CONFIRMED (absent)

- **Location:** no navigation module or UI. The minimap slot is reserved (`UIConfig.lua:29`, `MobileControlsController.lua:30`). `MapDefinitions.GetNearestNode` is a linear scan (`238-249`).
- **Replace/improve:**
  - Shared `Navigation`: A\* over the node graph respecting `CanTravel`, with edge cost = length / speed, and a spatial hash for nearest-node lookup.
  - `MinimapController`: map rendering generated from `MapDefinitions` (roads as rotated Frames in a clipped canvas, or a pre-rendered uploaded image; **no map image asset exists yet**), plus a player arrow and POI icons from the 90 POIs.
  - Full-screen map with a waypoint, a route polyline, and a 3D route ribbon or beams.
- **Dependents:** MapDefinitions (indexing), H1 (ramps must be drivable), the mobile layout, the `Notify` remote for "route recalculated" messages, and the main menu (map key binding; `InputConfig` already has an `M` placeholder comment).
- **Test:** unit tests for A\* on the real graph (all 90 POIs reachable from all 14 spawns; one-way ramps respected); route recalculation after deviating > 30 studs; minimap at 60 FPS on a mid-range mobile device.

### MEDIUM

#### M1 · Rear-wheel grip stays reduced after a handbrake exit — P0 · CONFIRMED (logic)

- **Location:** `VehicleController.lua:116-124` (`setRearGrip` caches `c.LowGrip`), `189`, `268` (new state starts with `LowGrip = false`), `225-243` (`leave` never restores).
- **Problem:**
  - Exiting while holding the handbrake above 8 studs/s leaves the rear wheels' **local** `CustomPhysicalProperties` at 45% grip. The server never changes the property, so nothing replicates back to fix it.
  - On re-entry the new state says `LowGrip = false`, so `setRearGrip(c, false)` returns early. The driver's client simulates the car with low rear grip until the handbrake is used again: oversteer and spins.
- **Replace/improve:** initialise `LowGrip = nil` (forcing the first apply) and restore grip in `leave()`. Better still, keep grip in a per-wheel state that is always rewritten on enter.
- **Dependents:** H3/M10 (any future grip model).
- **Test:** at 60 km/h hold Space, press F, re-enter, then compare a constant-radius turn against a fresh car (lateral slip must match).

#### M2 · Lane markings and crosswalks are collidable and protrude — P0 · CONFIRMED

- **Location:** `RoadBuilder.lua:184-198` (line strips: top at road + 0.03, thickness 0.06), `281-295` (crosswalks: centre at pad top, so the top is +0.03); `Kit.lua:24-36` (`finish` keeps the default `CanCollide = true`).
- **Problem:**
  - Thousands of thin collidable parts sit 0.03 studs proud of the asphalt. Fast-spinning cylinder wheels hit a lip at every lane change and crossing (chatter, small hops).
  - They also add collision geometry and raycast hits: camera collision, ground raycasts.
- **Replace/improve:** markings and crosswalks get `CanCollide = false, CanQuery = false, CanTouch = false`, or are set flush or below the surface. **Caution:** the `Markings` folder also holds barriers (`204-213`), bridge rails (`233-234`) and piers (`241`), which **must stay collidable**. Move those into a `Barriers` folder rather than blanket-editing the folder.
- **Dependents:** CameraController and CharacterService raycasts, the bake output.
- **Test:** count collidable parts before and after; drive across a crosswalk at 100 km/h and log vertical acceleration spikes (should drop to the asphalt baseline).

#### M3 · Physical unit inconsistency (speed display vs gravity) — P1 (decision) · CONFIRMED

- **Location:** `VehicleDefinitions.lua:137-140` (0.28 m/stud); default `Workspace.Gravity` = 196.2 (used in `VehicleFactory.lua:544-546`); acceleration/brake values in definitions.
- **Problem:**
  - The HUD treats 1 stud as 0.28 m (110 studs/s ≈ 111 km/h, car length ≈ 4 m, which is realistic).
  - At that scale, gravity is 196.2 studs/s² ≈ **5.6 g**. Weight transfer, suspension sag, jump arcs and especially friction limits (μ·g) are ~5.6× real, so cars almost never slide and fall unnaturally fast.
  - The definitions' `Accel` (≈1 g) and `Brake` values live in a different "world".
- **Replace/improve:** pick a unit policy before tuning:
  - (a) Keep global gravity and add a per-vehicle upward `VectorForce` so effective vehicle gravity is ~35–60 studs/s²; re-derive springs from the effective g.
  - (b) Lower `Workspace.Gravity` and re-tune `JumpPower`.
  - Record the decision in the project context.
- **Dependents:** VehicleFactory mass tuning, all handling tuning, H3 lean math, future traffic AI braking distances.
- **Test:** a tuning table (0–100 km/h time, 100–0 braking distance, max lateral g on a skidpad) measured against agreed targets per class.

#### M4 · Car rolls on slopes with the driver idle; throttle persists 0.3 s after exit — P0 · CONFIRMED

- **Location:** `VehicleController.lua:152` (idle = `coastTorque` only), `VehicleFactory.lua:557` (coast = mass·4·R/n); `VehicleService.lua:301-306` (0.3 s delay before server ownership); `VehicleController.lua:225-231` (driveStep stops immediately on leave).
- **Problem:**
  - The steepest grade is 11.8%: the along-slope component ≈ 23 studs/s² against ≈ 4 studs/s² of coast decel, so a stopped car with its driver idle **rolls away**.
  - On exit the client stops updating motors but still owns the car for 0.3 s with the last command (possibly full throttle), so the car lurches.
- **Replace/improve:** auto-hold when |v| < 1 and there is no throttle (apply `brakeTorque`). In `leave()`, write a brake command to the motors locally before firing `RequestExit`, or have the server take ownership immediately on unseat (keeping the parking-brake delay).
- **Test:** stop mid-ramp for 10 s and measure drift (target < 0.2 studs). Exit at full throttle and measure distance travelled after the exit request (target < 1 stud).

#### M5 · Exiting at speed keeps the vehicle's velocity — P1 · CONFIRMED (logic) / VERIFY (visual result)

- **Location:** `VehicleService.lua:467-489`.
- **Problem:**
  - There is no speed gate. After `SeatWeld` is destroyed, the character keeps the vehicle's velocity (100+ studs/s) and the client-owned character is then pivoted to a spot computed **before** the deferral.
  - Expect flinging, clipping into the car or surroundings, or landing far away. The `ServerTeleportAt` grace hides it from validation.
- **Replace/improve:** a design decision. Either block exit above ~15 studs/s (show "slow down"), or implement a deliberate "bail" (tumble animation). In both cases set the character's root velocity explicitly on exit.
- **Test:** exit at 0/20/60/120 km/h on flat road and next to walls; record the final position, velocity, and any clipping.

#### M6 · Streaming robustness of vehicles — P1 · VERIFY

- **Location:** `Workspace.StreamingEnabled = true`; `VehicleFactory.lua:408` (default `ModelStreamingMode`); `VehicleController.lua:262, 272-282` (`PrimaryPart` and `GetDescendants` read **once** at enter); `AudioController.lua:32-35`.
- **Problem:**
  - With non-atomic streaming, parts of a vehicle model can arrive at different times. If any knuckle, wheel or constraint is missing at the moment of `enter()`, the motor and steer lists are incomplete for the whole ride (pulls to one side or doesn't drive).
  - If `PrimaryPart` hasn't streamed, `driveStep` errors every frame (`c.Chassis.Parent` on nil).
  - The risk is low when the player is next to the car, but it is non-deterministic.
- **Replace/improve:**
  - `model.ModelStreamingMode = Atomic` for vehicles, and `PersistentPerPlayer` plus `AddPersistentPlayer(driver)` while driving.
  - In `enter()`, wait for the expected counts (attributes: wheel count, steer count) with a timeout, or rescan on `DescendantAdded`.
- **Test:** set `StreamingMinRadius` = 32 and `StreamingTargetRadius` = 64 in a test place, enter vehicles right after they stream in, and assert motors == wheels and steers == expected (log counts).

#### M7 · Spawn race and unbaked world — P1 · CONFIRMED (ordering) / VERIFY (frequency)

- **Location:**
  - `WorldService.lua:93-109`: async build.
  - `WorldBuilder.lua:106-115`: ground is step 2; Kit yields every 350 parts.
  - `CharacterService.lua:79-101`: if the raycast misses, it falls back to Y = 0.
  - `CharacterService.lua:123-129`.
- **Problem:**
  - The first players, and every Studio Play Solo, can spawn before the ground/blocks under the spawn exist. They then end up at y=0 inside the later 0.8-stud blocks, or fall.
  - The whole city (tens of thousands of parts + terrain) is also rebuilt on **every** server start, which costs startup time and memory spikes, and it all streams in to joining clients.
- **Replace/improve:** use `WorldBuilder.Bake()` for production places (already supported) and save the baked world. Make `CharacterService` wait for `WorldReady`, or a new `GroundReady` signal, before `PivotTo`; this pairs with H7.
- **Test:** 10× cold Play Solo runs logging the spawn raycast hit and part name, plus server startup time before and after baking.

#### M8 · Vehicle audio: no assets, simplistic engine model — P2 · CONFIRMED

- **Location:** `AudioConfig.lua:10-21` (all IDs `""`); `VehicleFactory.lua:512-535` (no Sound instances are created without IDs); `VehicleService.lua:260-263, 294-299, 542-551`; `AudioController.lua:22-44` (a loop with nothing to act on).
- **Problem:**
  - Vehicles are silent.
  - Even with assets, the model is one loop pitched by speed: no throttle or load, no idle/rev layers, no gears. The horn round-trips through the server (latency = ping).
  - There are no skid, impact, indicator-tick, wind or ambient sounds, no `SoundGroup` hierarchy, and no volume settings.
- **Replace/improve:**
  - Source licensed or original assets.
  - An engine model with simulated RPM and gears, throttle-driven volume/pitch layers, and positional sounds for remote vehicles.
  - Horn played instantly on the local client and replicated through an attribute.
  - SoundGroups (Master/Vehicles/World/UI) with volumes persisted through H6.
- **Test:** asset preload check; pitch range at idle and red-line; 3D roll-off at 10/80/140 studs; horn latency on a 200 ms simulated ping.

#### M9 · Seat touch-sit bypasses the enter validation (motorcycles) — P1 · CONFIRMED (Seat default) / VERIFY

- **Location:** `VehicleFactory.lua:465-484` (`Seat` created with `Disabled = false` and `CanTouch` default `true`; bike seats exposed at `ctx.yW + 1.55`).
- **Problem:** walking or jumping into a parked bike seats the player instantly without the prompt or the distance/rate checks. Car seats are inside the collidable body, so the risk there is lower.
- **Replace/improve:** `seat.Disabled = true` (or `CanTouch = false`), and sit only through the server path. **VERIFY** in Studio whether `Seat:Sit()` works while `Disabled`; if not, toggle `Disabled` around the call inside `_tryEnter`.
- **Test:** sprint into a parked bike 20× and confirm you never get seated; the prompt still seats you.

#### M10 · Handling model limitations — P1/P2 · CONFIRMED

- **Location:** `VehicleFactory.lua:337` (single friction value), `349-364`; `VehicleController.lua:139-189`.
- **Problem:**
  - Isotropic Coulomb friction: no slip-angle-based lateral force, so the car either grips completely or slides.
  - Drift only through a handbrake friction swap.
  - The same grip on asphalt, grass and terrain.
  - No Ackermann, no anti-roll, no ABS or brake bias, no traction control.
  - Gamepad deadzone isn't rescaled.
- **Replace/improve:** in order of value, after M3:
  1. Ackermann (different target angles for the inner and outer wheel).
  2. Surface grip table from a per-wheel downward raycast (material → multiplier).
  3. Anti-roll forces.
  4. ABS-lite and brake bias.
  5. Optionally, a per-wheel lateral force curve through `VectorForce`.
- **Test:** skidpad (radius 30 studs), slalom, step-steer and braking-on-grass tests with logged lateral g, yaw rate and slip.

#### M11 · Vehicle lifecycle gaps (despawn, ownership, cleanup) — P2 · CONFIRMED

- **Location:** `VehicleService.lua:313-371` (spawn only), `348-355` (`Destroying` clears only `records`/`seatRecords`), `621` (`lastSpeedWarn` is never cleared).
- **Problem:**
  - There's no API to despawn a vehicle safely (eject occupants, restore massless/IK, release ownership, disconnect connections).
  - There's no concept of a vehicle **owner** or locking.
  - There's no player-spawned vehicle path, although the POIs `dealership_car`, `dealership_moto`, `garage` and `gas` already exist.
  - There's no damage or health.
  - Today nothing is destroyed, so this is latent. It becomes a bug the moment spawning is added.
- **Replace/improve:** `VehicleService:DespawnVehicle(record, reason)`; an `OwnerUserId` attribute with lock state; a one-personal-vehicle limit; cleanup on `PlayerRemoving`; a damage model later.
- **Test:** 500 spawn/despawn cycles with occupants (track the instance count and `records` size); kick a player while driving; destroy a vehicle mid-drive and confirm every occupant is restored.

#### M12 · Map generator missing; MapData replicated to every client — P1 (process) · CONFIRMED

- **Location:** `MapData.lua:1` ("generated by tools/mapgen.py — don't hand-edit"); `MapDefinitions.lua:5`; `ReplicatedStorage.Shared`.
- **Problem:**
  - The generator isn't in the place or the repository, so road fixes (H1), new districts or validation can't be regenerated.
  - All 348 KB of the source string replicates to every client and is parsed at client start (DebugHUD requires it).
- **Replace/improve:** commit `mapgen.py` and its config to the repository. Keep the server-only data (lots, props, blocks) out of `ReplicatedStorage`, or split it into `MapData.Server` and `MapData.Client` (nodes, edges, districts, POIs).
- **Test:** regenerate MapData and check it is byte-identical with the same seed; measure client memory before and after the split.

### LOW

| ID | Finding | Location | Fix | Test |
|---|---|---|---|---|
| L1 | **Analog triggers defeated.** R2/L2 are also bound as digital actions, so `math.max(1, trigger)` is always 1. The stick deadzone isn't rescaled. | `InputConfig.lua:34-35`; `VehicleController.lua:87-92` | Remove R2/L2 from the digital bindings; rescale `(x - dz)/(1 - dz)` | Half-press R2 gives ~0.5 throttle in a telemetry print |
| L2 | **Indicator blinking runs on the server**, so every blinking car replicates material/colour changes to all clients every 0.4 s | `VehicleService.lua:130-142, 662-675` | The server sets only the `Indicator` attribute; clients animate locally (tag `Vehicle`) | Network receive (KB/s) with 10 cars blinking, before and after |
| L3 | **Street lamps switched on the server** (2,367 heads: material + colour + light), causing a replication burst at dusk/dawn. ~789 lamp SpotLights plus building lights is a heavy load for mobile. | `WeatherService.lua:82-104`; `PropBuilder.lua:18-37`; `Config.World.LampLightEvery = 3` | Clients switch lamps from the `IsNight` attribute; enable lights by distance on the client; graphics-quality setting | MicroProfiler and network at 18:15 game time; mobile FPS downtown at night |
| L4 | **Debug HUD can be toggled by any player in live servers** (F3); verbose logging is on in production | `Config.lua:50-54`; `DebugHUDController.lua:116` | Gate F3 behind Studio or an admin list; `VerboseLogging = RunService:IsStudio()` | A live test with a non-admin account |
| L5 | **Camera safety net never recovers**: after 3 errors it unbinds forever, and vehicle camera requests silently stop working | `CameraController.lua:451-464, 487-496` | Retry the bind after a cooldown or on the next mode change; report the error | Inject an error in a scripted camera supplier; the camera recovers within 2 s |
| L6 | **OnFoot actions stay bound in vehicles.** `V`/DPadUp cycles the (hidden) base camera mode and saves the setting; LeftShift/LeftCtrl are sunk | `InputController.lua:105-123`; `VehicleController.lua:293` | Disable the OnFoot context while in a vehicle, or make the actions context-aware | Press V while driving; the setting must stay unchanged |
| L7 | **Double character watch**: `watchCharacter` runs from both `task.spawn` and `CharacterChanged` at start, connecting the SeatPart listener twice (harmless today) | `VehicleController.lua:388-391` | Guard by character identity, or use a Maid per character | Count connections on the first spawn |
| L8 | **Ride height duplicated**: chassis heights are hard-coded in `SpawnAtGround` (0.9/1) as well as the factory | `VehicleService.lua:380-382` vs `VehicleFactory.lua:411-413, 583` | Expose `VehicleFactory.ComputeRideHeight(def)` | Change a chassis size and confirm the spawn height still matches |
| L9 | **Dead code**: the car `Upright` align is never enabled (flip uses `PivotTo`) | `VehicleFactory.lua:499-510`; `VehicleService.lua:153-156` | Remove it, or use it for a soft flip-assist | — |
| L10 | **Prompts overlap**: all passenger seats share `UIOffset (0, 40)`; prompts use the default Roblox style, against UIConfig's own visual-style rule | `VehicleFactory.lua:485-496` | One contextual "Enter" prompt that picks the nearest free seat; custom prompt UI | Approach a 4-seat car; one clear prompt |
| L11 | **Animation assets empty and unused** (`CarEnter`/`Exit`, `DriveIdle`, `BikeRide`/`Lean`); R6 has no hand IK | `AnimationConfig.lua:14-33`; no callers of `AnimationController:Play` | Author the R15/R6 animations; hook them into enter/exit/lean | Visual check, R6 and R15 |
| L12 | **Physics stepping not pinned**; with adaptive stepping, constraint-heavy vehicles may run at a lower rate | Workspace properties | Evaluate `PhysicsSteppingMethod = Fixed` (**VERIFY** the cost) | Wheel jitter and CPU comparison |
| L13 | **`Notify` remote unused**; no user-facing notifications (for example "Vehicle reset", "Can't exit at speed") | `RemoteRegistry.lua:18` | A `NotificationController` | — |

---

## 7. TODOs, placeholders and missing assets

| Item | Location | Type |
|---|---|---|
| Vehicle camera values marked "GEÇİCİ" (temporary) | `CameraConfig.lua:51` | Placeholder values |
| DataService "Phase 7" | `PlayerService.lua:2` | Deferred |
| Settings persistence/UI "Phase 11" | `SettingsController.lua:2` | Deferred |
| Movement penalties "Phase 12" | `MovementValidationService.lua:3, 18` | Deferred (log only) |
| Minimap "Phase 9" slot | `UIConfig.lua:29`, `MobileControlsController.lua:30` | Reserved UI space |
| `MobileControlsController.lua:5` says vehicle layouts are "added in Phase 3" | Header comment | Stale comment (they exist) |
| `Config.SandboxPlaceIds = {}` | `Config.lua:16` | Missing configuration |
| **All audio IDs empty** (engine car/bike, horn car/bike) | `AudioConfig.lua:10-21` | Missing assets |
| **All 14 animation IDs empty** | `AnimationConfig.lua:14-33` | Missing assets |
| Map image / minimap texture | — | Missing asset |
| Traffic light and stop-sign models | — | Missing assets |
| `tools/mapgen.py` | Referenced in `MapData.lua:1` | Missing source |
| `SOLARA_PROJECT_CONTEXT.md` | Not provided in this session | Missing document |

---

## 8. Implementation roadmap (proposed — awaiting approval)

Each phase ends with its acceptance tests passing. Sizes are relative (S ≈ 1–2 sessions, M ≈ 3–5, L ≈ 6+).

### Phase 1 — Stabilisation hotfixes (P0) · Size M

Fix what is broken before adding anything. These are small, isolated edits with no new systems.

1. **H1** junction steps: RoadBuilder fix plus a geometry validation command.
2. **M2** markings non-collidable (barriers split into their own folder).
3. **H2-a** server ownership on unanchor.
4. **M9** disable touch-sit.
5. **M1** grip-state reset.
6. **M4** auto-hold on slopes and a brake command on exit.
7. **L1** analog triggers and deadzone.
8. **L4** debug gating and logging level.
9. **L6** context-aware OnFoot actions.
10. **L7** double connection.

*Exit criteria:* the geometry validator reports 0 discontinuities; ownership test passes; ramp drive tests are clean.

### Phase 2 — Vehicle feel and authority (P1) · Size L

1. **M3** decide the unit/gravity policy (decision record), then re-derive the factory tuning.
2. **Telemetry overlay**: extend DebugHUD with a vehicle page (speed, wheel contact, suspension compression, lean, lateral g, ownership).
3. **H3** motorcycle rework (roll stabiliser, physics-derived visual lean, pitch freedom, parked-on-slope fix).
4. **M10** car handling upgrades (Ackermann, surface grip, anti-roll, ABS-lite).
5. **H4** vehicle camera rework (velocity-compensated follow, size-aware framing, speed FOV, look-back).
6. **M5** exit-at-speed policy; **M6** streaming-safe vehicles.
7. **H2-b** server position validation for driven vehicles.

*Exit criteria:* tuning table within targets; bike lean error < 5°; camera distance ±1 stud across speeds; streaming test passes.

### Phase 3 — Mobile and input (P1) · Size M

1. **H5** analog steering pad (an InputController analog channel), throttle options, jump-button handling, indicator/flip buttons, layout pass for safe areas.
2. A key/button rebinding foundation (data only; the UI comes in Phase 5).

*Exit criteria:* device-emulator matrix passes; no accidental unseat.

### Phase 4 — Data foundation (P1) · Size M

1. **H6** DataService (session lock, schema, migrations, autosave, `BindToClose`, mock store).
2. Shared settings validators; settings load/save remotes; per-player settings applied before spawn.

*Exit criteria:* persistence tests, failure injection, two-server lock test.

### Phase 5 — Front-end flow (P1) · Size M

1. **H7** ReplicatedFirst loading screen → main menu (scripted camera, Play/Settings/Mode) → server-validated spawn (`CharacterAutoLoads = false`, CharacterService updated in the same change).
2. Settings UI (camera, controls, audio, graphics quality, units).
3. **M7** bake decision: production place uses the baked world; spawn waits for ground.

*Exit criteria:* join-flow tests on PC, mobile and console; 20 join/leave cycles.

### Phase 6 — Navigation (P2) · Size L

1. **M12** bring `mapgen.py` into the repo; split client and server map data.
2. **H9** Navigation module (A\*, spatial index) → minimap → full map + POIs → waypoint + route guidance (2D line + 3D ribbon) → `Notify`-based prompts.

*Exit criteria:* routes from every spawn to every POI; recalculation; mobile FPS.

### Phase 7 — Traffic and pedestrians (P2) · Size L+

1. Traffic light and stop-sign geometry from node flags.
2. **H8** TrafficService: lane model, intersection controller, kinematic AI cars, density by district and time, LOD, collision fallback to physics.
3. PedestrianService on sidewalks and crosswalks, reacting to signals.
4. Performance budget enforcement (**L2**, **L3** done here, or earlier if profiling demands).

*Exit criteria:* 30-minute deadlock-free simulation; server ≤ 2 ms per 50 AI cars; mobile FPS target downtown.

### Phase 8 — Audio and animation (P2) · Size M (asset-dependent)

1. **M8** audio assets, engine RPM model, SoundGroups, horn locality, skid/impact/indicator sounds.
2. **L11** vehicle enter/exit/ride/lean animations (R15 + R6).

*Exit criteria:* audio and animation checklist; latency test.

### Phase 9 — Vehicle ownership and economy hooks (P2/P3) · Size L

1. **M11** despawn API, owner/lock, personal vehicle spawning (dealership/garage POIs), persistence of owned vehicles (Phase 4), optional damage and fuel (gas POIs).

*Exit criteria:* 500-cycle spawn/despawn soak; ownership rules enforced on the server.

**Dependency graph (summary)**

```
Phase 1 ──► Phase 2 ──► Phase 3
   │            │
   │            └──► Phase 7 (needs clean roads + server-owned physics + tuning)
   ├──► Phase 4 ──► Phase 5 ──► Phase 9
   └──► Phase 6 (needs H1 ramps fixed + mapgen.py)
Phase 8 can run in parallel once assets are sourced.
```

---

## 9. Test strategy

There are no automated tests today.

1. **Unit tests** (TestEZ or Jest-Lua, run in Studio or `run-in-roblox`) for pure modules: `MapDefinitions` parse and graph integrity, `VehicleDefinitions` math, `RateLimiter`, `Maid`, `Signal`, settings validators, and the future `Navigation` A\*.
2. **Geometry validator** (editor command): road continuity (H1), marking collision flags (M2), vehicle spot clearance.
3. **Scenario scripts** in a test place: an automated "drive bot" that runs a waypoint course on the client, logging telemetry to the Output as CSV (used for H1/H3/H4/M1/M4/M10).
4. **Multi-client tests:** Studio "Local Server + 2–4 clients" for ownership (H2), enter/exit races, seat contention and streaming (M6).
5. **Device emulator matrix** for every mobile-facing change (H5, H7, H9).
6. **Performance gates:** MicroProfiler captures, server heartbeat time, client FPS and memory (Stats) at fixed downtown and night camera spots, recorded per phase.

---

## 10. Decisions needed before implementation

1. **Project context:** please upload `SOLARA_PROJECT_CONTEXT.md`. It wasn't in this session, so the spec references ("Bölüm N") couldn't be validated.
2. **Map generator:** where is `tools/mapgen.py`? The H1 fix belongs in the generator if it is still the source of truth; otherwise it goes in `RoadBuilder`.
3. **Physics feel:** arcade (current direction) or semi-sim? This drives the unit policy (M3), the tyre model (M10) and the bike model (H3).
4. **Exit at speed (M5):** block it, or allow a deliberate "bail"?
5. **Platform priority:** is mobile the primary platform? That changes the ordering of Phases 2 and 3.
6. **Workflow:** is the project edited directly in Studio, or synced from files (Rojo or similar)? This decides how changes are delivered (patched `.rbxlx` vs script files).
