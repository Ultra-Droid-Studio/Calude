"""car_inventory/cutaway.py — side view + roof/glass removed views of every car. Usage: cutaway.py <repo> <inventory.json> <out.png>
Read-only: reads the model file, writes the given output only. Run with python3 -I."""
import json, sys
import numpy as np
from PIL import Image, ImageDraw
ROOT = sys.argv[1]
sys.path.insert(0, ROOT + "/tools")
import cosmo_cars_convert as C
cars = C.read_glb(ROOT + "/assets/cars/SOLARA_Cars.glb")
inv = json.load(open(sys.argv[2]))
W, H = 560, 300
sheet = Image.new("RGB", (W * 3, H * 12), (232, 235, 240))
d = ImageDraw.Draw(sheet)
for i, (car, parts) in enumerate(cars.items()):
    o = inv[car]
    ylo = o["cabin_box"]["y"][0]
    cut = []
    for name, T, N, rgb in parts:
        role = name.split("_", 1)[1].rsplit("_", 1)[0]
        if role == "Glass":
            continue
        keep = T.mean(1)[:, 1] < ylo + 0.05  # everything above the window line removed
        if keep.any():
            cut.append((name, T[keep], N[keep], rgb))
    a = C.render(parts, (W, H), yaw=90, pitch=5, lit=False)  # side view
    b = C.render(cut, (W, H), yaw=40, pitch=55, lit=False)    # roof + glass removed
    c = C.render(cut, (W, H), yaw=0, pitch=88, lit=False)     # top-down, cut
    for k, im in enumerate((a, b, c)):
        sheet.paste(im, (k * W, i * H))
    d.text((6, i * H + 4), f"{car}: side | roof+glass removed | top-down cut", fill=(0, 0, 0))
sheet.save(sys.argv[3])
