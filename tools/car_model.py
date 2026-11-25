#!/usr/bin/env python3
"""
car_model.py — offline mirror of ReplicatedStorage/Shared/VehiclePhysics.lua.
Prints the derived tuning values per car and PREDICTED (not measured) performance
from a simple 1-D longitudinal simulation. Used for docs/SOLARA_Phase2_CarPhysics.md.
Keep the formulas identical to the Lua module.
"""
import math, json, sys

C = dict(EffectiveGravity=42.0, MetersPerStud=0.28, RollingResistance=0.012, MinSlipSpeed=1.5,
         AbsSlip=0.10, BumpFraction=0.6, GearSpread=0.7, BallastFraction=0.35, ComHeight=1.0)

import re

def load_cars(path):
    """Parses src/ReplicatedStorage/Shared/VehicleDefinitions.lua (cars with a Physics table)."""
    text = open(path, encoding="utf-8").read()
    const = re.search(r"VehicleDefinitions\.CarPhysics = \{(.*?)\n\}", text, re.S).group(1)
    for k, v in re.findall(r"(\w+) = ([\d.]+)", const):
        if k in C or k in ("EffectiveGravity",):
            C[k] = float(v)
    cars = {}
    for m in re.finditer(r"\n\t(\w+) = \{\n(.*?)\n\t\},", text, re.S):
        cid, body = m.group(1), m.group(2)
        if "Physics = {" not in body:
            continue
        def num(key, src=body):
            return float(re.search(key + r" = ([\d.]+)", src).group(1))
        phys = re.search(r"Physics = \{(.*?)\n\t\t\}", body, re.S).group(1)
        P = {k: float(v) for k, v in re.findall(r"(\w+) = (-?[\d.]+)", phys)}
        drive = re.search(r'Drive = "(\w+)"', body).group(1)
        P["Drive"] = drive
        P["Gears"] = int(P["Gears"])
        cars[cid] = dict(Wheelbase=num("Wheelbase"), Track=num("Track"), MaxSpeed=num("MaxSpeed"),
                         Travel=num("Travel"), Clearance=num("Clearance"), Mass=num(r"\bMass"),
                         DisplayName=re.search(r'DisplayName = "([^"]+)"', body).group(1), Physics=P)
    return cars

CARS = load_cars(sys.argv[1]) if len(sys.argv) > 1 else None

def power_factor(r):
    r = min(max(r, 0.25), 1.0)
    return 0.55 + 0.9 * r - 0.45 * r * r

def derive(d):
    p = d["Physics"]; g = C["EffectiveGravity"]; mps = C["MetersPerStud"]
    wf = p["WeightFront"]; hz = d["Wheelbase"] / 2
    out = {}
    for axle, hzk, frac in (("F", "SpringHzFront", wf / 2), ("R", "SpringHzRear", (1 - wf) / 2)):
        w = 2 * math.pi * p[hzk]
        out["Sag" + axle] = g / (w * w)
        out["KperM" + axle] = frac * w * w
        out["CperM" + axle] = 2 * p["Damping"] * frac * w
    com_z = hz * (1 - 2 * wf)
    out["BallastZ"] = max(-hz * 0.95, min(hz * 0.95, com_z / C["BallastFraction"]))
    out["Ps"] = p["PowerKW"] * 1000 / p["MassKg"] / (mps * mps)
    vt = d["MaxSpeed"] * p.get("TopSpeedSlack", 1.03)
    rr = C["RollingResistance"] * g
    out["DragK"] = max((out["Ps"] / vt - rr) / (vt * vt), 0)
    out["LaunchA"] = p["LaunchG"] * g
    out["BrakeA"] = p["BrakeG"] * g
    out["GearTops"] = [vt * ((i + 1) / p["Gears"]) ** C["GearSpread"] for i in range(p["Gears"])]
    out["LatLimit"] = p["TireGrip"] * g * p["LatLimitScale"]
    out["Rr"] = rr; out["Vt"] = vt
    return out

def drive_accel(d, D, v, gear):
    top = D["GearTops"][gear - 1]
    pf = power_factor(v / top)
    return min(D["LaunchA"], D["Ps"] * pf / max(v, 1.0))

def kmh(v): return v * 0.28 * 3.6

def simulate(d, D):
    p = d["Physics"]; g = C["EffectiveGravity"]
    dt = 1 / 240; t = 0; v = 0; x = 0; gear = 1; shift = 0; thr = 0
    marks = {}
    wf = p["WeightFront"]; L = d["Wheelbase"]; h = C["ComHeight"]
    while t < 40 and v < d["MaxSpeed"] * 0.995:
        thr = min(1, thr + p["ThrottleRise"] * dt)
        if shift > 0:
            shift -= dt; f = 0.2
        else:
            f = 1
        a_drive = drive_accel(d, D, v, gear) * thr * f
        # traction limit of driven axle including longitudinal weight transfer
        transfer = a_drive * h / L / g
        if p["Drive"] == "FWD": load = wf - transfer
        elif p["Drive"] == "RWD": load = (1 - wf) + transfer
        else: load = 1.0
        a_drive = min(a_drive, p["TireGrip"] * g * load * (1 + p["TractionSlip"]))
        a = a_drive - D["DragK"] * v * v - D["Rr"]
        v = max(v + a * dt, 0); x += v * dt; t += dt
        if gear < p["Gears"] and v >= D["GearTops"][gear - 1] * 0.97:
            gear += 1; shift = p["ShiftTime"]
        for k in (60, 100, 140):
            if k not in marks and kmh(v) >= k: marks[k] = round(t, 1)
    # braking 100 (or max) -> 0 with ABS at grip limit
    v0 = min(100 / 1.008, d["MaxSpeed"])
    a_b = min(D["BrakeA"], p["TireGrip"] * g * 0.95)
    dist = v0 * v0 / (2 * (a_b + D["Rr"]))
    return marks, round(kmh(d["MaxSpeed"])), round(kmh(v0)), round(dist, 1), round(dist * 0.28, 1)

if __name__ == "__main__":
    for cid, d in CARS.items():
        D = derive(d); p = d["Physics"]
        marks, top, v0, dist, dist_m = simulate(d, D)
        lat_g = D["LatLimit"] / C["EffectiveGravity"] * C["EffectiveGravity"] / (9.81 / 0.28)
        steer_hi = math.degrees(math.atan(d["Wheelbase"] * D["LatLimit"] / (d["MaxSpeed"] ** 2)))
        print(f"{cid:16s} Ps={D['Ps']:7.0f} drag={D['DragK']:.2e} sagF={D['SagF']:.2f} sagR={D['SagR']:.2f} "
              f"ballastZ={D['BallastZ']:+.2f} 0-60={marks.get(60)} 0-100={marks.get(100)} 0-140={marks.get(140)} "
              f"top={top} brake{v0}->0={dist}st/{dist_m}m latG(real)={lat_g:.2f} steer@top={steer_hi:.1f}deg "
              f"gears={[round(kmh(x)) for x in D['GearTops']]}")
