#!/usr/bin/env python3
"""Isolated CPU candidate for continuous Haru palm/finger-web weights.

Reads the unchanged game GLBs and an actual recorded contact pose. Changes only
JOINTS_0/WEIGHTS_0 bytes in copies under builds/haru-hand-repair. No bpy, renderer,
mesh generation, new rig, UV edit, clip edit, or source GLB write is performed.
The report is a deformation diagnostic, not in-game acceptance.
"""
import argparse
import collections
import copy
import json
import math
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[4]
BASELINE_PATH = Path(__file__).resolve().parent / "fixtures/haru-hand-weight-baseline.json"
TYPES = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def multiply(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def inverse(matrix):
    rows = [list(row) + [float(r == c) for c in range(4)] for r, row in enumerate(matrix)]
    for col in range(4):
        pivot = max(range(col, 4), key=lambda r: abs(rows[r][col]))
        rows[col], rows[pivot] = rows[pivot], rows[col]
        divisor = rows[col][col]
        rows[col] = [v / divisor for v in rows[col]]
        for row in range(4):
            if row != col:
                factor = rows[row][col]
                rows[row] = [v - factor * w for v, w in zip(rows[row], rows[col])]
    return [row[4:] for row in rows]


def point(matrix, vertex):
    return tuple(sum(matrix[r][c] * vertex[c] for c in range(3)) + matrix[r][3] for r in range(3))


def quaternion_matrix(q):
    x, y, z, w = q
    return [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), 0],
            [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), 0],
            [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), 0], [0, 0, 0, 1]]


def normalise(weights):
    pairs = sorted(((bone, max(0, value)) for bone, value in weights.items() if value > .00001),
                   key=lambda pair: (-pair[1], pair[0]))[:4]
    total = sum(value for _, value in pairs)
    if total <= 0:
        raise ValueError("A repair vertex lost all influences")
    return {bone: value / total for bone, value in pairs}


class Glb:
    def __init__(self, path):
        self.path = path
        self.raw = bytearray(path.read_bytes())
        size = struct.unpack_from("<I", self.raw, 12)[0]
        self.document = json.loads(self.raw[20:20+size])
        self.binary_start = 20 + size + 8
        mesh_nodes = [n for n in self.document["nodes"] if "mesh" in n and "skin" in n]
        if len(mesh_nodes) != 1:
            raise ValueError("Expected Haru's single skinned mesh")
        node = mesh_nodes[0]
        primitives = self.document["meshes"][node["mesh"]]["primitives"]
        if len(primitives) != 1:
            raise ValueError("Expected Haru's single surface")
        self.primitive = primitives[0]
        self.skin = self.document["skins"][node["skin"]]
        self.names = [self.document["nodes"][n]["name"] for n in self.skin["joints"]]
        self.binds = [[[a[c*4+r] for c in range(4)] for r in range(4)]
                      for a in self.read(self.skin["inverseBindMatrices"])]
        self.rests = [inverse(matrix) for matrix in self.binds]
        attributes = self.primitive["attributes"]
        self.positions = self.read(attributes["POSITION"])
        self.joints = self.read(attributes["JOINTS_0"])
        self.weights = self.read(attributes["WEIGHTS_0"])
        if len(self.joints[0]) != 4:
            raise ValueError("Expected the four-influence contract")
        self.original = [{bone: weight for bone, weight in zip(joints, weights) if weight > 0}
                         for joints, weights in zip(self.joints, self.weights)]
        triangles = [row[0] for row in self.read(self.primitive["indices"])]
        self.triangles = [triangles[offset:offset+3] for offset in range(0, len(triangles), 3)]
        self.edges = set()
        for offset in range(0, len(triangles), 3):
            a, b, c = triangles[offset:offset+3]
            self.edges.update(tuple(sorted(edge)) for edge in [(a, b), (b, c), (c, a)])

    def layout(self, index):
        accessor = self.document["accessors"][index]
        view = self.document["bufferViews"][accessor["bufferView"]]
        fmt = "<" + TYPES[accessor["componentType"]] * WIDTHS[accessor["type"]]
        base = self.binary_start + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return accessor, fmt, base, view.get("byteStride", struct.calcsize(fmt))

    def read(self, index):
        accessor, fmt, base, stride = self.layout(index)
        return [struct.unpack_from(fmt, self.raw, base + stride * row) for row in range(accessor["count"])]

    def repaired_bytes(self, weights):
        raw = bytearray(self.raw)
        attributes = self.primitive["attributes"]
        joint_access, joint_fmt, joint_base, joint_stride = self.layout(attributes["JOINTS_0"])
        weight_access, weight_fmt, weight_base, weight_stride = self.layout(attributes["WEIGHTS_0"])
        if weight_access["componentType"] != 5126:
            raise ValueError("Expected float32 weights")
        changed = []
        allowed = set()
        for vertex, values in enumerate(weights):
            if all(abs(values.get(bone, 0) - self.original[vertex].get(bone, 0)) < 1e-9
                   for bone in values.keys() | self.original[vertex].keys()):
                continue
            pairs = list(normalise(values).items())
            joint_row = [bone for bone, _ in pairs] + [0] * (4-len(pairs))
            weight_row = [weight for _, weight in pairs] + [0.0] * (4-len(pairs))
            vertex_changed = False
            for fmt, start, stride, row in [(joint_fmt, joint_base, joint_stride, joint_row),
                                             (weight_fmt, weight_base, weight_stride, weight_row)]:
                offset = start + vertex * stride
                old_row = bytes(raw[offset:offset+struct.calcsize(fmt)])
                struct.pack_into(fmt, raw, offset, *row)
                vertex_changed = vertex_changed or old_row != raw[offset:offset+struct.calcsize(fmt)]
                allowed.update(range(offset, offset + struct.calcsize(fmt)))
            if vertex_changed:
                changed.append(vertex)
        differences = [i for i, (old, new) in enumerate(zip(self.raw, raw)) if old != new]
        if any(offset not in allowed for offset in differences):
            raise ValueError("A non-weight byte changed")
        return raw, changed, len(differences)

    def patch(self, destination, weights):
        raw, changed, count = self.repaired_bytes(weights)
        destination.write_bytes(raw)
        return changed, count


def baseline_record(asset):
    """Small immutable hand baseline, with direct array/index compatibility data."""
    attributes = asset.primitive["attributes"]
    uvs = asset.read(attributes["TEXCOORD_0"])
    hand_bones = {bone for bone, name in enumerate(asset.names) if "hand." in name or "finger" in name}
    vertices = {vertex for vertex, values in enumerate(asset.original)
                if any(values.get(bone, 0) > 0 for bone in hand_bones)}
    rows = [[vertex, [round(v, 10) for v in asset.positions[vertex]],
             [round(v, 10) for v in uvs[vertex]], asset.joints[vertex], asset.weights[vertex]]
            for vertex in sorted(vertices)]
    return {"file": asset.path.name, "vertex_count": len(asset.positions),
            "attribute_counts": {name: asset.document["accessors"][index]["count"]
                                 for name, index in attributes.items()},
            "index_count": asset.document["accessors"][asset.primitive["indices"]]["count"],
            "bind_names": asset.names, "bind_matrices": asset.binds,
            "hand_triangles": [triangle for triangle in asset.triangles if any(v in vertices for v in triangle)],
            "rows": rows}


def capture_baseline(source_dir, record_path):
    if BASELINE_PATH.exists():
        raise FileExistsError("The immutable hand baseline already exists; it is never automatically overwritten")
    entries = []
    for level in range(3):
        name = "CH_Haru" + ("_LOD%d" % level if level else "") + ".glb"
        entries.append(baseline_record(Glb(source_dir / name)))
    baseline = {"schema_version": 1,
                "scope": "Original unrepaired hand JOINTS_0/WEIGHTS_0 only. Restore in memory before every repair; never re-smooth production weights cumulatively.",
                "row_fields": ["vertex_index", "gltf_position", "uv0", "joints4", "weights4"],
                "compatibility_tolerance_m": 1e-7, "uv_tolerance": 1e-7,
                "diagnostic_pose": read_pose(record_path), "lods": entries}
    BASELINE_PATH.write_text(json.dumps(baseline, separators=(",", ":")) + "\n")
    return [len(entry["rows"]) for entry in entries]


def restore_baseline(asset, baseline):
    """Restore only copied hand bytes, after checking actual geometry/UV values."""
    attributes = asset.primitive["attributes"]
    counts = {name: asset.document["accessors"][index]["count"] for name, index in attributes.items()}
    if len(asset.positions) != baseline["vertex_count"] or counts != baseline["attribute_counts"]:
        raise ValueError("Hand baseline rejected: vertex/attribute array sizes differ")
    if asset.document["accessors"][asset.primitive["indices"]]["count"] != baseline["index_count"]:
        raise ValueError("Hand baseline rejected: topology array size differs")
    if asset.names != baseline["bind_names"] or any(abs(a-b) > 1e-7
            for actual, expected in zip(asset.binds, baseline["bind_matrices"])
            for row_a, row_b in zip(actual, expected) for a, b in zip(row_a, row_b)):
        raise ValueError("Hand baseline rejected: skin bind order or values differ")
    uvs = asset.read(attributes["TEXCOORD_0"])
    vertices = {row[0] for row in baseline["rows"]}
    local_triangles = [triangle for triangle in asset.triangles if any(v in vertices for v in triangle)]
    if local_triangles != baseline["hand_triangles"]:
        raise ValueError("Hand baseline rejected: hand vertex indices/topology differ")
    for vertex, position, uv, joints, weights in baseline["rows"]:
        if math.dist(asset.positions[vertex], position) > 1e-7:
            raise ValueError("Hand baseline rejected: actual hand position differs at vertex %d" % vertex)
        if math.dist(uvs[vertex], uv) > 1e-7:
            raise ValueError("Hand baseline rejected: actual hand UV differs at vertex %d" % vertex)
        if len(joints) != 4 or len(weights) != 4 or abs(sum(weights)-1) > 1e-6:
            raise ValueError("Invalid immutable hand baseline row")
    _, joint_fmt, joint_base, joint_stride = asset.layout(attributes["JOINTS_0"])
    _, weight_fmt, weight_base, weight_stride = asset.layout(attributes["WEIGHTS_0"])
    restored = 0
    for vertex, _, _, joints, weights in baseline["rows"]:
        if tuple(joints) != asset.joints[vertex] or tuple(weights) != asset.weights[vertex]:
            restored += 1
        struct.pack_into(joint_fmt, asset.raw, joint_base + vertex*joint_stride, *joints)
        struct.pack_into(weight_fmt, asset.raw, weight_base + vertex*weight_stride, *weights)
    asset.joints = asset.read(attributes["JOINTS_0"])
    asset.weights = asset.read(attributes["WEIGHTS_0"])
    asset.original = [{bone: weight for bone, weight in zip(joints, weights) if weight > 0}
                      for joints, weights in zip(asset.joints, asset.weights)]
    return restored


def repair(asset, rings, iterations, smoothness):
    groups = {}
    vertex_group = []
    for vertex in asset.positions:
        key = tuple(round(component, 6) for component in vertex)
        if key not in groups:
            groups[key] = []
        groups[key].append(len(vertex_group))
        vertex_group.append(key)
    original = {}
    for key, vertices in groups.items():
        summed = collections.defaultdict(float)
        for vertex in vertices:
            for bone, value in asset.original[vertex].items():
                summed[bone] += value / len(vertices)
        original[key] = normalise(summed)
    neighbours = {key: set() for key in groups}
    for a, b in asset.edges:
        ga, gb = vertex_group[a], vertex_group[b]
        if ga != gb:
            neighbours[ga].add(gb)
            neighbours[gb].add(ga)
    family = {}
    for side in ["L", "R"]:
        family[side] = {asset.names.index("DEF-hand."+side)} | {
            asset.names.index("DEF-finger%d.%s" % (finger, side)) for finger in range(5)}
    locked = set()
    cap_records = []
    for side in ["L", "R"]:
        for finger in range(5):
            bone = asset.names.index("DEF-finger%d.%s" % (finger, side))
            points = [(vertex, point(asset.binds[bone], position))
                      for vertex, position in enumerate(asset.positions)
                      if asset.original[vertex].get(bone, 0) >= .85]
            points = [(v, p) for v, p in points if p[1] > .005]
            if not points:
                continue
            maximum = max(p[1] for _, p in points)
            caps = [vertex for vertex, p in points if p[1] >= maximum - .004]
            locked.update(vertex_group[vertex] for vertex in caps)
            cap_records.append({"bone": asset.names[bone], "vertices": caps})
    eligible = set()
    for key, values in original.items():
        side = "L" if key[0] >= 0 else "R"
        if abs(key[0]) >= .27 and .66 <= key[1] <= .89 and sum(values.get(bone, 0) for bone in family[side]) > .999:
            eligible.add(key)
    dominant = {key: max(values, key=values.get) for key, values in original.items()}
    seeds = set()
    for key in eligible:
        for other in neighbours[key]:
            if other not in eligible or dominant[key] == dominant[other]:
                continue
            if "finger" in asset.names[dominant[key]] and "finger" in asset.names[dominant[other]]:
                seeds.update([key, other])
    region = set(seeds)
    for _ in range(rings):
        region.update(n for key in list(region) for n in neighbours[key] if n in eligible)
    mutable = region - locked
    values = copy.deepcopy(original)
    for _ in range(iterations):
        updated = {}
        for key in mutable:
            average = collections.defaultdict(float)
            for other in neighbours[key]:
                for bone, weight in values[other].items():
                    average[bone] += weight / len(neighbours[key])
            blend = {bone: (1-smoothness)*original[key].get(bone, 0) + smoothness*average.get(bone, 0)
                     for bone in original[key].keys() | average.keys()}
            updated[key] = normalise(blend)
        values.update(updated)
    result = list(asset.original)
    for key in region:
        for vertex in groups[key]:
            result[vertex] = values[key]
    return result, {"welded_hand_region_nodes": len(region), "mutable_nodes": len(mutable),
                    "locked_distal_nodes": len(locked), "caps": cap_records, "groups": groups,
                    "region": region}


def deformation(asset, weights, pose):
    transforms = {}
    for side, rotations in pose.items():
        for finger, q in enumerate(rotations):
            bone = asset.names.index("DEF-finger%d.%s" % (finger, side))
            transforms[bone] = multiply(multiply(asset.rests[bone], quaternion_matrix(q)), asset.binds[bone])
    positions = []
    for vertex, values in zip(asset.positions, weights):
        result = [0.0, 0.0, 0.0]
        for bone, weight in values.items():
            transformed = point(transforms[bone], vertex) if bone in transforms else vertex
            for axis in range(3):
                result[axis] += transformed[axis] * weight
        positions.append(result)
    return positions, set(transforms)


def edge_report(asset, weights, pose):
    deformed, bones = deformation(asset, weights, pose)
    rows = []
    for a, b in asset.edges:
        if not any(asset.original[v].get(bone, 0) > .05 for v in [a, b] for bone in bones):
            continue
        before = math.dist(asset.positions[a], asset.positions[b])
        after = math.dist(deformed[a], deformed[b])
        if .0005 < before < .035:
            rows.append({"vertices": [a, b], "rest_length_m": before, "posed_length_m": after,
                         "ratio": after / before, "extra_length_m": after-before})
    rows.sort(key=lambda row: row["ratio"], reverse=True)
    areas = []
    for triangle in asset.triangles:
        if not any(asset.original[v].get(bone, 0) > .05 for v in triangle for bone in bones):
            continue
        def area_normal(positions):
            a, b, c = [positions[v] for v in triangle]
            u = [b[k]-a[k] for k in range(3)]
            v = [c[k]-a[k] for k in range(3)]
            normal = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
            length = math.sqrt(sum(component*component for component in normal))
            return length, normal
        rest_area, rest_normal = area_normal(asset.positions)
        posed_area, posed_normal = area_normal(deformed)
        if rest_area > 1e-8:
            areas.append((posed_area/rest_area, sum(a*b for a, b in zip(rest_normal, posed_normal)) < 0))
    return {"hand_edges": len(rows), "peak_ratio": rows[0]["ratio"],
            "edges_over_3x": sum(row["ratio"] > 3 for row in rows),
            "peak_extra_length_m": max(row["extra_length_m"] for row in rows), "worst": rows[:12],
            "surface_diagnostic": {"hand_triangles": len(areas), "minimum_area_ratio": min(v[0] for v in areas),
                                   "triangles_under_tenth_rest_area": sum(v[0] < .10 for v in areas),
                                   "normals_reversed_vs_rest": sum(v[1] for v in areas),
                                   "scope": "Diagnostic only: a pose rotates surfaces, so a rest-normal reversal alone is not an inversion test."}}


def read_pose(path):
    source = json.loads(path.read_text())
    actor = source["cases"]["adult"]["samples"]["place"]["actors"]["haru"]
    result = {}
    for side, rotations in actor["motion"]["finger_rotations"].items():
        result[side] = [[float(v) for v in re.findall(r"[-+]?\d*\.?\d+(?:e[-+]?\d+)?", q)]
                        if isinstance(q, str) else q for q in rotations]
    return {"source": str(path.relative_to(ROOT)), "sample": "cases.adult.samples.place.actors.haru",
            "scope": "Actual recorded relative finger rotations; isolated finger FK at the unchanged bind hand, without rendering or full-body IK.",
            "rotations": result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "builds/haru-hand-repair/r2")
    parser.add_argument("--source-dir", type=Path, default=ROOT / "game/assets/models/haru")
    parser.add_argument("--capture-baseline", action="store_true", help="One-time explicit capture; refuses an existing fixture")
    parser.add_argument("--record", type=Path, default=ROOT / "builds/tabletop-presentation/headless.json")
    parser.add_argument("--rings", type=int, default=3)
    parser.add_argument("--iterations", type=int, default=24)
    parser.add_argument("--smoothness", type=float, default=.90)
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.record = args.record.resolve()
    args.source_dir = args.source_dir.resolve()
    if args.capture_baseline:
        print("Captured original hand baseline rows per LOD:", capture_baseline(args.source_dir, args.record))
        return
    baseline = json.loads(BASELINE_PATH.read_text())
    if not args.out.is_relative_to(ROOT / "builds/haru-hand-repair"):
        parser.error("Candidate output must stay under builds/haru-hand-repair")
    args.out.mkdir(parents=True, exist_ok=True)
    pose_path = args.out / "input-pose.json"
    if pose_path.exists():
        pose = json.loads(pose_path.read_text())
    elif args.record.exists():
        pose = read_pose(args.record)
    else:
        # A clean checkout has no ignored builds/ event log. Keep the same
        # measured contact available without re-running the game to make it.
        pose = baseline["diagnostic_pose"]
    pose_path.write_text(json.dumps(pose, indent=2) + "\n")
    report = {"scope": "Isolated weight-only candidates. CPU diagnostics do not satisfy the skill's extreme-pose, round-trip, or actual-engine delivery gates.",
              "immutable_hand_baseline": str(BASELINE_PATH.relative_to(ROOT)),
              "policy": {"rings": args.rings, "iterations": args.iterations, "smoothness": args.smoothness,
                         "pose": "Same recorded contact, not a better-scoring replacement pose."}, "lods": []}
    for level in range(3):
        name = "CH_Haru" + ("_LOD%d" % level if level else "") + ".glb"
        asset = Glb(args.source_dir / name)
        restored = restore_baseline(asset, baseline["lods"][level])
        repaired, details = repair(asset, args.rings, args.iterations, args.smoothness)
        changed, byte_count = asset.patch(args.out / name, repaired)
        candidate = Glb(args.out / name)
        actual = candidate.original
        seam_errors = []
        hand_bones = {bone for bone, name in enumerate(asset.names) if "hand." in name or "finger" in name}
        for key, vertices in details["groups"].items():
            if not any(asset.original[v].get(bone, 0) > .01 for v in vertices for bone in hand_bones):
                continue
            rows = [actual[v] for v in details["groups"][key]]
            if any(row != rows[0] for row in rows[1:]):
                seam_errors.append(key)
        cap_losses = [(cap["bone"], vertex, actual[vertex].get(asset.names.index(cap["bone"]), 0))
                      for cap in details["caps"] for vertex in cap["vertices"]
                      if actual[vertex].get(asset.names.index(cap["bone"]), 0) < .85-1e-6]
        before_pose, _ = deformation(asset, asset.original, pose["rotations"])
        after_pose, _ = deformation(asset, actual, pose["rotations"])
        cap_displacement = max(math.dist(before_pose[v], after_pose[v])
                               for cap in details["caps"] for v in cap["vertices"])
        bounds = [[min(asset.positions[v][axis] for v in changed), max(asset.positions[v][axis] for v in changed)]
                  for axis in range(3)] if changed else []
        record = {"level": level, "source": str(asset.path.relative_to(ROOT)), "candidate": str((args.out/name).relative_to(ROOT)),
                  "input_vertices_reset_to_original_hand_baseline": restored,
                  "changed_vertices": len(changed), "changed_weight_bytes": byte_count, "changed_bounds_gltf_m": bounds,
                  "welded_hand_region_nodes": details["welded_hand_region_nodes"], "mutable_nodes": details["mutable_nodes"],
                  "before": edge_report(asset, asset.original, pose["rotations"]),
                  "after": edge_report(asset, actual, pose["rotations"]),
                  "constraints": {"non_weight_bytes_unchanged": True,
                                  "position_values_unchanged": asset.positions == candidate.positions,
                                  "skin_bind_matrices_unchanged": asset.binds == candidate.binds,
                                  "nodes_and_animations_unchanged": asset.document["nodes"] == candidate.document["nodes"] and asset.document["animations"] == candidate.document["animations"],
                                  "maximum_influences": max(len(v) for v in actual),
                                  "peak_normalisation_error": max(abs(sum(v.values())-1) for v in actual),
                                  "seam_scope": "All coincident positions with any hand/digit influence, including unchanged hand regions.",
                                  "hand_seam_weight_mismatches": seam_errors, "distal_pad_weight_losses": cap_losses,
                                  "locked_distal_vertex_pose_displacement_m": cap_displacement}}
        if "L" in pose["rotations"]:
            mirrored = {"R": [[q[0], -q[1], -q[2], q[3]] for q in pose["rotations"]["L"]]}
            record["mirrored_right_stress"] = {"scope": "Inferred symmetric stress pose, not an actual observed right-hand game action.",
                                                "before": edge_report(asset, asset.original, mirrored),
                                                "after": edge_report(asset, actual, mirrored)}
        report["lods"].append(record)
        master_rows = {tuple(round(component, 6) for component in asset.positions[v]):
                       {"gltf_position": asset.positions[v],
                        "blender_position": [asset.positions[v][0], -asset.positions[v][2], asset.positions[v][1]],
                        "weights": {asset.names[bone]: weight for bone, weight in actual[v].items()}}
                       for v in changed}
        mapping = {"level": level, "object": "CH_Haru_Body_LOD%d" % level,
                   "mapping": "Match applied-scale master vertices by position within 1e-6m; GLB vertex indices include UV splits and must not be used as Blender indices.",
                   "vertices": list(master_rows.values())}
        mapping_name = "weights-for-master.json" if level == 0 else "weights-for-master-LOD%d.json" % level
        (args.out / mapping_name).write_text(json.dumps(mapping, indent=2)+"\n")
        print(name, "changed", len(changed), "edge peak", round(record["before"]["peak_ratio"], 3), "->", round(record["after"]["peak_ratio"], 3),
              ">3x", record["before"]["edges_over_3x"], "->", record["after"]["edges_over_3x"])
    (args.out / "report.json").write_text(json.dumps(report, indent=2)+"\n")


if __name__ == "__main__":
    main()
