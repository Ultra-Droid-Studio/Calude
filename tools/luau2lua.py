"""luau2lua.py — minimal Luau -> Lua 5.4 conversion for running world-gen modules offline with lupa.

Handles what the WorldGen modules use: type declarations (also multi-line), type annotations on parameters, locals
and return values (nested table types too), '::' casts, compound assignment (+= -= *= /=), generalized iteration
(`for k, v in t do` -> pairs), if-expressions (-> immediately invoked functions). `continue` is NOT supported
(cut functions that use it before converting). Not a general Luau compiler: verify the output loads.
"""
import re


def _strip_params(params):
    out, depth, cur = [], 0, ""
    for ch in params:
        if ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    names = []
    for p in out:
        p = p.strip()
        names.append(p.split(":")[0].strip() if ":" in p else p)
    return ", ".join(names)


def _function_line(line):
    m = re.search(r"\bfunction\b[^(]*\(", line)
    if not m:
        return line
    start = m.end()
    depth, j = 1, start
    while j < len(line) and depth:
        if line[j] in "({[":
            depth += 1
        elif line[j] in ")}]":
            depth -= 1
        j += 1
    if depth:
        return line  # multi-line parameter list: leave (not used by WorldGen)
    params = line[start:j - 1]
    rest = line[j:]
    rest = re.sub(r"^\s*:\s*[^=]*$", "", rest)  # return type to end of line
    return line[:start] + _strip_params(params) + ")" + rest


def _local_type(line):
    # local name: Type = value   /   local name: Type
    m = re.match(r"^(\s*local\s+)(\w+)\s*:\s*(.+)$", line)
    if not m or "function" in line:
        return line
    rest = m.group(3)
    depth = 0
    for i, ch in enumerate(rest):
        if ch in "({[<":
            depth += 1
        elif ch in ")}]>":
            depth -= 1
        elif ch == "=" and depth == 0:
            return m.group(1) + m.group(2) + " " + rest[i:]
    return m.group(1) + m.group(2)


def _if_expressions(t):
    i, res = 0, []
    while True:
        m = re.search(r"(=\s*|\(\s*|,\s*|return\s+|\{\s*)if ", t[i:])
        if not m:
            res.append(t[i:])
            break
        start = i + m.end() - 3
        res.append(t[i:start])
        j, depth = start, 0
        while j < len(t):
            c = t[j]
            if c in "([{":
                depth += 1
            elif c in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif c == "," and depth == 0:
                break
            elif c == "\n":
                break
            j += 1
        expr = t[start:j].strip()
        parts = re.split(r"\b(then|elseif|else)\b", expr[3:])
        body = "if " + parts[0].strip() + " then return " + parts[2].strip()
        k = 3
        while k < len(parts):
            if parts[k] == "elseif":
                body += " elseif " + parts[k + 1].strip() + " then return " + parts[k + 3].strip()
                k += 4
            else:
                body += " else return " + parts[k + 1].strip()
                k += 2
        res.append("(function() " + body + " end end)()")
        i = j
    return "".join(res)


def convert(src):
    lines, out, skipping, depth = src.split("\n"), [], False, 0
    for line in lines:
        if skipping:
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                skipping = False
            continue
        if re.match(r"\s*(export\s+)?type \w+", line):
            depth = line.count("{") - line.count("}")
            skipping = depth > 0
            continue
        line = re.sub(r"\s*::\s*[\w\.\?]+(\s*\{[^}]*\})?", "", line)
        line = _function_line(line)
        line = _local_type(line)
        m = re.match(r"^(\s*)([\w\.\[\]\"]+)\s*([+\-*/])=\s*(.+)$", line)
        if m:
            line = f"{m.group(1)}{m.group(2)} = {m.group(2)} {m.group(3)} ({m.group(4)})"
        m = re.match(r"(\s*for [\w, ]+ in )(\{[^}]*\}|[\w\.\[\]:]+(\(\))?)( do.*)$", line)
        if m and not m.group(2).startswith(("pairs", "ipairs")):
            line = m.group(1) + "pairs(" + m.group(2) + ")" + m.group(4)
        out.append(line)
    return _if_expressions("\n".join(out))
