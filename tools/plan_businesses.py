"""plan_businesses.py — City expansion stage 2: picks which shop lots become which businesses and writes
src/ReplicatedStorage/Shared/BusinessData.lua (plain data; can be edited by hand afterwards — rerunning this tool
overwrites hand edits).

The map does NOT change: only lots that are already shops are used.
  * Existing shop POIs (MapData "P" rows on storefront lots) keep their name; they get a business type + brand.
  * Decorative shops (style storefront_plain, previously a random name from a 16-name list with repeats) become:
      - requested businesses (bakery, corner store, greengrocer, pharmacy, ...) by per-district quotas, or
      - other small shops (barber, florist, ...) with unique names (not on the map).
Rules (checked again by tools/test_businesses.py):
  * district character decides the mix (quota table below), not "a shop in every building";
  * main-street types prefer lots facing an avenue, neighbourhood types prefer side streets;
  * same-type businesses keep a minimum distance (MIN_DIST); the gun shop goes to the Riverside lot nearest Ironside;
  * candidates are spread out (each pick maximises distance to the businesses already placed in the district);
  * every name is unique, every brand (font + colour) differs from its type-mates.

Usage: python3 -I tools/plan_businesses.py
"""
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPDATA = os.path.join(ROOT, "src/ReplicatedStorage/Shared/MapData.lua")
OUT = os.path.join(ROOT, "src/ReplicatedStorage/Shared/BusinessData.lua")

# ---------------------------------------------------------------- catalogue (names are original)
NAMES = {
    "bakery": ["Horno Dorado", "Miga & Co.", "La Espiga", "Pan del Puerto", "Sunrise Bakehouse", "Dulce Harina"],
    "bakkal": ["Esquina Siete", "Don Tito's", "Bodega Paloma", "Tienda Rosita", "Abasto Luna", "Kiosko Azul"],
    "minimarket": ["Mini Sol 24", "QuickPick Market", "Daily Mart", "Breeze Mini Market"],
    "greengrocer": ["Verde Fresco", "Fruta Viva", "Huerta del Barrio", "Green Basket"],
    "pharmacy": ["Farmacia Brisa", "SolaCare Pharmacy", "Farmacia Coral", "VitaPlus Pharmacy"],
    "restaurant": ["Azul Kitchen", "Salt & Ember", "Mareas", "Casa Bruma"],
    "fastfood": ["Flamingo Burger", "Wave Wings", "Pollo Rayo", "Cruise-In Burgers"],
    "diner": ["Mamá Lucía", "Sunny Side Diner", "Comedor Esperanza", "Blue Plate"],
    "cafe": ["Brisa Coffee", "Café Malecón", "Daydream Espresso", "Grano & Sal"],
    "internetcafe": ["Byte Harbor", "Pixel Lounge", "NetWave"],
    "dollarstore": ["Todo Mil", "Casa 99", "Everything Bazaar"],
    "gunshop": ["Gulfline Outfitters"],
}
# Other small shops (not on the map): type -> names
OTHER = {
    "boutique": ["Boutique Sol", "Maré Boutique", "Lino & Seda", "Coastline Threads", "Velvet Palm"],
    "barber": ["Navaja Barber Co.", "Fade Street Barbers", "Clipper Bay", "Old Razor"],
    "laundry": ["Suds & Sun Laundry", "Spin City Wash", "Lavandería Clara"],
    "florist": ["Flor de Sal", "Petal & Stem", "Jardín Rosa"],
    "books": ["Página Books", "Tidewater Books", "Dog-Ear Books"],
    "tailor": ["Hilo Fino Tailor", "Needle & Coast", "Sastrería Ruiz"],
    "surf": ["Swell Surf Shop", "Offshore Boards", "Ola Surf Co."],
    "gallery": ["Galería Lumbre", "Blue Hour Gallery", "Studio Arena"],
    "hardware": ["Tornillo Hardware", "Bolt & Beam", "Ferretería Faro"],
    "bike": ["Spoke Coast Bikes", "Rueda Bike Shop", "Pedal Palm"],
    "optics": ["Clearview Optics", "Óptica Mirada", "Lens Bay"],
    "phonerepair": ["FixPoint Phones", "Celular Rápido", "Signal Repair"],
    "gelato": ["Gelato Brisa", "Helados Nube", "Scoop Harbor"],
    "salon": ["Salón Aurora", "Glow Studio", "Rizos Beauty"],
    "records": ["Vinyl Tide", "Disco Sol Records", "Groove Alley"],
    "pets": ["Patitas Pet Shop", "Bark & Bay", "Pet Palma"],
    "jewelry": ["Joyería Perla", "Gold Coast Jewels", "Brillo"],
    "shoes": ["Paso Shoes", "Sole Coast", "Zapatería Mar"],
    "travel": ["Horizonte Travel", "Island Hop Tours", "Viajes Brisa"],
    "photo": ["Foto Flash", "Snapshot Studio", "Lente Dorada"],
    "toys": ["Juguetes Pipo", "Toy Lagoon"],
    "music": ["Acorde Music", "Strings & Drums"],
    "sports": ["Deportes Faro", "Court & Coast"],
    "tattoo": ["Tinta Azul Tattoo", "Inkwave Studio"],
}
FONTS = {
    "bakery": ["Fondamento", "Kalam", "Merriweather", "PatrickHand"],
    "bakkal": ["DenkOne", "PatrickHand", "Highway", "Ubuntu"],
    "minimarket": ["GothamBlack", "Oswald", "RobotoCondensed", "Ubuntu"],
    "greengrocer": ["Kalam", "IndieFlower", "FredokaOne", "PatrickHand"],
    "pharmacy": ["Nunito", "JosefinSans", "TitilliumWeb", "Roboto"],
    "restaurant": ["Bodoni", "Garamond", "Merriweather", "JosefinSans"],
    "fastfood": ["Bangers", "LuckiestGuy", "FredokaOne", "Cartoon"],
    "diner": ["Highway", "PermanentMarker", "Oswald", "Antique"],
    "cafe": ["AmaticSC", "Kalam", "JosefinSans", "Fondamento"],
    "internetcafe": ["Arcade", "Sarpanch", "Michroma"],
    "dollarstore": ["LuckiestGuy", "FredokaOne", "Bangers"],
    "gunshop": ["Oswald"],
    "supermarket": ["GothamBlack", "Ubuntu"],
    "general": ["Oswald", "RobotoCondensed", "DenkOne", "Ubuntu", "Highway", "Merriweather", "TitilliumWeb"],
    "other": ["JosefinSans", "Bodoni", "Kalam", "Oswald", "Nunito", "Merriweather", "Ubuntu", "Garamond", "AmaticSC",
              "DenkOne", "TitilliumWeb", "Fondamento", "PatrickHand", "RobotoCondensed", "Michroma", "Highway"],
}
# (primary, secondary) colour pairs per type (sign / awning colour, detail colour)
PALETTE = {
    "bakery": [((196, 132, 64), (250, 236, 210)), ((150, 82, 52), (244, 214, 170)), ((214, 168, 90), (92, 58, 38)), ((232, 150, 120), (255, 244, 230))],
    "bakkal": [((40, 120, 90), (250, 240, 210)), ((180, 60, 50), (250, 236, 200)), ((50, 90, 160), (255, 220, 90)), ((210, 140, 40), (40, 40, 40))],
    "minimarket": [((235, 90, 40), (255, 255, 255)), ((30, 140, 200), (255, 230, 80)), ((200, 30, 60), (255, 255, 255)), ((60, 170, 90), (255, 255, 255))],
    "greengrocer": [((70, 150, 60), (255, 220, 80)), ((120, 180, 60), (200, 60, 40)), ((40, 110, 70), (250, 160, 50)), ((150, 190, 70), (90, 50, 30))],
    "pharmacy": [((30, 160, 110), (255, 255, 255)), ((40, 120, 200), (255, 255, 255)), ((20, 150, 160), (240, 250, 250)), ((80, 170, 90), (255, 255, 255))],
    "restaurant": [((30, 40, 60), (220, 180, 110)), ((120, 40, 40), (240, 220, 190)), ((20, 90, 110), (250, 240, 220)), ((60, 50, 45), (230, 170, 90))],
    "fastfood": [((255, 92, 150), (255, 230, 90)), ((250, 180, 30), (200, 40, 40)), ((230, 60, 40), (255, 210, 60)), ((60, 200, 230), (255, 255, 255))],
    "diner": [((200, 40, 50), (240, 240, 240)), ((40, 150, 170), (250, 220, 120)), ((30, 60, 110), (240, 90, 80)), ((240, 170, 40), (60, 30, 20))],
    "cafe": [((110, 72, 50), (240, 226, 200)), ((40, 120, 130), (250, 240, 220)), ((200, 120, 140), (255, 246, 236)), ((60, 60, 60), (230, 200, 150))],
    "internetcafe": [((120, 80, 255), (60, 230, 255)), ((40, 220, 200), (255, 70, 200)), ((255, 60, 160), (90, 200, 255))],
    "dollarstore": [((255, 200, 30), (220, 30, 120)), ((240, 60, 140), (60, 200, 240)), ((70, 190, 90), (255, 220, 40))],
    "gunshop": [((40, 44, 48), (200, 150, 60))],
    "supermarket": [((70, 170, 80), (255, 255, 255)), ((230, 70, 50), (255, 255, 255))],
    "general": [((70, 100, 150), (240, 240, 240)), ((150, 110, 60), (250, 240, 220)), ((60, 130, 120), (255, 255, 255)), ((170, 70, 60), (250, 240, 220))],
    "other": [((230, 120, 150), (255, 255, 255)), ((50, 140, 160), (250, 240, 220)), ((120, 90, 170), (255, 230, 120)),
              ((240, 160, 60), (40, 40, 50)), ((40, 60, 90), (240, 200, 120)), ((90, 160, 110), (255, 250, 240)),
              ((200, 70, 70), (250, 240, 220)), ((70, 90, 110), (230, 230, 230)), ((250, 200, 180), (90, 60, 50))],
}
SIGN = {"bakery": "Awning", "bakkal": "Blade", "minimarket": "Box", "greengrocer": "Awning", "pharmacy": "Box",
        "restaurant": "Letters", "fastfood": "Box", "diner": "Letters", "cafe": "Blade", "internetcafe": "Letters",
        "dollarstore": "Box", "gunshop": "Box", "supermarket": "Box", "general": "Box", "other": "Box"}
MIN_DIST = {"bakery": 350, "bakkal": 300, "minimarket": 350, "greengrocer": 400, "pharmacy": 500, "restaurant": 200,
            "fastfood": 300, "diner": 300, "cafe": 200, "internetcafe": 600, "dollarstore": 500, "gunshop": 0}
MAIN_STREET = {"pharmacy", "restaurant", "fastfood", "cafe", "internetcafe", "supermarket"}  # prefer avenues
# New businesses per district (on storefront_plain lots). Centro has no free shop lots: its ground-floor shops
# come with the facade stage (3).
QUOTA = {
    "riverside": ["gunshop", "bakery", "bakkal", "greengrocer", "pharmacy", "internetcafe", "dollarstore", "bakery",
                  "bakkal", "cafe"],
    "vista": ["pharmacy", "bakery", "bakkal", "dollarstore", "greengrocer", "minimarket", "fastfood", "bakkal"],
    "costa": ["restaurant", "fastfood", "pharmacy", "bakery", "cafe"],
    "coral": ["restaurant", "fastfood", "bakery"],
    "drycreek": ["bakkal", "bakery"],
}
DISTRICT_OTHER = {
    "riverside": ["barber", "laundry", "tailor", "hardware", "records", "phonerepair", "pets", "shoes", "tattoo", "books",
                  "florist", "music", "bike", "photo"],
    "vista": ["hardware", "barber", "florist", "books", "optics", "pets", "laundry", "salon", "toys", "shoes", "sports",
              "bike", "photo", "phonerepair", "travel"],
    "costa": ["boutique", "surf", "gelato", "jewelry", "gallery", "salon", "shoes", "travel", "tattoo", "optics",
              "records", "photo", "florist", "sports", "boutique"],
    "coral": ["surf", "gelato", "boutique", "gallery", "travel", "jewelry", "salon", "photo", "sports", "florist",
              "shoes", "toys", "music", "boutique"],
    "drycreek": ["hardware", "barber", "laundry", "sports"],
}
EXISTING_TYPE = {"convenience": "minimarket", "grocery": "greengrocer", "cafe": "cafe", "fastfood": "fastfood",
                 "supermarket": "supermarket", "general": "general"}
IRONSIDE_EDGE = (-640.0, 880.0)  # Ironside's corner that faces Riverside


def parse():
    lots, pois, nodes, edges = {}, {}, {}, []
    for line in open(MAPDATA, encoding="utf-8"):
        f = line.rstrip("\n").split("|")
        if f[0] == "L":
            lots[int(f[1])] = dict(Id=int(f[1]), District=f[2], Style=f[3], X=float(f[5]), Z=float(f[6]),
                                   W=float(f[7]), D=float(f[8]), Rot=float(f[9]), Poi=f[12] if len(f) > 12 and f[12] else None)
        elif f[0] == "P":
            pois[f[1]] = dict(Id=f[1], Type=f[2], Name=f[3], Lot=int(f[9]))
        elif f[0] == "N":
            nodes[int(f[1])] = (float(f[2]), float(f[4]))
        elif f[0] == "E":
            edges.append((int(f[2]), int(f[3]), f[4]))
    segs = [(nodes[a][0], nodes[a][1], nodes[b][0], nodes[b][1], k) for a, b, k in edges if a in nodes and b in nodes]
    return lots, pois, segs


def front_point(lot):
    r = math.radians(lot["Rot"])
    lz = -(lot["D"] / 2 + 2)  # same convention as MapData POI entrances
    return lot["X"] + lz * math.sin(r), lot["Z"] + lz * math.cos(r)


def road_kind(lot, segs):
    x, z = front_point(lot)
    best, bd = None, 1e18
    for ax, az, bx, bz, k in segs:
        dx, dz = bx - ax, bz - az
        L = dx * dx + dz * dz
        t = 0 if L < 1e-9 else max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / L))
        d = math.hypot(x - ax - dx * t, z - az - dz * t)
        if d < bd:
            bd, best = d, k
    return best


def dist(a, b):
    return math.hypot(a["X"] - b["X"], a["Z"] - b["Z"])


def main():
    lots, pois, segs = parse()
    out = []  # business dicts
    used_names = set()
    name_index = {}
    brand_index = {}

    def take_name(t, pool):
        i = name_index.get(t, 0)
        while pool[i % len(pool)] in used_names:
            i += 1
            if i > 10 * len(pool):
                raise SystemExit("name pool exhausted for " + t)
        name_index[t] = i + 1
        n = pool[i % len(pool)]
        used_names.add(n)
        return n

    def brand(t, key):
        i = brand_index.get(key, 0)
        brand_index[key] = i + 1
        fonts, pal = FONTS[key], PALETTE[key]
        p = pal[i % len(pal)]
        # step the font independently so (font, colour) pairs differ within a type
        return fonts[(i + i // len(pal)) % len(fonts)], p[0], p[1]

    # 1) existing shop POIs on storefront lots
    for poi in sorted(pois.values(), key=lambda p: p["Id"]):
        lot = lots.get(poi["Lot"])
        if not lot or lot["Style"] != "storefront":
            continue
        t = EXISTING_TYPE.get(poi["Type"])
        if poi["Type"] == "restaurant":
            t = "diner" if "Diner" in poi["Name"] else "restaurant"
        if not t:
            continue
        used_names.add(poi["Name"])
        font, c1, c2 = brand(t, t)
        out.append(dict(Lot=lot["Id"], Poi=poi["Id"], Type=t, Name=poi["Name"], Map=True, Existing=True, Font=font,
                        Primary=c1, Secondary=c2, Sign=SIGN[t], Road=road_kind(lot, segs), District=lot["District"],
                        X=lot["X"], Z=lot["Z"]))

    # 2) new businesses on decorative shop lots
    free = {lid: l for lid, l in lots.items() if l["Style"] == "storefront_plain" and not l["Poi"]}
    for l in free.values():
        l["Road"] = road_kind(l, segs)
    for district in sorted(QUOTA):
        cands = [l for l in free.values() if l["District"] == district]
        for t in QUOTA[district]:
            same = [b for b in out if b["Type"] == t]
            placed = [b for b in out if b["District"] == district]
            best, best_score = None, -1e18
            for l in cands:
                if any(math.hypot(l["X"] - b["X"], l["Z"] - b["Z"]) < MIN_DIST[t] for b in same):
                    continue
                if t == "gunshop":
                    score = -math.hypot(l["X"] - IRONSIDE_EDGE[0], l["Z"] - IRONSIDE_EDGE[1])
                else:
                    spread = min([math.hypot(l["X"] - b["X"], l["Z"] - b["Z"]) for b in placed] or [400.0])
                    pref = l["Road"] == ("avenue" if t in MAIN_STREET else "street")
                    score = min(spread, 400.0) / 400.0 + (0.5 if pref else 0.0) - l["Id"] * 1e-7
                if score > best_score:
                    best, best_score = l, score
            if not best:
                raise SystemExit(f"no lot for {t} in {district}")
            cands.remove(best)
            del free[best["Id"]]
            font, c1, c2 = brand(t, t)
            out.append(dict(Lot=best["Id"], Poi=None, Type=t, Name=take_name(t, NAMES[t]), Map=True, Existing=False,
                            Font=font, Primary=c1, Secondary=c2, Sign=SIGN[t], Road=best["Road"], District=district,
                            X=best["X"], Z=best["Z"]))

    # 3) remaining decorative lots: other small shops, unique names, neighbours differ in type
    for district in sorted({l["District"] for l in free.values()}):
        cycle = DISTRICT_OTHER.get(district, list(OTHER))
        rest = sorted((l for l in free.values() if l["District"] == district), key=lambda l: (round(l["Z"] / 60), l["X"]))
        for i, l in enumerate(rest):
            t = cycle[i % len(cycle)]
            pool = OTHER[t]
            if all(n in used_names for n in pool):  # pool used up: next type with a free name
                t = next(k for k in cycle + list(OTHER) if any(n not in used_names for n in OTHER[k]))
                pool = OTHER[t]
            font, c1, c2 = brand(t, "other")
            out.append(dict(Lot=l["Id"], Poi=None, Type=t, Name=take_name(t, pool), Map=False, Existing=False,
                            Font=font, Primary=c1, Secondary=c2, Sign="Box", Road=l["Road"], District=district,
                            X=l["X"], Z=l["Z"]))

    out.sort(key=lambda b: b["Lot"])

    def rgb(c):
        return "{ %d, %d, %d }" % c

    def lua_str(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    lines = [
        "-- BusinessData: şehirdeki işletmeler (Şehir genişletme, aşama 2). ÜRETİLDİ: tools/plan_businesses.py",
        "-- Elle düzenlenebilir (isim, tür, renk, yazı tipi); aracı yeniden çalıştırmak elle yapılan değişiklikleri siler.",
        "-- Lot = MapData arsa kimliği (harita değişmez). Poi = mevcut önemli yer (varsa). Map = haritada / GPS'te görünür.",
        "-- Type: Businesses.Types'taki tür. Font: Enum.Font adı. Primary/Secondary: tabela/tente ve ayrıntı rengi.",
        "-- Sign: tabela biçimi (Box | Letters | Blade | Awning) — cephe aşamasında (3) kullanılacak.",
        "return {",
    ]
    for b in out:
        fields = [f"Lot = {b['Lot']}", f"Type = {lua_str(b['Type'])}", f"Name = {lua_str(b['Name'])}"]
        if b["Poi"]:
            fields.append(f"Poi = {lua_str(b['Poi'])}")
        fields += [f"Map = {'true' if b['Map'] else 'false'}", f"Font = {lua_str(b['Font'])}",
                   f"Primary = {rgb(b['Primary'])}", f"Secondary = {rgb(b['Secondary'])}", f"Sign = {lua_str(b['Sign'])}"]
        lines.append("\t{ " + ", ".join(fields) + " }, -- " + b["District"] + " / " + (b["Road"] or "?"))
    lines.append("}")
    open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    new = [b for b in out if b["Map"] and not b["Existing"]]
    print(f"wrote {OUT}: {len(out)} businesses ({len([b for b in out if b['Existing']])} existing, {len(new)} new on map, "
          f"{len([b for b in out if not b['Map']])} other shops)")
    for b in new:
        print(f"  {b['District']:10s} {b['Type']:12s} {b['Name']:22s} lot {b['Lot']} ({b['Road']})")


if __name__ == "__main__":
    main()
