#!/usr/bin/env python3
"""
build_place.py — sync the Luau sources in src/ into a Roblox .rbxlx place file.

    python3 tools/build_place.py place/SOLARA_Phase3.rbxlx src place/OUT.rbxlx [--patches tools/place_patches.json]

Mapping (Explorer path == directory path):
    src/<Service>/<Folder>/.../Name.lua         -> ModuleScript "Name"
    src/<Service>/<Folder>/.../Name.server.lua  -> Script "Name"
    src/<Service>/<Folder>/.../Name.client.lua  -> LocalScript "Name"
    directories                                 -> Folder (created if missing)

Rules:
    * Existing scripts: only their Source is replaced. All other properties are kept.
    * Missing scripts/folders are inserted under their parent (the parent service must exist).
    * Scripts that exist in the place but not in src/ are NEVER deleted (a warning is printed).
    * Property patches (JSON) set simple bool/string/number properties on existing instances.
    * The output is re-parsed as XML and every script is re-extracted and compared with src/.
"""
import hashlib
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

TOKEN = re.compile(
    r'<!\[CDATA\['
    r'|<Item class="(?P<cls>[^"]+)" referent="(?P<ref>[^"]+)">'
    r'|</Item>'
    r'|<string name="Name">(?P<name>[^<]*)</string>'
    r'|<ProtectedString name="Source">'
    r'|</ProtectedString>'
    r'|</Properties>'
)

EXT_CLASS = [(".server.lua", "Script"), (".client.lua", "LocalScript"), (".lua", "ModuleScript")]
SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}


def xml_unescape(s):
    return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&apos;", "'").replace("&amp;", "&")


def xml_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


class Node:
    def __init__(self, cls, ref, parent):
        self.cls, self.ref, self.parent = cls, ref, parent
        self.name = None
        self.children = []
        self.open_end = None
        self.props_end = None  # index of '</Properties>'
        self.close_start = None
        self.src_start = None
        self.src_end = None

    def path(self):
        parts, n = [], self
        while n is not None:
            parts.append(n.name)
            n = n.parent
        return "/".join(reversed(parts))


def scan(text):
    roots, stack, pos = [], [], 0
    pending_src = None
    while True:
        m = TOKEN.search(text, pos)
        if not m:
            break
        tok = m.group(0)
        if tok == "<![CDATA[":
            end = text.find("]]>", m.end())
            if end < 0:
                raise ValueError("unterminated CDATA")
            pos = end + 3
            continue
        if m.group("cls"):
            node = Node(m.group("cls"), m.group("ref"), stack[-1] if stack else None)
            node.open_end = m.end()
            (stack[-1].children if stack else roots).append(node)
            stack.append(node)
        elif tok == "</Item>":
            stack[-1].close_start = m.start()
            stack.pop()
        elif m.group("name") is not None:
            if stack and stack[-1].name is None and stack[-1].props_end is None:
                stack[-1].name = xml_unescape(m.group("name"))
        elif tok == '<ProtectedString name="Source">':
            pending_src = m.end()
        elif tok == "</ProtectedString>":
            if pending_src is not None and stack and stack[-1].props_end is None:
                stack[-1].src_start, stack[-1].src_end = pending_src, m.start()
            pending_src = None
        elif tok == "</Properties>":
            if stack and stack[-1].props_end is None:
                stack[-1].props_end = m.start()
        pos = m.end()
    if stack:
        raise ValueError("unbalanced <Item>")
    return roots


def source_of(text, node):
    raw = text[node.src_start:node.src_end]
    out, pos = [], 0
    while True:
        a = raw.find("<![CDATA[", pos)
        if a < 0:
            out.append(xml_unescape(raw[pos:]))
            break
        out.append(xml_unescape(raw[pos:a]))
        b = raw.find("]]>", a + 9)
        out.append(raw[a + 9:b])
        pos = b + 3
    return "".join(out)


def index(roots):
    idx = {}

    def walk(n):
        idx[n.path()] = n
        for c in n.children:
            walk(c)

    for r in roots:
        walk(r)
    return idx


def read_src(src_dir):
    """returns {explorer_path: (class, source)} and set of folder paths"""
    scripts, folders = {}, set()
    for dirpath, _dirnames, filenames in os.walk(src_dir):
        rel = os.path.relpath(dirpath, src_dir)
        if rel != ".":
            folders.add(rel.replace(os.sep, "/"))
        for fn in sorted(filenames):
            for ext, cls in EXT_CLASS:
                if fn.endswith(ext):
                    name = fn[: -len(ext)]
                    p = (rel.replace(os.sep, "/") + "/" if rel != "." else "") + name
                    with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                        scripts[p] = (cls, f.read())
                    break
    return scripts, folders


def new_ref(path, used):
    h = hashlib.sha1(path.encode()).hexdigest().upper()
    for i in range(0, 32):
        ref = "RBX" + h[i:i + 8] + "N"
        if ref not in used:
            used.add(ref)
            return ref
    raise RuntimeError("referent collision")


def item_xml(cls, name, ref, source=None, children_xml=""):
    props = '<string name="Name">%s</string>\n' % xml_escape(name)
    if source is not None:
        props += '\n<ProtectedString name="Source">%s</ProtectedString>\n' % cdata(source)
    return '<Item class="%s" referent="%s"><Properties>\n%s</Properties>\n%s</Item>\n' % (cls, ref, props, children_xml)


def build(base_path, src_dir, out_path, patches_path=None):
    with open(base_path, encoding="utf-8") as f:
        text = f.read()
    roots = scan(text)
    idx = index(roots)
    used = set(re.findall(r'referent="([^"]+)"', text))
    scripts, folders = read_src(src_dir)
    edits = []  # (start, end, replacement)
    report = {"changed": [], "unchanged": [], "created": [], "warnings": []}

    # 1) existing scripts
    for path, (cls, src) in sorted(scripts.items()):
        node = idx.get(path)
        if node is None:
            continue
        if node.cls != cls:
            raise SystemExit("class mismatch for %s: place=%s src=%s" % (path, node.cls, cls))
        if node.src_start is None:
            raise SystemExit("script without Source property: %s" % path)
        if source_of(text, node) == src:
            report["unchanged"].append(path)
        else:
            edits.append((node.src_start, node.src_end, cdata(src)))
            report["changed"].append(path)

    # 2) new scripts and folders, grouped under the deepest existing ancestor
    missing_scripts = {p: v for p, v in scripts.items() if p not in idx}
    missing_folders = {p for p in folders if p not in idx and p not in scripts}

    def build_subtree(path):
        """xml for a missing folder or script at `path` including its missing descendants"""
        prefix = path + "/"
        children = sorted({p[len(prefix):].split("/")[0] for p in list(missing_scripts) + list(missing_folders) if p.startswith(prefix)})
        child_xml = "".join(build_subtree(prefix + c) for c in children)
        name = path.split("/")[-1]
        if path in missing_scripts:
            cls, src = missing_scripts[path]
            report["created"].append("%s (%s)" % (path, cls))
            return item_xml(cls, name, new_ref(path, used), src, child_xml)
        report["created"].append("%s (Folder)" % path)
        return item_xml("Folder", name, new_ref(path, used), None, child_xml)

    tops = set()
    for p in list(missing_scripts) + list(missing_folders):
        parts = p.split("/")
        for i in range(1, len(parts) + 1):
            sub = "/".join(parts[:i])
            if sub not in idx:
                parent = "/".join(parts[: i - 1])
                if parent not in idx:
                    raise SystemExit("parent service/instance missing for %s" % p)
                tops.add(sub)
                break
    for top in sorted(tops):
        parent = idx["/".join(top.split("/")[:-1])]
        edits.append((parent.close_start, parent.close_start, build_subtree(top)))

    # 3) scripts in the place that are not in src
    for path, node in idx.items():
        if node.cls in SCRIPT_CLASSES and path not in scripts:
            report["warnings"].append("kept (not in src): " + path)

    # 4) property patches
    if patches_path:
        with open(patches_path, encoding="utf-8") as f:
            patches = json.load(f)
        for p in patches:
            node = idx.get(p["path"])
            if node is None:
                raise SystemExit("patch target missing: " + p["path"])
            tag, prop, value = p["type"], p["property"], str(p["value"])
            region_start, region_end = node.open_end, node.props_end
            region = text[region_start:region_end]
            m = re.search(r'<%s name="%s">[^<]*</%s>' % (tag, re.escape(prop), tag), region)
            new = '<%s name="%s">%s</%s>' % (tag, prop, xml_escape(value), tag)
            if m:
                if m.group(0) != new:
                    edits.append((region_start + m.start(), region_start + m.end(), new))
            else:
                edits.append((region_end, region_end, new + "\n"))
            report["changed"].append("%s.%s = %s" % (p["path"], prop, value))

    # apply edits back to front
    edits.sort(key=lambda e: (e[0], e[1]), reverse=True)
    out = text
    for start, end, rep in edits:
        out = out[:start] + rep + out[end:]

    # verification
    ET.fromstring(out.encode("utf-8"))  # well-formed
    vroots = scan(out)
    vidx = index(vroots)
    for path, (cls, src) in scripts.items():
        node = vidx.get(path)
        if node is None or node.cls != cls or source_of(out, node) != src:
            raise SystemExit("verification failed for " + path)

    with open(out_path, "w", encoding="utf-8", newline="") as f:
        f.write(out)
    return report


if __name__ == "__main__":
    args = sys.argv[1:]
    patches = None
    if "--patches" in args:
        i = args.index("--patches")
        patches = args[i + 1]
        del args[i:i + 2]
    if len(args) != 3:
        print(__doc__)
        sys.exit(2)
    rep = build(args[0], args[1], args[2], patches)
    for k in ("changed", "created", "warnings"):
        for line in rep[k]:
            print("%-9s %s" % (k.upper(), line))
    print("unchanged scripts: %d" % len(rep["unchanged"]))
    print("OK ->", args[2])
