#!/usr/bin/env python3
"""Dry-run or apply the bounded Haru finger/lower-body skin-weight repair."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [ROOT / "game/assets/models/haru" / name for name in
           ["CH_Haru.glb", "CH_Haru_LOD1.glb", "CH_Haru_LOD2.glb"]]
COMPONENTS = {5121: ("B", 255), 5123: ("H", 65535), 5125: ("I", 4294967295), 5126: ("f", None)}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
FINGER = re.compile(r"^DEF-finger[0-9]+\.[LR]$")
LOWER_BODY = re.compile(r"^DEF-(?:thigh|shin|foot|toe)\.[LR]$")


def identifier(raw):
    return {"sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw), "purpose": "artifact identification only"}


def plan(path):
    raw = path.read_bytes()
    if raw[:4] != b"glTF" or struct.unpack_from("<I", raw, 4)[0] != 2:
        raise ValueError(f"Not a GLB 2 file: {path}")
    json_length, kind = struct.unpack_from("<II", raw, 12)
    if kind != 0x4E4F534A:
        raise ValueError("Expected first JSON chunk")
    document = json.loads(raw[20:20 + json_length])
    binary_header = 20 + json_length
    binary_length, binary_kind = struct.unpack_from("<II", raw, binary_header)
    if binary_kind != 0x004E4942:
        raise ValueError("Expected embedded BIN chunk")
    binary_start = binary_header + 8
    if binary_start + binary_length > len(raw):
        raise ValueError("Truncated BIN chunk")
    cache = {}

    def accessor(index):
        if index not in cache:
            item = document["accessors"][index]
            if "sparse" in item:
                raise ValueError("Sparse skin attributes need a separate repair")
            view = document["bufferViews"][item["bufferView"]]
            component, maximum = COMPONENTS[item["componentType"]]
            fmt = "<" + component * WIDTHS[item["type"]]
            start = binary_start + view.get("byteOffset", 0) + item.get("byteOffset", 0)
            stride = view.get("byteStride", struct.calcsize(fmt))
            values = [struct.unpack_from(fmt, raw, start + row * stride) for row in range(item["count"])]
            if item.get("normalized", False) and maximum:
                values = [tuple(value / maximum for value in row) for row in values]
            cache[index] = (values, start, stride, fmt, item)
        return cache[index]

    edits = {}
    finger_counts, lower_counts = Counter(), Counter()
    removed = []
    affected_primitives = []
    for node in document["nodes"]:
        if "mesh" not in node or "skin" not in node:
            continue
        skin = document["skins"][node["skin"]]
        names = [document["nodes"][joint].get("name", "") for joint in skin["joints"]]
        for surface, primitive in enumerate(document["meshes"][node["mesh"]]["primitives"]):
            attributes = primitive["attributes"]
            if "JOINTS_0" not in attributes or "WEIGHTS_0" not in attributes:
                continue
            if "JOINTS_1" in attributes or "WEIGHTS_1" in attributes:
                raise ValueError("Multiple influence sets need a separate repair")
            joints = accessor(attributes["JOINTS_0"])[0]
            weights, start, stride, fmt, item = accessor(attributes["WEIGHTS_0"])
            affected = []
            for vertex, (vertex_joints, vertex_weights) in enumerate(zip(joints, weights)):
                target = [(names[joint], weight) for joint, weight in zip(vertex_joints, vertex_weights)
                          if FINGER.fullmatch(names[joint]) and weight >= .85]
                discarded = [(slot, names[joint], weight) for slot, (joint, weight) in enumerate(zip(vertex_joints, vertex_weights))
                             if weight > 0 and LOWER_BODY.fullmatch(names[joint])]
                if not target or not discarded:
                    continue
                retained = [weight if not LOWER_BODY.fullmatch(names[joint]) else 0.0
                            for joint, weight in zip(vertex_joints, vertex_weights)]
                total = sum(retained)
                if total <= 0:
                    raise ValueError("Repair would remove all influences")
                result = [weight / total for weight in retained]
                component, maximum = COMPONENTS[item["componentType"]]
                if maximum is not None:
                    if not item.get("normalized", False):
                        raise ValueError("Integer weights must be normalized")
                    scaled = [value * maximum for value in result]
                    quantized = [int(value) for value in scaled]
                    for slot in sorted(range(len(result)), key=lambda slot: scaled[slot] - quantized[slot], reverse=True)[:maximum - sum(quantized)]:
                        quantized[slot] += 1
                    packed = struct.pack(fmt, *quantized)
                else:
                    packed = struct.pack(fmt, *result)
                key = (attributes["WEIGHTS_0"], vertex)
                record = (start + vertex * stride, packed)
                if key in edits and edits[key] != record:
                    raise ValueError("Shared weight accessor has inconsistent skin mapping")
                if key not in edits:
                    finger_counts.update(name for name, _ in target)
                    lower_counts.update(name for _, name, _ in discarded)
                    removed.append(sum(weight for _, _, weight in discarded))
                edits[key] = record
                affected.append(vertex)
            if affected:
                affected_primitives.append({"mesh": node.get("name", ""), "surface": surface,
                    "weight_accessor": attributes["WEIGHTS_0"], "vertex_indices": affected})
    output = bytearray(raw)
    for offset, packed in edits.values():
        output[offset:offset + len(packed)] = packed
    changed_offsets = {offset + byte for offset, packed in edits.values() for byte in range(len(packed))}
    if len(output) != len(raw) or any(a != b and offset not in changed_offsets
                                     for offset, (a, b) in enumerate(zip(raw, output))):
        raise AssertionError("Unexpected edit outside planned WEIGHTS_0 rows")
    record = {"file": path.relative_to(ROOT).as_posix(), "input": identifier(raw), "planned_output": identifier(output),
        "affected_vertices": len(edits), "finger_vertices": dict(finger_counts), "discarded_lower_body_influences": dict(lower_counts),
        "removed_weight_range": [min(removed), max(removed)] if removed else [],
        "affected_primitives": affected_primitives, "modified_attributes": ["WEIGHTS_0"] if edits else [],
        "byte_scope": "Only encoded WEIGHTS_0 rows. GLB JSON, chunk lengths, joint indices, all other buffer bytes and images are retained verbatim."}
    return raw, bytes(output), record


def update_asset_manifest(repair, report_path):
    if not any(record["affected_vertices"] for record in repair["assets"]):
        return
    path = ROOT / "game/assets/models/haru/asset-manifest.json"
    asset = json.loads(path.read_text())
    previous_revision = asset.get("revision", "")
    for record in repair["assets"]:
        filename = Path(record["file"]).name
        asset.setdefault("lod_sha256", {})[filename] = record["planned_output"]["sha256"]
        if filename == "CH_Haru.glb":
            asset["exported_glb_sha256"] = record["planned_output"]["sha256"]
    asset["generated"] = datetime.now(timezone.utc).isoformat()
    asset["revision"] = "r4-finger-lower-body-weight-isolation"
    asset["finger_lower_body_weight_repair"] = {
        "script": "tools/repair_haru_finger_weights.py", "previous_revision": previous_revision,
        "manifest": report_path.relative_to(ROOT).as_posix(), "rule": repair["rule"],
        "changed_vertices": [record["affected_vertices"] for record in repair["assets"]],
        "removed_influences": [record["discarded_lower_body_influences"] for record in repair["assets"]],
        "removed_weight_ranges": [record["removed_weight_range"] for record in repair["assets"]],
        "preserved_bytes": "All bytes outside the selected WEIGHTS_0 rows, including GLB JSON, positions, normals, UVs, joints, bind poses, animations, materials and embedded images.",
        "identification_only": "The input/output SHA values identify the assets. They are not a game, skin-contact or rendering test.",
        "authoring_master": asset.get("source", ""),
        "authoring_master_sync": "Separate Blender authoring-copy synchronization and clean reimport pending; the current source master has not been overwritten.",
        "runtime_quality_status": "Pending actual deformed-skin contact and game rendering checks."}
    path.write_text(json.dumps(asset, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write the planned repair after backing up all three originals")
    parser.add_argument("--manifest", type=Path, help="Report path; default is in ignored builds/asset-repairs/haru-finger-weights")
    args = parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    directory = ROOT / "builds/asset-repairs/haru-finger-weights" / stamp
    plans = [(path, *plan(path)) for path in TARGETS]
    manifest = {"mode": "apply" if args.apply else "dry-run", "tool": "tools/repair_haru_finger_weights.py",
        "rule": "For vertices with a DEF-fingerN.L/R influence >=0.85, remove positive DEF-thigh/shin/foot/toe.L/R weights and normalize only the retained influences. All other vertices and attributes remain byte-identical.",
        "scope": "Asset repair and identification record, not a game, rendering or contact quality test.", "assets": [record for _, _, _, record in plans]}
    if args.apply:
        backup = directory / "originals"
        backup.mkdir(parents=True, exist_ok=False)
        for path, raw, _, record in plans:
            if path.read_bytes() != raw:
                raise RuntimeError("An asset changed since this repair was planned")
            destination = backup / path.name
            shutil.copy2(path, destination)
            if destination.read_bytes() != raw:
                raise RuntimeError("Backup content differs from the original")
            record["backup"] = destination.relative_to(ROOT).as_posix()
        for path, _, output, _ in plans:
            path.write_bytes(output)
    destination = args.manifest or directory / "manifest.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    if args.apply:
        update_asset_manifest(manifest, destination)
    for _, _, _, record in plans:
        print(json.dumps({key: record[key] for key in ["file", "affected_vertices", "finger_vertices", "discarded_lower_body_influences", "removed_weight_range"]}))
    print(f"Manifest: {destination}")
    print("No runtime, renderer or quality test was performed.")


if __name__ == "__main__":
    main()
