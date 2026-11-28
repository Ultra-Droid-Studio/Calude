"""car_inventory/classify.py — rough automatic labels for sub-objects (mirrors, exhaust area, spoiler, plates). Usage: classify.py <inventory.json> <out.json>
Read-only: reads the model file, writes the given output only. Run with python3 -I."""
import json, sys
inv = json.load(open(sys.argv[1]))
res = {}
for car, o in inv.items():
    lo, hi = o["lo"], o["hi"]
    W = hi[0] - lo[0]
    gy = o["cabin_box"]["y"][0]
    zlo, zhi = o["cabin_box"]["z"]
    wc = o["wheels"]["RL"]["center"][1]
    found = {"mirror": [], "exhaust": [], "spoiler": [], "plate": [], "bumper_or_grille": [], "other_small": []}
    for c in o["comps"]:
        a, b = c["lo"], c["hi"]
        cx, cy, cz = [(a[i] + b[i]) / 2 for i in range(3)]
        sx, sy, sz = [b[i] - a[i] for i in range(3)]
        part = c["part"].rsplit("_", 1)[0]
        if part in ("Headlight", "TailLight", "ReverseLight", "IndicatorL", "IndicatorR", "SirenRed", "SirenBlue", "Glass"):
            continue
        if c["tris"] <= 90 and abs(cx) > W * 0.36 and gy - 0.35 < cy < gy + 0.35 and zlo - 0.9 < cz < zlo + 0.9 and sx < 0.45:
            found["mirror"].append((part, c["tris"], round(cx, 2), round(cy, 2), round(cz, 2)))
        elif cz > hi[2] - 0.6 and cy < wc + 0.2 and max(sx, sy) < 0.4 and c["tris"] <= 160 and sz < 0.7:
            found["exhaust"].append((part, c["tris"], round(cx, 2), round(cy, 2), round(cz, 2), round(sx, 2), round(sy, 2)))
        elif cz > zhi and cy > gy - 0.1 and sx > 1.0 and sy < 0.6:
            found["spoiler"].append((part, c["tris"], round(cy, 2), round(cz, 2), round(sx, 2)))
        elif (abs(a[2] - lo[2]) < 0.25 or abs(b[2] - hi[2]) < 0.25) and 0.25 < sx < 0.7 and sy < 0.25 and sz < 0.12:
            found["plate"].append((part, "front" if cz < 0 else "rear"))
        elif (abs(a[2] - lo[2]) < 0.35 or abs(b[2] - hi[2]) < 0.35) and sx > 1.2 and sy < 0.8:
            found["bumper_or_grille"].append((part, "front" if cz < 0 else "rear", c["tris"]))
    res[car] = found
    print(f"== {car}")
    for k, v in found.items():
        if v and k != "other_small":
            print(f"  {k}: {v}")
json.dump(res, open(sys.argv[2], "w"), indent=1)
