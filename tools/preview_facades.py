"""preview_facades.py — schematic front elevations (day and night) of sample buildings from the recorded parts of
tools/test_city_facades.py. NOT a Roblox render: flat colours, orthographic front view, DejaVu font instead of the
brand fonts. Purpose: see sign styles, shop bands, deco/brick details and which parts light up at night.
"""
import math

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SMALL = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
PANEL_W, PANEL_H = 420, 330


def _local(part, lot):
    th = math.radians(lot.Rotation)
    c, s = math.cos(th), math.sin(th)
    bx, by, bz = lot.Center.X, (lot.BaseY or 0), lot.Center.Z
    sx, sy, sz = (v / 2 for v in part["Size"])
    R, P = part["R"], part["P"]
    xs, ys, zs = [], [], []
    for dx in (-sx, sx):
        for dy in (-sy, sy):
            for dz in (-sz, sz):
                wx = P[0] + R[0] * dx + R[1] * dy + R[2] * dz
                wy = P[1] + R[3] * dx + R[4] * dy + R[5] * dz
                wz = P[2] + R[6] * dx + R[7] * dy + R[8] * dz
                ox, oz = wx - bx, wz - bz
                xs.append(c * ox - s * oz)
                zs.append(s * ox + c * oz)
                ys.append(wy - by)
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _pick(new_parts, lots):
    """Sample lots: one per sign style, Centro shop band, deco with neon fin, brick with tank, a billboard."""
    want = []

    def first(pred):
        for lid in sorted(new_parts):
            lot = lots[lid]
            if lid not in [w[0] for w in want] and pred(lot, new_parts[lid]):
                return lid
        return None

    def biz(lot, sign=None, district=None, unit=None):
        b = lot.Business
        return b is not None and (sign is None or b.Sign == sign) and (district is None or lot.District == district) \
            and (unit is None or b.Unit == unit)

    rules = [
        ("Kutu tabela (Box)", lambda l, p: biz(l, "Box", "riverside") and l.Style == "storefront_plain"),
        ("Bayrak tabela (Blade)", lambda l, p: biz(l, "Blade", "riverside")),
        ("Çizgili tente (Awning)", lambda l, p: biz(l, "Awning", "riverside")),
        ("Harf tabela (Letters)", lambda l, p: biz(l, "Letters", "costa")),
        ("Art deco + neon kanat", lambda l, p: l.Style == "deco_lowrise" and l.District == "costa"
         and any(q["Name"] == "NeonFin" for q in p) and l.Width >= 30),
        ("Centro zemin kat dükkânı", lambda l, p: biz(l, None, "centro", "Ground") and l.Business.Map and l.Width >= 40),
        ("Tuğla apartman (klima, su deposu)", lambda l, p: l.Style == "apartment_brick" and l.District == "riverside"
         and any(q["Name"] == "Tank" for q in p)),
        ("Reklam panosu", lambda l, p: any(q["Name"] == "Billboard" for q in p)),
    ]
    for title, pred in rules:
        lid = first(pred)
        if lid is not None:
            want.append((lid, title))
    return want


def _draw_building(img, ox, oy, parts, lot, night, title):
    d = ImageDraw.Draw(img)
    sky = (14, 18, 34) if night else (176, 214, 236)
    d.rectangle([ox, oy, ox + PANEL_W - 1, oy + PANEL_H - 1], fill=sky)
    boxes = [(p, _local(p, lot)) for p in parts]
    # front view: only the front half of the building matters
    x0 = min(b[0] for _, b in boxes)
    x1 = max(b[1] for _, b in boxes)
    y1 = max(b[3] for _, b in boxes)
    margin = 18
    scale = min((PANEL_W - 2 * margin) / max(x1 - x0, 1), (PANEL_H - 2 * margin - 34) / max(y1, 1))
    ground = oy + PANEL_H - margin - 10

    def X(v):
        return ox + PANEL_W / 2 + (v - (x0 + x1) / 2) * scale

    def Y(v):
        return ground - v * scale

    d.rectangle([ox, ground, ox + PANEL_W - 1, oy + PANEL_H - 1], fill=(60, 62, 66) if not night else (24, 25, 28))
    glow_layer = Image.new("RGB", img.size, (0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    labels = []
    for p, b in sorted(boxes, key=lambda pb: -pb[1][4]):  # far first
        col = p["Color"]
        glowing = night and ("NightGlow" in p["Tags"] or "ShopWindow" in p["Tags"])
        if p["Material"] == "Material.Glass":
            col = _mix(col, (40, 52, 64), 0.45)
        if p["Transparency"] >= 0.99 and not p["Labels"]:
            continue
        if night:
            if glowing:
                col = p["Attr"].get("NightColor", col)
            elif p["Material"] == "Material.Neon":
                pass
            else:
                col = _mix(col, (10, 12, 24), 0.78)
        rect = [X(b[0]), Y(b[3]), X(b[1]), Y(b[2])]
        if rect[2] - rect[0] < 1:
            rect[2] = rect[0] + 1
        if p["Transparency"] < 0.99:
            d.rectangle(rect, fill=col)
            if glowing or (night and p["Material"] == "Material.Neon"):
                gd.rectangle(rect, fill=col)
        for lab in p["Labels"]:
            if lab["Face"].endswith("Front"):
                labels.append((rect, lab, night and "NightText" in p["Tags"], p["Attr"].get("NightTextColor")))
    if night:
        halo = glow_layer.filter(ImageFilter.GaussianBlur(8))
        img.paste(ImageChops.screen(img, halo))  # light spill around lit signs / windows
        d = ImageDraw.Draw(img)
    for rect, lab, lit, night_text in labels:
        h = max(rect[3] - rect[1], 6)
        size = max(int(h * 0.62), 7)
        f = ImageFont.truetype(FONT, size)
        text = lab["Text"]
        while f.getlength(text) > (rect[2] - rect[0]) * 0.94 and size > 6:
            size -= 1
            f = ImageFont.truetype(FONT, size)
        col = lab["Color"] if (lit or not night) else _mix(lab["Color"], (10, 12, 24), 0.7)
        if night and lit and night_text:
            col = night_text
        d.text(((rect[0] + rect[2]) / 2, (rect[1] + rect[3]) / 2), text, font=f, fill=col, anchor="mm")
    tf = ImageFont.truetype(SMALL, 13)
    d.rectangle([ox, oy, ox + PANEL_W - 1, oy + 24], fill=(16, 18, 24))
    d.text((ox + 8, oy + 5), title, font=tf, fill=(235, 235, 240))


def render(new_parts, lots, path):
    picks = _pick(new_parts, lots)
    cols = 4
    rows_per = math.ceil(len(picks) / cols)
    img = Image.new("RGB", (cols * PANEL_W, rows_per * 2 * PANEL_H + 40), (10, 11, 14))
    d = ImageDraw.Draw(img)
    hf = ImageFont.truetype(FONT, 18)
    d.text((10, 10), "Aşama 3 cepheleri — şematik ön görünüş (üst: gündüz, alt: gece). Roblox görüntüsü değildir.",
           font=hf, fill=(240, 240, 240))
    for i, (lid, title) in enumerate(picks):
        lot = lots[lid]
        name = lot.Business.Name if lot.Business is not None else ""
        label = f"{title} · {name}" if name else title
        cx = (i % cols) * PANEL_W
        r = i // cols
        _draw_building(img, cx, 40 + r * 2 * PANEL_H, new_parts[lid], lot, False, label + " · gündüz")
        _draw_building(img, cx, 40 + r * 2 * PANEL_H + PANEL_H, new_parts[lid], lot, True, label + " · gece")
    img.save(path)
    print("wrote", path, img.size, "samples:", [t for _, t in picks])
