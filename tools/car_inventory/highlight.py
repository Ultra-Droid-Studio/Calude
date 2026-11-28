"""car_inventory/highlight.py — renders the detected mirrors (cyan) and exhaust area (magenta). Usage: highlight.py <repo> <classes.json> <out.png>
Read-only: reads the model file, writes the given output only. Run with python3 -I."""
import json, sys
import numpy as np
from PIL import Image, ImageDraw
ROOT = sys.argv[1]
sys.path.insert(0, ROOT + "/tools")
import cosmo_cars_convert as C
cars = C.read_glb(ROOT + "/assets/cars/SOLARA_Cars.glb")
cls = json.load(open(sys.argv[2]))
W, H = 420, 260
sheet = Image.new("RGB", (W * 4, H * 6), (232, 235, 240))
d = ImageDraw.Draw(sheet)
for i, (car, parts) in enumerate(cars.items()):
    ex = [tuple(e[2:5]) for e in cls[car]["exhaust"]]
    mi = [tuple(e[2:5]) for e in cls[car]["mirror"]]
    out = []
    for name, T, N, rgb in parts:
        cen = T.mean(1)
        col = np.tile(np.array(rgb, float), (len(T), 1))
        for (x, y, z) in ex:
            m = (np.abs(cen[:, 0] - x) < 0.25) & (np.abs(cen[:, 1] - y) < 0.2) & (np.abs(cen[:, 2] - z) < 0.4)
            if "Detail" in name: col[m] = (255, 0, 255)
        for (x, y, z) in mi:
            m = (np.abs(cen[:, 0] - x) < 0.18) & (np.abs(cen[:, 1] - y) < 0.15) & (np.abs(cen[:, 2] - z) < 0.2)
            if "Detail" in name or "Paint" in name: col[m] = (0, 220, 255)
        for k in range(len(T)):
            out.append((name, T[k:k+1], N[k:k+1], tuple(int(c) for c in col[k])))
    a = C.render(out, (W, H), yaw=150, pitch=8, lit=False)
    b = C.render(out, (W, H), yaw=30, pitch=15, lit=False)
    x0, y0 = (i % 2) * 2 * W, (i // 2) * H
    sheet.paste(a, (x0, y0)); sheet.paste(b, (x0 + W, y0))
    d.text((x0 + 6, y0 + 4), f"{car}: magenta = exhaust (detected), cyan = mirrors", fill=(0, 0, 0))
sheet.save(sys.argv[3])
