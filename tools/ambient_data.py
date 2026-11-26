"""
ambient_data.py — loads the REAL MapData into Lua tables shaped like MapDefinitions.GetData(), for the
offline ambient (traffic + pedestrian) tests. Field indices are the documented line layout:
  E|id|a|b|kind|width|lanesF|lanesB|speed|name|flags|span0|span1
NOTE: the Sidewalk flag is read from the documented flags column (field 11), like MapDefinitions since Phase 6.
Before Phase 6 the game parser read field 12 (bug, fixed with the user's approval) and Sidewalk was always false.
Pass correct_sidewalks=False to reproduce that old data (used to check that no pedestrian spawns without sidewalks).
"""


def load(lua, path="src/ReplicatedStorage/Shared/MapData.lua", correct_sidewalks=True, businesses=True):
    lines = open(path, encoding="utf-8").read().split("\n")
    T = lua.table_from

    def P(x, y, z):
        return T({"X": x, "Y": y, "Z": z})

    nodes, node_list, edges, edge_list = {}, [], {}, []
    pois, props, districts, lots = [], [], [], []
    meta = None
    for l in lines:
        f = l.split("|")
        t = f[0]
        if t == "M":
            meta = dict(HalfSize=float(f[1]), RoadTop=float(f[2]), BlockTop=float(f[3]), Sidewalk=float(f[4]))
        elif t == "N":
            flags = f[5] if len(f) > 5 else ""
            n = dict(Id=int(f[1]), Position=P(float(f[2]), float(f[3]), float(f[4])), Signal="s" in flags,
                     Stop="t" in flags, Crosswalk="c" in flags, Elevated="f" in flags, Edges=[])
            nodes[n["Id"]] = n
            node_list.append(n)
        elif t == "E":
            flags = (f[10] if correct_sidewalks else (f[11] if len(f) > 11 else "")) if len(f) > 10 else ""
            e = dict(Id=int(f[1]), A=int(f[2]), B=int(f[3]), Kind=f[4], Width=float(f[5]),
                     LanesForward=int(float(f[6])), LanesBackward=int(float(f[7])), Speed=float(f[8]), Name=f[9],
                     Sidewalk="w" in flags, Bridge="b" in flags)
            edges[e["Id"]] = e
            edge_list.append(e)
        elif t == "P":
            pois.append(dict(Id=f[1], Type=f[2], Name=f[3], Entrance=P(float(f[6]), 0, float(f[7])), District=f[8]))
        elif t == "L":
            # L|id|district|style|use|cx|cz|w|d|rot|h|seed|poi|baseY  (MapDefinitions ile aynı alanlar)
            lots.append(dict(Id=int(f[1]), District=f[2], Style=f[3], Use=f[4], Center=P(float(f[5]), 0, float(f[6])),
                             Width=float(f[7]), Depth=float(f[8]), Rotation=float(f[9]), Height=float(f[10]),
                             Seed=float(f[11]), PoiId=(f[12] if len(f) > 12 and f[12] != "" else None),
                             BaseY=float(f[13]) if len(f) > 13 and f[13] != "" else 0.0))
        elif t == "X":
            props.append(dict(Kind=f[1], X=float(f[2]), Z=float(f[3]), Yaw=float(f[4]), Y=float(f[5])))
        elif t == "D":
            districts.append(dict(Id=f[1], Name=f[2], Type=f[3], MinX=float(f[4]), MinZ=float(f[5]),
                                  MaxX=float(f[6]), MaxZ=float(f[7]), DayDensity=float(f[8]), NightDensity=float(f[9])))
    for e in edge_list:
        nodes[e["A"]]["Edges"].append(e["Id"])
        nodes[e["B"]]["Edges"].append(e["Id"])
    lnodes = {}
    lnode_list = []
    for n in node_list:
        d = dict(n)
        d["Edges"] = T(n["Edges"])
        tbl = T(d)
        lnodes[n["Id"]] = tbl
        lnode_list.append(tbl)
    ledges = {}
    ledge_list = []
    for e in edge_list:
        tbl = T(e)
        ledges[e["Id"]] = tbl
        ledge_list.append(tbl)
    data = T({
        "Meta": T(meta), "Nodes": T(lnodes), "NodeList": T(lnode_list), "Edges": T(ledges), "EdgeList": T(ledge_list),
        "POIs": T([T(p) for p in pois]), "Props": T([T(p) for p in props]),
        "Districts": T([T(d) for d in districts]), "Lots": T([T(l) for l in lots]),
    })
    if businesses:
        # Same as the game (MapDefinitions.parse): business registry on lots, new businesses as POIs
        apply_businesses(lua, data)
    return data, dict(nodes=nodes, edges=edges, meta=meta, pois=pois, props=props, districts=districts, lots=lots)


def apply_businesses(lua, data, root="src/ReplicatedStorage/Shared"):
    """Runs the REAL Businesses.Apply (City expansion stage 2) on the loaded data. Returns the Businesses module."""
    biz_data = lua.execute(open(root + "/BusinessData.lua", encoding="utf-8").read())
    biz = lua.execute(open(root + "/Businesses.lua", encoding="utf-8").read())
    biz._Data = biz_data
    vec = lua.eval("function(x, y, z) return { X = x, Y = y, Z = z } end")
    biz.Apply(data, vec)
    return biz
