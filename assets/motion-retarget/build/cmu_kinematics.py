"""Forward kinematics for the selected CMU/Vicon ASF/AMC subset (stdlib only).

Column vectors, right-handed source coordinates, metres, +Y up. ASF XYZ and
AMC rx/ry/rz mean successive fixed-axis rotations: Rz @ Ry @ Rx. For bone b,
C is its ASF calibration, M the ordered AMC rotations, D = C @ M @ C.T;
W_b = W_parent @ D; end_b = start_b + W_b @ (direction_b * length_b).
Calibration axes do NOT rotate a resting bone or leak into its children's
reference frames. Both the accumulated delta quaternion W and actual axis
orientation W @ C are exposed explicitly; they are different quantities.

Primary references (read 2026-11-05):
https://graphics.cs.cmu.edu/nsp/course/cs229/info/ACCLAIMdef.html
https://graphics.cs.cmu.edu/nsp/course/cs229/info/Acclaim_Skeleton_Format.html
https://graphics.cs.cmu.edu/nsp/course/15-464/Spring07/handouts/sceneGraph.pdf
http://mocap.cs.cmu.edu/info.php

This is CMU/Vicon, not a general Acclaim importer: nonzero preset root
orientation is rejected. Vicon explicitly sets it to zero to avoid vendor
ambiguity; subject 79 uses zero. Nonzero AMC root motion and nonzero calibrated
bone axes are fully evaluated. Uncaptured finger/thumb AMC channels are never
used. Their ASF segments are optional reference-only geometry, not finger
motion or evidence of hand/prop contact. No target rig, IK, smoothing, floor
correction, root locking, contact, frame omission or random process is added.
"""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import math
from pathlib import Path

_SOURCE_SPEC = importlib.util.spec_from_file_location("hourglass_cmu_source", Path(__file__).with_name("cmu_source.py"))
_source = importlib.util.module_from_spec(_SOURCE_SPEC)
_SOURCE_SPEC.loader.exec_module(_source)
UNCAPTURED = frozenset(_source.UNCAPTURED)
CLIPS = {"79_10": "chopping onions", "79_13": "mixing batter", "79_23": "putting on a jacket", "79_25": "moving heavy box", "79_42": "eating soup"}
IDENTITY = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
SCOPE = "Original CMU whole-body source kinematics only; no target retarget, captured fingers, prop contact, foot planting or natural-gameplay acceptance."


def vector3(value, name="vector"):
    if not isinstance(value, (list, tuple)) or len(value) != 3 or any(isinstance(x, bool) or not isinstance(x, (float, int)) or not math.isfinite(x) for x in value):
        raise ValueError(f"Invalid finite {name}")
    return tuple(float(x) for x in value)


def add(a, b):return tuple(x+y for x, y in zip(a, b))
def scale(a, value):return tuple(x*value for x in a)
def dot(a, b):return sum(x*y for x, y in zip(a, b))
def length(a):return math.sqrt(dot(a, a))
def transpose(matrix):return tuple(tuple(matrix[j][i] for j in range(3)) for i in range(3))
def multiply(a, b):return tuple(tuple(sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)) for i in range(3))
def rotate(matrix, value):return tuple(dot(row, value) for row in matrix)


def rotation_order(channels, angles_rad):
    """Apply listed rotations successively about fixed axes, not moving axes."""
    if len(channels) != len(angles_rad) or len(set(channels)) != len(channels):
        raise ValueError("Rotation channel/order mismatch")
    result = IDENTITY
    for channel, angle in zip(channels, angles_rad):
        if channel not in {"rx", "ry", "rz"} or isinstance(angle, bool) or not isinstance(angle, (float, int)) or not math.isfinite(angle):
            raise ValueError("Unsupported/nonfinite rotation channel")
        c, s = math.cos(angle), math.sin(angle)
        current = {"rx": ((1, 0, 0), (0, c, -s), (0, s, c)),
                   "ry": ((c, 0, s), (0, 1, 0), (-s, 0, c)),
                   "rz": ((c, -s, 0), (s, c, 0), (0, 0, 1))}[channel]
        result = multiply(current, result)
    return result


def quaternion_xyzw(matrix):
    """Unit active rotation quaternion for column vectors, in engine XYZW order."""
    trace = sum(matrix[i][i] for i in range(3))
    if trace > 0:
        s = 2*math.sqrt(max(0.0, trace+1))
        q = ((matrix[2][1]-matrix[1][2])/s, (matrix[0][2]-matrix[2][0])/s, (matrix[1][0]-matrix[0][1])/s, s/4)
    else:
        index = max(range(3), key=lambda i: matrix[i][i])
        j, k = (index+1) % 3, (index+2) % 3
        s = 2*math.sqrt(max(0.0, 1+matrix[index][index]-matrix[j][j]-matrix[k][k]))
        if s <= 1e-15:raise ValueError("Singular source rotation")
        values = [0.0]*4
        values[index] = s/4
        values[j] = (matrix[j][index]+matrix[index][j])/s
        values[k] = (matrix[k][index]+matrix[index][k])/s
        values[3] = (matrix[k][j]-matrix[j][k])/s
        q = tuple(values)
    q = scale(q, 1/length(q))
    return scale(q, -1) if q[3] < 0 else q


class Kinematics:
    def __init__(self, skeleton):
        # Own the calibration: callers may modify parser/fixture dictionaries.
        self.skeleton = copy.deepcopy(skeleton)
        root_orientation = vector3(skeleton["root_orientation_degrees"], "root orientation")
        if any(abs(x) > 1e-12 for x in root_orientation):
            raise ValueError("Nonzero preset root orientation is outside the CMU/Vicon zero-preset subset")
        self.root_origin = vector3(skeleton["root_origin_m"], "root position")
        if skeleton["root_axis"] != "XYZ" or skeleton["root_order"] != ["tx", "ty", "tz", "rx", "ry", "rz"]:
            raise ValueError("Unsupported CMU root axes/channels")
        self.bones = self.skeleton["bones"]
        self.parents = self.skeleton["parents"]
        if not self.bones or set(self.parents) != set(self.bones) or "root" in self.bones:
            raise ValueError("Invalid connected skeleton")
        self.order = []
        pending = list(self.bones)
        while pending:
            progress = [name for name in pending if self.parents[name] == "root" or self.parents[name] in self.order]
            if not progress:raise ValueError("Cyclic/disconnected skeleton")
            self.order.extend(progress)
            pending = [name for name in pending if name not in progress]
        self.axis = {};self.offset = {};self.direction_normalization = {}
        for name in self.order:
            bone = self.bones[name]
            if bone["axis_order"] != "XYZ":raise ValueError("Unsupported ASF axis order")
            degrees = vector3(bone["axis_degrees"], "ASF axis")
            self.axis[name] = rotation_order(["rx", "ry", "rz"], [math.radians(x) for x in degrees])
            direction = vector3(bone["direction"], "bone direction")
            norm = length(direction)
            size = bone["length_m"]
            if abs(norm-1) > .0001 or not isinstance(size, (float, int)) or isinstance(size, bool) or not math.isfinite(size) or size <= 0:
                raise ValueError("Invalid calibrated bone direction/length")
            # ASF directions are unit vectors printed at limited precision.
            # Normalize that rounding (recorded), retaining the stated length.
            self.offset[name] = scale(direction, size/norm)
            self.direction_normalization[name] = norm
            rotation_order(bone["dof"], [0.0]*len(bone["dof"]))
        self.channel_names = {name for name in self.order if self.bones[name]["dof"] and name not in UNCAPTURED} | {"root"}

    def solve_rest(self):
        """ASF zero-channel geometry; nonzero axes calibrate motion, not rest."""
        return self.solve_frame({"root_translation_m": [0, 0, 0],
                                 "rotation_channels_rad": {name: [0.0]*(3 if name == "root" else len(self.bones[name]["dof"])) for name in self.channel_names}})

    def solve_frame(self, frame):
        translation = vector3(frame["root_translation_m"], "AMC root translation")
        channels = frame["rotation_channels_rad"]
        # Ignore only the named uncaptured finger/thumb channels, even if a
        # caller supplies them. Any missing/unknown captured channel is an error.
        if not isinstance(channels, dict) or set(channels)-UNCAPTURED != self.channel_names:
            raise ValueError("Missing/extra captured channels")
        root_values = vector3(channels["root"], "AMC root rotation")
        root_rotation = rotation_order(["rx", "ry", "rz"], root_values)
        root_position = add(self.root_origin, translation)
        rotations = {"root": root_rotation};ends = {"root": root_position};records = {}
        for name in self.order:
            bone = self.bones[name];parent = self.parents[name]
            values = [0.0]*len(bone["dof"]) if name in UNCAPTURED or not bone["dof"] else channels[name]
            motion = rotation_order(bone["dof"], values)
            calibration = self.axis[name]
            local_delta = multiply(multiply(calibration, motion), transpose(calibration))
            world_delta = multiply(rotations[parent], local_delta)
            start = ends[parent];end = add(start, rotate(world_delta, self.offset[name]))
            rotations[name] = world_delta;ends[name] = end
            records[name] = {"parent": parent, "start_m": start, "end_m": end,
                             "world_delta_xyzw": quaternion_xyzw(world_delta),
                             "world_axis_xyzw": quaternion_xyzw(multiply(world_delta, calibration)),
                             "local_delta_xyzw": quaternion_xyzw(local_delta),
                             "motion_status": "uncaptured_reference_only" if name in UNCAPTURED else "captured_rotation" if bone["dof"] else "calibrated_fixed_offset"}
        return {"root_position_m": root_position, "root_xyzw": quaternion_xyzw(root_rotation), "bones": records}

    def solve_clip(self, clip):
        fps = clip["fps"]
        if isinstance(fps, bool) or not isinstance(fps, (float, int)) or not math.isfinite(fps) or fps <= 0 or not clip["frames"]:
            raise ValueError("Finite positive frame rate and frames required")
        frames = [];previous = None
        for index, original in enumerate(clip["frames"]):
            frame = self.solve_frame(original)
            if previous is not None:
                frame["root_xyzw"] = _continuous(frame["root_xyzw"], previous["root_xyzw"])
                for name in self.order:
                    for key in ["world_delta_xyzw", "world_axis_xyzw", "local_delta_xyzw"]:
                        frame["bones"][name][key] = _continuous(frame["bones"][name][key], previous["bones"][name][key])
            frame["source_frame"] = index+1;frame["time_s"] = index/fps
            frames.append(frame);previous = frame
        return {"fps": fps, "duration_s": len(frames)/fps, "sample_span_s": (len(frames)-1)/fps, "frames": frames}


def _continuous(quaternion, previous):return scale(quaternion, -1) if dot(quaternion, previous) < 0 else quaternion


def pack_frame(model, frame):
    return {"source_frame": frame.get("source_frame", 0), "time_s": frame.get("time_s", 0),
            "root_m": frame["root_position_m"], "root_xyzw": frame["root_xyzw"],
            "starts_m": [frame["bones"][name]["start_m"] for name in model.order],
            "ends_m": [frame["bones"][name]["end_m"] for name in model.order],
            "world_delta_xyzw": [frame["bones"][name]["world_delta_xyzw"] for name in model.order],
            "world_axis_xyzw": [frame["bones"][name]["world_axis_xyzw"] for name in model.order]}


def source_review(source: Path):
    skeleton = _source.parse_asf((source/"79.asf").read_text())
    model = Kinematics(skeleton)
    clips = {}
    for name, description in CLIPS.items():
        original = _source.parse_amc((source/(name+".amc")).read_text(), skeleton, 60)
        solved = model.solve_clip(original)
        bbox_min = [math.inf]*3; bbox_max = [-math.inf]*3
        min_foot = math.inf;max_foot = -math.inf
        for frame in solved["frames"]:
            for name_bone, bone in frame["bones"].items():
                if name_bone in UNCAPTURED:continue
                for point in [bone["start_m"], bone["end_m"]]:
                    for axis in range(3):bbox_min[axis] = min(bbox_min[axis], point[axis]);bbox_max[axis] = max(bbox_max[axis], point[axis])
                if name_bone in {"lfoot", "rfoot", "ltoes", "rtoes"}:
                    min_foot = min(min_foot, bone["end_m"][1]);max_foot = max(max_foot, bone["end_m"][1])
        clips[name] = {"description": description, "fps": solved["fps"], "duration_s": solved["duration_s"], "sample_span_s": solved["sample_span_s"],
                       "frame_count": len(solved["frames"]), "bounds_m": {"min": bbox_min, "max": bbox_max}, "foot_tip_y_range_m": [min_foot, max_foot],
                       "frames": [pack_frame(model, frame) for frame in solved["frames"]]}
    return {"schema": 1, "scope": SCOPE, "coordinates": "right handed +Y up, source axes retained; metres; quaternion XYZW; fixed-axis XYZ",
            "equations": "C=Rz(axis.z)*Ry(axis.y)*Rx(axis.x); M=ordered fixed-axis AMC; D=C*M*C^-1; W=parent.W*D; tip=start+W*normalized(direction)*length",
            "source_files": [str(source/"79.asf")]+[str(source/(key+".amc")) for key in CLIPS],
            "references": ["http://mocap.cs.cmu.edu/info.php", "https://graphics.cs.cmu.edu/nsp/course/cs229/info/ACCLAIMdef.html", "https://graphics.cs.cmu.edu/nsp/course/15-464/Spring07/handouts/sceneGraph.pdf"],
            "attribution": "The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217.",
            "unsupported": ["nonzero preset root orientation", "bone translation/stretch DOFs", "non-XYZ ASF calibration", "uncaptured fingers/thumb motion", "prop trajectories/contact"],
            "bone_order": model.order, "parents": [model.parents[name] for name in model.order],
            "lengths_m": [model.bones[name]["length_m"] for name in model.order],
            "uncaptured_reference_only": sorted(UNCAPTURED), "direction_input_norms": model.direction_normalization,
            "rest": pack_frame(model, model.solve_rest()), "clips": clips}


def main(argv=None):
    root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=root/"assets/motion-sources/cmu")
    parser.add_argument("--output", type=Path, default=root/"builds/cmu-source-review/source-motion.json")
    args = parser.parse_args(argv)
    report = source_review(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, separators=(",", ":"), allow_nan=False)+"\n")
    print(json.dumps({"scope": SCOPE, "bones": len(report["bone_order"]), "output": str(args.output), "clips": {name: {key: clip[key] for key in ["frame_count", "fps", "duration_s", "bounds_m", "foot_tip_y_range_m"]} for name, clip in report["clips"].items()}}, indent=2))


if __name__ == "__main__":main()
