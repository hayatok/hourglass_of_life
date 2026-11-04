"""Numeric animation candidate contracts on the three actual existing skins.

No native import, body appearance, floor, cloth or real grasp acceptance.
"""
from pathlib import Path
import copy
import importlib.util
import math
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("cmu_retarget", ROOT/"assets/motion-retarget/build/03_retarget_cmu.py")
r = importlib.util.module_from_spec(spec);spec.loader.exec_module(r)


class CmuRetarget(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = ROOT/"assets/motion-sources/cmu"
        cls.model = r.fk.Kinematics(r.fk._source.parse_asf((path/"79.asf").read_text()))
        cls.originals = {key: r.fk._source.parse_amc((path/(name+".amc")).read_text(), cls.model.skeleton, 60) for key, name in r.CLIPS.items()}
        cls.rigs = {key: r.TargetRig(ROOT/"game/assets/models"/key/(label+".glb")) for key, label in r.TARGETS.items()}

    def near(self, actual, expected, tolerance=1e-9):
        self.assertEqual(len(actual), len(expected))
        self.assertLessEqual(max(abs(a-b) for a, b in zip(actual, expected)), tolerance)

    def test_direction_alignment_handles_right_angle_and_antiparallel(self):
        self.near(r.qrotate(r.arc((0, 1, 0), (1, 0, 0)), (0, 1, 0)), (1, 0, 0))
        self.near(r.qrotate(r.arc((0, 1, 0), (0, -1, 0)), (0, 1, 0)), (0, -1, 0))

    def test_real_bind_offsets_and_direction_calibration(self):
        rest = self.model.solve_rest()
        for ident, rig in self.rigs.items():
            with self.subTest(target=ident):
                self.assertEqual(len(rig.joints), 35);self.assertLess(rig.bind_error, .00005)
                result = r.Retarget(self.model, rig).solve(rest, rest)
                self.assertLess(result["max_direction_vector_error"], .00005)

    def test_all_three_people_and_clips_keep_actual_joint_offsets_scales_and_limbs(self):
        for ident, rig in self.rigs.items():
            transfer = r.Retarget(self.model, rig)
            for key, original in self.originals.items():
                first = self.model.solve_frame(original["frames"][0])
                for at in [0, len(original["frames"])//3, len(original["frames"])*2//3, len(original["frames"])-1]:
                    result = transfer.solve(self.model.solve_frame(original["frames"][at]), first)
                    with self.subTest(target=ident, clip=key, frame=at+1):
                        self.assertLess(result["max_direction_vector_error"], .00005)
                        for index in rig.joints:
                            name = rig.nodes[index]["name"]
                            local = result["local"][index]
                            self.assertEqual(local["scale"], rig.local[index]["scale"])
                            if name != "DEF-pelvis":self.assertEqual(local["position"], rig.local[index]["position"])
                            self.assertAlmostEqual(sum(x*x for x in local["rotation"]), 1, places=11)
                        for side in ["L", "R"]:
                            for a, b in [("upper_arm", "forearm"), ("forearm", "hand"), ("thigh", "shin"), ("shin", "foot")]:
                                i, j = rig.ids[f"DEF-{a}.{side}"], rig.ids[f"DEF-{b}.{side}"]
                                actual = math.dist(r.position(result["world"][i]), r.position(result["world"][j]))
                                original_length = math.dist(r.position(rig.rest[i]), r.position(rig.rest[j]))
                                self.assertAlmostEqual(actual, original_length, delta=.000002)
                        root = rig.ids["DEF-root"]
                        self.near(r.position(result["world"][root]), r.position(rig.rest[root]))

    def test_stationary_source_heading_removed_once_without_coordinate_reflection(self):
        original = self.originals["cmu_chop"]["frames"][0]
        poses = []
        for yaw in [0, math.pi/2]:
            channels = copy.deepcopy(original);channels["rotation_channels_rad"]["root"] = [0, yaw, 0]
            solved = self.model.solve_frame(channels)
            poses.append(r.Retarget(self.model, self.rigs["nagisa"]).solve(solved, solved))
        for index in self.rigs["nagisa"].joints:
            self.near(poses[0]["local"][index]["position"], poses[1]["local"][index]["position"])
            a, b = poses[0]["local"][index]["rotation"], poses[1]["local"][index]["rotation"]
            self.assertAlmostEqual(abs(sum(x*y for x, y in zip(a, b))), 1, places=10)

    def test_pelvis_relative_motion_remains_while_root_and_limb_offsets_stay_fixed(self):
        rig = self.rigs["ryo"];transfer = r.Retarget(self.model, rig)
        first = self.model.solve_frame(self.originals["cmu_mix"]["frames"][0]);later = copy.deepcopy(first)
        delta = (.10, .04, -.20)
        later["root_position_m"] = tuple(first["root_position_m"][i]+delta[i] for i in range(3))
        result = transfer.solve(later, first)
        yaw = result["first_heading_removed_rad"];c, s = math.cos(-yaw), math.sin(-yaw)
        expected = (c*delta[0]+s*delta[2], delta[1], -s*delta[0]+c*delta[2])
        expected = tuple(x*transfer.translation_scale for x in expected)
        self.near(result["pelvis_delta_m"], expected)
        self.near(r.position(result["world"][rig.ids["DEF-pelvis"]]), r.fk.add(r.position(rig.rest[rig.ids["DEF-pelvis"]]), expected), .000002)
        self.assertEqual(result["local"][rig.ids["DEF-root"]]["position"], rig.local[rig.ids["DEF-root"]]["position"])

    def test_forearm_includes_captured_wrist_pronation_without_changing_aim(self):
        raw = copy.deepcopy(self.originals["cmu_mix"]["frames"][0]);second = copy.deepcopy(raw)
        second["rotation_channels_rad"]["rwrist"][0] += .4
        first = self.model.solve_frame(raw);changed = self.model.solve_frame(second)
        rig = self.rigs["nagisa"];transfer = r.Retarget(self.model, rig)
        a, b = transfer.solve(first, first), transfer.solve(changed, first)
        index = rig.ids["DEF-forearm.R"]
        self.assertLess(abs(sum(x*y for x, y in zip(a["local"][index]["rotation"], b["local"][index]["rotation"]))), .99)
        self.near(a["source_directions"]["DEF-forearm.R"], b["source_directions"]["DEF-forearm.R"], .000001)

    def test_uncaptured_fingers_and_unmapped_cloth_keep_target_local_bind(self):
        original = self.originals["cmu_soup"]["frames"][330]
        source = self.model.solve_frame(original);first = self.model.solve_frame(self.originals["cmu_soup"]["frames"][0])
        for rig in self.rigs.values():
            result = r.Retarget(self.model, rig).solve(source, first)
            for index in rig.joints:
                name = rig.nodes[index]["name"]
                if name.startswith("DEF-finger") or name.startswith("DEF-apron"):
                    self.assertEqual(result["local"][index], rig.local[index])

    def test_candidate_time_and_phase_metadata_do_not_invent_contact(self):
        original = {"fps": 60, "frames": self.originals["cmu_chop"]["frames"][:4]}
        clip = r.generate_clip(self.model, self.rigs["rin"], original)
        self.assertEqual(clip["times"], [0, 1/60, 2/60, 3/60])
        self.assertEqual([f["source_frame"] for f in clip["observations"]], [1, 2, 3, 4])
        self.assertEqual([f["source_time_seconds"] for f in clip["observations"]], clip["times"])
        self.assertEqual(len(clip["tracks"]), 35)
        self.assertFalse(clip["contract"]["loop"]);self.assertFalse(clip["contract"]["root_motion"])
        self.assertFalse(clip["contract"]["contact_phases"]["contact_verified"])
        self.assertEqual(clip["contract"]["contact_phases"]["events"], [])
        for values in clip["tracks"].values():self.assertEqual(len(values), 4)


if __name__ == "__main__":unittest.main()
