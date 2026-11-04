#!/usr/bin/env python3
"""Record real index-side skin contacts for sewing; no renderer or quality test."""
import argparse
import json
import math
import struct
from pathlib import Path

from measure_finger_pads import COMPONENTS, ROOT, WIDTHS


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def intersect(origin, direction, a, b, c):
    edge_a, edge_b = sub(b, a), sub(c, a)
    p = cross(direction, edge_b)
    determinant = dot(edge_a, p)
    if abs(determinant) < 1e-12:
        return None
    offset = sub(origin, a)
    u = dot(offset, p) / determinant
    q = cross(offset, edge_a)
    v = dot(direction, q) / determinant
    distance = dot(edge_b, q) / determinant
    if u < 0 or v < 0 or u + v > 1 or distance <= 0:
        return None
    return distance, (1 - u - v, u, v)


def section_probes(triangles, height, outward):
    section = []
    for _, _, triangle in triangles:
        for a, b in zip(triangle, triangle[1:] + triangle[:1]):
            if (a[1] - height) * (b[1] - height) > 0 or abs(a[1] - b[1]) < 1e-10:
                continue
            weight = (height - a[1]) / (b[1] - a[1])
            section.append(tuple(a[axis] + (b[axis] - a[axis]) * weight for axis in range(3)))
    if not section:
        return []
    lo = [min(point[axis] for point in section) for axis in range(3)]
    hi = [max(point[axis] for point in section) for axis in range(3)]
    # This origin is only a ray fixture. The contact remains the first actual
    # triangle hit; no section midpoint is ever returned as a skin contact.
    x = hi[0] + .005 if outward[0] > 0 else lo[0] - .005
    return [((x, height, lo[2] + (hi[2] - lo[2]) * fraction), tuple(-v for v in outward),
             "thumb_side_of_actual_triangle_section", {"minimum": lo, "maximum": hi, "z_fraction": fraction})
            for fraction in [.5, .25, .75]]


def measure(source, distal):
    raw = (ROOT / source.removeprefix("res://")).read_bytes()
    size = struct.unpack_from("<I", raw, 12)[0]
    document = json.loads(raw[20:20 + size])
    binary = raw[28 + size:]
    cache = {}

    def accessor(index):
        if index not in cache:
            item = document["accessors"][index]
            view = document["bufferViews"][item["bufferView"]]
            fmt = "<" + COMPONENTS[item["componentType"]] * WIDTHS[item["type"]]
            start = view.get("byteOffset", 0) + item.get("byteOffset", 0)
            values = [struct.unpack_from(fmt, binary, start + row * view.get("byteStride", struct.calcsize(fmt)))
                      for row in range(item["count"])]
            if item.get("normalized", False) and item["componentType"] != 5126:
                maximum = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535}[item["componentType"]]
                values = [tuple(max(-1, value / maximum) for value in row) for row in values]
            cache[index] = values
        return cache[index]

    result = {}
    for side in ["L", "R"]:
        bone = "DEF-finger1." + side
        point = distal.get(side, {}).get("index", {}).get("point", [])
        if len(point) != 3:
            result[side] = {"supported": False, "reason": "No measured distal index extent."}
            continue
        origin = (0, point[1] * .60, 0)
        direction = (1 if side == "L" else -1, 0, 0)
        closest = None
        for node in document["nodes"]:
            if "mesh" not in node or "skin" not in node:
                continue
            skin = document["skins"][node["skin"]]
            slots = [slot for slot, joint in enumerate(skin["joints"])
                     if document["nodes"][joint].get("name") == bone]
            if not slots:
                continue
            slot = slots[0]
            bind = accessor(skin["inverseBindMatrices"])[slot]
            for surface, primitive in enumerate(document["meshes"][node["mesh"]]["primitives"]):
                attributes = primitive["attributes"]
                if primitive.get("mode", 4) != 4 or "JOINTS_0" not in attributes:
                    continue
                vertices = accessor(attributes["POSITION"])
                joints = accessor(attributes["JOINTS_0"])
                weights = accessor(attributes["WEIGHTS_0"])
                indices = [entry[0] for entry in accessor(primitive["indices"])] if "indices" in primitive else list(range(len(vertices)))
                rigid = {}
                for index, (vertex, vertex_joints, vertex_weights) in enumerate(zip(vertices, joints, weights)):
                    weight = sum(w for joint, w in zip(vertex_joints, vertex_weights) if joint == slot)
                    if weight < .999:
                        continue
                    local = tuple(sum(bind[column * 4 + row] * vertex[column] for column in range(3)) + bind[12 + row]
                                  for row in range(3))
                    rigid[index] = (local, weight)
                triangles = []
                for offset in range(0, len(indices) - 2, 3):
                    selected = indices[offset:offset + 3]
                    if not all(index in rigid for index in selected):
                        continue
                    triangle = [rigid[index][0] for index in selected]
                    triangles.append((offset, selected, triangle))
                probes = [(origin, direction, "bone_axis_toward_thumb", {})] + section_probes(triangles, origin[1], direction)
                for priority, (query_origin, query_direction, method, section) in enumerate(probes):
                    for offset, selected, triangle in triangles:
                        hit = intersect(query_origin, query_direction, *triangle)
                        if hit is None or closest is not None and (priority, hit[0]) >= closest[:2]:
                            continue
                        distance, barycentric = hit
                        contact = tuple(sum(barycentric[i] * triangle[i][axis] for i in range(3)) for axis in range(3))
                        normal = cross(sub(triangle[1], triangle[0]), sub(triangle[2], triangle[0]))
                        magnitude = math.sqrt(dot(normal, normal))
                        closest = (priority, distance, {"supported": True, "bone": bone, "mode": "index_side",
                            "source": source, "mesh": node.get("name", ""), "mesh_index": node["mesh"], "surface": surface,
                            "skin_index": node["skin"], "bind_index": slot, "triangle": offset // 3,
                            "vertex_indices": selected, "vertices_bind_local": triangle, "barycentric": barycentric,
                            "skin_weights": [rigid[index][1] for index in selected],
                            "minimum_skin_weight": min(rigid[index][1] for index in selected),
                            "point": contact, "normal": [value / magnitude for value in normal],
                            "query_method": method, "query_section": section,
                            "query_origin": query_origin, "query_direction": query_direction, "ray_distance": distance})
        result[side] = closest[2] if closest else {"supported": False, "reason": "No fully weighted index-side triangle intersects the ray."}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "data/sewing-finger-pad-contacts.json")
    args = parser.parse_args()
    distal = json.loads((ROOT / "data/finger-pad-contacts.json").read_text())
    models = {source: {"hands": measure(source, entry["hands"])} for source, entry in distal["models"].items()}
    output = {"schema_version": 1,
        "method": "Ray at 60% of the measured distal index local-Y extent. First try the bone axis toward the thumb side (+X for L, -X for R). If the skin is off the bone axis, cast inward from the thumb side of its actual triangle cross section. The first real triangle hit supplies the barycentric point. All three triangle vertices must have index-bone weight >=0.999.",
        "scope": "Sewing-only index-side contacts. Existing distal thumb/index contacts and board behavior remain separate. Contact data generation is not a rendering or quality test.",
        "generator": "tools/measure_sewing_finger_pads.py", "models": models}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    supported = sum(hand.get("supported", False) for model in models.values() for hand in model["hands"].values())
    print(f"Recorded {supported} sewing index-side surface contacts across {len(models)} model sources; no renderer or quality test run.")


if __name__ == "__main__":
    main()
