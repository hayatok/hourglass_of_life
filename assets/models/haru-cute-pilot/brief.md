# Haru cute character pilot

Use `assets/artwork/cute-cast-pilot/haru-concept-v2-jrpg.png` as the current selected 2D candidate. The latest direction is closer to Trails in the Sky: anime JRPG linework, cel shading, expressive eyes and approximately six-head adult proportions. The orange jacket, navy work trousers, navy hair, amber eyes and A-pose remain the Haru design. The rounded rendered-3D v1 at `assets/artwork/cute-cast-pilot/haru-concept-v1.png` is rejected. No paid 3D generation has been submitted and no 3D result exists.

Tripo operations belong to the logged-in Chrome session operated by the main agent. This folder contains offline production notes only. The selected reference path and SHA-256, and the rejected reference, are recorded in `import-contract.json`.

The current twelve-person game stays frozen. The four shared-rig variants remain the playable placeholders until a replacement passes the checks below. A downloaded static GLB is a base-mesh candidate, not an integrated animated character.

## First deliverable

The main agent recorded this Chrome setup: H3.1, 30,000 triangles, 2K texture, texture and PBR enabled, Ultra off, private visibility. The browser displayed a 30-credit estimate and a balance of 2,925 at that check. The paid generation button has not been clicked; confirmation of this one-model plan is pending. These are browser observations, not billed credits or a finished model. Rigging, animation and LOD work are outside this first generation.

After approval, generate one textured character from the selected v2 image. Keep the native GLB, textures, preview, visible model/settings, browser task identifier and the credits actually shown or charged in the browser. Use `prompt.txt` only where the browser offers a compatible prompt field. Do not submit additional rigging, retarget, texture or export jobs automatically. Review the mesh before choosing the next step.

Check the approximately six-head adult silhouette, face, hands, finger separation, armpits, trouser gap, feet and pocket tools from front, back and three-quarter views. A single front image does not establish the back of the costume. The supplied A-pose has separated limbs, but it is not the T-pose recommended by the Tripo rigging recipe; inspect the free rig-check result before committing to any paid rig.

## Integration route

1. Preserve the raw download and inspect it in a separate staging scene. Measure actual triangles, texture sizes, materials, scale and orientation. The Chrome source setting is 30k triangles. The proposed 12k / 6k / 2k production LOD values remain local optimization targets after source review, not generated assets or measured performance.
2. Prefer fitting the existing 35-bone DEF rig to the new proportions, binding the new mesh and transferring the existing nine clips locally. This preserves the current contact interface and avoids paying for animations already present in the project. Keep the selected six-head anime JRPG proportions rather than reshaping the candidate to the source Aoi body. Current Haru displays at about 1.77 m, from a 1.71 m source and a 1.035 height scale.
3. If Tripo auto-rigging is selected after mesh review, retain the unrigged GLB too. A Tripo or Mixamo skeleton requires a deliberate bone/rest-pose mapping and retarget work; renaming bones alone is insufficient. Its available locomotion presets do not establish the game's talk, work, seated conversation, meal and sleep clips. Existing clips still need local retargeting and contact checks.
4. Preserve the generated material atlas. The current Haru manifest recolors fixed cells in an 8-by-8 source palette. Applying those swatches to an arbitrary Tripo atlas would damage unrelated texture regions. Replace or disable that override for the candidate, and keep hair aging disabled until the hair region is explicitly identified.
5. Retain facial controls and produce compatible LODs. Current rendering discovers a Face mesh by name and uses Blink, Smile, Sad, Tired, LookLeft and LookRight. The current LOD loader requires matching part names, surface counts, blend-shape names and skin bind records, and keeps one skeleton and animation clock.
6. Compare the reference, raw mesh, rigged mesh and in-game result. Verify idle, walk, talk, work, sit_talk, sleep, wave, eat and rest; feet on the ground; wrists on the real worktable and cup; hips on a chair; body/head on the dedicated bed; camera framing; and LOD transitions. Then make the single-character production switch separately, retaining the current variant as a fallback.

The exact current bones and clips are recorded in `import-contract.json`. The runtime contracts are in `game/scripts/resident_contacts.gd`, `game/scripts/jrpg_resident_model.gd` and `game/scripts/resident_avatar.gd`. No game-core file was modified while preparing this pilot.
