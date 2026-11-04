"""Analytic FK/rotation-order checks and real CMU kinematic invariants.

No retarget, skin contact, captured fingers, floor plant or naturalness verdict.
"""
from pathlib import Path
import copy
import importlib.util
import math
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("cmu_kinematics", ROOT/"assets/motion-retarget/build/cmu_kinematics.py")
fk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fk)


def fixture(bones, root_origin=(0, 0, 0), root_orientation=(0, 0, 0)):
    """Pass a tiny calibrated ASF through the real source parser, not a mock."""
    lines = [":version 1.10", ":units", "mass 1", "length 0.0254", "angle deg", ":root", "order TX TY TZ RX RY RZ", "axis XYZ",
             "position "+" ".join(map(str, root_origin)), "orientation "+" ".join(map(str, root_orientation)), ":bonedata"]
    for index, bone in enumerate(bones):
        lines += ["begin", f"id {index+1}", "name "+bone["name"], "direction "+" ".join(map(str, bone.get("direction", (0, 1, 0)))),
                  f"length {bone.get('length', 1)}", "axis "+" ".join(map(str, bone.get("axis", (0, 0, 0))))+" XYZ"]
        if bone.get("dof"):lines += ["dof "+" ".join(bone["dof"])]
        lines += ["end"]
    lines += [":hierarchy", "begin"]
    parents = {}
    for bone in bones:parents.setdefault(bone.get("parent", "root"), []).append(bone["name"])
    lines += [parent+" "+" ".join(children) for parent, children in parents.items()]+["end"]
    return fk._source.parse_asf("\n".join(lines))


def frame(model, rotations=None, root_translation=(0, 0, 0), root_rotation=(0, 0, 0)):
    channels = {name: [0]*len(model.bones[name]["dof"]) for name in model.channel_names if name != "root"}
    channels["root"] = list(root_rotation)
    channels.update(rotations or {})
    return {"root_translation_m": list(root_translation), "rotation_channels_rad": channels}


def quaternion_rotate(q, vector):
    # Independent Hamilton sandwich: v' = v + 2*w*(qv cross v) +
    # 2*(qv cross (qv cross v)). No matrix or Euler helper from the solver.
    def cross(a, b):return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
    uv = cross(q[:3], vector);uuv = cross(q[:3], uv)
    return tuple(vector[i]+2*q[3]*uv[i]+2*uuv[i] for i in range(3))


class CmuKinematics(unittest.TestCase):
    def near(self, actual, expected, places=10):
        for a, b in zip(actual, expected):self.assertAlmostEqual(a, b, places=places)

    def test_cmu_axis_example_nonzero_calibration(self):
        # CMU 15-464 sceneGraph example: axis 0 90 0 takes local x to -z;
        # AMC -90 about that x is therefore +90 about original global z.
        model = fk.Kinematics(fixture([{"name": "head", "axis": (0, 90, 0), "dof": ["rx"]}]))
        result = model.solve_frame(frame(model, {"head": [-math.pi/2]}))
        self.near(result["bones"]["head"]["end_m"], (-1, 0, 0))
        self.near(quaternion_rotate(result["bones"]["head"]["world_delta_xyzw"], (0, 1, 0)), (-1, 0, 0))

    def test_noncommuting_dof_order_is_not_xyz_guess(self):
        values = []
        for order in [["rx", "ry"], ["ry", "rx"]]:
            model = fk.Kinematics(fixture([{"name": "arm", "direction": (0, 0, 1), "dof": order}]))
            values.append(model.solve_frame(frame(model, {"arm": [math.pi/2, math.pi/2]}))["bones"]["arm"]["end_m"])
        self.near(values[0], (0, -1, 0));self.near(values[1], (1, 0, 0))

    def test_xyz_calibration_itself_uses_fixed_axis_order(self):
        # C=Ry90*Rx90 carries calibrated z to -Y. A +90 local-z rotation
        # therefore carries global +X to +Z (the moving-axis reading does not).
        model = fk.Kinematics(fixture([{"name": "arm", "direction": (1, 0, 0), "axis": (90, 90, 0), "dof": ["rz"]}]))
        result = model.solve_frame(frame(model, {"arm": [math.pi/2]}))
        self.near(result["bones"]["arm"]["end_m"], (0, 0, 1))

    def test_rest_axes_are_not_applied_as_extra_parent_motion(self):
        model = fk.Kinematics(fixture([{"name": "a", "length": 2, "axis": (23, -37, 66), "dof": ["rx", "rz"]},
                                      {"name": "b", "parent": "a", "direction": (1, 0, 0), "axis": (12, 81, -22)}]))
        result = model.solve_rest()
        self.near(result["bones"]["a"]["start_m"], (0, 0, 0));self.near(result["bones"]["a"]["end_m"], (0, 2, 0))
        self.near(result["bones"]["b"]["end_m"], (1, 2, 0))
        self.near(result["bones"]["b"]["world_delta_xyzw"], (0, 0, 0, 1))
        self.assertNotEqual(result["bones"]["a"]["world_axis_xyzw"], result["bones"]["a"]["world_delta_xyzw"])

    def test_parent_endpoint_and_root_motion_are_accumulated_once(self):
        model = fk.Kinematics(fixture([{"name": "a", "axis": (0, 90, 0), "length": 2, "dof": ["rx"]},
                                      {"name": "b", "parent": "a", "axis": (37, -23, 61)},
                                      {"name": "branch", "direction": (1, 0, 0), "axis": (0, 0, 45)}], root_origin=(.5, 1, -.5)))
        result = model.solve_frame(frame(model, {"a": [-math.pi/2]}, root_translation=(1, 0, 0), root_rotation=(0, 0, math.pi/2)))
        self.near(result["root_position_m"], (1.5, 1, -.5))
        self.near(result["bones"]["a"]["end_m"], (1.5, -1, -.5))
        self.near(result["bones"]["b"]["end_m"], (1.5, -2, -.5))
        self.near(result["bones"]["branch"]["end_m"], (1.5, 2, -.5))

    def test_rotation_quaternions_survive_180_degree_branch(self):
        model = fk.Kinematics(fixture([{"name": "a", "dof": ["rx", "ry", "rz"]}]))
        for axis in range(3):
            for degrees in [0, 90, 179, 180, 181, 270]:
                angles = [0, 0, 0];angles[axis] = math.radians(degrees)
                result = model.solve_frame(frame(model, {"a": angles}))["bones"]["a"]
                self.near(quaternion_rotate(result["world_delta_xyzw"], (0, 1, 0)), result["end_m"])
                self.assertAlmostEqual(sum(x*x for x in result["world_delta_xyzw"]), 1, places=12)

    def test_clip_time_and_quaternion_hemisphere_are_continuous(self):
        model = fk.Kinematics(fixture([{"name": "a", "dof": ["ry"]}]))
        frames = [frame(model, {"a": [math.radians(y)]}, root_rotation=(0, math.radians(y), 0)) for y in [170, 179, 181, 190]]
        solved = model.solve_clip({"fps": 60, "frames": frames})
        self.assertEqual(solved["sample_span_s"], 3/60);self.assertEqual(solved["duration_s"], 4/60)
        self.assertEqual([f["source_frame"] for f in solved["frames"]], [1, 2, 3, 4])
        for a, b in zip(solved["frames"], solved["frames"][1:]):
            self.assertGreater(sum(x*y for x, y in zip(a["root_xyzw"], b["root_xyzw"])), 0)
            self.assertGreater(sum(x*y for x, y in zip(a["bones"]["a"]["world_delta_xyzw"], b["bones"]["a"]["world_delta_xyzw"])), 0)

    def test_uncaptured_finger_channels_never_change_reference_segments(self):
        model = fk.Kinematics(fixture([{"name": "wrist", "dof": ["rz"]},
                                      {"name": "lthumb", "parent": "wrist", "direction": (1, 0, 0), "dof": ["rx", "rz"]}]))
        initial = frame(model, {"wrist": [.3]});extra = copy.deepcopy(initial)
        extra["rotation_channels_rad"]["lthumb"] = [83, -27]
        self.assertEqual(model.solve_frame(initial), model.solve_frame(extra))
        self.assertEqual(model.solve_frame(initial)["bones"]["lthumb"]["motion_status"], "uncaptured_reference_only")

    def test_mutating_input_calibration_does_not_change_model(self):
        skeleton = fixture([{"name": "a", "axis": (0, 90, 0), "dof": ["rx"]}]);model = fk.Kinematics(skeleton)
        expected = model.solve_rest();skeleton["bones"]["a"]["length_m"] = 99;skeleton["parents"]["a"] = "a"
        self.assertEqual(model.solve_rest(), expected)

    def test_unsupported_or_invalid_input_rejected(self):
        with self.assertRaises(ValueError):fk.Kinematics(fixture([{"name": "a"}], root_orientation=(0, 90, 0)))
        model = fk.Kinematics(fixture([{"name": "a", "dof": ["rx"]}]))
        for bad in [frame(model, {"a": [math.nan]}), frame(model, {"a": []}), frame(model, root_translation=(0, math.inf, 0))]:
            with self.assertRaises(ValueError):model.solve_frame(bad)
        bad = frame(model);bad["rotation_channels_rad"].pop("a")
        with self.assertRaises(ValueError):model.solve_frame(bad)
        with self.assertRaises(ValueError):model.solve_clip({"fps": 0, "frames": [frame(model)]})

    def test_all_selected_source_frames_keep_calibrated_segment_and_hierarchy(self):
        source = ROOT/"assets/motion-sources/cmu"
        skeleton = fk._source.parse_asf((source/"79.asf").read_text());model = fk.Kinematics(skeleton)
        self.assertEqual(len(model.order), 30)
        for name in fk.CLIPS:
            clip = fk._source.parse_amc((source/(name+".amc")).read_text(), skeleton, 60)
            # All frames are evaluated: none silently drops a bone/channel.
            for index, original in enumerate(clip["frames"]):
                result = model.solve_frame(original)
                with self.subTest(clip=name, frame=index+1):
                    self.assertEqual(len(result["bones"]), 30)
                    for bone_name, bone in result["bones"].items():
                        start, end = bone["start_m"], bone["end_m"]
                        self.assertTrue(all(math.isfinite(x) for x in start+end+bone["world_delta_xyzw"]+bone["world_axis_xyzw"]))
                        self.assertAlmostEqual(math.dist(start, end), skeleton["bones"][bone_name]["length_m"], places=10)
                        self.near(start, result["root_position_m"] if bone["parent"] == "root" else result["bones"][bone["parent"]]["end_m"])
                        self.assertAlmostEqual(sum(x*x for x in bone["world_axis_xyzw"]), 1, places=11)
                        expected_offset = quaternion_rotate(bone["world_delta_xyzw"], model.offset[bone_name])
                        self.near(tuple(end[i]-start[i] for i in range(3)), expected_offset)


if __name__ == "__main__":unittest.main()
