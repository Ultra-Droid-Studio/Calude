#!/usr/bin/env python3
"""roblox_upload_asset.py — uploads a 3D model (.glb / .fbx) to Roblox as a Model asset with Open Cloud (no Studio),
waits for processing and prints the asset id. With --set <Key> it also writes the id into
src/ServerScriptService/WorldGen/AssetIds.lua, so the next built place loads the model at runtime
(InsertService:LoadAsset on the server).

API key: read from the ROBLOX_API_KEY environment variable (never from the command line). Create it at
https://create.roblox.com/dashboard/credentials with the "Assets API" (asset:read + asset:write). The creator
(--user-id or --group-id) must be the SAME account/group that owns the game, otherwise LoadAsset refuses the model.

Usage:
  export ROBLOX_API_KEY=...            # Windows PowerShell:  $env:ROBLOX_API_KEY="..."
  python3 tools/roblox_upload_asset.py assets/streetlights/StreetLights.glb --user-id 123456 \
      --name "SOLARA Street Lights" --set StreetLights
Only the Python standard library is used.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

API = "https://apis.roblox.com/assets/v1"
CONTENT_TYPES = {".glb": "model/gltf-binary", ".gltf": "model/gltf+json", ".fbx": "model/fbx"}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_IDS = os.path.join(ROOT, "src", "ServerScriptService", "WorldGen", "AssetIds.lua")


def call(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} from {url}: {e.read().decode(errors='replace')[:500]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    who = ap.add_mutually_exclusive_group(required=True)
    who.add_argument("--user-id")
    who.add_argument("--group-id")
    ap.add_argument("--name", required=True)
    ap.add_argument("--description", default="SOLARA 3D model")
    ap.add_argument("--set", help="AssetIds.lua key to write the new id into (e.g. StreetLights)")
    args = ap.parse_args()

    key = os.environ.get("ROBLOX_API_KEY")
    if not key:
        raise SystemExit("ROBLOX_API_KEY is not set")
    ext = os.path.splitext(args.file)[1].lower()
    if ext not in CONTENT_TYPES:
        raise SystemExit("unsupported file type " + ext)
    creator = {"userId": str(args.user_id)} if args.user_id else {"groupId": str(args.group_id)}
    request = {"assetType": "Model", "displayName": args.name[:50], "description": args.description[:1000],
               "creationContext": {"creator": creator}}
    data = open(args.file, "rb").read()
    boundary = "----solara" + uuid.uuid4().hex
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n".encode() + json.dumps(request).encode() + b"\r\n",
        (f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{os.path.basename(args.file)}\"\r\n"
         f"Content-Type: {CONTENT_TYPES[ext]}\r\n\r\n").encode() + data + b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    op = call("POST", f"{API}/assets", key, b"".join(parts), f"multipart/form-data; boundary={boundary}")
    op_id = op.get("operationId") or op.get("path", "").split("/")[-1]
    print("uploaded, processing… operation", op_id)
    for _ in range(60):
        if op.get("done"):
            break
        time.sleep(3)
        op = call("GET", f"{API}/operations/{op_id}", key)
    if not op.get("done"):
        raise SystemExit("still processing after 3 minutes; check later: GET " + f"{API}/operations/{op_id}")
    if "error" in op:
        raise SystemExit("upload failed: " + json.dumps(op["error"]))
    asset_id = op.get("response", {}).get("assetId")
    print("asset id:", asset_id)
    if args.set and asset_id:
        src = open(ASSET_IDS, encoding="utf-8").read()
        new, n = re.subn(rf"(\b{re.escape(args.set)} = )\d+", rf"\g<1>{int(asset_id)}", src)
        if n != 1:
            raise SystemExit(f"key {args.set} not found in AssetIds.lua")
        open(ASSET_IDS, "w", encoding="utf-8").write(new)
        print(f"AssetIds.{args.set} = {asset_id} written; rebuild the place and publish it")


if __name__ == "__main__":
    main()
