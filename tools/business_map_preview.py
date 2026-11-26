"""business_map_preview.py — draws docs/city_businesses_preview.png: roads, district names and every business
(City expansion stage 2) from the REAL MapData + BusinessData, coloured by type. Top = north (-Z), like the game map.

Usage: python3 -I tools/business_map_preview.py <lupa-site-packages>
"""
import os
import sys

sys.path.insert(0, sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
os.chdir(ROOT)
from lupa import LuaRuntime  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402
import ambient_data  # noqa: E402

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
TYPES = [  # type, Turkish label, colour
    ("supermarket", "Süpermarket", (60, 200, 90)), ("minimarket", "Market", (255, 140, 40)),
    ("bakkal", "Bakkal", (250, 210, 60)), ("bakery", "Fırın", (210, 150, 80)),
    ("greengrocer", "Manav", (150, 220, 70)), ("pharmacy", "Eczane", (40, 200, 160)),
    ("restaurant", "Restoran", (230, 70, 70)), ("fastfood", "Fast food", (255, 90, 160)),
    ("diner", "Lokanta", (200, 110, 60)), ("cafe", "Kafe", (170, 120, 90)),
    ("internetcafe", "İnternet kafe", (140, 110, 255)), ("dollarstore", "Milyoncu", (255, 80, 200)),
    ("gunshop", "Silah dükkânı", (230, 230, 230)), ("general", "Mağaza", (110, 150, 210)),
]
COL = {t: c for t, _, c in TYPES}

lua = LuaRuntime(unpack_returned_tuples=True)
data, raw = ambient_data.load(lua)
lots = {l.Id: l for l in data.Lots.values()}
biz = [l.Business for l in data.Lots.values() if l.Business is not None]

# view: the urban part of the county
X0, X1, Z0, Z1 = -4200, 4100, -4500, 2100
S = 0.16  # px per stud
W, H = int((X1 - X0) * S), int((Z1 - Z0) * S)
LEG = 250
img = Image.new("RGB", (W + LEG, H), (22, 25, 32))
d = ImageDraw.Draw(img)
f_small = ImageFont.truetype(FONT, 12)
f_dist = ImageFont.truetype(BOLD, 15)
f_title = ImageFont.truetype(BOLD, 17)


def px(x, z):
    return (x - X0) * S, (z - Z0) * S


for e in raw["edges"].values():
    a, b = raw["nodes"][e["A"]]["Position"], raw["nodes"][e["B"]]["Position"]
    width = max(1, int(e["Width"] * S))
    colour = (110, 118, 136) if e["Kind"] in ("freeway", "highway", "ramp") else (70, 76, 90)
    d.line([px(a.X, a.Z), px(b.X, b.Z)], fill=colour, width=width)
# other (non-map) shops: small grey dots
for b in biz:
    if not b.Map:
        l = lots[b.Lot]
        x, y = px(l.Center.X, l.Center.Z)
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(120, 126, 140))
# map businesses
for b in biz:
    if b.Map:
        l = lots[b.Lot]
        x, y = px(l.Center.X, l.Center.Z)
        r = 6 if not b.Poi else 4
        d.ellipse([x - r, y - r, x + r, y + r], fill=COL.get(b.Type, (255, 255, 255)),
                  outline=(255, 255, 255) if not b.Poi else (10, 10, 14), width=2 if not b.Poi else 1)
for dist in raw["districts"]:
    cx, cz = (dist["MinX"] + dist["MaxX"]) / 2, (dist["MinZ"] + dist["MaxZ"]) / 2
    if X0 < cx < X1 and Z0 < cz < Z1 and dist["Type"] not in ("rural", "wetland"):
        x, y = px(cx, cz)
        d.text((x, y), dist["Name"].upper(), font=f_dist, fill=(200, 204, 214), anchor="mm")
# gun shop label
for b in biz:
    if b.Type == "gunshop":
        l = lots[b.Lot]
        x, y = px(l.Center.X, l.Center.Z)
        d.text((x + 9, y), b.Name, font=f_small, fill=(230, 230, 230), anchor="lm")

# legend
lx = W + 16
d.rectangle([W, 0, W + LEG, H], fill=(16, 18, 24))
d.text((lx, 16), "İşletmeler (aşama 2)", font=f_title, fill=(240, 240, 240))
y = 48
for t, label, c in TYPES:
    n_new = sum(1 for b in biz if b.Map and b.Type == t and not b.Poi)
    n_old = sum(1 for b in biz if b.Map and b.Type == t and b.Poi)
    d.ellipse([lx, y + 2, lx + 12, y + 14], fill=c)
    d.text((lx + 20, y), f"{label}  {n_old + n_new}" + (f"  (+{n_new} yeni)" if n_new else ""), font=f_small,
           fill=(220, 220, 226))
    y += 22
y += 8
d.ellipse([lx, y + 2, lx + 12, y + 14], fill=(120, 126, 140))
d.text((lx + 20, y), f"Diğer dükkânlar {sum(1 for b in biz if not b.Map)}", font=f_small, fill=(220, 220, 226))
y += 22
d.text((lx, y + 8), "Büyük beyaz kenarlı = yeni\nKüçük = mevcut yer\nKuzey yukarıda", font=f_small, fill=(160, 164, 176))
out = os.path.join(ROOT, "docs", "city_businesses_preview.png")
img.save(out)
print("wrote", out, img.size)
