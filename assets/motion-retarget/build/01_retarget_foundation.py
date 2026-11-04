"""Reproducible animation-only CC0 transfer; never modifies a source model.

Standard Python: --inspect-only (GLB metadata/rest/stride inspection).
Blender 4.2+: blender --background --factory-startup --python THIS -- --targets nagisa
No render, engine invocation, network or old-model export is performed here.
"""
from __future__ import annotations

import argparse
import bisect
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "assets/motion-sources/quaternius"
SOURCE = SOURCE_DIR / "Unreal-Godot/UAL1_Standard.glb"
SOURCE_RM = SOURCE_DIR / "Unreal-Godot/UAL1_Standard_RM.glb"
BUILD = ROOT / "builds/motion-retarget"
RUNTIME = ROOT / "game/assets/motion/foundation"
TARGETS = {"nagisa": ("CH_Nagisa", 1.65), "ryo": ("CH_Ryo", 1.76), "rin": ("CH_Rin", 1.22)}
CLIPS = {
    "idle": ("Idle_Loop", True),
    "walk": ("Walk_Loop", True),
    "walk_formal": ("Walk_Formal_Loop", True),
    "sit_enter": ("Sitting_Enter", False),
    "sit_idle": ("Sitting_Idle_Loop", True),
    "sit_exit": ("Sitting_Exit", False),
    "talk": ("Idle_Talking_Loop", True),
}
MAPPING = {"DEF-pelvis": "pelvis", "DEF-spine_01": "spine_01", "DEF-spine_02": "spine_02",
           "DEF-chest": "spine_03", "DEF-neck": "neck_01", "DEF-head": "Head"}
for side, suffix in (("L", "l"), ("R", "r")):
    for target, source in (("clavicle", "clavicle"), ("upper_arm", "upperarm"),
                           ("forearm", "lowerarm"), ("hand", "hand"), ("thigh", "thigh"),
                           ("shin", "calf"), ("foot", "foot"), ("toe", "ball")):
        MAPPING[f"DEF-{target}.{side}"] = f"{source}_{suffix}"
    for index, finger in enumerate(("thumb", "index", "middle", "ring", "pinky")):
        MAPPING[f"DEF-finger{index}.{side}"] = f"{finger}_01_{suffix}"


def inspector():
    spec = importlib.util.spec_from_file_location("foundation_glb_inspector", SOURCE_DIR / "inspect_glb.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


IO = inspector()


def target_path(target):
    return ROOT / "game/assets/models" / target / f"{TARGETS[target][0]}.glb"


def identity(path):
    return {"path": str(path.relative_to(ROOT)), "bytes": path.stat().st_size,
            "sha256_identification_only": hashlib.sha256(path.read_bytes()).hexdigest()}


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n")


def clip_info(doc, binary, name):
    animation = next(item for item in doc["animations"] if item["name"] == name)
    times = sorted({row[0] for sampler in animation["samplers"]
                    for row in IO.accessor(doc, binary, sampler["input"])})
    return animation, times[0], times[-1]


def rest_record(doc):
    worlds, parents = IO.world_matrices(doc["nodes"])
    return {node["name"]: {"parent": doc["nodes"][parents[i]]["name"] if i in parents else None,
            "local_translation": node.get("translation", [0, 0, 0]),
            "local_rotation_xyzw": node.get("rotation", [0, 0, 0, 1]),
            "world_position_m": IO.position(worlds[i]),
            "world_basis_rows": [row[:3] for row in worlds[i][:3]]}
            for i, node in enumerate(doc["nodes"]) if i in doc["skins"][0]["joints"]}


def leg_length(record, names):
    def distance(a, b):
        return math.dist(record[a]["world_position_m"], record[b]["world_position_m"])
    return sum(distance(names[side][0], names[side][1]) + distance(names[side][1], names[side][2])
               for side in ("L", "R")) * .5


def contact_geometry(doc, binary):
    """Actual sole vertices plus every influence; no invented contact offsets."""
    worlds, _ = IO.world_matrices(doc["nodes"])
    skin = doc["skins"][0]
    palette = [doc["nodes"][index]["name"] for index in skin["joints"]]
    inverse_bind = IO.accessor(doc, binary, skin["inverseBindMatrices"])
    candidates = {side: [] for side in ("L", "R")}
    for node in doc["nodes"]:
        if "mesh" not in node or node.get("skin") != 0:
            continue
        for primitive_index, primitive in enumerate(doc["meshes"][node["mesh"]]["primitives"]):
            attrs = primitive["attributes"]
            if "JOINTS_0" not in attrs:
                continue
            positions = IO.accessor(doc, binary, attrs["POSITION"])
            joints = IO.accessor(doc, binary, attrs["JOINTS_0"])
            weights = IO.accessor(doc, binary, attrs["WEIGHTS_0"])
            for vertex, (position, slots, values) in enumerate(zip(positions, joints, weights)):
                for side in ("L", "R"):
                    allowed = {f"DEF-foot.{side}", f"DEF-toe.{side}"}
                    if sum(w for slot, w in zip(slots, values) if palette[slot] in allowed) < .9999:
                        continue
                    influences, world = [], [0.0, 0.0, 0.0]
                    for slot, weight in zip(slots, values):
                        if weight <= 0:
                            continue
                        ib = inverse_bind[slot]
                        local = [sum(ib[c * 4 + r] * position[c] for c in range(3)) + ib[12 + r] for r in range(3)]
                        bone_world = worlds[skin["joints"][slot]]
                        for r in range(3):
                            world[r] += weight * (sum(bone_world[r][c] * local[c] for c in range(3)) + bone_world[r][3])
                        influences.append({"bone": palette[slot], "weight": weight, "bone_local_position": local})
                    candidates[side].append({"mesh": node["name"], "primitive": primitive_index,
                                             "vertex": vertex, "position": list(position),
                                             "rest_world_position": world, "influences": influences})
    result = {"method": "actual source GLB sole vertices; complete skin influences and inverse-bind-derived bone-local positions", "feet": {}}
    for side, points in candidates.items():
        if not points:
            raise ValueError(f"No fully foot-descendant weighted shoe vertices for {side}")
        floor = min(item["rest_world_position"][1] for item in points)
        low = [item for item in points if item["rest_world_position"][1] <= floor + .006]
        min_z, max_z = [function(item["rest_world_position"][2] for item in low) for function in (min, max)]
        centre_x = sum(item["rest_world_position"][0] for item in low) / len(low)
        selected = {}
        for key, fraction in (("heel", .1), ("ball", .7), ("toe", .9)):
            z = min_z + (max_z - min_z) * fraction
            selected[key] = min(low, key=lambda item: abs(item["rest_world_position"][2] - z) + .35 * abs(item["rest_world_position"][0] - centre_x))
        result["feet"][side] = {"rest_floor_y_m": floor, "points": selected}
    return result


def inspect(targets):
    source, binary = IO.load_glb(SOURCE)
    rm, rm_binary = IO.load_glb(SOURCE_RM)
    source_rest = rest_record(source)
    source_leg = leg_length(source_rest, {s: [f"{b}_{s.lower()}" for b in ("thigh", "calf", "foot")] for s in ("L", "R")})
    result = {"scope": "Metadata/rest/encoded source-root inspection only. Not a retarget/render/gait test.",
              "source": identity(SOURCE), "root_motion_source": identity(SOURCE_RM),
              "license": "CC0-1.0", "source_rest": source_rest, "source_leg_length_m": source_leg,
              "mapping": MAPPING, "clips": {}, "targets": {},
              "missing_source_coverage": ["walk_start", "walk_stop", "turn_90", "turn_180"]}
    for key, (name, loop) in CLIPS.items():
        _, start, end = clip_info(source, binary, name)
        animation, _, _ = clip_info(rm, rm_binary, name)
        root_channel = next(c for c in animation["channels"] if c["target"]["path"] == "translation"
                            and rm["nodes"][c["target"]["node"]]["name"] == "root")
        values = IO.accessor(rm, rm_binary, animation["samplers"][root_channel["sampler"]]["output"])
        delta = [values[-1][i] - values[0][i] for i in range(3)]
        # root's local Y points along glTF +Z in this specific source bind.
        root_index = root_channel["target"]["node"]
        parent = next((i for i, n in enumerate(rm["nodes"]) if root_index in n.get("children", [])), None)
        rm_worlds, _ = IO.world_matrices(rm["nodes"])
        if parent is not None:
            delta = [sum(rm_worlds[parent][r][c] * delta[c] for c in range(3)) for r in range(3)]
        stride = math.hypot(delta[0], delta[2])
        result["clips"][key] = {"source_clip": name, "loop": loop, "duration_seconds": end - start,
                                "root_displacement_world_m": delta, "source_stride_m": stride,
                                "source_speed_mps": stride / (end - start)}
    required = set(MAPPING) | {"DEF-root", "DEF-apron_front", "DEF-apron_back"}
    for target in targets:
        path = target_path(target)
        doc, target_binary = IO.load_glb(path)
        record = rest_record(doc)
        if set(record) != required:
            raise ValueError(f"{target}: incompatible target joint set: {set(record) ^ required}")
        length = leg_length(record, {s: [f"DEF-{b}.{s}" for b in ("thigh", "shin", "foot")] for s in ("L", "R")})
        result["targets"][target] = {"input": identity(path), "scene_height_m": TARGETS[target][1],
                                      "rest": record, "leg_length_m": length, "translation_scale": length / source_leg,
                                      "contact_geometry": contact_geometry(doc, target_binary)}
    write_json(BUILD / "inspection.json", result)
    return result


class RigData:
    """Exact glTF local/world transforms and weighted source surface samples."""
    def __init__(self, path):
        from mathutils import Matrix, Quaternion, Vector
        self.doc, self.binary = IO.load_glb(path)
        self.nodes = self.doc["nodes"]
        self.ids = {node["name"]: i for i, node in enumerate(self.nodes)}
        self.parents = {child: i for i, node in enumerate(self.nodes) for child in node.get("children", [])}
        self.locals = [Matrix(IO.local_matrix(node)) for node in self.nodes]
        self.rest = self.world(self.locals)
        self.skin = self.doc["skins"][0]
        self.joints = [self.nodes[i]["name"] for i in self.skin["joints"]]
        self.joint_ids = set(self.skin["joints"])
        self.order = sorted(self.skin["joints"], key=self.depth)
        binds = IO.accessor(self.doc, self.binary, self.skin["inverseBindMatrices"])
        self.inverse_bind = [Matrix([[row[c * 4 + r] for c in range(4)] for r in range(4)]) for row in binds]
        self.feet = {side: [] for side in ("L", "R")}
        for node_id, node in enumerate(self.nodes):
            if "mesh" not in node or node.get("skin") != 0:
                continue
            for primitive in self.doc["meshes"][node["mesh"]]["primitives"]:
                attrs = primitive["attributes"]
                if "JOINTS_0" not in attrs:
                    continue
                positions = IO.accessor(self.doc, self.binary, attrs["POSITION"])
                joints = IO.accessor(self.doc, self.binary, attrs["JOINTS_0"])
                weights = IO.accessor(self.doc, self.binary, attrs["WEIGHTS_0"])
                for co, slots, values in zip(positions, joints, weights):
                    for side in ("L", "R"):
                        names = {f"DEF-foot.{side}", f"DEF-toe.{side}"} if "DEF-root" in self.ids else {f"foot_{side.lower()}", f"ball_{side.lower()}", f"ball_leaf_{side.lower()}"}
                        foot_weight = sum(w for slot, w in zip(slots, values) if self.joints[slot] in names)
                        if foot_weight < .5:
                            continue
                        self.feet[side].append((Vector(co), [(int(slot), float(w)) for slot, w in zip(slots, values) if w > 0]))
        if any(not points for points in self.feet.values()):
            raise ValueError(f"{path}: no measured weighted foot surface vertices")

    def depth(self, index):
        count = 0
        while index in self.parents:
            count += 1
            index = self.parents[index]
        return count

    def world(self, local):
        cache = {}
        def get(index):
            if index not in cache:
                cache[index] = get(self.parents[index]) @ local[index] if index in self.parents else local[index].copy()
            return cache[index]
        return [get(i) for i in range(len(local))]

    def surfaces(self, world, side):
        from mathutils import Vector
        skin_matrices = [world[index] @ bind for index, bind in zip(self.skin["joints"], self.inverse_bind)]
        return [sum(((skin_matrices[slot] @ co) * weight for slot, weight in influences), Vector())
                for co, influences in self.feet[side]]


class ClipSampler:
    def __init__(self, rig, name):
        self.rig = rig
        animation, self.start, self.end = clip_info(rig.doc, rig.binary, name)
        self.channels = []
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            interpolation = sampler.get("interpolation", "LINEAR")
            if interpolation not in ("LINEAR", "STEP"):
                raise ValueError(f"Unsupported source interpolation {interpolation}")
            target = channel["target"]
            if target["path"] not in ("translation", "rotation", "scale"):
                continue
            self.channels.append((target["node"], target["path"], interpolation,
                                  [row[0] for row in IO.accessor(rig.doc, rig.binary, sampler["input"])],
                                  IO.accessor(rig.doc, rig.binary, sampler["output"])))

    def sample(self, seconds):
        from mathutils import Matrix, Quaternion, Vector
        transforms = {i: list(matrix.decompose()) for i, matrix in enumerate(self.rig.locals)}
        for index, kind, interpolation, times, values in self.channels:
            right = min(len(times) - 1, bisect.bisect_right(times, seconds))
            left = max(0, right - 1)
            mix = 0 if right == left or interpolation == "STEP" else max(0, min(1, (seconds - times[left]) / (times[right] - times[left])))
            a, b = values[left], values[right]
            if kind == "rotation":
                transforms[index][1] = Quaternion((a[3], *a[:3])).slerp(Quaternion((b[3], *b[:3])), mix).normalized()
            else:
                transforms[index][0 if kind == "translation" else 2] = Vector(a).lerp(Vector(b), mix)
        return self.rig.world([Matrix.LocRotScale(*transforms[i]) for i in range(len(self.rig.nodes))])


def transfer_setup(source, target):
    from mathutils import Vector
    corrections = {}
    for target_name, source_name in MAPPING.items():
        target_q = target.rest[target.ids[target_name]].to_quaternion()
        source_q = source.rest[source.ids[source_name]].to_quaternion()
        target_axis = target_q @ Vector((0, 1, 0))
        source_axis = source_q @ Vector((0, 1, 0))
        calibrated = target_axis.rotation_difference(source_axis) @ target_q
        corrections[target_name] = source_q.inverted() @ calibrated
    return corrections


def forward(target, rotations, pelvis_position):
    from mathutils import Matrix, Vector
    worlds = [matrix.copy() for matrix in target.rest]
    for index in target.order:
        name = target.nodes[index]["name"]
        parent = target.parents.get(index)
        local = target.locals[index]
        location = worlds[parent] @ local.translation if parent is not None else local.translation.copy()
        if name == "DEF-pelvis":
            location = pelvis_position.copy()
        rotation = rotations.get(name)
        if rotation is None:
            rotation = (worlds[parent].to_quaternion() @ local.to_quaternion()) if parent is not None else local.to_quaternion()
        worlds[index] = Matrix.LocRotScale(location, rotation, Vector((1, 1, 1)))
    return worlds


def leg_solve(target, rotations, pelvis_position, worlds, side, ankle_goal, source_world, source):
    """Two rigid segments. No bone translation/scale/length is altered."""
    from mathutils import Vector
    names = [f"DEF-{part}.{side}" for part in ("thigh", "shin", "foot")]
    hip_i, knee_i, ankle_i = [target.ids[name] for name in names]
    hip = worlds[hip_i].translation
    upper = target.locals[knee_i].translation.length
    lower = target.locals[ankle_i].translation.length
    offset = ankle_goal - hip
    distance = max(abs(upper - lower) + .000001, min(upper + lower - .000001, offset.length))
    axis = offset.normalized()
    suffix = side.lower()
    source_hip, source_knee, source_ankle = [source_world[source.ids[f"{name}_{suffix}"]].translation for name in ("thigh", "calf", "foot")]
    source_axis = (source_ankle - source_hip).normalized()
    bend = source_knee - source_hip
    bend -= source_axis * bend.dot(source_axis)
    if bend.length < .00001:
        bend = Vector((0, 0, 1)) - source_axis * source_axis.z
    # Preserve the source knee's bend plane when a target has a wider native
    # stance; projecting its almost-straight shin onto a different axis can
    # otherwise invent an inward knee bend for Ryo/Rin.
    bend = source_axis.rotation_difference(axis) @ bend
    bend.normalize()
    along = (upper * upper + distance * distance - lower * lower) / (2 * distance)
    height = math.sqrt(max(0, upper * upper - along * along))
    knee = hip + axis * along + bend * height
    clamped_ankle = hip + axis * distance
    for index, child, goal_direction in ((hip_i, knee_i, knee - hip), (knee_i, ankle_i, clamped_ankle - knee)):
        name = target.nodes[index]["name"]
        q = rotations[name]
        actual_axis = q @ target.locals[child].translation
        rotations[name] = actual_axis.rotation_difference(goal_direction) @ q
    return forward(target, rotations, pelvis_position), (clamped_ankle - ankle_goal).length


def apron_adaptation(target, rotations, worlds):
    """Unmapped garment follows the actual thigh flexion, never shrinks a stride."""
    from mathutils import Quaternion, Vector
    pelvis_q = worlds[target.ids["DEF-pelvis"]].to_quaternion()
    rest_pelvis_q = target.rest[target.ids["DEF-pelvis"]].to_quaternion()
    right = pelvis_q @ Vector((1, 0, 0))
    anterior, posterior = 0.0, 0.0
    for side in ("L", "R"):
        hip = worlds[target.ids[f"DEF-thigh.{side}"]].translation
        knee = worlds[target.ids[f"DEF-shin.{side}"]].translation
        leg = pelvis_q.inverted() @ (knee - hip)
        angle = math.atan2(leg.z, -leg.y)
        anterior = max(anterior, angle)
        posterior = max(posterior, -angle)
    for name, angle in (("DEF-apron_front", -anterior), ("DEF-apron_back", posterior)):
        base = pelvis_q @ rest_pelvis_q.inverted() @ target.rest[target.ids[name]].to_quaternion()
        rotations[name] = Quaternion(right, angle) @ base


def transfer_clip(source, source_rm, target, corrections, scale, key, fps):
    from mathutils import Vector
    source_clip, loop = CLIPS[key]
    sample = ClipSampler(source, source_clip)
    sample_rm = ClipSampler(source_rm, source_clip)
    duration = sample.end - sample.start
    count = round(duration * fps)
    times = [duration * i / count for i in range(count + 1)]
    source_frames = [sample.sample(sample.start + time) for time in times]
    source_rm_frames = [sample_rm.sample(sample_rm.start + time) for time in times]
    # The source foot envelope comes from actual weighted source surface vertices.
    source_low = [{side: min(p.y for p in source.surfaces(world, side)) for side in ("L", "R")} for world in source_frames]
    # Ground belongs to the model's actual rest soles. The source animation can
    # briefly tunnel a toe below it; using the deepest animated vertex as floor
    # incorrectly excludes the ordinary flat-foot stance from support intervals.
    floor_reference = min(min(p.y for p in source.surfaces(source.rest, side)) for side in ("L", "R"))
    contact = [{side: frame[side] <= floor_reference + .025 for side in ("L", "R")} for frame in source_low]
    frames, observations, reachable_peak = [], [], 0.0
    source_pelvis_rest = source.rest[source.ids["pelvis"]].translation
    target_pelvis_rest = target.rest[target.ids["DEF-pelvis"]].translation
    for frame_index, source_world in enumerate(source_frames):
        rotations = {name: source_world[source.ids[source_name]].to_quaternion() @ corrections[name]
                     for name, source_name in MAPPING.items()}
        rotations["DEF-root"] = target.rest[target.ids["DEF-root"]].to_quaternion()
        pelvis = target_pelvis_rest + (source_world[source.ids["pelvis"]].translation - source_pelvis_rest) * scale
        world = forward(target, rotations, pelvis)
        goals = {}
        for side in ("L", "R"):
            foot = target.ids[f"DEF-foot.{side}"]
            source_foot = source.ids[f"foot_{side.lower()}"]
            goals[side] = target.rest[foot].translation + (source_world[source_foot].translation - source.rest[source_foot].translation) * scale
            world, residual = leg_solve(target, rotations, pelvis, world, side, goals[side], source_world, source)
            reachable_peak = max(reachable_peak, residual)
        # Measured shoe sole envelope, not ankle landmarks. During support, adapt
        # ankle height to the target shoe. Swing feet only receive penetration correction.
        for side in ("L", "R"):
            low = min(p.y for p in target.surfaces(world, side))
            if contact[frame_index][side] or low < .005:
                goals[side].y += .005 - low
                world, residual = leg_solve(target, rotations, pelvis, world, side, goals[side], source_world, source)
                reachable_peak = max(reachable_peak, residual)
        apron_adaptation(target, rotations, world)
        world = forward(target, rotations, pelvis)
        frames.append(world)
        sole = {side: target.surfaces(world, side) for side in ("L", "R")}
        observations.append({"time": times[frame_index], "source_contact_height_candidate": contact[frame_index],
                             "sole_min_y_m": {side: min(p.y for p in sole[side]) for side in ("L", "R")},
                             "ankles_world_m": {side: list(world[target.ids[f"DEF-foot.{side}"]].translation) for side in ("L", "R")}})
    root_start = source_rm_frames[0][source_rm.ids["root"]].translation
    root_end = source_rm_frames[-1][source_rm.ids["root"]].translation
    displacement = root_end - root_start
    stride = math.hypot(displacement.x, displacement.z) * scale
    tracks = {}
    for index in target.order:
        parent = target.parents.get(index)
        name = target.nodes[index]["name"]
        values = []
        previous = None
        for world in frames:
            local = world[parent].inverted() @ world[index] if parent is not None else world[index]
            location, quaternion, size = local.decompose()
            if previous is not None and quaternion.dot(previous) < 0:
                quaternion.negate()
            previous = quaternion.copy()
            values.append({"position": list(location), "rotation": [quaternion.x, quaternion.y, quaternion.z, quaternion.w], "scale": list(size)})
        tracks[name] = values
    seam = max((frames[0][i].translation - frames[-1][i].translation).length for i in target.order)
    angular_seam = max(frames[0][i].to_quaternion().rotation_difference(frames[-1][i].to_quaternion()).angle for i in target.order)
    contract = {"source_clip": source_clip, "length_seconds": duration, "loop": loop, "sample_rate_hz": fps,
                "samples": len(times), "root_motion": False, "authored_stride_m": stride,
                "authored_speed_mps": stride / duration, "source_rm_displacement_m": list(displacement),
                "translation_scale": scale, "bone_length_policy": "target rest lengths unchanged; no joint scale",
                "loop_seam_position_m": seam if loop else None, "loop_seam_angle_rad": angular_seam if loop else None,
                "max_unreachable_ankle_residual_m": reachable_peak,
                "source_rest_sole_floor_y_m": floor_reference,
                "source_animated_sole_min_y_m": min(min(frame.values()) for frame in source_low),
                "support_event_method": "candidate intervals from actual weighted source sole height <= measured source REST sole floor + 0.025m; not yet visually accepted stance events",
                "support_candidates": intervals(times, contact),
                "seat_alignment": "requires real seat adapter; source pelvis displacement retained" if key.startswith("sit_") else None,
                "review_status": "not_rendered"}
    return {"times": times, "tracks": tracks, "world_frames": frames, "contract": contract, "observations": observations}


def intervals(times, flags):
    result = {side: [] for side in ("L", "R")}
    for side in result:
        start = None
        for i, flag in enumerate(flags):
            if flag[side] and start is None:
                start = times[i]
            if start is not None and (not flag[side] or i == len(flags) - 1):
                result[side].append([start, times[i]])
                start = None
    return result


def floats(values):
    # Nine significant digits preserve the exported PackedFloat32 samples.
    return ", ".join(format(float(value), ".9g") for value in values)


def write_library(path, clips, skeleton_path):
    lines = [f'[gd_resource type="AnimationLibrary" load_steps={len(clips) + 1} format=3]', ""]
    for key, data in clips.items():
        contract = data["contract"]
        lines += [f'[sub_resource type="Animation" id="Animation_{key}"]', f'resource_name = "{key}"',
                  f'length = {contract["length_seconds"]:.9g}', f'loop_mode = {1 if contract["loop"] else 0}']
        index = 0
        for bone, values in data["tracks"].items():
            for kind, field in (("position_3d", "position"), ("rotation_3d", "rotation"), ("scale_3d", "scale")):
                packed = []
                for time, sample in zip(data["times"], values):
                    packed.extend([time, 1, *sample[field]])
                prefix = f"tracks/{index}"
                lines += [f'{prefix}/type = "{kind}"', f'{prefix}/imported = false', f'{prefix}/enabled = true',
                          f'{prefix}/path = NodePath("{skeleton_path}:{bone}")', f'{prefix}/interp = 1',
                          f'{prefix}/loop_wrap = true', f'{prefix}/keys = PackedFloat32Array({floats(packed)})']
                index += 1
        lines.append("")
    lines += ["[resource]", "_data = {"]
    lines += [f'&"{key}": SubResource("Animation_{key}")' + ("," if i < len(clips) - 1 else "") for i, key in enumerate(clips)]
    lines += ["}", ""]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines))


def curve_list(action):
    if hasattr(action, "layers"):
        return [curve for layer in action.layers for strip in layer.strips for bag in strip.channelbags for curve in bag.fcurves]
    return list(action.fcurves)


def bake_master(target_id, target, clips, fps, path):
    import bpy
    from mathutils import Matrix
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.scene.render.fps = fps
    bpy.ops.import_scene.gltf(filepath=str(target_path(target_id)), bone_heuristic="BLENDER", guess_original_bind_pose=False)
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise ValueError(f"Expected exactly one target armature, got {len(armatures)}")
    arm = armatures[0]
    arm.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    # glTF Y-up -> Blender Z-up, preserving +Z forward as Blender -Y.
    conversion = Matrix.Rotation(math.pi * .5, 4, "X")
    # Blender's bone display orientation can differ from the encoded GLB rest;
    # transfer the deformation (pose @ inverse_rest), not a guessed local Euler.
    blender_rest = {bone.name: arm.matrix_world @ bone.matrix_local for bone in arm.data.bones}
    for key, clip in clips.items():
        action = bpy.data.actions.new(key)
        action.use_fake_user = True
        action["loop"] = clip["contract"]["loop"]
        action["speed_mps"] = clip["contract"]["authored_speed_mps"]
        action["root_motion"] = False
        action["source_clip"] = clip["contract"]["source_clip"]
        arm.animation_data_create()
        arm.animation_data.action = action
        if hasattr(action, "slots"):
            arm.animation_data.action_slot = action.slots.new(id_type="OBJECT", name=arm.name)
        for time, world in zip(clip["times"], clip["world_frames"]):
            frame = time * fps
            bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
            desired_poses = {}
            for index in target.order:
                name = target.nodes[index]["name"]
                deformation = conversion @ (world[index] @ target.rest[index].inverted()) @ conversion.inverted()
                desired_poses[name] = arm.matrix_world.inverted() @ deformation @ blender_rest[name]
            for index in target.order:
                name = target.nodes[index]["name"]
                pose_bone = arm.pose.bones[name]
                bone = arm.data.bones[name]
                # Convert the complete intended parent pose explicitly. Depending
                # on stale depsgraph parent matrices causes order-dependent keys;
                # evaluating every skinned mesh once per bone is also needlessly slow.
                if bone.parent:
                    basis = bone.matrix_local.inverted() @ bone.parent.matrix_local @ desired_poses[bone.parent.name].inverted() @ desired_poses[name]
                else:
                    basis = bone.matrix_local.inverted() @ desired_poses[name]
                pose_bone.rotation_mode = "QUATERNION"
                pose_bone.matrix_basis = basis
                pose_bone.keyframe_insert("location", frame=frame, group=name)
                pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=name)
                pose_bone.keyframe_insert("scale", frame=frame, group=name)
        for curve in curve_list(action):
            for point in curve.keyframe_points:
                point.interpolation = "LINEAR"
    arm.animation_data.action = bpy.data.actions["idle"]
    if hasattr(arm.animation_data, "action_slot"):
        arm.animation_data.action_slot = arm.animation_data.action.slots[0]
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = max(round(clip["contract"]["length_seconds"] * fps) for clip in clips.values())
    bpy.context.scene.frame_set(0)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(path))


def run(args):
    targets = args.targets.split(",")
    if any(target not in TARGETS for target in targets) or len(set(targets)) != len(targets):
        raise ValueError("--targets must be a comma-separated subset of nagisa,ryo,rin")
    inspection = inspect(targets)
    if args.inspect_only:
        print("Foundation motion source/rest inspection written; no retarget/render tests executed.")
        return
    try:
        import bpy
        from mathutils import Matrix
    except ImportError as exc:
        raise RuntimeError("Transfer requires Blender; use --inspect-only for standard Python inspection") from exc
    source = RigData(SOURCE)
    source_rm = RigData(SOURCE_RM)
    for target_id in targets:
        target = RigData(target_path(target_id))
        corrections = transfer_setup(source, target)
        scale = inspection["targets"][target_id]["translation_scale"]
        clips = {key: transfer_clip(source, source_rm, target, corrections, scale, key, args.fps) for key in CLIPS}
        out = BUILD / target_id
        bake_master(target_id, target, clips, args.fps, out / f"{TARGETS[target_id][0]}_FoundationMotion.blend")
        write_library(RUNTIME / f"{target_id}.tres", clips, args.skeleton_path)
        contract = {"format": 1, "target": target_id, "target_input_identification": identity(target_path(target_id)),
                    "source": identity(SOURCE), "source_rm": identity(SOURCE_RM), "license": "CC0-1.0",
                    "license_file": "assets/motion-sources/quaternius/License.txt",
                    "authoring_units": "metres; glTF/Godot +Y up,+Z forward; Blender +Z up,-Y forward",
                    "animation_root_path": "existing target AnimationPlayer.get_root(); resolve in actor adapter",
                    "target_skeleton_relative_path": args.skeleton_path, "track_prefix": args.skeleton_path + ":",
                    "track_transform_convention": "Godot4 absolute parent-relative bone TRS, includes target rest",
                    "world_movement_owner": "ResidentMotor; clips have no root X/Z or root yaw displacement",
                    "mapping": MAPPING, "translation_scale": scale,
                    "contact_geometry": inspection["targets"][target_id]["contact_geometry"],
                    "geometry_policy": "No model output or mutation. Existing geometry/skin/rest/old9clips read-only.",
                    "unmapped_source_features": "three finger phalanges collapse to first proximal joint; no finger-chain fidelity claim",
                    "inferred_secondary_adaptation": "unmapped apron_front/back follows actual thigh flexion; visual garment review pending",
                    "missing_coverage": ["walk_start", "walk_stop", "turn_90", "turn_180"],
                    "clips": {key: clip["contract"] for key, clip in clips.items()},
                    "review_status": "retarget_baked_not_visually_accepted",
                    "tests": "No natural gait, foot-slip acceptance, seat alignment, source roundtrip or game integration established by generation."}
        write_json(RUNTIME / f"{target_id}.contract.json", contract)
        for key, clip in clips.items():
            write_json(out / f"{key}.samples.json", {"contract": clip["contract"], "frames": clip["observations"]})
        print(f"TRANSFER BAKED {target_id}: {len(clips)} clips; leg scale {scale:.6f}; visual review pending", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect-only", action="store_true")
    parser.add_argument("--targets", default="nagisa,ryo,rin")
    parser.add_argument("--fps", type=int, default=30, choices=(30, 60))
    parser.add_argument("--skeleton-path", default="Skeleton3D")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    args = parser.parse_args(argv)
    if any(character in args.skeleton_path for character in ('"', ":", "\n", "\r")) or not args.skeleton_path:
        parser.error("--skeleton-path must be a non-empty NodePath node portion")
    run(args)


if __name__ == "__main__":
    main()
