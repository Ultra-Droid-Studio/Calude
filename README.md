# SOLARA (Roblox) — source workspace

| Path | What |
|---|---|
| `src/` | Every Luau script of the game, one file per script. Directory = Explorer path. `Name.server.lua` = Script, `Name.client.lua` = LocalScript, `Name.lua` = ModuleScript. |
| `place/SOLARA_Phase3.rbxlx` | Original place as uploaded (baseline). |
| `place/SOLARA_Phase1_MainMenu.rbxlx` | Baseline + Phase 1 (main menu). |
| `place/SOLARA_Phase2_CarPhysics.rbxlx` | **Current build:** baseline + Phase 1 + Phase 2 (car physics). Open this in Roblox Studio. |
| `tools/build_place.py` | Writes `src/` into a place file. Existing scripts get their Source replaced, missing scripts/folders are inserted, nothing is deleted, and the output is verified. |
| `tools/place_patches.json` | Explicit property changes applied by the build (for example `Players.CharacterAutoLoads`). |
| `docs/` | Phase 0 audit, Phase 1 notes, Phase 2 car physics report + test course procedure. |
| `tools/car_model.py` | Offline mirror of the car physics formulas; prints derived tuning values and predicted performance. |

Rebuild the place after editing `src/`:

```
python3 tools/build_place.py place/SOLARA_Phase3.rbxlx src place/SOLARA_Phase2_CarPhysics.rbxlx --patches tools/place_patches.json
```
