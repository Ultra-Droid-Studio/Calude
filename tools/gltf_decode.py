"""gltf_decode.py — reads a .glb (also with EXT_meshopt_compression, KHR_mesh_quantization, EXT_texture_webp) into
plain numpy arrays. Used by the converters for the user's Kenney and Rocketbox models.

Needs: numpy, Pillow (with WebP), and for meshopt-compressed files the `meshoptimizer` Python package
(pip install meshoptimizer). Only data is read; nothing in the file is executed.

load(path) -> Gltf with:
  .json                    the glTF JSON
  .accessor(i)             numpy array (dequantised: normalized integers -> float)
  .image(i)                PIL image
  .node_world(i)           4x4 world matrix of node i
  .mesh_nodes()            [(node index, mesh index, world matrix)]
  .primitive(p)            dict: POSITION, NORMAL, TEXCOORD_0, JOINTS_0, WEIGHTS_0, indices (n,3), material
"""
import json
import struct

import numpy as np

COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


class Gltf:
    def __init__(self, path):
        data = open(path, "rb").read()
        magic, version, total = struct.unpack_from("<4sII", data, 0)
        if magic != b"glTF" or version != 2:
            raise ValueError("not a glTF 2.0 binary: " + path)
        pos, self.bin = 12, b""
        self.json = None
        while pos < min(total, len(data)):
            length, kind = struct.unpack_from("<I4s", data, pos)
            chunk = data[pos + 8:pos + 8 + length]
            if kind == b"JSON":
                self.json = json.loads(chunk)
            elif kind == b"BIN\x00":
                self.bin = chunk
            pos += 8 + length
        self._views = {}

    # -- buffers
    def _buffer(self, i):
        b = self.json["buffers"][i]
        if "uri" in b:
            raise ValueError("external buffers are not supported")
        return self.bin

    def view(self, i):
        if i in self._views:
            return self._views[i]
        bv = self.json["bufferViews"][i]
        ext = bv.get("extensions", {}).get("EXT_meshopt_compression")
        if ext:
            import meshoptimizer as mo
            src = self._buffer(ext["buffer"])[ext.get("byteOffset", 0):ext.get("byteOffset", 0) + ext["byteLength"]]
            count, stride, mode = ext["count"], ext["byteStride"], ext["mode"]
            if mode == "ATTRIBUTES":
                out = mo.decode_vertex_buffer(count, stride, src, dtype=np.dtype(("V", stride)))
                out = np.frombuffer(out.tobytes(), np.uint8).copy()
                flt = ext.get("filter", "NONE")
                if flt == "OCTAHEDRAL":
                    out = mo.decode_filter_oct(out, count, stride)
                elif flt == "QUATERNION":
                    out = mo.decode_filter_quat(out, count, stride)
                elif flt == "EXPONENTIAL":
                    out = mo.decode_filter_exp(out, count, stride)
            elif mode in ("TRIANGLES", "INDICES"):
                # decode to 32-bit indices (the output width is the caller's choice; the wrapper's array is uint32),
                # then store them at the view's own index width
                fn = mo.decode_index_buffer if mode == "TRIANGLES" else mo.decode_index_sequence
                idx = fn(count, 4, src)
                out = np.frombuffer(idx.astype("<u2" if stride == 2 else "<u4").tobytes(), np.uint8)
            else:
                raise ValueError("unknown meshopt mode " + mode)
            raw = out.tobytes()
        else:
            buf = self._buffer(bv["buffer"])
            raw = buf[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        self._views[i] = raw
        return raw

    def accessor(self, i):
        a = self.json["accessors"][i]
        dtype = np.dtype(COMPONENT[a["componentType"]]).newbyteorder("<")
        width = WIDTH[a["type"]]
        count = a["count"]
        if "bufferView" in a:
            bv = self.json["bufferViews"][a["bufferView"]]
            raw = self.view(a["bufferView"])
            stride = bv.get("byteStride") or bv.get("extensions", {}).get("EXT_meshopt_compression", {}).get("byteStride") \
                or dtype.itemsize * width
            if bv.get("extensions", {}).get("EXT_meshopt_compression", {}).get("mode") in ("TRIANGLES", "INDICES"):
                stride = dtype.itemsize * width
            off = a.get("byteOffset", 0)
            arr = np.ndarray((count, width), dtype, raw, off, (stride, dtype.itemsize)).copy()
        else:
            arr = np.zeros((count, width), dtype)
        if a.get("normalized"):
            if dtype.kind == "u":
                arr = arr.astype(np.float64) / np.iinfo(dtype).max
            else:
                arr = np.maximum(arr.astype(np.float64) / np.iinfo(dtype).max, -1.0)
        if "sparse" in a:
            raise ValueError("sparse accessors are not supported")
        return arr[:, 0] if width == 1 else arr

    # -- images
    def image(self, i):
        from io import BytesIO
        from PIL import Image
        im = self.json["images"][i]
        return Image.open(BytesIO(self.view(im["bufferView"]))).convert("RGBA")

    def texture_image(self, tex_index):
        t = self.json["textures"][tex_index]
        src = t.get("source")
        ext = t.get("extensions", {})
        for name in ("EXT_texture_webp", "KHR_texture_basisu", "MSFT_texture_dds"):
            if name in ext:
                src = ext[name]["source"]
        return self.image(src)

    # -- scene
    def node_local(self, i):
        n = self.json["nodes"][i]
        if "matrix" in n:
            return np.array(n["matrix"], float).reshape(4, 4).T
        t = np.array(n.get("translation", [0, 0, 0]), float)
        x, y, z, w = n.get("rotation", [0, 0, 0, 1])
        s = np.array(n.get("scale", [1, 1, 1]), float)
        R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        M = np.eye(4)
        M[:3, :3] = R @ np.diag(s)
        M[:3, 3] = t
        return M

    def parents(self):
        out = {}
        for i, n in enumerate(self.json["nodes"]):
            for c in n.get("children", []):
                out[c] = i
        return out

    def node_world(self, i):
        par = self.parents()
        M = self.node_local(i)
        p = par.get(i)
        while p is not None:
            M = self.node_local(p) @ M
            p = par.get(p)
        return M

    def mesh_nodes(self):
        return [(i, n["mesh"], self.node_world(i)) for i, n in enumerate(self.json["nodes"]) if "mesh" in n]

    def primitive(self, prim):
        out = {k: self.accessor(v) for k, v in prim["attributes"].items()}
        if "indices" in prim:
            out["indices"] = self.accessor(prim["indices"]).astype(np.int64).reshape(-1, 3)
        else:
            out["indices"] = np.arange(len(out["POSITION"])).reshape(-1, 3)
        out["material"] = prim.get("material")
        return out


def load(path):
    return Gltf(path)
