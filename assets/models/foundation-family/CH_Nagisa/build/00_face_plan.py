"""Register face construction landmarks on the supplied front/profile pixels.

CPU/Pillow only. These are uncertain reference measurements, not mesh-fit proof.
The original reference and its existing body calibration remain unchanged.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "ref/turnaround-v1.png"
SCALE = 1.65 / 975
GROUND = 989

# Source-sheet pixels, read from the front/profile head at 4x. The source is an
# approximate orthographic AI sheet; eyelash/hair edges are not skin landmarks.
FRONT_IMAGE_SIDES = {
    "hair_crown": (318, 14), "hair_part": (332, 27),
    "brow_outer.L": (286, 88), "brow_peak.L": (298, 84), "brow_inner.L": (307, 87),
    "brow_inner.R": (334, 87), "brow_peak.R": (344, 84), "brow_outer.R": (356, 88),
    "eye_outer.L": (282, 106), "eye_upper.L": (298, 95), "eye_inner.L": (309, 106),
    "eye_lower.L": (298, 118), "pupil.L": (298, 107),
    "eye_inner.R": (332, 106), "eye_upper.R": (343, 95), "eye_outer.R": (359, 106),
    "eye_lower.R": (343, 118), "pupil.R": (343, 107),
    "nose_root": (320, 114), "nose_tip": (320, 128),
    "nose_wing.L": (315, 130), "nose_wing.R": (325, 130),
    "mouth_corner.L": (308, 141), "lip_upper": (320, 141), "mouth_seam": (320, 143),
    "lip_lower": (320, 146), "mouth_corner.R": (333, 141),
    "cheek.L": (284, 130), "jaw.L": (295, 154), "chin": (320, 164),
    "jaw.R": (345, 154), "cheek.R": (357, 130),
    "temple_skin.L": (280, 113), "temple_skin.R": (361, 113),
    "ear_inner.L": (273, 122), "ear_inner.R": (368, 121),
    "neck_front_midline": (320, 181),
}
# The list above is transcribed in image-left/right order. Published suffixes
# use the delivery rig's anatomical convention: L is +X, image-right in front.
FRONT = {
    (name[:-2] + (".R" if name.endswith(".L") else ".L") if name.endswith((".L", ".R")) else name): point
    for name, point in FRONT_IMAGE_SIDES.items()
}
PROFILE = {
    "hair_crown": (755, 13), "hair_back_high": (686, 65), "hair_back_mid": (662, 119),
    "hair_nape": (728, 171), "forehead_visible": (808, 80),
    "brow_ridge": (805, 85), "eye_upper": (799, 96), "pupil": (796, 107),
    "eye_lower": (796, 117), "nose_root": (808, 113), "nose_bridge": (814, 119),
    "nose_tip": (818, 126), "nose_under": (813, 132), "philtrum": (810, 137),
    "lip_upper": (810, 141), "mouth_seam": (808, 143), "lip_lower": (806, 147),
    "chin_front": (800, 157), "chin": (796, 163), "jaw_under": (782, 161),
    "ear_upper": (758, 112), "ear_inner": (757, 122), "ear_lobe": (760, 132),
    "neck_front": (779, 179), "neck_back": (742, 176),
}
VIEWS = {
    "front": {"points": FRONT, "axis_source_x": 318, "crop": (235, 0, 408, 185)},
    "side": {"points": PROFILE, "axis_source_x": 746, "crop": (650, 0, 835, 185)},
}


def main():
    image = Image.open(REFERENCE).convert("RGB")
    if image.size != (1536, 1024):
        raise ValueError("Reference changed; do not silently reuse the pixel registration")
    report = {
        "status": "manually_registered_source_landmarks_not_mesh_fit",
        "reference": "ref/turnaround-v1.png", "height_m": 1.65, "heads": 6.5,
        "metres_per_source_pixel": SCALE, "landmark_uncertainty_px": [2, 4],
        "axes": "Blender +Z up,-Y forward,+X anatomical left",
        "views": {}, "mesh_fit": "not run; silhouette blockout gate must pass before forms",
        "notes": [
            "Visible iris/pupil registration refines the older broad eye-centre marker; the body calibration is not changed.",
            "Unknown depth in front and lateral coordinate in profile are kept null, not invented.",
            "Front/profile smile and hair occlusion differ; compare per-view residuals against the stated uncertainty.",
            "Actual eyes/lids/lips require geometry and close rendered overlays; landmark count alone is not quality proof.",
            "Published .L/.R suffixes are anatomical: L is +X/image-right in the front view.",
        ],
    }
    for name, view in VIEWS.items():
        crop = image.crop(view["crop"])
        canvas = crop.resize((crop.width * 4, crop.height * 4))
        draw = ImageDraw.Draw(canvas)
        rows = []
        for number, (feature, (x, y)) in enumerate(view["points"].items(), 1):
            lateral = (x - view["axis_source_x"]) * SCALE
            projection = [lateral, None, (GROUND - y) * SCALE] if name == "front" else [None, -lateral, (GROUND - y) * SCALE]
            obscured = feature in {"neck_front", "neck_front_midline", "temple_skin.L", "temple_skin.R"}
            rows.append({"index": number, "feature": feature, "source_px": [x, y], "world_projection_m": projection,
                         "use_for_skin_fit": not obscured and not feature.startswith("hair_"),
                         "visibility": "partly occluded; construction guide only" if obscured else "visible reference feature",
                         "uncertainty_px": 4 if obscured or feature.startswith("hair_") else 2})
            cx, cy = (x - view["crop"][0]) * 4, (y - view["crop"][1]) * 4
            draw.ellipse((cx - 3, cy - 3, cx + 3, cy + 3), fill=(25, 128, 205))
            draw.text((cx + 5, cy - 5), str(number), fill=(15, 80, 150))
        report["views"][name] = {"crop": list(view["crop"]), "axis_source_x": view["axis_source_x"], "landmarks": rows}
        canvas.save(ROOT / f"review/face-{name}-landmarks.png")
    (ROOT / "ref/face-landmarks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Registered {len(FRONT)} front and {len(PROFILE)} profile source landmarks; mesh fitting and face acceptance pending")


if __name__ == "__main__":
    main()
