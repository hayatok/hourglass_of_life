"""Source-format checks; no animation, skin contact or natural-motion verdict."""
from pathlib import Path
import importlib.util
import math
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/motion-sources/cmu"
spec = importlib.util.spec_from_file_location("cmu_source", ROOT / "assets/motion-retarget/build/cmu_source.py")
cmu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cmu)


class CmuSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.asf = (SOURCE / "79.asf").read_text()
        cls.skeleton = cmu.parse_asf(cls.asf)
        cls.amc = (SOURCE / "79_13.amc").read_text()

    def test_calibrated_units_and_hierarchy(self):
        self.assertEqual(len(self.skeleton["bones"]), 30)
        # CMU documents .45-scaled inches, rather than metres or centimetres.
        self.assertAlmostEqual(self.skeleton["bones"]["lfemur"]["length_m"], .4134532977777778)
        self.assertEqual(self.skeleton["parents"]["lfemur"], "lhipjoint")

    def test_real_clips_complete(self):
        for name, count in [("79_10", 703), ("79_13", 664), ("79_23", 730), ("79_25", 603), ("79_42", 793)]:
            with self.subTest(name=name):
                clip = cmu.parse_amc((SOURCE / (name + ".amc")).read_text(), self.skeleton, 60)
                self.assertEqual(len(clip["frames"]), count)
                self.assertEqual(clip["fps"], 60)
                self.assertEqual(clip["seconds"], count / 60)
                self.assertNotIn("lfingers", clip["frames"][0]["rotation_channels_rad"])
                self.assertNotIn("rthumb", clip["frames"][0]["rotation_channels_rad"])

    def test_rotation_unit_is_radians(self):
        clip = cmu.parse_amc(self.amc, self.skeleton, 60)
        self.assertAlmostEqual(clip["frames"][0]["rotation_channels_rad"]["root"][0], math.radians(3.23727))
        self.assertAlmostEqual(clip["frames"][0]["root_translation_m"][1], 1.0562448888888888)

    def test_missing_body_channels_rejected(self):
        lines = self.amc.splitlines()
        del lines[next(i for i, line in enumerate(lines) if line.startswith("lhumerus "))]
        with self.assertRaises(ValueError):cmu.parse_amc("\n".join(lines), self.skeleton, 60)

    def test_wrong_channel_count_rejected(self):
        with self.assertRaises(ValueError):cmu.parse_amc(self.amc.replace("rradius 41.7793", "rradius 41.7793 0", 1), self.skeleton, 60)

    def test_nonfinite_and_missing_time_rejected(self):
        with self.assertRaises(ValueError):cmu.parse_amc(self.amc.replace("rradius 41.7793", "rradius nan", 1), self.skeleton, 60)
        with self.assertRaises(ValueError):cmu.parse_amc(self.amc, self.skeleton, 0)

    def test_disconnected_skeleton_rejected(self):
        with self.assertRaises(ValueError):cmu.parse_asf(self.asf.replace("lhipjoint lfemur", "lhipjoint", 1))


if __name__ == "__main__":unittest.main()
