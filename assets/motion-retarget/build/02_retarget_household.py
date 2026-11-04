"""Animation-only household source transfer; old models and seven clips stay read-only.

Standard Python: python3 THIS --inspect-only --targets nagisa,ryo,rin
Coordinated heavy slot only: Blender --background --factory-startup --python THIS -- --targets nagisa
"""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BUILD = ROOT / "builds/motion-retarget/household"
RUNTIME = ROOT / "game/assets/motion/household"
CLIPS = {
    "pickup_table": ("PickUp_Table", False),
    "interact": ("Interact", False),
    "fixing_kneeling": ("Fixing_Kneeling", False),
    "push_loop": ("Push_Loop", True),
}
MISSING = ["two_hand_carry", "food_preparation", "stir_pot", "eat_with_utensil", "wash_dish", "fold_laundry", "write_notebook"]


def load_transfer():
    spec = importlib.util.spec_from_file_location("household_foundation_transfer", HERE / "01_retarget_foundation.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.CLIPS = CLIPS
    module.BUILD = BUILD
    return module


def run(args):
    transfer = load_transfer()
    targets = args.targets.split(",")
    if len(set(targets)) != len(targets) or any(target not in transfer.TARGETS for target in targets):
        raise ValueError("--targets must contain unique nagisa,ryo,rin IDs")
    inspection = transfer.inspect(targets)
    inspection["scope"] = "Encoded source clips/rest/weights only; no natural-household-action acceptance."
    inspection["missing_source_coverage"] = MISSING
    inspection["action_semantics"] = {
        "pickup_table": "Actual table reach/pick source, to be adapted to the real prop and support height.",
        "interact": "Actual generic interaction source; not a cooking/washing/writing clip.",
        "fixing_kneeling": "Actual kneeling repair source; not enabled as standing table work.",
        "push_loop": "Actual pushing loop; does not establish a two-hand carrying gait.",
    }
    transfer.write_json(BUILD / "inspection.json", inspection)
    if args.inspect_only:
        print("Household encoded source/rest inspection saved. No Blender/engine or action-quality check executed.")
        return
    try:
        import bpy  # noqa: F401
    except ImportError as exc:
        raise RuntimeError("Retargeting requires the parent-coordinated Blender slot") from exc
    source = transfer.RigData(transfer.SOURCE)
    rm = transfer.RigData(transfer.SOURCE_RM)
    for target_id in targets:
        target = transfer.RigData(transfer.target_path(target_id))
        corrections = transfer.transfer_setup(source, target)
        scale = inspection["targets"][target_id]["translation_scale"]
        clips = {key: transfer.transfer_clip(source, rm, target, corrections, scale, key, args.fps) for key in CLIPS}
        # The existing master writer selects an action named idle for its
        # viewport preview. The convenience alias exists only in this new
        # animation-authoring master, and is explicitly not an authored idle.
        master_clips = {"idle": clips["interact"], **clips}
        master = BUILD / target_id / f"{transfer.TARGETS[target_id][0]}_HouseholdMotion.blend"
        transfer.bake_master(target_id, target, master_clips, args.fps, master)
        transfer.write_library(RUNTIME / f"{target_id}.tres", clips, args.skeleton_path)
        contract = {
            "format": 1, "target": target_id,
            "source": transfer.identity(transfer.SOURCE), "source_rm": transfer.identity(transfer.SOURCE_RM),
            "target_input_identification": transfer.identity(transfer.target_path(target_id)),
            "license": "CC0-1.0", "license_file": "assets/motion-sources/quaternius/License.txt",
            "track_prefix": args.skeleton_path + ":", "target_skeleton_relative_path": args.skeleton_path,
            "track_transform_convention": "Godot4 absolute parent-relative bone TRS; target local lengths and unit scale preserved",
            "world_movement_owner": "ResidentMotor only; clips have no root X/Z or yaw movement",
            "geometry_policy": "No model output, skin edits, old animation output or foundation library overwrite",
            "source_mapping": transfer.MAPPING, "translation_scale": scale,
            "clips": {key: value["contract"] for key, value in clips.items()},
            "missing_source_coverage": MISSING,
            "runtime_authoring": "Semantic whole-body work paths are authored in FoundationHouseholdPose against actual world targets. Carry/seated actions preserve incoming lower body.",
            "master_preview_alias": "idle in the new .blend aliases Interact only; it is excluded from the runtime AnimationLibrary",
            "review_status": "baked_not_rendered_or_visually_accepted",
        }
        transfer.write_json(RUNTIME / f"{target_id}.contract.json", contract)
        for key, value in clips.items():
            transfer.write_json(BUILD / target_id / f"{key}.samples.json", {"contract": value["contract"], "frames": value["observations"]})
        print(f"HOUSEHOLD TRANSFER {target_id}: four actual source clips, geometry unchanged; visual review pending", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect-only", action="store_true")
    parser.add_argument("--targets", default="nagisa,ryo,rin")
    parser.add_argument("--fps", type=int, default=30, choices=(30, 60))
    parser.add_argument("--skeleton-path", default="Skeleton3D")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    args = parser.parse_args(argv)
    if not args.skeleton_path or any(char in args.skeleton_path for char in ('"', ":", "\n", "\r")):
        parser.error("--skeleton-path must be a valid node-only track prefix")
    run(args)


if __name__ == "__main__":
    main()
