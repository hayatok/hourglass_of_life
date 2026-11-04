"""CPU-only CMU whole-body candidates for existing DEF rigs; no runtime writes.

Run with ordinary Python. Outputs only to a builds/ staging directory. Original
models, animation libraries and providers remain untouched. Source and target
are both right-handed +Y-up metre coordinates. Only the first root heading is
removed once; no coordinate reflection, root locking per frame or body scaling.

A target bone's actual bind-to-child direction is aligned to the corresponding
ASF rest segment. Captured world-axis quaternions supply swing AND twist; a
composite neck/forearm receives the smallest additional swing needed to match
its true endpoint direction. Target local offsets/scales stay unchanged, while
pelvis displacement is relative to source frame 1 and scaled by leg length.
No captured sole/prop/finger contact is available in these ASF/AMC files. None
is invented here, and no foot IK or per-frame floor lift is baked.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def load_script(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


fk = load_script("cmu_candidate_fk", HERE/"cmu_kinematics.py")
io = load_script("cmu_candidate_glb", ROOT/"assets/motion-sources/quaternius/inspect_glb.py")
TARGETS = {"nagisa": "CH_Nagisa", "ryo": "CH_Ryo", "rin": "CH_Rin"}
CLIPS = {"cmu_chop": "79_10", "cmu_mix": "79_13", "cmu_soup": "79_42"}
# target: (source chain's first/last segment, target child defining the real
# longitudinal bind direction). A terminal uses its encoded bind +Y axis.
MAPPING = {
    "DEF-spine_01": ("lowerback", "lowerback", "DEF-spine_02"),
    "DEF-spine_02": ("upperback", "upperback", "DEF-chest"),
    "DEF-chest": ("thorax", "thorax", "DEF-neck"),
    "DEF-neck": ("lowerneck", "upperneck", "DEF-head"),
    "DEF-head": ("head", "head", None),
}
for side, short in [("L", "l"), ("R", "r")]:
    for target, first, last, child in [
        ("clavicle", "clavicle", "clavicle", "upper_arm"),
        ("upper_arm", "humerus", "humerus", "forearm"),
        ("forearm", "radius", "wrist", "hand"),
        ("hand", "hand", "hand", "finger2"),
        ("thigh", "femur", "femur", "shin"),
        ("shin", "tibia", "tibia", "foot"),
        ("foot", "foot", "foot", "toe"),
        ("toe", "toes", "toes", None),
    ]:MAPPING[f"DEF-{target}.{side}"] = (short+first, short+last, f"DEF-{child}.{side}" if child else None)


def sub(a, b):return tuple(x-y for x, y in zip(a, b))
def norm(v):
    size = fk.length(v)
    if size < 1e-12:raise ValueError("Zero retarget direction")
    return fk.scale(v, 1/size)
def cross(a, b):return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def qnorm(q):return norm(q)
def qinv(q):return (-q[0], -q[1], -q[2], q[3])
def qmul(a, b):
    x, y, z, w = a;u, v, s, t = b
    return (w*u+x*t+y*s-z*v, w*v-x*s+y*t+z*u, w*s+x*v-y*u+z*t, w*t-x*u-y*v-z*s)
def qrotate(q, vector):
    uv = cross(q[:3], vector);uuv = cross(q[:3], uv)
    return tuple(vector[i]+2*q[3]*uv[i]+2*uuv[i] for i in range(3))
def arc(a, b):
    a, b = norm(a), norm(b);d = max(-1.0, min(1.0, fk.dot(a, b)))
    if d < -.999999999:
        basis = min([(1, 0, 0), (0, 1, 0), (0, 0, 1)], key=lambda v: abs(fk.dot(a, v)))
        return (*norm(cross(a, basis)), 0.0)
    return qnorm((*cross(a, b), 1+d))


def rotation_from_matrix(matrix):
    x = norm(tuple(matrix[i][0] for i in range(3)))
    y0 = tuple(matrix[i][1] for i in range(3));y = norm(sub(y0, fk.scale(x, fk.dot(x, y0))))
    z = cross(x, y)
    if fk.dot(z, tuple(matrix[i][2] for i in range(3))) <= 0:raise ValueError("Mirrored bind axes are unsupported")
    return fk.quaternion_xyzw(tuple(tuple(column[row] for column in [x, y, z]) for row in range(3)))


def trs(location, q, size):
    x, y, z, w = q
    rotation = ((1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)),
                (2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)),
                (2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)))
    return [[rotation[r][c]*size[c] for c in range(3)]+[location[r]] for r in range(3)]+[[0, 0, 0, 1]]


def transform_point(matrix, point):return tuple(sum(matrix[r][c]*point[c] for c in range(3))+matrix[r][3] for r in range(3))
def position(matrix):return tuple(matrix[r][3] for r in range(3))
def inverse_affine_point(matrix, point):
    # Inverse of the actual parent linear transform, including its unchanged
    # encoded scale; this is only needed for the moving pelvis translation.
    a, b, c = [tuple(matrix[r][i] for r in range(3)) for i in range(3)]
    det = fk.dot(a, cross(b, c))
    if abs(det) < 1e-12:raise ValueError("Singular target parent")
    value = sub(point, position(matrix))
    return tuple(fk.dot(row, value)/det for row in [cross(b, c), cross(c, a), cross(a, b)])


class TargetRig:
    def __init__(self, path):
        self.path = Path(path);self.doc, self.binary = io.load_glb(self.path)
        if len(self.doc.get("skins", [])) != 1:raise ValueError("Exactly one target skin required")
        self.nodes = self.doc["nodes"];self.ids = {node["name"]: i for i, node in enumerate(self.nodes)}
        self.rest, self.parents = io.world_matrices(self.nodes)
        self.skin = self.doc["skins"][0];self.joints = list(self.skin["joints"])
        def depth(index):
            value = 0
            while index in self.parents:index = self.parents[index];value += 1
            return value
        self.order = sorted(range(len(self.nodes)), key=depth)
        required = set(MAPPING) | {"DEF-root", "DEF-pelvis"}
        if not required <= set(self.ids):raise ValueError("Missing required DEF target joints")
        self.local = []
        for node in self.nodes:
            if "matrix" in node:raise ValueError("Target matrix nodes need an explicit TRS decomposition; not guessed")
            self.local.append({"position": tuple(node.get("translation", [0, 0, 0])),
                               "rotation": qnorm(tuple(node.get("rotation", [0, 0, 0, 1]))),
                               "scale": tuple(node.get("scale", [1, 1, 1]))})
        self.bind_q = [rotation_from_matrix(matrix) for matrix in self.rest]
        self.bind_direction = {}
        for name, (_, _, child) in MAPPING.items():
            self.bind_direction[name] = norm(sub(position(self.rest[self.ids[child]]), position(self.rest[self.ids[name]]))) if child else qrotate(self.bind_q[self.ids[name]], (0, 1, 0))
        self.bind_direction["DEF-pelvis"] = norm(sub(position(self.rest[self.ids["DEF-spine_01"]]), position(self.rest[self.ids["DEF-pelvis"]])))
        self.bind_error = self._bind_error()
        if self.bind_error > .00005:raise ValueError("Target node rest disagrees with actual skin inverse bind")
        self.leg_m = 0.0
        for side in ["L", "R"]:
            points = [position(self.rest[self.ids[f"DEF-{part}.{side}"]]) for part in ["thigh", "shin", "foot"]]
            self.leg_m += (math.dist(points[0], points[1])+math.dist(points[1], points[2]))/2

    def _bind_error(self):
        binds = io.accessor(self.doc, self.binary, self.skin["inverseBindMatrices"])
        mesh_nodes = [i for i, node in enumerate(self.nodes) if node.get("skin") == 0 and "mesh" in node]
        error = 0.0
        for index, packed in zip(self.joints, binds):
            inverse = [[packed[c*4+r] for c in range(4)] for r in range(4)]
            product = io.multiply(self.rest[index], inverse)
            for mesh in mesh_nodes:error = max(error, max(abs(product[r][c]-self.rest[mesh][r][c]) for r in range(4) for c in range(4)))
        return error


def source_chain(frame, first, last):return norm(sub(frame["bones"][last]["end_m"], frame["bones"][first]["start_m"]))


class Retarget:
    def __init__(self, model, target):
        self.model = model;self.target = target;self.rest = model.solve_rest()
        source_leg = sum(model.bones[side+"femur"]["length_m"]+model.bones[side+"tibia"]["length_m"] for side in ["l", "r"])/2
        self.translation_scale = target.leg_m/source_leg
        self.rest_dir = {};self.calibration = {}
        for name, (first, last, _) in MAPPING.items():
            self.rest_dir[name] = source_chain(self.rest, first, last)
            self.calibration[name] = qmul(arc(target.bind_direction[name], self.rest_dir[name]), target.bind_q[target.ids[name]])
        self.calibration["DEF-pelvis"] = qmul(arc(target.bind_direction["DEF-pelvis"], (0, 1, 0)), target.bind_q[target.ids["DEF-pelvis"]])

    def solve(self, frame, first_frame):
        forward = qrotate(first_frame["root_xyzw"], (0, 0, 1))
        yaw = math.atan2(forward[0], forward[2]);align = (0, math.sin(-yaw/2), 0, math.cos(-yaw/2))
        desired = {};directions = {}
        for name, (first, last, _) in MAPPING.items():
            # Recover captured world delta from the actual ASF axis frame,
            # rather than treating a calibrated joint quaternion as a bone aim.
            delta = qmul(frame["bones"][last]["world_axis_xyzw"], qinv(self.rest["bones"][last]["world_axis_xyzw"]))
            direction = source_chain(frame, first, last)
            swing = arc(qrotate(delta, self.rest_dir[name]), direction)
            delta = qnorm(qmul(swing, delta))
            desired[name] = qnorm(qmul(qmul(align, delta), self.calibration[name]))
            directions[name] = qrotate(align, direction)
        desired["DEF-pelvis"] = qnorm(qmul(qmul(align, frame["root_xyzw"]), self.calibration["DEF-pelvis"]))
        pelvis_delta = fk.scale(qrotate(align, sub(frame["root_position_m"], first_frame["root_position_m"])), self.translation_scale)
        pelvis = fk.add(position(self.target.rest[self.target.ids["DEF-pelvis"]]), pelvis_delta)
        locals_out = [];worlds = [None]*len(self.target.nodes);world_q = [None]*len(self.target.nodes)
        for index in self.target.order:
            name = self.target.nodes[index]["name"];parent = self.target.parents.get(index)
            original = self.target.local[index]
            parent_q = world_q[parent] if parent is not None else (0, 0, 0, 1)
            q = qnorm(qmul(qinv(parent_q), desired[name])) if name in desired else original["rotation"]
            location = inverse_affine_point(worlds[parent], pelvis) if name == "DEF-pelvis" and parent is not None else pelvis if name == "DEF-pelvis" else original["position"]
            local = {"position": location, "rotation": q, "scale": original["scale"]}
            while len(locals_out) <= index:locals_out.append(None)
            locals_out[index] = local
            matrix = trs(location, q, original["scale"])
            worlds[index] = io.multiply(worlds[parent], matrix) if parent is not None else matrix
            world_q[index] = qnorm(qmul(parent_q, q))
        error = 0.0
        for name, (_, _, child) in MAPPING.items():
            actual = norm(sub(position(worlds[self.target.ids[child]]), position(worlds[self.target.ids[name]]))) if child else norm(tuple(worlds[self.target.ids[name]][r][1] for r in range(3)))
            error = max(error, math.dist(actual, directions[name]))
        return {"local": locals_out, "world": worlds, "pelvis_delta_m": pelvis_delta, "source_directions": directions, "max_direction_vector_error": error, "first_heading_removed_rad": yaw}


def generate_clip(model, rig, original):
    source = model.solve_clip(original);retarget = Retarget(model, rig)
    first = source["frames"][0];tracks = {rig.nodes[index]["name"]: [] for index in rig.joints};observations = []
    previous = {};max_error = 0.0
    for frame in source["frames"]:
        result = retarget.solve(frame, first);max_error = max(max_error, result["max_direction_vector_error"])
        for index in rig.joints:
            name = rig.nodes[index]["name"];value = result["local"][index].copy()
            if name in previous and fk.dot(previous[name], value["rotation"]) < 0:value["rotation"] = fk.scale(value["rotation"], -1)
            previous[name] = value["rotation"];tracks[name].append(value)
        observations.append({"source_frame": frame["source_frame"], "source_time_seconds": frame["time_s"], "pelvis_relative_m": result["pelvis_delta_m"],
                             "target_ankle_joint_m": {side: position(result["world"][rig.ids[f"DEF-foot.{side}"]]) for side in ["L", "R"]},
                             "target_hand_joint_m": {side: position(result["world"][rig.ids[f"DEF-hand.{side}"]]) for side in ["L", "R"]}})
    return {"times": [frame["time_s"] for frame in source["frames"]], "tracks": tracks, "observations": observations,
            "contract": {"length_seconds": source["duration_s"], "sample_span_seconds": source["sample_span_s"], "loop": False, "sample_rate_hz": source["fps"], "samples": len(source["frames"]),
                         "root_motion": False, "pelvis_relative_motion": True, "first_heading_removed_rad": retarget.solve(first, first)["first_heading_removed_rad"],
                         "pelvis_translation_scale": retarget.translation_scale, "max_direction_vector_error": max_error,
                         "contact_phases": {"annotation_status": "source motion only; no measured tool/prop/sole contact", "source_frame_1_time_seconds": 0, "events": [], "contact_verified": False},
                         "hand_roll_calibration": "Target bind roll retained after longitudinal alignment; CMU has no captured skin palm landmark. Anatomical palm/prop alignment requires native review and actual target hand contacts.",
                         "bone_policy": "Original target local joint translations/scales retained exactly; only pelvis translation and bone rotation animate. No frame-wide/body scale, no floor IK or surface-height guessing.",
                         "unmapped_bones": "Target fingers/cloth/socket locals retained from bind; they follow their parent. No uncaptured CMU finger/thumb animation transferred."}}


def write_library(path, clips):
    def values(items):return ", ".join(format(float(value), ".9g") for value in items)
    lines = [f'[gd_resource type="AnimationLibrary" load_steps={len(clips)+1} format=3]', ""]
    for key, clip in clips.items():
        lines += [f'[sub_resource type="Animation" id="Animation_{key}"]', f'resource_name = "{key}"', f'length = {clip["contract"]["length_seconds"]:.9g}', 'loop_mode = 0']
        index = 0
        for name, samples in clip["tracks"].items():
            for kind, field in [("position_3d", "position"), ("rotation_3d", "rotation"), ("scale_3d", "scale")]:
                packed = []
                for at, sample in zip(clip["times"], samples):packed.extend([at, 1, *sample[field]])
                prefix = f"tracks/{index}"
                lines += [f'{prefix}/type = "{kind}"', f'{prefix}/imported = false', f'{prefix}/enabled = true', f'{prefix}/path = NodePath("Skeleton3D:{name}")',
                          f'{prefix}/interp = 1', f'{prefix}/loop_wrap = false', f'{prefix}/keys = PackedFloat32Array({values(packed)})']
                index += 1
        lines.append("")
    lines += ['[resource]', '_data = {']+[f'&"{key}": SubResource("Animation_{key}")'+("," if i<len(clips)-1 else "") for i, key in enumerate(clips)]+['}', '']
    path.write_text("\n".join(lines))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--targets", default="nagisa,ryo,rin")
    parser.add_argument("--output", type=Path, default=ROOT/"builds/motion-retarget/cmu")
    args = parser.parse_args(argv);targets = args.targets.split(",")
    if len(set(targets)) != len(targets) or any(key not in TARGETS for key in targets):parser.error("Unique existing target IDs required")
    output = args.output.resolve()
    if not output.is_relative_to((ROOT/"builds").resolve()):parser.error("Candidate output must remain under this repository's builds/")
    source = ROOT/"assets/motion-sources/cmu";skeleton = fk._source.parse_asf((source/"79.asf").read_text());model = fk.Kinematics(skeleton)
    originals = {key: fk._source.parse_amc((source/(name+".amc")).read_text(), skeleton, 60) for key, name in CLIPS.items()}
    summaries = {}
    for ident in targets:
        rig = TargetRig(ROOT/"game/assets/models"/ident/(TARGETS[ident]+".glb"))
        clips = {key: generate_clip(model, rig, originals[key]) for key in CLIPS}
        directory = output/ident;directory.mkdir(parents=True, exist_ok=True)
        write_library(directory/"candidate.tres", clips)
        contract = {"format": 1, "target": ident, "status": "numeric_candidate; native reimport/body motion/skin contact/cloth review pending",
                    "source": "assets/motion-sources/cmu/79.asf + selected AMC", "license": "CMU database terms; incorporation allowed, original data sale prohibited; not CC0",
                    "license_reference": "assets/motion-sources/cmu/README.md", "attribution": "The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217.",
                    "target_input": str(rig.path.relative_to(ROOT)), "skin_bind_count": len(rig.joints), "bind_rest_vs_mesh_max_component_error": rig.bind_error,
                    "coordinates": "Source and target right-handed +Y up metres. Constant initial source heading removed once. No axis reflection or per-frame root lock.",
                    "track_transform_convention": "Godot absolute parent-relative local TRS; original target offsets/scales retained", "world_transform_owner": "ResidentMotor; DEF-root fixed to target rest, relative pelvis motion only",
                    "source_mapping": MAPPING, "clips": {key: {"source_clip": CLIPS[key], **clip["contract"]} for key, clip in clips.items()}}
        (directory/"candidate.contract.json").write_text(json.dumps(contract, indent=2, allow_nan=False)+"\n")
        for key, clip in clips.items():(directory/(key+".samples.json")).write_text(json.dumps({"scope": "Kinematic observations, not contact events", "frames": clip["observations"]}, separators=(",", ":"), allow_nan=False)+"\n")
        summaries[ident] = {"binds": len(rig.joints), "translation_scale": clips["cmu_chop"]["contract"]["pelvis_translation_scale"],
                            "clips": {key: {"source": CLIPS[key], "samples": clip["contract"]["samples"], "max_direction_vector_error": clip["contract"]["max_direction_vector_error"]} for key, clip in clips.items()}}
        print("CMU candidate staged:", ident, "(no runtime/model/provider changes)", flush=True)
    (output/"summary.json").write_text(json.dumps({"scope": "Numeric animation candidates only; native reimport and full-body/contact review pending", "targets": summaries}, indent=2, allow_nan=False)+"\n")


if __name__ == "__main__":main()
