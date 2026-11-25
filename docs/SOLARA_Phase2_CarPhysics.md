# SOLARA — Phase 2: Car Physics Overhaul

**Build:** `place/SOLARA_Phase2_CarPhysics.rbxlx` (Phase 3 original + Phase 1 menu + Phase 2 car physics).
**Status: implemented, NOT yet tested in Roblox Studio.**
- Every number in the tuning tables comes from the offline model `tools/car_model.py`, which mirrors the Lua formulas. These are **predictions, not measurements**.
- The code passes the Luau linter, and the place file is verified on build.
- Nothing here claims the cars feel realistic until the Studio test course (§5) has been run and its `[TEST]` results compared with the targets.

**Scope:** cars only (7 vehicles). Motorcycles keep their previous physics and step function exactly. Camera, world generation and the menu were not changed in this phase.

---

## 1. Why the old model felt wrong (from the Phase 0 audit)

| Old behaviour | Cause |
|---|---|
| Glued, then suddenly snaps loose | Tyre μ ≈ 1.3 against Roblox gravity 196 studs/s². At the HUD's own scale (1 stud = 0.28 m) that is about **7 g** of grip. |
| Stiff, twitchy suspension | Springs were sized for 5.6× real gravity, so every car felt like a toy model. |
| Instant full power | The motor targeted top speed with a torque taper. A keyboard press gave 100% throttle on the first frame. |
| Brakes lock instantly | Brakes were motor target 0 with no ABS. Locked wheels lose steering. |
| Steering snaps | Linear speed scaling with no reference to grip. It's easy to exceed the tyre at speed and spin. |
| All cars feel alike | One formula with a few scaled constants. No weight distribution, gearing, drag or drivetrain character. |
| Rolls down slopes; lurches after exit; handbrake-exit grip bug (audit M1/M4) | No hold logic; local state not reset on exit. |

## 2. The model

### 2.1 Unit policy: real-scale vehicles inside Roblox gravity
- **1 stud = 0.28 m** for speed, power and drag. This is the same scale the HUD and the definitions already used.
- **Cars live in `EffectiveGravity = 42 studs/s²`** (1.2 × real g). Each car carries constant upward `VectorForce`s: one on the chassis and one per wheel. These cancel the rest of Roblox's 196.2 studs/s². Characters, props and everything else keep normal Roblox gravity.
- Why: with real-scale gravity, real engineering values apply directly.
  - Spring frequency in Hz gives real sag and body motion (2–4° of roll per g with no anti-roll hack).
  - Tyre μ ≈ 0.85–1.2 gives real cornering and braking limits.
  - Weight transfer comes out right because suspension forces carry it.
- 1.2 g instead of 1.0 g is a game-feel choice: slightly more grip and less floaty jumps. It is one constant (`VehicleDefinitions.CarPhysics.EffectiveGravity`).

### 2.2 What is physical and what is assisted

| Layer | Physical (Roblox solver) | Assisted (CarPhysics, client, per frame) |
|---|---|---|
| Suspension | Spring + damper per corner; per-axle frequency and damping ratio; ballast part sets the real weight distribution and centre-of-gravity height | — |
| Weight transfer | **Emergent**: chassis pitches/rolls on the springs, so tyre normal loads change | Mild tyre load sensitivity (more load → slightly lower μ), so transfer shapes cornering balance |
| Engine | Wheel hinge motors deliver torque | Virtual gearbox, power curve, shift cut, throttle ramp, top speed set by power vs drag |
| Traction | Tyre friction against ground | Traction control caps wheel overspeed at `TractionSlip`. Static → kinetic μ with hysteresis = controlled traction loss |
| Brakes | Motor torque per wheel, front/rear bias | ABS keeps wheel slip ≤ 10%; handbrake locks the rear and lowers rear μ |
| Steering | Servo per front wheel | Grip-limited angle (full lock at speed ≈ cornering limit), Ackermann, speed-dependent steering rate, counter-steer when sliding |
| Stability | — | Yaw-rate stability torque (ESC-like) on the ground; rotation damping + upright assist in the air |
| Recovery | — | Stuck/tipped detection → server-validated reset |
| Aero / rolling | — | Drag ∝ v², rolling resistance × surface, downforce ∝ v² (GT only) |
| Surface | — | One raycast per frame (wheels round-robin, ~15 Hz each) → grip and rolling resistance per material |

### 2.3 Key formulas (`ReplicatedStorage/Shared/VehiclePhysics.lua`)

| Quantity | Formula | Purpose |
|---|---|---|
| Corner spring rate | `k = m_corner · (2πf)²` | Natural frequency f in Hz, the standard ride metric |
| Static sag | `g_eff / (2πf)²` | Car sits at its design ride height; no hard-coded preload |
| Damping | `c = 2ζ · m_corner · 2πf` | Damping ratio ζ decides how fast the bounce dies (no bouncing) |
| Ride geometry | 60% of travel above ride, 40% below | More bump room for kerbs and road steps |
| Ballast Z | `COM_z = (L/2)(1−2·WeightFront)`, ballast holds 35% of the mass | The front/rear static load really changes |
| Power-limited accel | `a = P_specific · powerFactor(rpm) / v`, capped by `LaunchG` | Strong low-speed pull, then power fall-off; gears change the pull |
| Drag | `K = (P/v_top − a_roll) / v_top²` | Top speed *emerges* from power and drag at `MaxSpeed × 1.03` (`MaxSpeed` itself is unchanged) |
| Steering limit | `δ = atan(L · a_lat / v²) + SlipAllowance`, ≤ `MaxSteer` | Full stick ≈ grip limit, so high speed is controlled, not twitchy |
| Traction control | wheel surface speed ≤ `v + max(1.5, TractionSlip · v)` | Controlled wheelspin; RWD/pickup can cross into kinetic grip (power oversteer) |
| ABS | brake target surface speed = `0.9 · v` | Shortest stop with steering kept |
| Yaw stability | `τ = −(r − r_wanted) · StabilityGain · I_yaw`, with deadband | Prevents spins; low gain on the GT for freedom |

## 3. Requirement checklist (what to verify in Studio)

| # | Requirement | How it is addressed | Verified by test |
|---|---|---|---|
| 1 | Smooth, class-dependent acceleration | Throttle ramp (`ThrottleRise` 2.6–7 /s), launch cap, power curve, gears, shift cut | ACCEL |
| 2 | Braking: speed/force aware, no instant stop, stable, better handbrake | `BrakeG` + bias + ABS; brake ramp; handbrake ramps grip and releases smoothly; hold on slopes | BRAKE |
| 3 | Speed-sensitive steering, no snaps | Grip-limited angle, slew rate 5.5–6.5 /s low → 1.6–3 /s high, faster return to centre, gamepad expo | SLALOM, HAIRPIN, LANECHANGE |
| 4 | Suspension | Frequency/damping per axle from mass, bump-biased travel | ROUGH |
| 5 | Traction, controlled loss, FWD/RWD/AWD | Per-wheel torque split, traction control, static↔kinetic hysteresis, surface table | SKIDPAD, ACCEL on grass |
| 6 | Weight transfer, connected cornering | Physical suspension + ballast COM + load sensitivity | BRAKE, SKIDPAD |
| 7 | Collision response, recovery | Air damping + upright assist, stability torque, stuck/tip → server reset (server checks: stopped AND (tipped OR ≤ 2 wheels grounded)) | Manual: drive off the platform edge, onto barriers |
| 8 | Vehicle identity | 7 separate parameter sets (§4) | All |
| 9 | Performance, ownership, validation | No per-frame tables; one raycast per frame; 6 lightweight force/torque objects per car (no new joints); ownership code untouched; server speed check unchanged | MicroProfiler |

## 4. Vehicle-by-vehicle tuning report

### 4.1 Parameters (`VehicleDefinitions.Catalog.<id>.Physics`)

| Vehicle | Drive | kg · kW | Weight F | μ (F/R mult.) | Springs F/R Hz · ζ | Brake g · bias F | Gears · shift | Throttle rise | Steer rate low/high | Stability | Traction slip |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Pico** (compact) | FWD | 1050 · 70 | 0.62 | 0.95 (1.00/1.02) | 1.60/1.75 · 0.40 | 0.95 · 0.68 | 4 · 0.22 s | 4.5 /s | 5.5 / 2.6 | 6 | 0.08 |
| **Vela** (sedan) | RWD | 1450 · 125 | 0.54 | 1.00 (1.00/1.00) | 1.35/1.50 · 0.38 | 1.00 · 0.64 | 5 · 0.25 s | 3.8 /s | 4.6 / 2.2 | 6 | 0.10 |
| **Rayo GT** (sports) | AWD 35/65 | 1350 · 270 | 0.46 | 1.20 (1.00/1.00) + downforce 0.12 g @100 | 2.10/2.30 · 0.50 | 1.20 · 0.60 | 6 · 0.10 s | 7.0 /s | 6.5 / 3.0 | 3.5 | 0.14 |
| **Terra** (SUV) | AWD 45/55 | 2050 · 175 | 0.55, CoG +0.45 | 0.88 (0.97/1.03) | 1.20/1.35 · 0.36 | 0.88 · 0.66 | 5 · 0.30 s | 3.2 /s | 4.0 / 1.8 | 8 | 0.08 |
| **Mesa** (pickup) | RWD | 1950 · 165 | 0.58, CoG +0.30 | 0.90 (1.00/0.95) | 1.30/1.70 · 0.33 | 0.88 · 0.70 | 4 · 0.30 s | 4.0 /s | 4.2 / 2.0 | 5 | **0.22** |
| **Porter** (van) | FWD | 2250 · 105 | 0.60, CoG +0.50 | 0.85 (0.98/1.03) | 1.25/1.50 · 0.36 | 0.82 · 0.68 | 4 · 0.35 s | 2.6 /s | 3.6 / 1.6 | 9 | 0.06 |
| **Brisa Works** (utility) | RWD | 2400 · 140 | 0.55, CoG +0.35 | 0.88 (1.00/1.00) | 1.30/1.60 · 0.38 | 0.85 · 0.66 | 4 · 0.35 s | 2.8 /s | 3.5 / 1.6 | 8 | 0.10 |

`MaxSpeed`, `MaxSteer`, `ReverseSpeed` and all geometry are unchanged from Phase 0.

### 4.2 Derived Roblox values and PREDICTED performance (offline model)

| Car | Mass (Roblox) | k front / rear | c front / rear | Sag F/R (studs) | Bump / droop | Ballast Z | Drag K | 0-60 km/h | 0-100 km/h | 100→0 m | Grip target (real g) | Steer @ top speed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Pico | 60 | 1880 / 1378 | 150 / 100 | 0.42 / 0.35 | 0.72 / 0.48 | −2.61 | 8.5e-04 | 4.7 s | — | 32.9 (96→0) | 1.14 | 5.5° |
| Vela | 80 | 1554 / 1634 | 139 / 132 | 0.58 / 0.47 | 0.72 / 0.48 | −0.98 | 7.2e-04 | 4.0 s | 10.0 s | 34.1 | 1.20 | 4.8° |
| Rayo GT | 75 | 3003 / 4229 | 228 / 293 | 0.24 / 0.20 | 0.48 / 0.32 | +1.01 | 6.7e-04 | 2.3 s | 4.2 s | 28.5 | 1.44 | 5.3° |
| Terra | 105 | 1642 / 1700 | 157 / 144 | 0.74 / 0.58 | 0.96 / 0.64 | −1.31 | 8.2e-04 | 4.1 s | 11.2 s | 38.7 | 1.05 | 4.2° |
| Mesa | 110 | 2128 / 2636 | 172 / 163 | 0.63 / 0.37 | 0.96 / 0.64 | −2.38 | 9.4e-04 | 4.1 s | 13.2 s | 37.8 | 1.08 | 5.3° |
| Porter | 115 | 2128 / 2043 | 195 / 156 | 0.68 / 0.47 | 0.84 / 0.56 | −2.86 | 6.9e-04 | 6.2 s | — | 32.9 (91→0) | 1.02 | 4.9° |
| Brisa Works | 120 | 2202 / 2729 | 205 / 206 | 0.63 / 0.42 | 0.96 / 0.64 | −1.54 | 8.8e-04 | 5.4 s | — | 31.8 (91→0) | 1.05 | 5.2° |

"—" means the car's top speed is below that mark. The k/c units are Roblox units (k = Mass × per-mass rate). Run `python3 tools/car_model.py src/ReplicatedStorage/Shared/VehicleDefinitions.lua` to regenerate these after any tuning change.

### 4.3 Intended driving identity (verify each in Studio)

- **Pico:** lightest and most eager. Quick steering, short gears, front-heavy FWD, so at the limit the nose washes wide gently (safe understeer). Stops in the shortest distance for its speed. Should feel "flickable" in the slalom.
- **Vela:** the reference car. Neutral, comfortable (soft springs, ζ 0.38), stable at speed. RWD but its traction slip stays under the kinetic threshold, so no power oversteer unless you provoke it with the handbrake.
- **Rayo GT:** fastest, firmest (2.1–2.3 Hz, ζ 0.5), shortest 100→0 (28.5 m), highest grip plus downforce. Rear-biased AWD gives a slightly loose rear on power. Lowest stability assist (3.5), so it's the most "alive". Fast steering.
- **Terra:** heavy, tall (CoG +0.45), soft. Visible body roll and dive, longest braking (38.7 m), safe understeer, slow steering, strong stability assist.
- **Mesa:** light empty rear axle (58% front, rear grip 0.95) with a stiff rear spring and **traction slip 0.22**. The only car that steps out on throttle in tight corners, so it needs a careful right foot. Lazy 4-speed.
- **Porter:** slowest to respond (throttle rise 2.6/s, steer 3.6→1.6/s), high CoG, heavy. Rolls in turns but the strongest stability assist keeps it safe. The bus of the fleet.
- **Brisa Works:** heaviest, but its lower CoG makes it calmer than the van. Stiff rear, steady, slow steering, predictable.

## 5. Test course (repeatable)

**Enable (Studio only):**
1. Select **Workspace** in Explorer → Properties → **Attributes → + Add attribute**: name `SolaraTestCourse`, type **boolean**, value **true**.
2. **Play**. Press OYNA in the menu. You are teleported to the course start, with one of each car lined up facing +X.
3. Get in with **F**. The telemetry panel opens automatically; **F4** toggles it.
4. Every result prints to **Output** as a `[TEST] …` line. **Copy those lines back to me**; they are the measured data the tuning gets corrected against.

The course is an independent asphalt platform at Y = 400 over the Dry Creek plains. It is built the same way every run, and nothing from world generation is involved. On a live server it is never built.

| # | Test | How to drive it | Recorded automatically |
|---|---|---|---|
| 1 | **Straight acceleration** | Stop fully on lane z=0 (distance boards every 200 studs). Floor the throttle and hold. | `ACCEL` 0-60 / 0-100 / 0-140 times, top speed reached |
| 2 | **Emergency braking** | Above 80 km/h on the main lane, full brake (S / LT) until stopped. Don't steer. | `BRAKE` stopping distance (studs and m), time, normalized 100→0, max side-slip, heading drift |
| 3 | **Slalom** | Lane z=250: weave the 9 cones (60-stud spacing) through the start and finish gates. | `SLALOM` time, entry speed, max lateral g, max slip, cones touched |
| 4 | **Tight corner** | 180° hairpin: enter the x=1150 gate heading +X on the upper half, go around the cone ring, exit through the lower half heading −X. | `HAIRPIN` time, max lateral g, slip, cones |
| 5 | **Rough road** | Lane z=−300 at ≈50 km/h, then repeat at ≈80 km/h: speed bumps, alternating side bumps, a **0.66-stud step** (copy of the city's ramp/junction lips), rough patch. | `ROUGH` vertical accel RMS/peak (g), bottom-outs, airborne events |
| 6 | **High-speed stability** | Main lane at ≥120 km/h (Rayo ≥140): 14-stud lane change between the cone pairs at x 1500→1620. | `LANECHANGE` entry speed, max lateral g, max slip, max yaw rate, cones |
| + | **Skidpad** | Circle the R 90 cone ring at (2050, 270), steadily increasing speed until the car runs wide. Keep it in the ring ≥ 5 s. | `SKIDPAD` sustained lateral g |

### 5.1 Pass criteria (proposed; agree or adjust before tuning)

| Test | Pass |
|---|---|
| ACCEL | Each car within ±20% of its predicted 0-60 (§4.2). Ranking from fastest to slowest: Rayo < Vela ≈ Terra ≈ Mesa < Pico < Brisa < Porter. No wheel hop or stall at launch. |
| BRAKE | Normalized 100→0 within ±15% of prediction. **Heading drift < 3°, max slip < 4°** (stable). No wheel shows KAYIYOR (sliding) on the panel during straight braking. |
| SLALOM | No spin (max slip < 15°). Rayo/Pico clearly faster than Terra/Porter/Brisa. Steering never jumps. |
| HAIRPIN | Completed at walking-to-moderate speed with no 3-point turn; the inside front wheel turns more (Ackermann). |
| ROUGH (50 km/h) | No airborne events; ≤ 1 bottom-out (the 0.66 step). Body settles within ~1.5 oscillations; no endless bouncing. |
| ROUGH (80 km/h) | No loss of control (max slip < 8°); the car stays upright. |
| LANECHANGE | ≥ 120 km/h, max slip < 6°, no cones, no oscillation after the manoeuvre. |
| SKIDPAD | Sustained lateral g within ±15% of the grip target (§4.2). Pico/Porter/Terra understeer at the limit; Mesa can oversteer on throttle. |
| Recovery | Drive into the barrier or off the platform edge: within ~3 s of being stuck or tipped (holding throttle), the server resets the car upright. |
| Slope | Stop on any city ramp and release all inputs for 10 s: the car does not roll (drift < 0.2 studs). |
| Exit | Exit at 60 km/h with throttle held: the car doesn't lurch forward and slows to a stop. |
| Motorcycles | Unchanged: ride one of each bike; behaviour must match before this phase. |
| Performance | MicroProfiler (Ctrl+F6) on the client while driving: `CarPhysics` step well under 0.2 ms/frame. |

## 6. Files

### Modified
| Explorer path | Change |
|---|---|
| `ReplicatedStorage/Shared/VehicleDefinitions` | + `MetersPerStud`, + `CarPhysics` constants, + documented `Physics` table per car, + `UsesCarPhysics()`. Legacy fields kept (motorcycles and garage stats use them). |
| `ServerScriptService/Vehicles/VehicleFactory` | Car branch: ballast, bump-biased strut geometry, per-axle springs/damping, anti-gravity forces, `Forces`/`Stability` movers, hold torque, attributes; `ComputeRideHeight()`. **The motorcycle path is unchanged.** |
| `ServerScriptService/Services/VehicleService` | Spawn height from `ComputeRideHeight` (motorcycle value identical); `RequestFlip` also accepts a stopped car with ≤ 2 grounded wheels (server raycasts, rate-limited as before). |
| `StarterPlayer/StarterPlayerScripts/Controllers/VehicleController` | Cars use `CarPhysics` on PreSimulation with analog triggers and stick expo; on exit the car is set to hold locally (fixes the M1 grip bug and M4 lurch). **Motorcycles keep the old step, and triggers stay digital for them.** |
| `ReplicatedStorage/Modules/InputConfig` | R2/L2 removed from the digital gas/brake bindings (read analog); + `ToggleTelemetry` (F4) |

### Created
| Explorer path | Purpose |
|---|---|
| `ReplicatedStorage/Shared/VehiclePhysics` | Formulas shared by server and client |
| `StarterPlayer/StarterPlayerScripts/Vehicles/CarPhysics` (+ folder) | Runtime car model (driver's client) |
| `StarterPlayer/StarterPlayerScripts/Controllers/VehicleTelemetryController` | F4 panel + automatic test recorders |
| `ServerScriptService/Services/VehicleTestService` | Studio-only, opt-in course setup |
| `ServerScriptService/Testing/VehicleTestCourse` (+ folder) | Course geometry |
| `tools/car_model.py` (repo only) | Offline mirror of the formulas → tuning report numbers |

## 7. Risks to watch in the first Studio run, and the knob for each

| If you see… | Likely cause | First knob |
|---|---|---|
| Cars float, sit too high, or bottom out at rest | Anti-gravity vs mass mismatch, or `CurrentPosition` sign assumption | Panel "sıkış" (compression) should read **≈0.40** for every wheel at rest. Report the values. |
| Wobble/jitter at rest | Springs too stiff for Roblox's solver at small masses | Lower `SpringHz` 10–15% or raise `Damping` to 0.45 |
| Too floaty over crests and ramps | Effective gravity too low for taste | `CarPhysics.EffectiveGravity` 42 → 50 |
| Spins too easily / never slides | Stability or kinetic thresholds | `StabilityGain`, `KineticGrip`, `SlideEnterAngle` |
| Steering feels numb at speed | Grip-limited steering too conservative | `LatLimitScale` +0.05, `SlipAllowanceDeg` +1 |
| Slides forever on handbrake | Rear grip recovery too slow | `HandbrakeGrip` up, or release rate (3/s) up |

## 8. Not in this phase (deliberately)
- **Motorcycles** (audit H3): waiting until car physics passes testing, as requested.
- **Vehicle camera lag** (audit H4) and **mobile analog steering** (audit H5): these affect feel, but they are camera/UI work. Next candidates after this phase passes.
- **City road steps** (audit H1, up to 1.30 studs at ramp/junction edges): this is world generation. The ROUGH test reproduces the 0.66-stud step so suspension can be judged against it, but the real fix belongs in RoadBuilder/mapgen with your approval.
- **Parked-vehicle network ownership** (audit H2): left as-is because this phase must preserve ownership behaviour. It's a security fix worth its own approval.
