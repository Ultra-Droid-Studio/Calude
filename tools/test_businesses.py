#!/usr/bin/env python3
"""test_businesses.py — City expansion stage 2: business registry checks on the REAL data and code.

Runs src/ReplicatedStorage/Shared/Businesses.lua + BusinessData.lua through lupa on the REAL MapData (via
tools/ambient_data.py, which applies Businesses exactly like MapDefinitions.parse), plus the REAL Entrances module.
Checks:
  [1] every business sits on an existing shop lot (storefront / storefront_plain), one business per lot, every
      storefront_plain lot has a business (no more random repeated names), existing POIs keep name/type
  [2] every requested category exists (bakery, corner shop, mini market, supermarket, greengrocer, pharmacy,
      restaurant, fast food, diner, café, internet café, variety store, gun shop)
  [3] names unique (also against all other POIs); brands: (font, colour) unique within a type; fonts are valid
      Enum.Font names
  [4] district rules: neighbourhood types in residential/town districts, gun shop in Riverside nearest Ironside,
      same-type minimum distance, quotas per district respected
  [5] map/GPS: new map businesses became POIs (id biz_<lot>, entrance = MapData convention, lot.PoiId set), entrance
      is off the carriageway, every NEW map business has a verified door (Entrances) whose walkway reaches the sidewalk
Usage: python3 -I tools/test_businesses.py <lupa-site-packages>
"""
import math
import os
import sys

sys.path.insert(0, sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
from lupa import LuaRuntime  # noqa: E402
import ambient_data  # noqa: E402
import plan_businesses as plan  # noqa: E402

VALID_FONTS = {"Legacy", "Arial", "ArialBold", "SourceSans", "SourceSansBold", "SourceSansLight", "SourceSansItalic",
               "Bodoni", "Garamond", "Cartoon", "Code", "Highway", "SciFi", "Arcade", "Fantasy", "Antique",
               "SourceSansSemibold", "Gotham", "GothamMedium", "GothamBold", "GothamBlack", "AmaticSC", "Bangers",
               "Creepster", "DenkOne", "Fondamento", "FredokaOne", "GrenzeGotisch", "IndieFlower", "JosefinSans",
               "Jura", "Kalam", "LuckiestGuy", "Merriweather", "Michroma", "Nunito", "Oswald", "PatrickHand",
               "PermanentMarker", "Roboto", "RobotoCondensed", "RobotoMono", "Sarpanch", "SpecialElite",
               "TitilliumWeb", "Ubuntu"}
REQUIRED = ["bakery", "bakkal", "minimarket", "supermarket", "greengrocer", "pharmacy", "restaurant", "fastfood",
            "diner", "cafe", "internetcafe", "dollarstore", "gunshop"]
NEIGHBOURHOOD = {"bakkal", "bakery", "greengrocer", "dollarstore"}
NEIGHBOURHOOD_DISTRICTS = {"riverside", "vista", "drycreek", "costa", "coral", "palm", "bayview", "pinebrook"}

fails = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not ok:
        fails.append(name)


lua = LuaRuntime(unpack_returned_tuples=True)
base, raw = ambient_data.load(lua, businesses=False)
before_pois = len(list(base.POIs.values()))
data, raw = ambient_data.load(lua)
types_mod = lua.execute(open("src/ReplicatedStorage/Shared/Businesses.lua", encoding="utf-8").read())
types = {k: v for k, v in types_mod.Types.items()}

lots = {l.Id: l for l in data.Lots.values()}
raw_pois = {p["Id"]: p for p in raw["pois"]}
businesses = [l.Business for l in data.Lots.values() if l.Business is not None]
all_pois = list(data.POIs.values())

# ---------------------------------------------------------------- [1]
lot_ids = [b.Lot for b in businesses]
check("[1] one business per lot", len(lot_ids) == len(set(lot_ids)), f"{len(lot_ids)} businesses")
bad_style = [b.Lot for b in businesses if lots[b.Lot].Style not in ("storefront", "storefront_plain")
             and not (b.Unit == "Ground" and lots[b.Lot].Style in plan.CENTRO_STYLES and lots[b.Lot].District == "centro")]
check("[1] businesses only on existing shop lots (+ Centro ground floors of office / modern apartment buildings)",
      not bad_style, str(bad_style[:5]))
ground = [b for b in businesses if b.Unit == "Ground"]
centro_avenue = [l for l in data.Lots.values() if l.District == "centro" and l.Style in plan.CENTRO_STYLES]
check("[1] Centro: ground-floor shops only in Solara Centro", all(
    lots[b.Lot].District == "centro" for b in ground), f"{len(ground)} ground-floor shops")
plain = [l for l in data.Lots.values() if l.Style == "storefront_plain"]
check("[1] every decorative shop lot has a business", all(l.Business is not None for l in plain), f"{len(plain)} lots")
lines = open("src/ReplicatedStorage/Shared/BusinessData.lua", encoding="utf-8").read().count("\t{ Lot = ")
check("[1] registry rows == businesses applied", lines == len(businesses), f"{lines}")
changed = [p for p in all_pois if p.Id in raw_pois and (p.Name != raw_pois[p.Id]["Name"] or p.Type != raw_pois[p.Id]["Type"])]
check("[1] existing POIs keep name and type", not changed)

# ---------------------------------------------------------------- [2]
present = {b.Type for b in businesses if b.Map}
missing = [t for t in REQUIRED if t not in present]
check("[2] all requested business types present", not missing, "missing " + ", ".join(missing) if missing else
      ", ".join(f"{t}:{sum(1 for b in businesses if b.Type == t and b.Map)}" for t in REQUIRED))
unknown = [b.Type for b in businesses if b.Map and b.Type not in types]
check("[2] map business types are in Businesses.Types", not unknown, str(unknown))

# ---------------------------------------------------------------- [3]
names = [b.Name for b in businesses]
dup = sorted({n for n in names if names.count(n) > 1})
check("[3] business names unique", not dup, str(dup))
other_poi_names = [p.Name for p in all_pois if p.Business is None]
clash = sorted(set(names) & set(other_poi_names))
check("[3] no clash with other POI names", not clash, str(clash))
bad_font = sorted({b.Font for b in businesses if b.Font not in VALID_FONTS})
check("[3] fonts are valid Enum.Font names", not bad_font, str(bad_font))
brand_dup = []
for t in {b.Type for b in businesses if b.Map}:
    keys = [(b.Font, tuple(b.Primary.values())) for b in businesses if b.Type == t]
    if len(keys) != len(set(keys)):
        brand_dup.append(t)
check("[3] brand (font + colour) unique within each type", not brand_dup, str(brand_dup))
check("[3] decorative shop signs no longer repeat", len({b.Name for b in businesses if not b.Map}) ==
      len([b for b in businesses if not b.Map]))

# ---------------------------------------------------------------- [4]
wrong_area = [(b.Name, lots[b.Lot].District) for b in businesses if b.Map and b.Type in NEIGHBOURHOOD and
              lots[b.Lot].District not in NEIGHBOURHOOD_DISTRICTS]
check("[4] neighbourhood shops in neighbourhood/town districts", not wrong_area, str(wrong_area))
guns = [b for b in businesses if b.Type == "gunshop"]
gun_ok = len(guns) == 1 and lots[guns[0].Lot].District == "riverside"
if gun_ok:
    g = lots[guns[0].Lot]
    gd = math.hypot(g.Center.X - plan.IRONSIDE_EDGE[0], g.Center.Z - plan.IRONSIDE_EDGE[1])
    others = [l for l in plain if l.District == "riverside" and l.Id != g.Id]
    gun_ok = all(math.hypot(l.Center.X - plan.IRONSIDE_EDGE[0], l.Center.Z - plan.IRONSIDE_EDGE[1]) >= gd for l in others)
check("[4] one gun shop, Riverside lot nearest Ironside", gun_ok)
too_close = []
mapped = [b for b in businesses if b.Map]
for i, a in enumerate(mapped):
    for b in mapped[i + 1:]:
        if a.Type == b.Type and a.Type in plan.MIN_DIST:
            la, lb = lots[a.Lot], lots[b.Lot]
            d = math.hypot(la.Center.X - lb.Center.X, la.Center.Z - lb.Center.Z)
            # existing POIs were placed by the map generator; the rule binds every NEW business
            new_pair = not (a.Poi and b.Poi)
            if new_pair and d < plan.MIN_DIST[a.Type]:
                too_close.append(f"{a.Name}/{b.Name} {d:.0f}")
check("[4] same-type minimum distance", not too_close, "; ".join(too_close[:4]))
centro_types = sorted(b.Type for b in ground if b.Map)
check("[4] Centro quota (pharmacy, internet café, restaurant, café on the map)",
      centro_types == sorted(plan.CENTRO_QUOTA), str(centro_types))
quota_bad = []
for district, quota in plan.QUOTA.items():
    for t in set(quota):
        n = sum(1 for b in mapped if b.Type == t and not b.Poi and lots[b.Lot].District == district)
        if n != quota.count(t):
            quota_bad.append(f"{district}/{t} {n}!={quota.count(t)}")
check("[4] district quotas respected", not quota_bad, str(quota_bad[:5]))

# ---------------------------------------------------------------- [5]
new_map = [b for b in mapped if not b.Poi]
check("[5] new map businesses became POIs", len(all_pois) == before_pois + len(new_map),
      f"{before_pois} -> {len(all_pois)} (+{len(new_map)})")
poi_bad = []
for b in new_map:
    lot = lots[b.Lot]
    pid = "biz_" + str(b.Lot)
    poi = next((p for p in all_pois if p.Id == pid), None)
    if poi is None or lot.PoiId != pid or poi.Type != b.Type or poi.Name != b.Name:
        poi_bad.append(pid)
        continue
    r = math.radians(lot.Rotation)
    ex = lot.Center.X - (lot.Depth / 2 + 2) * math.sin(r)
    ez = lot.Center.Z - (lot.Depth / 2 + 2) * math.cos(r)
    if abs(poi.Entrance.X - ex) > 1e-6 or abs(poi.Entrance.Z - ez) > 1e-6:
        poi_bad.append(pid + " entrance")
check("[5] POI id / lot.PoiId / entrance convention", not poi_bad, str(poi_bad[:5]))

# entrance off the carriageway (compare with the existing shop POIs: same rule)
segs = []
for e in raw["edges"].values():
    a, b = raw["nodes"][e["A"]], raw["nodes"][e["B"]]
    segs.append((a["Position"].X, a["Position"].Z, b["Position"].X, b["Position"].Z, e["Width"]))


def on_road(x, z):
    for ax, az, bx, bz, w in segs:
        dx, dz = bx - ax, bz - az
        L = dx * dx + dz * dz
        t = 0 if L < 1e-9 else max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / L))
        if math.hypot(x - ax - dx * t, z - az - dz * t) < w / 2:
            return True
    return False


road_new = []
for b in new_map:
    p = next(p for p in all_pois if p.Id == "biz_" + str(b.Lot))
    if on_road(p.Entrance.X, p.Entrance.Z):
        road_new.append(b.Name)
check("[5] new POI entrances are not on a road", not road_new, str(road_new))

# doors: real Entrances registry on the real graphs
TG = lua.execute(open("src/ReplicatedStorage/Shared/Ambient/TrafficGraph.lua", encoding="utf-8").read())
PG = lua.execute(open("src/ReplicatedStorage/Shared/Ambient/PedGraph.lua", encoding="utf-8").read())
EN = lua.execute(open("src/ReplicatedStorage/Shared/Ambient/Entrances.lua", encoding="utf-8").read())
CFG = lua.execute(open("src/ReplicatedStorage/Modules/AmbientConfig.lua", encoding="utf-8").read())
graph = TG.Build(data, CFG.Traffic)
pgraph = PG.Build(data, graph)
reg = EN.Build(data, pgraph, PG, graph)
door_lots = set()
for d in (reg.List.values() if reg.List is not None else []):
    door_lots.add(d.LotId)
no_door = [b.Name for b in mapped if not b.Poi and b.Lot not in door_lots]
check("[5] every NEW map business has a verified door to the sidewalk", not no_door,
      f"{len(new_map) - len(no_door)}/{len(new_map)}" + (" missing: " + ", ".join(no_door) if no_door else ""))
old_no_door = [b.Name for b in mapped if b.Poi and b.Lot not in door_lots]
print("INFO existing POI shops without a door (rural roads without sidewalk, unchanged): " + ", ".join(old_no_door))

print()
print("RESULT:", "PASS" if not fails else "FAIL " + "; ".join(fails))
sys.exit(1 if fails else 0)
