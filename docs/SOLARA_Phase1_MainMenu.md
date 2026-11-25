# SOLARA — Phase 1: Main Menu and Front-End

**Deliverable:** `place/SOLARA_Phase1_MainMenu.rbxlx`. This is your `SOLARA_Phase3.rbxlx` with the changes below applied.
**Source of truth:** the `src/` tree (one file per script; directory = Explorer path), synced into the place with `tools/build_place.py`.
**Not touched (verified with `git diff`):** vehicle physics (VehicleFactory, VehicleService, VehicleController, VehicleDefinitions) and world generation (WorldGen/*, WorldService, MapData, MapDefinitions).

---

## 1. What the player gets

| Moment | Behaviour |
|---|---|
| **Join** | A black veil fades into the SOLARA menu. The world isn't covered by a frozen loading screen: a slow aerial shot sweeps around the downtown towers. Until the city is built and streamed in, a lightweight sunset scene drawn from plain frames (no images) is shown instead, then cross-fades away. No character exists yet. |
| **OYNA / PLAY** | One spawn request goes to the server. The status line shows progress ("Şehre giriliyor…", or "Şehir hazırlanıyor…" if the server is still building the world). After a short fade the player stands at a spawn point with normal camera, controls, mobile buttons and prompts. Double clicks and repeated presses can't create a second character. |
| **GARAJ / GARAGE** | A polished placeholder marked **YAKINDA / COMING SOON**. It shows the real vehicle catalogue (12 vehicles: top speed in km/h, acceleration, handling, braking, seats, drive, factory colours) and explains how to drive today (walk up to a parked vehicle and press F). There are no buttons or prices that pretend purchasing works. |
| **AYARLAR / SETTINGS** | Four tabs: **Graphics** (visual effects, shadows, reduce motion), **Camera** (mode, sensitivity, invert Y, field of view, shoulder side, smoothing), **Audio** (master / vehicles / ambient / interface volume), **Controls** (mobile button size, plus a key-bindings reference). Changes apply immediately. A footer note says honestly that settings last for the session and saving between sessions comes later. |
| **Respawn** | After death, or if the character disappears, the server respawns the player after `Config.Spawn.RespawnDelay` (4 s). The menu does not reappear. |
| **Reopen the menu** | **P** on keyboard, **D-Pad Left** on gamepad, **☰** button (top-left, touch only). The camera slowly orbits the player, gameplay input is locked and PLAY becomes **DEVAM ET / RESUME**. Close it with RESUME, **P**, **Backspace** or **B**. The world keeps running because the game is multiplayer. The menu won't open while you're in a vehicle; a short toast explains why. |
| **Language** | Turkish if the player's Roblox language is Turkish, otherwise English. |

The design is original to SOLARA. The logo is a striped setting sun plus the SOLARA wordmark (built from frames and gradients, so no uploaded assets are needed). It uses UIConfig's sunset-orange and coral accents on dark translucent panels, the Gotham type family, numbered menu entries (`01 / 02 / 03`), and minimal glyph icons (chevrons, round key badges). The reference screenshot informed only the mood: dusk skyline and a left-aligned menu column.

## 2. Architecture

```
ServerScriptService/Services/CharacterService   ← server-authoritative spawn (RequestSpawn), respawn, ReplicationFocus
ReplicatedStorage/Shared/RemoteRegistry          ← + PlayerRemotes.RequestSpawn (C2S), PlayerRemotes.SpawnStatus (S2C)
ReplicatedStorage/Shared/SettingsSchema          ← single definition of every setting (shared, for later server validation)
ReplicatedStorage/Modules/FrontEndConfig         ← menu shots, stream focus, timeouts

StarterPlayerScripts/Controllers/
  FrontEndController   state machine: Title → Spawning → Playing ⇄ Paused; owns lock/unlock + camera request
  GraphicsController   applies Graphics settings locally (post effects, shadows)
  SettingsController   now schema-driven + pluggable store (session store today, DataService later)
  AudioController      + local mixer: SoundGroups Master → Vehicles / World / Interface
StarterPlayerScripts/FrontEnd/            (UI modules; not auto-started by ClientBootstrap)
  Shell        the ONLY ScreenGui "SolaraFrontEnd" (ResetOnSpawn=false): backdrop, safe area, canvas, ☰, toast, veil
  Backdrop     fallback sunset scene + legibility vignettes
  MenuCamera   camera "suppliers" for CameraController:RequestScripted (Title sweep, Pause orbit)
  MenuInput    keyboard / gamepad / stick navigation with hold-to-repeat
  Focus        one focus model shared by mouse hover, keyboard and gamepad
  Fader        cheap transparency + slide transitions (no CanvasGroups, no blur)
  Widgets      buttons, setting rows (toggle / stepper / slider), tab bar, key hints, logo sun
  Theme, Strings
  Screens/MainScreen, Screens/SettingsScreen, Screens/GarageScreen
```

**Ownership rules respected**
- **Camera:** only CameraController writes `Camera.CFrame`. The menu leaves a scripted request (owner `"FrontEnd"`, priority 80), and on close calls `Release` + `SnapBehindCharacter`.
- **Input:** while the menu is open, the InputController context `OnFoot` is off and the new `Menu` context is on (bound at High priority). PlayerModule controls, ProximityPrompts, Roblox touch controls (`GuiService.TouchControlsEnabled`), our mobile buttons (`SetLayout("Hidden")`) and the player list/backpack/health CoreGuis are disabled. Everything is restored on close.
- **Vehicles:** while seated, controls, prompts and mobile layout belong to VehicleController. The menu never opens there, and if a vehicle seat grabs the player while the pause menu is open, the menu closes and hands over.
- **No background input capture:** when the menu is closed, no full-screen frame is visible. Only the 44 px ☰ (touch) and the non-interactive toast can appear. The veil hides itself when transparent. While the menu is open, the backdrop sinks input so swipes don't rotate the gameplay camera afterwards.

**Spawn safety (server, `CharacterService`)**
- `Players.CharacterAutoLoads = false`. It is set in the place file **and** enforced at Init.
- `RequestSpawn` is rate-limited (3, refilling 0.5/s) and requires a session. It goes through `SpawnPlayer()`:
  - If the character is already alive, it only marks the player in-game; no second character is created.
  - A per-player `Spawning` lock stops concurrent loads.
  - It waits for the world (up to 30 s full build, then up to 15 s for at least the ground step). This also fixes the spawn race found in the audit (M7).
- While in the menu, `player.ReplicationFocus` points at an invisible anchored part near the menu shot, so the city streams in with no character. It is cleared right before `LoadCharacter`.
- Respawn runs through `Humanoid.Died` / `CharacterRemoving` → after `RespawnDelay`, if still in-game and not alive → `SpawnPlayer("Respawn")`. Every path is idempotent.

**Persistence-ready settings:** `SettingsController:SetStore({ Load, Save })` swaps the in-memory session store for a DataStore-backed one later. `Export()`/`Import()` carry `{ Version, Values }`. `SettingsSchema.Sanitize()` is shared, so the server can validate with the same rules.

## 3. Files

### Modified (10 scripts + 1 property)
| Explorer path | Change |
|---|---|
| `Players` (property) | `CharacterAutoLoads` **true → false** |
| `ServerScriptService/Services/CharacterService` | Spawn on request, world wait, single-character lock, respawn handling, ReplicationFocus, `SolaraMenuFocus` part; no longer forces auto-load |
| `ReplicatedStorage/Shared/RemoteRegistry` | + `PlayerRemotes.RequestSpawn`, `PlayerRemotes.SpawnStatus` |
| `ReplicatedStorage/Shared/Constants` | + `Attributes.InGame` |
| `ReplicatedStorage/Modules/InputConfig` | + `OpenMenu` (P / D-Pad Left); + `Menu` context actions (Up/Down/Left/Right, Accept, Back, TabPrev/Next, Close) |
| `ReplicatedStorage/Modules/AudioConfig` | + empty `Interface` sound IDs (Move/Select/Back) |
| `StarterPlayer/StarterPlayerScripts/Controllers/InputController` | Every non-OnFoot context binds at High priority (it was Vehicle only) |
| `…/Controllers/SettingsController` | Schema-driven; same public API (`Get/Set/ResetToDefaults/Changed`), plus `Export/Import/SetStore/IsDefault/GetSchema` |
| `…/Controllers/CameraController` | Scripted supplier may also return `Camera.Focus`; `SnapBehindCharacter` discards queued look input |
| `…/Controllers/MobileControlsController` | Button size × `MobileButtonScale` setting; re-layout on change |
| `…/Controllers/AudioController` | Local SoundGroup mixer, volume settings, vehicle sounds routed to the Vehicles group, `PlayInterface()` |

### Created (16 scripts + 2 folders)
| Explorer path | Type |
|---|---|
| `ReplicatedStorage/Shared/SettingsSchema` | ModuleScript |
| `ReplicatedStorage/Modules/FrontEndConfig` | ModuleScript |
| `StarterPlayer/StarterPlayerScripts/Controllers/FrontEndController` | ModuleScript (controller) |
| `StarterPlayer/StarterPlayerScripts/Controllers/GraphicsController` | ModuleScript (controller) |
| `StarterPlayer/StarterPlayerScripts/FrontEnd` | Folder |
| `…/FrontEnd/Shell`, `Backdrop`, `MenuCamera`, `MenuInput`, `Focus`, `Fader`, `Widgets`, `Theme`, `Strings` | ModuleScripts |
| `…/FrontEnd/Screens` | Folder |
| `…/FrontEnd/Screens/MainScreen`, `SettingsScreen`, `GarageScreen` | ModuleScripts |

### Repository tooling (not in the game)
`tools/build_place.py` (src → .rbxlx; the unchanged round-trip is byte-identical), `tools/place_patches.json`, `src/` (all scripts), `place/` (original + Phase 1 place).

## 4. Roblox Studio — how to install

**Option A (recommended, if you haven't changed the place since the Phase 3 upload):** in Studio, *File → Open from File…* → `place/SOLARA_Phase1_MainMenu.rbxlx`, then *File → Publish to Roblox As…* your existing experience (or *Save to File*).

**Option B (your place has newer edits):** in your place:
1. Select `Players` and untick **CharacterAutoLoads** in Properties.
2. For each **modified** script in §3, open it and replace its whole source with the file from `src/` (same path).
3. Create each **new** script/folder in §3 at the same Explorer path. Use the **ModuleScript** type for all of them, and copy the matching `src/…​.lua` content.
4. Make sure the folder is named exactly `FrontEnd` and the subfolder `Screens`.

## 5. Roblox Studio — test procedure

Open **View → Output** and keep it visible. Every log line is prefixed `[S]` (server) or `[C]` (client) plus a system name.

**T1 · Fresh join**
1. *Home → Play* (F5).
2. Expect a black screen fading into the menu: SOLARA sun + wordmark, `01 OYNA`, `02 GARAJ`, `03 AYARLAR`, your avatar and name top-right, and the version bottom-left.
3. The status line moves through `Şehir hazırlanıyor %…` → `Şehir yükleniyor` → `Şehir hazır` (green dot). The sunset backdrop cross-fades to the live aerial city shot, which drifts slowly.
4. In Explorer → Workspace there is **no** character model for you. In Players → *you* → Attributes, `InGame = false`. The mouse cursor is free. W/A/S/D move the menu focus, not a character.

**T2 · Play**
1. Click **OYNA** (or press Enter with it focused).
2. Status reads `Şehre giriliyor…`, then a short fade.
3. You stand at a spawn point in the plaza with the camera behind you. WASD moves you, the mouse rotates the camera (locked cursor), V cycles the camera mode, and F enters a parked car.
4. Server Output shows `[S][CharacterService] Doğdu: <you> sebep: Menu` **once**. Attribute `InGame = true`.

**T3 · No duplicate spawn**
1. Stop, Play again, and on the menu click OYNA 5 times very fast (or hammer Enter).
2. Exactly one character in Workspace and one `Doğdu` line.

**T4 · Respawn**
1. While playing: *Esc → Reset Character → Reset*. Or, in the server Command Bar: `game.Players:GetPlayers()[1].Character.Humanoid.Health = 0`.
2. After ~4 s you respawn at a spawn point and the camera follows. The menu does **not** open and controls work.
3. Output shows `Öldü:` then `Doğdu: … sebep: Respawn`. Repeat 3×.

**T5 · Reopen the menu (pause)**
1. While on foot, press **P**. The camera slowly orbits your character, the menu shows `DEVAM ET`, and the footer shows `Enter Seç · P Kapat`.
2. WASD/Space do nothing to the character.
3. Close with **P**, **Backspace**, or by clicking DEVAM ET. The camera snaps behind you and movement works.
4. Inside a car press **P**: a toast "Menüyü açmak için önce araçtan in." appears and the menu stays closed.

**T6 · Settings navigation** (from the title menu and from the pause menu)
1. Open AYARLAR.
2. **Q / E** switch tabs, **W/S** or arrows move between rows, **A/D** or arrows change values, **Enter** toggles, **Backspace** goes back. With the mouse, hover highlights rows, clicking toggles, and sliders drag.
3. Check that each change actually applies:
   - *Gölgeler* off → shadows disappear.
   - *Görsel efektler* off → bloom/sun rays/colour grading off.
   - *Kamera hassasiyeti* 3.0 → resume and feel faster mouse look.
   - *Kamera modu* → Birinci şahıs → on resume you are in first person.
   - *Görüş alanı* +15 → wider view.
   - *Hareketi azalt* on → the menu camera stops drifting and transitions are instant.
4. *Bu sekmeyi sıfırla* restores that tab's defaults.
5. Settings survive a respawn (T4) within the same session.

**T7 · Garage**
1. Open GARAJ and move through the 12 vehicles.
2. Details and stat bars update. The `YAKINDA` badge and the "Satın alma bu sürümde yok" box are visible. There are no purchase or spawn buttons.

**T8 · Mobile layout**
1. *Test → Device* (emulator): try **iPhone SE**, **iPhone 14 Pro** (landscape) and **iPad**.
2. The menu fits without overlap and stays below the Roblox top bar. Tap OYNA to play. While the menu is open there is no thumbstick or jump button.
3. In game, the **☰** button sits top-left under the Roblox top bar; tap it to open the pause menu.
4. Swipe the background while the menu is open, then resume: the camera must **not** jump.
5. In Settings → Controls → *Mobil buton boyutu* → Büyük: resume and confirm the sprint/camera buttons are larger.
6. Get in a car: ☰ disappears, and the vehicle buttons work as before.

**T9 · Gamepad** (connect an Xbox/PlayStation controller to the PC)
1. D-Pad/left stick move focus (hold to repeat), **A** selects, **B** goes back, **LB/RB** switch settings tabs, and D-Pad Left/Right change values.
2. In game, **D-Pad Left** opens the pause menu and **B** closes it.

**T10 · Repeated joining / multiplayer**
1. *Test → Clients and Servers → 2 players → Start*.
2. Both windows show the menu. Player 1 plays while Player 2 stays in the menu: Player 2 has no character, and Player 1 sees nobody standing at spawn.
3. Player 2 plays; each player has exactly one character.
4. Close Player 2's window, then add a player again (or Stop/Start 3×). There should be no errors or warnings besides the expected ones in §6.

**T11 · Slow world start**
1. If you have **not** baked the world, the first PLAY right after the server starts may show `Şehir hazırlanıyor, birazdan…` while the server waits for ground and world.
2. The player must never fall through the map at spawn.

## 6. Known limitations (by design for this phase)
- **Settings aren't saved between sessions** yet. The store seam is ready; the DataService phase plugs in.
- **Audio** sliders work, but SOLARA has no sound assets yet (vehicle or interface), so nothing is audible. The settings screen says so.
- **Roblox's graphics-quality level can't be changed by game scripts.** The Graphics tab offers SOLARA's own toggles and points to Esc → Settings.
- The pause menu **doesn't pause the world** (multiplayer), and it's unavailable inside vehicles.
- `SolaraMenuFocus` is an invisible anchored part in Workspace. Leave it alone; the server recreates it at start.
- If you open a place where `Players.CharacterAutoLoads` is still on, the server logs `CharacterAutoLoads açıktı; …kapatılıyor` and fixes it. A player who joined before that line could auto-spawn once; PLAY then just activates that character.
