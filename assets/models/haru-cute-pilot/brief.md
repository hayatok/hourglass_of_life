# Haru cute character pilot

Use `assets/artwork/cute-cast-pilot/haru-concept-v2-jrpg.png` as the current selected 2D candidate. The latest direction is closer to Trails in the Sky: anime JRPG linework, cel shading, expressive eyes and approximately six-head adult proportions. The orange jacket, navy work trousers, navy hair, amber eyes and A-pose remain the Haru design. The rounded rendered-3D v1 at `assets/artwork/cute-cast-pilot/haru-concept-v1.png` is rejected. After explicit approval, the main agent generated this one candidate in Chrome and saved the raw GLB. The generation consumed 30 credits; the browser balance changed from 2,925 to 2,895. No extra generation or processing was submitted. The raw mesh has no rig, animation or facial controls.

Tripo operations belong to the logged-in Chrome session operated by the main agent. This folder contains offline production notes only. The selected reference path and SHA-256, and the rejected reference, are recorded in `import-contract.json`.

The current body candidate is r3 in `game/assets/models/haru/`: r1's bound body and nine clips, r2's distance-LOD texture deduplication and r3's LOD seam correction. The raw review and asset production did not alter game-core scripts. Runtime adapter integration and real-town contact checks are tracked separately. The runtime now has UV-based Blink/TiredEyes controls; Smile, full facial-expression support, hair aging and gait stance sliding remain acceptance work.

## First deliverable

The completed Chrome generation used H3.1, a 30,000-triangle setting, 2K texture, texture/PBR enabled, Ultra off, remove-lighting enabled and private visibility. Task `5b0ff371-e44b-44b0-be05-f1433d089f00` produced 29,046 triangles and 17,990 vertices. The exported raw GLB is 3,247,068 bytes. `generation.json` records the approved 30-credit charge, browser observations and raw SHA-256. Local binding, nine clips and three LODs were subsequently produced without additional Tripo charges.

The immutable native result is `raw/CH_Haru_JRPG_Pilot_Raw.glb`. Preserve it and the recorded settings, task identifier and charge. Use `prompt.txt` only where the browser offers a compatible prompt field. Do not submit additional rigging, retarget, texture or export jobs automatically. Review the mesh before choosing the next step.

The approximately six-head adult silhouette, face, finger separation, armpits, trouser gap, feet and pocket tools were inspected from front, back and three-quarter views. A single front image does not establish the back of the costume. Binding uses the existing local DEF family; no paid auto-rig or animation job was submitted.

## Integration route

1. The raw file is immutable. `review/raw-import.json` records its source counts and unchanged local geometry. Side/back details remain generated interpretations.
2. The derived model narrows torso/legs/head by 4% and rotates separated arms 2.12 degrees toward neutral at the shoulder. Hands retain their local shape. UVs and atlas pixels are unchanged. Both fixed-reference silhouette gates pass; see the derived result below.
3. The existing Aoi 35-bone family and nine clips are transferred to fitted Haru joints. Target-specific regional weights are normalized with at most four influences per vertex; no vertex is unweighted. The canonical production height is 1.71 m with body scale 1.0. The earlier 1.77 m height is retained only for raw/reference calibration.
4. LOD0 preserves all three original embedded images and material descriptors byte-for-byte. Runtime TextureToon samples the ordinary UV atlas. Distance LODs contain no images and retain the actor's LOD0 material override; standalone distance-LOD previews are intentionally untextured. Old 8-by-8 palette recoloring and hair-cell aging remain disabled.
5. Current r3 LODs are 29,046 / 12,190 / 3,482 triangles. Each has one mesh, one surface, the same 35 bind poses and nine clips. The historical 12k / 6k / 2k targets were not adopted. Clean reimport verifies skin/weights, original-image hashes and loop seams; it does not establish performance in the town.
6. Runtime checks track the actual imported source, pixels, nine clips, ground/worktable/cup/chair/bed contacts and LOD switching separately. The current face uses `TEXTURE_EYES`: two UV-shader controls, Blink and TiredEyes, with no facial blend shapes or eye-gaze morph. Smile/full facial controls and hair aging remain final acceptance work. `rest` is an intentional hold pose, rather than a moving clip.

The exact current bones and clips are recorded in `import-contract.json`. The runtime contracts are in `game/scripts/resident_contacts.gd`, `game/scripts/jrpg_resident_model.gd` and `game/scripts/resident_avatar.gd`. No game-core file was modified while preparing this pilot.

## Derived result, r1

This section records the first body candidate. Current r2/r3 changes are recorded below; r1 evidence remains historical.

The derived front reaches bbox-aligned IoU 0.9252 with maximum ten-band width difference 0.0235 of total height. Fixed world registration gives IoU 0.9170 and maximum band difference 0.0114. Reference matte, threshold, axis and ground row are unchanged. `review/derived-compare-front.png` and `review/derived-world-front/` retain both comparisons. The raw result below remains historical and is not overwritten.

The Blender pose sheet covers full stride, forward conversation gesture, work reach, seated pose, sleep, torso twist, deep knee/elbow bend and a manual overhead limit. The overhead test uses upper-arm local Z rotations of ±146.1 degrees; wrists reach 1.7756 m and fingertips 1.9277 m, above the 1.71 m head top. These are real poses, not additional game clips. Whole-body images show no obvious collapsed joint, open hole or garment penetration; this remains a visual assessment. The sleep and overhead cameras include the full body. `review/poses/poses.json` records angles and bounds.

The fitted foot trajectory gives a best-fit playback speed of 1.796324 m/s at 30 fps, rather than inheriting Aoi's 1.633106 value. `review/walk-measurement.json` records the low support-window samples. The inherited FK stance velocity varies substantially, so the estimate does not prove that feet never slide. Actual locomotion still requires town-camera review.

`review/rig-validate.json` reports no failures, with the retained coincident UV/normal seam vertices as one warning. `review/roundtrip-check.json` verifies clean import of the three frozen GLBs, matching 35-bone bind poses, normalized weights, nine clips and loop seams below 1 mm. LOD0 rest height is 1.7100002 m; the decimated LOD bounds differ by at most 2.1 mm. The canonical rest skeleton remains identical.

## Current r2/r3 corrections

r2 removes the duplicated images from LOD1/2 while keeping their material slots, UVs and skin. In four isolated native Godot processes, TextureToon/SourcePBR r1/r2 comparisons pass 140 checks and all six matched screenshots are pixel-identical. RenderingServer texture accounting after subtracting the empty viewport falls from 150,999,031 to 50,335,741 bytes, about 96 MiB saved. This is renderer accounting for one actor, not physical RAM or full-town performance. See `review/r2/`.

r3 welds coincident geometric vertices before decimation while retaining UV coordinates on face loops. This avoids the large facial, hair and neck cracks caused when each UV seam side was reduced separately. Both LODs keep identical inverse-bind matrices and nine animation tracks/samples. Native GPU rest/idle/head-turn comparisons at forced close range and actual 95/40 px subject height show the large cracks removed. The two comparison runs pass 17 structural checks each; these checks support the rendered evidence rather than replace it. See `review/lod-seams/`.

The current LODs still contain small unmatched geometric boundaries totaling 30.89 mm, including 8.57 mm around head/neck. This does not establish a fully watertight mesh. LOD0 and all original atlas bytes remain unchanged. Old r1/r2 GLBs are retained under `builds/haru-cute-pilot/`; real gameplay evidence from the static-atlas stage remains labeled `r1-static-atlas`.

## Historical raw comparison result

Blender 5.2.1 imported the raw file successfully: 1 mesh, 1 material, 29,046 triangles, 17,990 vertices, three 2048-by-2048 PBR images and no armature, skin, clips or shape keys. Review placement scales the imported one-metre source to an inferred 1.77 m on a parent empty; local mesh coordinates and face indices are unchanged. The production adapter later requests a 1.71 m canonical asset; that is a separate calibration.

The approximate front-concept comparison gives bbox-aligned IoU 0.8750 and world-registered IoU 0.8758. The reference axis is measured independently from face, neck and chest samples at column 498.5, rather than assumed to be the image centre. The maximum ten-band width difference is 0.0352 of total height (0.0310 in world registration), near the hands. Overall hand span is approximately 6.4% wider than the reference. The 0.90 forms IoU target has not passed. This supports continuing with the mesh as a base candidate, while retaining local proportion and hand corrections as unfinished work; it does not establish finished visual acceptance.

`review/raw-validate.json` passes the 30k triangle and UV checks but warns about 3,485 near-duplicate vertices; imported UV/normal seams must be distinguished from unintended duplicates before cleanup. There are 6,528 boundary edges in the split imported mesh and 203 connected pieces. These counts do not establish manifold deformation topology. The raw file remains unchanged. Back and side surfaces shown in the review are Tripo interpretations without matching reference views.
