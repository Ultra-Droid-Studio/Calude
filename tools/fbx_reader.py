"""
fbx_reader.py — minimal reader for BINARY FBX 7.x files (no external dependencies).

Reads the node tree and extracts what the car-pack converter needs:
  meshes (Model + Geometry: vertices, polygons, per-polygon material index),
  materials (name, diffuse colour), model transforms (Lcl Translation/Rotation/Scaling),
  parent/child links (Connections), and GlobalSettings (UpAxis, UnitScaleFactor).
Only data is parsed; nothing in the file is executed.
"""
import struct
import zlib

HEADER = b"Kaydara FBX Binary  \x00"


class Node:
    __slots__ = ("name", "props", "children")

    def __init__(self, name, props, children):
        self.name, self.props, self.children = name, props, children

    def find(self, name):
        for c in self.children:
            if c.name == name:
                return c
        return None

    def find_all(self, name):
        return [c for c in self.children if c.name == name]


def _read_array(data, pos, fmt, size):
    length, encoding, comp_len = struct.unpack_from("<III", data, pos)
    pos += 12
    raw = data[pos:pos + comp_len]
    pos += comp_len
    if encoding == 1:
        raw = zlib.decompress(raw)
    values = list(struct.unpack("<%d%s" % (length, fmt), raw[:length * size]))
    return values, pos


def _read_prop(data, pos):
    t = chr(data[pos])
    pos += 1
    if t == "Y":
        return struct.unpack_from("<h", data, pos)[0], pos + 2
    if t == "C":
        return bool(data[pos]), pos + 1
    if t == "I":
        return struct.unpack_from("<i", data, pos)[0], pos + 4
    if t == "F":
        return struct.unpack_from("<f", data, pos)[0], pos + 4
    if t == "D":
        return struct.unpack_from("<d", data, pos)[0], pos + 8
    if t == "L":
        return struct.unpack_from("<q", data, pos)[0], pos + 8
    if t in "fdlib":
        fmt, size = {"f": ("f", 4), "d": ("d", 8), "l": ("q", 8), "i": ("i", 4), "b": ("?", 1)}[t]
        return _read_array(data, pos, fmt, size)
    if t in "SR":
        n = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        raw = data[pos:pos + n]
        return (raw.decode("utf-8", "replace") if t == "S" else raw), pos + n
    raise ValueError("unknown FBX property type %r at %d" % (t, pos - 1))


def _read_node(data, pos, wide):
    if wide:
        end, nprops, _plen = struct.unpack_from("<QQQ", data, pos)
        pos += 24
    else:
        end, nprops, _plen = struct.unpack_from("<III", data, pos)
        pos += 12
    name_len = data[pos]
    pos += 1
    if end == 0:
        return None, pos
    name = data[pos:pos + name_len].decode("ascii", "replace")
    pos += name_len
    props = []
    for _ in range(nprops):
        value, pos = _read_prop(data, pos)
        props.append(value)
    children = []
    sentinel = 25 if wide else 13
    while pos < end:
        if end - pos == sentinel and data[pos:end] == b"\x00" * sentinel:
            pos = end
            break
        child, pos = _read_node(data, pos, wide)
        if child is None:
            break
        children.append(child)
    return Node(name, props, children), end


def read(path):
    data = open(path, "rb").read()
    if not data.startswith(HEADER):
        raise ValueError("not a binary FBX: " + path)
    version = struct.unpack_from("<I", data, 23)[0]
    wide = version >= 7500
    pos = 27
    roots = []
    while pos < len(data):
        node, pos = _read_node(data, pos, wide)
        if node is None:
            break
        roots.append(node)
    return version, Node("root", [], roots)


def _props70(node):
    out = {}
    p70 = node.find("Properties70") if node else None
    if p70:
        for p in p70.find_all("P"):
            out[p.props[0]] = p.props[4:]
    return out


def scene(path):
    """Returns dict: version, up_axis, unit_scale, models{id: {...}}, materials{id: {...}}, parents{child: parent}"""
    version, root = read(path)
    gs = _props70(root.find("GlobalSettings"))
    objects = root.find("Objects")
    geoms, models, materials = {}, {}, {}
    for n in objects.children:
        oid, cls = n.props[0], n.props[1].split("\x00")[0]
        if n.name == "Geometry":
            verts = n.find("Vertices").props[0]
            idx = n.find("PolygonVertexIndex").props[0]
            polys, cur = [], []
            for i in idx:
                if i < 0:
                    cur.append(-i - 1)
                    polys.append(cur)
                    cur = []
                else:
                    cur.append(i)
            mat_layer = n.find("LayerElementMaterial")
            mats = None
            mapping = None
            if mat_layer:
                mats = mat_layer.find("Materials").props[0]
                mapping = mat_layer.find("MappingInformationType").props[0]
            geoms[oid] = dict(name=cls, verts=[tuple(verts[i:i + 3]) for i in range(0, len(verts), 3)],
                              polys=polys, mats=mats, mapping=mapping)
        elif n.name == "Model":
            p = _props70(n)
            models[oid] = dict(name=cls, kind=n.props[2],
                               t=tuple(p.get("Lcl Translation", (0, 0, 0))),
                               r=tuple(p.get("Lcl Rotation", (0, 0, 0))),
                               s=tuple(p.get("Lcl Scaling", (1, 1, 1))),
                               pre=tuple(p.get("PreRotation", (0, 0, 0))),
                               geometry=None, materials=[], children=[])
        elif n.name == "Material":
            p = _props70(n)
            color = p.get("DiffuseColor") or p.get("Diffuse") or (0.8, 0.8, 0.8)
            materials[oid] = dict(name=cls, color=tuple(color[:3]),
                                  opacity=(p.get("Opacity") or (1.0,))[0] if p.get("Opacity") else 1.0,
                                  transparency=(p.get("TransparencyFactor") or (0.0,))[0] if p.get("TransparencyFactor") else 0.0)
    parents = {}
    conns = root.find("Connections")
    for c in conns.find_all("C") if conns else []:
        kind, child, parent = c.props[0], c.props[1], c.props[2]
        if kind != "OO":
            continue
        if child in geoms and parent in models:
            models[parent]["geometry"] = geoms[child]
        elif child in materials and parent in models:
            models[parent]["materials"].append(materials[child])
        elif child in models:
            parents[child] = parent
            if parent in models:
                models[parent]["children"].append(child)
    return dict(version=version,
                up_axis=(gs.get("UpAxis") or (1,))[0], up_sign=(gs.get("UpAxisSign") or (1,))[0],
                front_axis=(gs.get("FrontAxis") or (2,))[0], front_sign=(gs.get("FrontAxisSign") or (1,))[0],
                unit_scale=(gs.get("UnitScaleFactor") or (1.0,))[0],
                models=models, parents=parents)
