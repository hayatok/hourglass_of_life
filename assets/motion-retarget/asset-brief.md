# Foundation motion transfer

ASSET      AN_Foundation — animation-only derivatives for CH_Nagisa, CH_Ryo and CH_Rin

CATEGORY   character; existing humanoid bipeds, articulation/animation/delivery scope only

VIEWS      Reference is the actual Quaternius CC0 Universal Animation Library Standard GLB, not a supplied turnaround image. Compare the source and target animation from front, side and three-quarter views, at ordinary gameplay size and close enough to see both soles. No rendered review has passed at brief creation.

SCALE      1 unit = 1 metre. Existing target scene heights are Nagisa 1.65 m, Ryo 1.76 m and Rin 1.22 m. Bone lengths and existing geometry are retained. Translation/stride scale is the mean target hip→knee→ankle length divided by the same measured source length; head size and total height do not decide leg stride.

PROPORTIONS Source pelvis/ankle heights are .91670/.10370 m; target pelvis/ankle heights are Nagisa .94000/.12000, Ryo 1.00941/.12886, Rin .65078/.08308 m. Each target has 35 skin joints, versus 65 source joints. Source upper arms are horizontal in the T-pose; target upper arms descend in their rest poses. Arm, forearm, thigh and shin lengths, shoulder width, hip width and rest rotations are recorded by the reproducible inspection. These are file measurements, not visual acceptance.

PARTS      Existing body, face, materials, textures, weights, skeletons and old nine clips are read-only. New per-target AnimationLibrary resources carry bone animation only. The Blender review master imports existing geometry without editing it and contains the baked target actions. No replacement model is exported.

SILHOUETTE Preserve each resident's height and proportions; a planted sole supports the pelvis; a swing leg clears the floor; arms hang naturally with elbows bending forward; sitting visibly lowers the pelvis and bends knees without an instantaneous pose change.

MATERIALS  Original target materials are retained in review masters; this pipeline does not author textures/materials or change game shaders.

ARTICULATION Source `root/pelvis/spine_01/spine_02/spine_03/neck_01/Head`, arms, legs, hands and first finger phalanges map to the existing `DEF-*` hierarchy. World quaternion transfer uses a virtual orientation calibration so the source T-pose does not get applied as another downward rotation on top of the target A/rest pose. Child translations retain actual target bone lengths. Pelvis displacement and authored stride use measured leg-length scale. Source three-phalange fingers reduce to the target's single proximal finger joint; exact fingertip articulation cannot be retained. A bounded two-segment leg solve adapts ankle trajectories to the target's lengths. Actual weighted shoe vertices supply the ground envelope; no bone landmark is labelled a sole. Apron bones have no source counterpart; their leg-following clearance rotation is explicitly an inferred secondary adaptation, not an authored source animation.

INFERRED   Mapping from source spine_03 to target chest, first phalanx to each single target finger, ankle-trajectory scaling, target sole ground baseline and apron clearance adaptation are retarget decisions. Source clip names establish coverage only; successful transfer and natural movement require rendered review. Adult source timing on Rin is a transferred motion and is not evidence of child-specific acting. No dedicated walk start, stop, 90° turn or 180° turn exists in this source set.

TARGET     Godot 4; `game/assets/motion/foundation/{nagisa,ryo,rin}.tres`, each an AnimationLibrary. Keys: `idle`, `walk`, `walk_formal`, `sit_enter`, `sit_idle`, `sit_exit`, `talk`. Position/rotation/scale keys are absolute parent-relative Godot 4 bone poses, including rest, not rest-relative deltas. Default track prefix is `Skeleton3D:DEF-*`; it can be changed at generation using `--skeleton-path`. The actor adapter can duplicate the library and replace the node portion using the actual AnimationPlayer-root→Skeleton3D relative path. Motor world yaw/translation must not be applied again by the clips. Raw source and RM root displacement are retained in metadata; delivered root X/Z displacement is zero.

## Reproduction and review

Source/license inventory: `assets/motion-sources/quaternius/source.json`, `inventory.json`, `License.txt`. Official source: <https://quaternius.com/packs/universalanimationlibrary.html>. Godot pose convention: <https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html>.

Light inspection (standard Python, no engine):

```sh
python3 assets/motion-retarget/build/01_retarget_foundation.py --inspect-only
```

After the root agent grants the heavy-process slot:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python assets/motion-retarget/build/01_retarget_foundation.py -- --targets nagisa
```

Run the canonical resident first. Inspect a full walk loop and sit-enter/idle/exit, then run `--targets ryo,rin`. The script writes review `.blend`, transfer observations, the per-clip contract and runtime `.tres`. Build intermediates and sample data belong under `builds/motion-retarget`; only the animation-only library/contract ship under the new runtime folder. Reruns replace only files owned by this pipeline. Source/model file digests identify inputs and are not tests or acceptance counts.

## Visible acceptance still required

- A complete 10 m journey at ordinary gameplay size: no skating stance foot, sideways knee collapse, reversed elbow bend, floating floor contact or clothes cutting through the stride.
- Front/side walk loops at native authored speed and at the motor's actual 1.1 m/s, with playback rate derived from measured stride rather than the old minute clock. Record planted-foot horizontal drift over the support interval and show the same interval in the capture; a numeric probe alone cannot approve the gait.
- Start, arrival, 90° and 180° changes of direction need separately authored transition poses/clips or a tested support-foot/step adaptation. Idle/walk mixing by speed alone is insufficient evidence. These are deliberately marked missing in the contract.
- Sit enter→idle→exit must align with a real seat and foot support. The raw retarget clip does not establish furniture alignment; the action/seat adapter remains responsible.
- Review all three actual target meshes. A retarget/export pass or clip-name count does not establish natural animation.

The motor's turn state owns world yaw. Future turn clips must add local stance/swing-foot motion while preserving the supported world foot; they must not add root yaw to the motor a second time.

## Next: real start, stop and turn steps

These are new authored transition clips, derived from the source walk's weight transfer. Renaming a walk, rotating a frozen idle pose, or scaling every joint angle is insufficient. Generate left/right entry variants: `start_left/right`, `stop_left/right`, `turn_90_left/right`, `turn_180_left/right`. Keep the seven transferred clips as their source reference.

1. **Publish support events before authoring transitions.** In `Walk_Loop`, frames 0–20 and 20–40 are opposite half-steps at 30 fps (native half-step duration 0.666667 s). Inspect heel/flat/toe support using source RM motion plus the actual weighted sole surface, and then the target shoe. Use the rest sole as the floor reference: the source's toe-off mesh briefly penetrates the floor, so its deepest animated vertex is not a valid floor. Height alone currently produces candidates, not accepted support locks. A final event also needs a low world velocity at the chosen material contact point; never lock a foot that is still swinging.

2. **Capture one contact owner.** On entry to a transition, retain the current gait phase, current evaluated full-body pose and the world position/orientation of the supported shoe. The contact anchor is a documented point on the actual shoe surface (heel/ball/toe triangle plus barycentric coordinate and skin influences), not an arbitrary ankle offset. A heel-to-toe roll changes support point deliberately; it does not silently create a new anchor each frame. The free foot has no contact claim until landing. Save the support side, anchor, phase, swing start/goal, current motor transform and transition progress.

3. **Start with a visible first step.** Use a selected source half-step for pelvis/torso/arm weight transfer and the swing knee's bend plane. Keep the rear support shoe's entry world anchor. Plan the swing shoe's first landing from the motor's actual acceleration distance and the next walk contact pose, then solve the two unchanged leg lengths to it. The default 1.1 m/s, 1.8 m/s² profile accelerates for about 0.611 s over 0.336 m; this is a movement contract, not an instruction to shrink all bone rotations. Convert each world foot target through the inverse current motor transform. Blend upper-body entry from the captured pose, preserve the support foot, and enter the walk at the matching landed-foot phase. Rin needs its own leg-length/velocity feasibility check; adult fixed step distance is not copied to the child.

4. **Stop with a closing step.** Choose a left/right stop according to the current actual support, rather than restarting walk phase zero. Keep that support world point while the motor brakes; finish the already airborne foot's visible arc to a safe final stance. Default full-speed braking distance is about 0.275 m at 2.2 m/s². Use the motor's predicted stopping transform for the landing, then shift the pelvis over the two feet and settle into idle. A very short stop must still land the foot; it cannot swap to idle mid-air. If a planned target is outside either leg's reach, shorten/change the step and lower/shift the pelvis within the stance envelope; never lengthen a bone or move the authoritative root to hide the failure.

5. **Turn by stepping both feet.** A 90° turn uses two alternating small steps; 180° uses four. Each step reuses a source half-step's weight transfer and bent-knee timing but reauthors the free shoe path as a short arc around the motor pivot, with 4–7 cm floor clearance instead of the source's full forward stride. This is a new foot trajectory, not a 45% joint-amplitude scale. Land the lead shoe at the next body heading and native stance width, transfer support, then bring the trailing shoe into the new orientation. The old support sole stays at its world anchor until its own toe release; hip/knee IK counter-rotates against the motor yaw. Turning the sole on the floor requires an explicit heel/ball pivot, not a drifting anchor.

6. **Give steps enough time.** Start with calm 0.5 s half-steps: 90° takes 1 s, 180° takes 2 s, plus the motor's final settle window. Limit the motor turn rate to at most π/2 rad/s for this prototype, within its existing upper bound, or add a turn-duration handshake. Sampling a 1 s two-step clip in the present ~0.65 s 90° root turn would rush the replant. Drive local turn pose by the motor's actual turn progress; exported root yaw is zero. A chest/head lead is local acting, never a second world-heading owner.

7. **Bake and integrate one complete journey.** Generate target-specific transition poses with support constraints, keep no root translation/yaw in the library, and let the actor select left/right variants using the sign of turn angle and the actual support side. Any runtime adaptation consumes the post-blend full-body pose; no second IK layer rewrites already accepted contact. Review idle→start→10 m walk→stop, a closed 90° corner and a 180° return at both normal and slow playback, from front/side and the normal game camera. Compare foot material-point movement during each claimed support interval with what the video actually shows. Reject a run with a spinning planted sole, airborne idle swap, crossed knee, visibly stretched stride or double body turn even if clip loading and controller checks pass.

`game/foundation/foundation_locomotion_pose.gd` implements these transitions as a post-animation SkeletonModifier3D, sampling the seven transferred clips for the complete body and solving the supported/free foot trajectories. `check_locomotion.gd` is a small real-skeleton integration/replay probe. Code completion and that probe do not replace the normal-camera start/stop/corner/reversal review; natural-gait acceptance is still pending. The library itself remains the seven transferred reference clips.

Attach the modifier as a child of the actual Skeleton3D and call `configure(actor, library, contract, actor.snapshot().profile)`. For each rendered tick, advance the motor, call `modifier.advance(actor.pose(), delta, current_action.is_empty())`, and then advance the AnimationTree. SkeletonModifier callbacks run after AnimationTree and are deferred. Manual processing uses `Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL` and `skeleton.advance(delta)`, which is also deferred; each observed pose must await `modification_processed`/`skeleton_updated`. A long loop of tick calls without these callbacks does not observe the intermediate steps.

The modifier is the final locomotion-pose owner; action clips retain the AnimationTree when locomotion is disabled. Wait for `is_settled()` after stopping before starting furniture/action clips. Save the modifier's JSON-safe opaque `snapshot()` together with the motor/action state. Preflight with the side-effect-free `can_restore()`, restore the motor first, then `modifier.restore()`. The opaque state includes both world shoe anchors, selected real material points, swing start/landing transforms, source/body phase, turn step, clocks, captured entry/final bone poses and input serial; restoring merely the motor's position is insufficient for a mid-step save.
