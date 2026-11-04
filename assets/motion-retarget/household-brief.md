# Household action foundation

ASSET: animation-only household library and final skeletal action provider.
CATEGORY: human biped animation; existing Nagisa/Ryo/Rin geometry and the seven foundation locomotion clips remain read-only.
REFERENCE: encoded CC0 Quaternius UAL1_Standard and UAL1_Standard_RM animations. No new captured cooking, eating, washing or folding reference exists in this package.
SCALE: existing target rigs at their authored scene heights; local arm/leg offsets and scales remain unchanged. ResidentMotor alone owns body world transforms.
ARTICULATION: root/body/feet/shoulders/arms/palms/fingers must form a readable complete action. Carry and seated work retain the incoming locomotion/furniture pelvis, legs and shoe supports exactly.
SOURCE: PickUp_Table (0.8333s), Interact (2s), Fixing_Kneeling (5.2s), Push_Loop (2.6667s). All three target libraries and new authoring masters have been generated. Metadata/rest inspection is saved under builds/motion-retarget/household.
INFERRED: phase-to-source timing and prepare/stir/wash/fold/write paths are explicit runtime authoring. No dedicated source carry, cooking, eating, dishwashing, folding or writing clip is claimed. Kneeling source is supplied for review but cannot become contact-ready before actual knee/support adaptation exists.
TARGET: separate game/assets/motion/household/{id}.tres library; actual house follow camera and closer side/front views. No model output or original animation overwrite.

## Controller contract

Configure the modifier after locomotion and furniture with `configure(actor, base_library, base_contract, profile)`, then `set_action_library(action_library, action_contract)`. `calibration().carry_grip_center_actor` is the real rig's comfortable grip midpoint; the controller subtracts the prop's actual local grip midpoint to obtain a stable body-relative prop-origin frame.

Requests supply `action`, `phase`, `progress`, `pose_seconds`, `posture`, real world palm targets, and optionally `object:{id,world,local_grips|grips,support_local}` and the actual `support_point`. Local/world grip frames use +Z for the palm normal and +Y for the fingers' long direction. `mouth_palm_transform` must include the real utensil grip-to-tip offset; a mouth point alone cannot certify eating.

The controller keeps the object at its source during reach. Actual final skin contact plus a displayed closed grasp enables `transfer_ready("grasp")`; only the controller then commits holder changes. Lift/carry/lower use controller-authored continuous object frames. Open release, the same previously grasped object and actual prop-bottom/support coincidence enable `transfer_ready("release")`. The provider changes no holder, resource, clock or task result.

`object_transforms` is an optional rendering proposal fitted to final actual palms. It is never a resource state or permission to move a prop before the grasp gate. Avoid a feedback loop where a prop follows a rest hand and the same hand then chases that prop.

## First visible cut

Show one complete table reach → grasp → lift → four-metre walk with tray → controlled lower → release → recover at ordinary speed. The real prop must stay still until contact, remain rigid between both hands while walking, and come to rest on its destination before release. Repeat with the smaller rig and a basket. Review whole-body balance, source-to-work transitions, shoe sliding, shoulders, elbows, wrist orientation, cloth/bench penetration and camera readability.

Then connect real tools and materials for preparation, stirring, washing, folding, notebook work and seated eating. A moving hand over an empty worktop is a prototype path, not completed household-action acceptance. Food recovery requires a real utensil-to-mouth target and physical meal sequence. Missing support geometry or unreachable contacts must keep work readiness false.

## Reproduction and verification status

`python3 assets/motion-retarget/build/02_retarget_household.py --inspect-only` uses standard Python only. In a root-coordinated heavy slot, run Blender with that script and `-- --targets nagisa`, then the other targets sequentially. The new `.blend` preview has a documented `idle` alias of Interact solely because the shared master writer expects a preview action; the runtime library contains only the four real named clips.

`check_household_pose.gd` is a controlled real-rig/real-tray fixture, with transfer gates, lower-body preservation, JSON mid-carry replay and seated overlay. It refuses a missing generated source library by default. Nagisa and Ryo completed the adult transfer baseline (18 checks each in headless and GPU runs); actual carried palm errors stayed below 1cm, and the input lower body was never written by the overlay. Key GPU frames were viewed for grasp/lift/carry/lower/release/recover and seated preparation. This is a controlled fixture, not actual-house work/resource integration or full natural-action acceptance.

Rin uses the same real .62m-wide handle span as an explicit negative affordance case: `-- rin --expect-unreachable`. Its source reach is physically insufficient; the actual tray stays on its source and holder commits remain zero. This is not a completed child carry. A later success case needs a separate smaller real carrier/low support or the child's own book/model. No arm length, contact threshold or object width is changed to make the adult tray fit.

The controller must enforce the real prop bounds against the measured torso front, preserve worktop clearance before moving out, and route around the counter. The fixture uses raised handles, real native worktops and a clear side route. The available carrier frame is high and wide on the narrow existing rigs; shoulder/arm acting, old rigid apron deformation and coarse finger closure remain visual limitations. Eating without the real mouth/utensil target remains not ready. The other semantic work paths are not yet accepted with actual tools/material deformation. Hashes, if emitted by the build, identify inputs only.
