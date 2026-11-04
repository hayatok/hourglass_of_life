# Resident body production sources

The three resident bodies use the accepted front concepts and immutable Tripo raw meshes. The scripts produce derived forms, fitted humanoid skins, nine clips and compatible distance LODs. Raw images are retained in LOD0; LOD1/2 are geometry-only and use the actor's material override.

## Tools and dependencies

Production used Blender **5.2.1** and plain Python **3.11.16** with **Pillow 13.0.0**. Install the plain Python dependency with:

```sh
python3 -m venv /tmp/hourglass-jrpg-tools
/tmp/hourglass-jrpg-tools/bin/python -m pip install -r assets/models/jrpg-resident-renewal/build/requirements.txt
```

Blender supplies `bpy`, `bmesh` and `mathutils`; these are not pip dependencies. The three generic helpers used for initialization, export and validation are copied under `vendor/`. Their local origin, snapshot date, MIT declaration and complete import inventory are in `vendor/README.md` and `vendor/sources.json`. No installed Codex skill or user-home directory is needed at runtime. The original source package supplied no separate copyright notice or remote revision.

The input raw GLBs and selected concepts are already in `../{saki,tomo,yui}/raw/` and `assets/artwork/jrpg-resident-renewal/`. `06_bind.py` also uses the tracked animation masters `assets/models/CH_{Fumi,Ryo,Maho}/CH_*_animation_master.blend` and their matching motion profiles. Those files are project inputs, not external packages.

## Authoring sources and output ownership

The preserved editable masters are:

- `assets/models/jrpg-resident-renewal/source/saki/CH_Saki_AnimationMaster.blend`
- `assets/models/jrpg-resident-renewal/source/tomo/CH_Tomo_AnimationMaster.blend`
- `assets/models/jrpg-resident-renewal/source/yui/CH_Yui_AnimationMaster.blend`

These three packed snapshots contain the accepted body, rig, animation actions and distance meshes. They were copied from the final local production masters without removing the originals. Their Blender body material is the original imported material; the Godot UV-eye controls are separate runtime layout/shader files. The editable masters do not claim Blender eyelid or mouth morphs.

`builds/jrpg-resident-renewal/` remains ignored scratch space for raw/forms/rig/delivery/clean-import working files. The retained snapshots do not depend on that scratch history for manual editing. The procedural rebuild below regenerates its own working files from the tracked raw and source animation masters.

The **runtime delivery of record is `game/assets/models/{saki,tomo,yui}/`** with the accepted actor face metadata and scene settings. Per-person `exports/` is regenerable body-only staging. It duplicates the body GLBs/clip contracts and may carry older, unsupported face metadata. No build step automatically copies staging into the game folder. Inspect the new outputs and explicitly integrate them as a revision; do not overwrite accepted game face keys or layouts from staging.

## Running the phases

Run from the repository root, with one Blender process at a time and `--threads 2`. On macOS the binary is `/Applications/Blender.app/Contents/MacOS/Blender`; another platform can set its installed path. Rendering is CPU-limited and should not run alongside Godot/other Blender jobs.

```sh
RENEWAL_BUILD=assets/models/jrpg-resident-renewal/build
RENEWAL_PYTHON=/tmp/hourglass-jrpg-tools/bin/python
RENEWAL_BLENDER=/Applications/Blender.app/Contents/MacOS/Blender

"$RENEWAL_PYTHON" "$RENEWAL_BUILD/00_prepare_references.py"
"$RENEWAL_BLENDER" --background --threads 2 --python "$RENEWAL_BUILD/01_import_review.py"
"$RENEWAL_BLENDER" --background --threads 2 --python "$RENEWAL_BUILD/03_fit_forms.py"
"$RENEWAL_BLENDER" --background --threads 2 --python "$RENEWAL_BUILD/06_bind.py"

# One resident at a time; these phases can render and take several minutes.
for resident in saki tomo yui; do
  "$RENEWAL_BLENDER" --background --threads 2 --python "$RENEWAL_BUILD/07_pose_review.py" -- "$resident"
  "$RENEWAL_PYTHON" "$RENEWAL_BUILD/10_compose_poses.py" "$resident"
  "$RENEWAL_BLENDER" --background --threads 2 --python "$RENEWAL_BUILD/08_deformation_audit.py" -- "$resident"
  "$RENEWAL_BLENDER" --background --threads 2 --python "$RENEWAL_BUILD/09_export.py" -- "$resident"
  "$RENEWAL_PYTHON" "$RENEWAL_BUILD/11_check_delivery.py" "$resident"
  "$RENEWAL_BLENDER" --background --threads 2 --python "$RENEWAL_BUILD/12_roundtrip.py" -- "$resident"
  "$RENEWAL_BLENDER" --background --threads 2 --python "$RENEWAL_BUILD/13_validate_masters.py" -- "$resident"
done
```

1. `00_prepare_references.py` establishes the fixed matte, image axis, ground and metre scale. `01_import_review.py` imports the raw mesh into the calibrated master.
2. `03_fit_forms.py` applies the accepted arm/hem fitting changes. The small front comparison and world-registration inputs are retained under each resident’s `production-inputs/`; generated `review/` folders are disposable. The commands above do **not** regenerate all historic raw/forms turntable or silhouette-comparison images. After changing forms, repeat and review those comparisons before adopting a new candidate; reusing their historical numbers is not a new visual acceptance.
3. `06_bind.py` retains the original named 35 bones, adding `DEF-skirt_middle` for Saki and Yui. Arm and cloth membership follows adjacency, including UV-split copies. Hands stay separated from the leg family, camera weighting has a gradual boundary, and lower skirt motion is shared rather than split by left/right shins.
4. `07_pose_review.py` renders nine body poses; `10_compose_poses.py` composes those renders. `08_deformation_audit.py` records actual edge lengths, coincident-seam separation and arm/lower-body influence conflicts.
5. `09_export.py` measures target-foot motion, welds derived LOD seams before decimation and exports body-only staging. Original encoded images are restored to LOD0; distance LOD images are removed.
6. `11_check_delivery.py` directly compares triangle-corner UV coordinates, skin weights, inverse bind matrices and animation values. Decoded input image identity belongs only to provenance. `12_roundtrip.py` imports each LOD into a fresh Blender scene, measures real skin movement and loop closure, and renders the base. `13_validate_masters.py` records topology, UV, weight and triangle-budget results.

## Evidence and limits

Hashes identify source files only. They are not assertions, quality tests, acceptance gates or counted checks. Declared and observed identifiers may both be recorded without a comparison or a failure outcome. Transform-only geometry and UV preservation use direct numerical arrays instead of hashes, with no replacement test counts. Decoded input-atlas identity is also provenance; rendered visual changes and actual animation/skin behavior are separate evidence.

Historical delivery reports and rendered comparisons were removed during cleanup. Regenerate only the needed review; do not inherit earlier successful counts. `11_check_delivery.py` records source-image identity under `provenance_only`.

This portability/source-maintenance change was checked by Python syntax compilation and static dependency inspection only. Blender, export, rendering and Godot acceptance were **not** rerun for it. The upstream helpers are copied without behavior changes. Other Blender/Pillow versions and other operating systems have not been exercised with this pipeline.

The body contracts are Saki 36 bones / 1.65m, Tomo 35 / 1.70m, Yui 36 / 1.70m, with nine named clips each. The extra skirt helper's seated rotation is baked. Single-front-image side/back details remain inferred. Actor integration, real furniture and pillow contact, foot sliding, eye appearance at different LODs, fuller facial controls and hair aging require their own runtime evidence; successful export alone does not establish them.
