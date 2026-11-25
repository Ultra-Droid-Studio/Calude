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
| `place/SOLARA_Fix4_BlackLayer.rbxlx` | **Current build:** + bug-fix roadmap step 4 (dark layer covering the screen in game). Open this in Roblox Studio. |
| `tools/build_place.py` | Writes `src/` into a place file. Existing scripts get their Source replaced, missing scripts/folders are inserted, nothing is deleted, and the output is verified. |
| `tools/place_patches.json` | Explicit property changes applied by the build (for example `Players.CharacterAutoLoads`). |
| `docs/` | Phase 0 audit, Phase 1 notes, Phase 2 car physics report + test course procedure, Phase 3 driving UI, Phase 4 navigation. |
| `tools/test_driving_layout.py` | Runs the real `DrivingLayout.lua` (needs `pip install lupa`) over 184 screen/option combinations: overlap, bounds, 44 px touch targets. |
| `tools/test_navigation.py` | Runs the real `Navigation.lua` on the real `MapDefinitions` data (needs `lupa`): 1260 routes, snapping, unreachable cases, simulated drives with rerouting. |
| `tools/car_model.py` | Offline mirror of the car physics formulas; prints derived tuning values and predicted performance. |

Rebuild the place after editing `src/`:

```
python3 tools/build_place.py place/SOLARA_Phase3.rbxlx src place/SOLARA_Fix4_BlackLayer.rbxlx --patches tools/place_patches.json
```
