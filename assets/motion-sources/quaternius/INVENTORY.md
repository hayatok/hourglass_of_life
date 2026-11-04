# Quaternius Universal Animation Library — free Standard

- Official product: https://quaternius.com/packs/universalanimationlibrary.html
- Official distribution: https://quaternius.itch.io/universal-animation-library
- Edition: **Standard (free)**, official changelog v3.0 dated 2026-06-16.
- Original archive: `Universal Animation Library[Standard].zip` (15,904,933 bytes).
- Archive's own license declaration: **CC0 1.0 Universal**, retained verbatim in `License.txt` and `README.txt`.
- Download used the anonymous “No thanks, just take me to the downloads” route. No account, purchase, email, external upload or explicit terms-acceptance control was used. Transient HTTP 429 responses were respected by waiting; no alternate-host/rate-limit bypass was used.
- `.gdignore` keeps these raw source files out of automatic Godot import. Runtime derivatives/retargeted clips belong in a separate later integration step.

## What was inspected

Only ZIP contents and GLB JSON/binary accessors were parsed, using `inspect_glb.py` and Python's standard library. `inventory.json` records every clip, duration, sample rate, root/pelvis channel, skin joint, static local TRS, inverse bind matrix and selected world bind positions. No Blender/Godot import, rendered visual evaluation, contact/foot-slip check or successful retarget is established by this inventory.

Both extracted GLBs contain the same **43 named animations** and one **65-joint** skin, with baked sample times at approximately 30 Hz. The product-wide “120+” and “8 directions” descriptions do **not** establish that those features are present in the free Standard archive.

## Relevant actual clips

| Need | Exact free Standard clip | Duration | `_RM` root displacement per clip |
|---|---|---:|---:|
| Walk | `Walk_Loop` | 1.333333 s | +Z 1.3 m |
| Formal walk | `Walk_Formal_Loop` | 1.333333 s | +Z 1.3 m |
| Jog forward | `Jog_Fwd_Loop` | 0.933333 s | +Z 5.0 m |
| Sprint | `Sprint_Loop` | 0.666667 s | +Z 5.5 m |
| Sit down | `Sitting_Enter` | 1.300000 s | 0 m |
| Stand up from sitting | `Sitting_Exit` | 1.033333 s | 0 m |
| Sitting | `Sitting_Idle_Loop`, `Sitting_Talking_Loop` | See JSON | See JSON |
| Standing/idle | `Idle_Loop`, `Idle_Talking_Loop` | See JSON | See JSON |
| Dedicated walk start/stop | **No specifically named clip present** | — | — |
| Dedicated 90°/180° turn | **No specifically named clip present** | — | — |
| Eight-direction walk set | **No such named set present** | — | — |

The non-`_RM` versions of the six walk/jog/sprint/sit-transition clips above have constant root translation. The `_RM` walk displacement implies about 0.975 m/s at native duration; jog/sprint imply about 5.357/8.25 m/s in encoded source units. These are file-coordinate observations, not validated runtime world speeds. Pelvis/body movement remains a separate set of channels. Both sitting transitions have stationary root translation even in `_RM`; a suffix does not guarantee translation for every action.

## Rig and rest pose

- glTF 2.0, Y-up, right-handed metre coordinates; asset generator is `Khronos glTF Blender I/O v4.5.48`.
- Scene root node `Armature` has a mesh child `Mannequin` and a single skeleton root joint `root`; the hip joint is `pelvis`.
- Spine: `pelvis → spine_01 → spine_02 → spine_03 → neck_01 → Head`.
- Arms: `clavicle_l/r → upperarm_l/r → lowerarm_l/r → hand_l/r`.
- Legs: `thigh_l/r → calf_l/r → foot_l/r → ball_l/r → ball_leaf_l/r`.
- Each hand has `thumb/index/middle/ring/pinky_01..03` plus `_04_leaf` joints.
- Static `root` local quaternion is approximately `(-0.70710677, 0, 0, 0.70710677)`; do not equate local joint axes directly with the target rig's axes.
- The encoded default/rest joint positions have both upper arms horizontal (angle below 0.00004° from horizontal), consistent with a T-pose. The first sample of named `A_TPose` is also horizontal. This conclusion is from joint transforms, not a render.
- Selected static world positions: pelvis `(0, .91670, -.05010)`, shoulders `(±.19190, 1.44080, -.06540)`, wrists `(±.73890, 1.44080, -.06540)`, ankles `(±.08900, .10370, -.03580)` metres. Head joint height is not total character mesh height.

## Complete clip names (same in regular and RM)

- `A_TPose`
- `Crouch_Fwd_Loop`
- `Crouch_Idle_Loop`
- `Dance_Loop`
- `Death01`
- `Driving_Loop`
- `Fixing_Kneeling`
- `Hit_Chest`
- `Hit_Head`
- `Idle_Loop`
- `Idle_Talking_Loop`
- `Idle_Torch_Loop`
- `Interact`
- `Jog_Fwd_Loop`
- `Jump_Land`
- `Jump_Loop`
- `Jump_Start`
- `PickUp_Table`
- `Pistol_Aim_Down`
- `Pistol_Aim_Neutral`
- `Pistol_Aim_Up`
- `Pistol_Idle_Loop`
- `Pistol_Reload`
- `Pistol_Shoot`
- `Punch_Cross`
- `Punch_Jab`
- `Push_Loop`
- `Roll`
- `Sitting_Enter`
- `Sitting_Exit`
- `Sitting_Idle_Loop`
- `Sitting_Talking_Loop`
- `Spell_Simple_Enter`
- `Spell_Simple_Exit`
- `Spell_Simple_Idle_Loop`
- `Spell_Simple_Shoot`
- `Sprint_Loop`
- `Swim_Fwd_Loop`
- `Swim_Idle_Loop`
- `Sword_Attack`
- `Sword_Idle`
- `Walk_Formal_Loop`
- `Walk_Loop`
