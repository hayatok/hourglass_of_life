#!/usr/bin/env python3
"""Measure distal skin points for the game's single-bone thumb/index fingers.

This reads existing GLBs with the Python standard library; no renderer, rig edit,
or geometry generation is involved. The output is authored contact data, not a
quality test. Its points still need inspection on the actually deformed actor.
"""
import argparse
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def measure(path):
    raw = path.read_bytes()
    json_size = struct.unpack_from("<I", raw, 12)[0]
    document = json.loads(raw[20:20 + json_size])
    binary_offset = 20 + json_size
    binary_size = struct.unpack_from("<I", raw, binary_offset)[0]
    binary = raw[binary_offset + 8:binary_offset + 8 + binary_size]
    cache = {}

    def accessor(index):
        if index in cache:
            return cache[index]
        item = document["accessors"][index]
        view = document["bufferViews"][item["bufferView"]]
        fmt = "<" + COMPONENTS[item["componentType"]] * WIDTHS[item["type"]]
        stride = view.get("byteStride", struct.calcsize(fmt))
        offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        values = [struct.unpack_from(fmt, binary, offset + row * stride)
                  for row in range(item["count"])]
        if item.get("normalized", False) and item["componentType"] != 5126:
            maximum = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535}[item["componentType"]]
            values = [tuple(max(-1, value / maximum) for value in row) for row in values]
        cache[index] = values
        return values

    names = {f"DEF-finger{finger}.{side}": [] for side in ["L", "R"] for finger in [0, 1]}
    for node in document["nodes"]:
        if "mesh" not in node or "skin" not in node:
            continue
        skin = document["skins"][node["skin"]]
        binds = accessor(skin["inverseBindMatrices"])
        slots = {slot: document["nodes"][joint]["name"]
                 for slot, joint in enumerate(skin["joints"])
                 if document["nodes"][joint].get("name") in names}
        for primitive in document["meshes"][node["mesh"]]["primitives"]:
            attributes = primitive["attributes"]
            if "JOINTS_0" not in attributes:
                continue
            for vertex, joints, weights in zip(accessor(attributes["POSITION"]),
                                               accessor(attributes["JOINTS_0"]),
                                               accessor(attributes["WEIGHTS_0"])):
                for slot, weight in zip(joints, weights):
                    if slot not in slots or weight < .85:
                        continue
                    matrix = binds[slot]
                    point = [sum(matrix[column * 4 + row] * vertex[column] for column in range(3))
                             + matrix[12 + row] for row in range(3)]
                    if point[1] > .005:
                        names[slots[slot]].append(point)
    result = {}
    for side in ["L", "R"]:
        result[side] = {}
        for finger, label in [(0, "thumb"), (1, "index")]:
            name = f"DEF-finger{finger}.{side}"
            points = names[name]
            if not points:
                result[side][label] = {"supported": False, "reason": "No strongly weighted distal mesh points."}
                continue
            end = max(point[1] for point in points)
            cap = [point for point in points if point[1] >= end - .004]
            result[side][label] = {
                "supported": bool(cap), "bone": name,
                "point": [round(sum(point[axis] for point in cap) / len(cap), 10) for axis in range(3)],
                "strong_vertex_count": len(points), "distal_cap_vertex_count": len(cap),
                "maximum_local_y_m": round(end, 10),
            }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "data/finger-pad-contacts.json")
    args = parser.parse_args()
    models = {}
    for scene in sorted((ROOT / "game/scenes/characters").glob("*.tscn")):
        match = re.search(r'path="(res://game/assets/models/[^\"]+\.glb)"', scene.read_text())
        if match:
            source = match[1]
            models[source] = {"scene": "res://" + scene.relative_to(ROOT).as_posix(),
                              "hands": measure(ROOT / source.removeprefix("res://"))}
    output = {
        "schema_version": 1,
        "method": "Centroid of the distal 4 mm band of mesh vertices with thumb/index skin weight >= 0.85, in that finger's bind-local coordinates.",
        "scope": "Measured distal skin contact points. Single-bone fingers rotate at their bases; this does not add finger joints or prove anatomical accuracy.",
        "generator": "tools/measure_finger_pads.py", "models": models,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    print(f"Measured contact data for {len(models)} model sources; no renderer or quality test run.")


if __name__ == "__main__":
    main()
