# SOLARA (Roblox) — source workspace

| Path | What |
|---|---|
| `src/` | Every Luau script of the game, one file per script. Directory = Explorer path. `Name.server.lua` = Script, `Name.client.lua` = LocalScript, `Name.lua` = ModuleScript. |
| `place/SOLARA_Phase3.rbxlx` | Original place as uploaded (baseline). |
| `place/SOLARA_Phase1_MainMenu.rbxlx` | Baseline + Phase 1 (main menu). |
| `place/SOLARA_Phase2_CarPhysics.rbxlx` | Baseline + Phase 1 + Phase 2 (car physics). |
| `place/SOLARA_Phase3_DrivingUI.rbxlx` | + Phase 3 (driving camera, HUD, mobile controls). |
| `place/SOLARA_Phase4_Navigation.rbxlx` | + Phase 4 (minimap, full map, GPS navigation). |
| `place/SOLARA_Fix1_MenuFade.rbxlx` | + bug-fix roadmap step 1 (menu texts disappearing after screen changes). |
| `place/SOLARA_Fix2_MenuCity.rbxlx` | + bug-fix roadmap step 2 (far city missing behind the main menu). |
| `place/SOLARA_Fix3_WheelWobble.rbxlx` | + bug-fix roadmap step 3 (wheels wobbling by themselves, cars and motorcycles). |
| `place/SOLARA_Fix4_BlackLayer.rbxlx` | + bug-fix roadmap step 4 (dark layer covering the screen in game). |
| `place/SOLARA_Fix5_MinimapFrame.rbxlx` | + bug-fix roadmap step 5 (minimap content spilling outside its frame). |
| `place/SOLARA_Phase6_TrafficAI.rbxlx` | + Phase 6 (traffic and pedestrian AI, sidewalk parser fix). |
| `place/SOLARA_Cars.rbxlx` | + 3D car models (Quaternius CC0) wired in; they appear once the `.glb` files are imported in Studio (docs/SOLARA_CarPack.md). |
| `place/SOLARA_City2.rbxlx` | **Current build:** + city expansion stage 2: business registry (127 businesses, 28 new on the map/GPS incl. bakeries, corner shops, pharmacies, internet café, variety store, gun shop), unique shop names, brand colours and fonts on shop signs; offline tests PASS, not yet tested in Studio (docs/SOLARA_City2_Businesses.md). Open this in Roblox Studio. |
| `place/SOLARA_MapStability.rbxlx` | Previous build: + minimap / full map / GPS stability fix (docs/SOLARA_MapStability.md). |
| `place/SOLARA_MobileCamera.rbxlx` | Previous build: + mobile fix: the Roblox movement joystick no longer turns the camera; camera turns only by dragging elsewhere (docs/SOLARA_MobileCamera.md). |
| `place/SOLARA_VehicleStability.rbxlx` | + vehicle physics stability fix (road micro-steps removed, motorcycle traction control/ABS, fixed physics stepping; docs/SOLARA_VehicleStability.md). |
| `place/SOLARA_LivingCity.rbxlx` | + Living City (denser, faster traffic with signal plans; 80 pedestrians with R15 models and IK walking; pedestrians entering/leaving buildings through doors; City density setting). Car models still need the Studio import above. |
| `assets/carpack/` | Converted car pack: `<Car>.glb` for Studio's Import 3D, `carpack.json`, `LICENSE.txt` (CC0). |
| `tools/build_place.py` | Writes `src/` into a place file. Existing scripts get their Source replaced, missing scripts/folders are inserted, nothing is deleted, and the output is verified. |
| `tools/place_patches.json` | Explicit property changes applied by the build (for example `Players.CharacterAutoLoads`). |
| `docs/` | Phase 0 audit, Phase 1 notes, Phase 2 car physics report + test course procedure, Phase 3 driving UI, Phase 4 navigation, Phase 6 traffic AI, car pack, Living City (`SOLARA_LivingCity.md`), vehicle stability (`SOLARA_VehicleStability*.md`), mobile camera (`SOLARA_MobileCamera.md`), map/GPS stability (`SOLARA_MapStability.md`), city expansion plan + stages (`SOLARA_CityExpansion_Plan.md`, `SOLARA_City2_Businesses.md`). |
| `tools/test_driving_layout.py` | Runs the real `DrivingLayout.lua` (needs `pip install lupa`) over 184 screen/option combinations: overlap, bounds, 44 px touch targets. |
| `tools/test_navigation.py` | Runs the real `Navigation.lua` on the real `MapDefinitions` data (needs `lupa`): 1260 routes, snapping, unreachable cases, simulated drives with rerouting. |
| `tools/test_ambient.py` | Runs the real traffic/pedestrian modules on the real MapData (needs `lupa`): lane and sidewalk graphs, 10 min downtown with flow metrics, extra seeds, blocked lane, closed junction exit, jaywalking player, moving player, two players, night/noon, density presets, signal plans, building entrances, procedural walk (foot sliding). `tools/ambient_data.py` loads the map for it. |
| `tools/test_road_surface.py` | Runs the real `RoadBuilder.lua` (Luau converted for this file) on the real map with Vector3/CFrame stand-ins and measures the driving surface along every lane: steps, gaps, collidable markings. |
| `tools/preview_ped.py` | Draws the NPC R15 rig in poses from the real `PedAnim.lua` (Motor6D math) → `docs/livingcity_ped_preview.png`. |
| `tools/carpack_convert.py`, `tools/fbx_reader.py` | Converts the Quaternius FBX car pack into Roblox-ready `.glb` files (one part per material, split wheels) and renders `docs/carpack_preview.png`. |
| `tools/car_model.py` | Offline mirror of the car physics formulas; prints derived tuning values and predicted performance. |

Rebuild the place after editing `src/`:

```
python3 tools/build_place.py place/SOLARA_Phase3.rbxlx src place/SOLARA_City2.rbxlx --patches tools/place_patches.json
```
