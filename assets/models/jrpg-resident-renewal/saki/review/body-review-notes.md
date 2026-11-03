# Body candidate review

This is asset production evidence from agent rendering and numerical inspection. It is not a human playtest or complete character acceptance.

The accepted front forms retain the resident's costume and adult proportions. Bbox-registered IoU is 0.9275; world-registered IoU is 0.9355. Maximum normalized band-width differences are 0.0156 / 0.0135, against the forms limits of 0.90 IoU and 0.03 width difference. The reference matte, ground registration and image axis were fixed before fitting.

The target is 1.65 m. The original 35 named bones are retained, with 36 total bones. Skirts use a common middle helper plus the front/back lower helpers, avoiding independent left/right leg control of the outer garment. Skin weights are normalized with at most four influences. The source UVs and decoded original image pixels are checked numerically at delivery; source hashes are provenance only.

The pose sheet covers target walk stride, conversation, work reach, seated conversation, sleep, arms above the head, torso twist, deep knees/elbows and head yaw. The deep-bend sheet is an ungrounded manual limit pose, not evidence of chair or floor contact. Actual Godot furniture contacts, foot sliding, eyelid behavior and LOD presentation are separate runtime acceptance steps.

The sampled clip surfaces have no separation between coincident UV-seam vertices and no vertices combining an arm family with a thigh/shin/apron family. Local stretching remains in the generated topology; this is not a claim of perfect topology or a watertight surface. The largest recorded sampled edge changes from 4.66 mm to 30.22 mm. See deformation-audit.json for the exact vertices, weights and clip phases.

Real height, side/back anatomy, hidden garment interiors, joint centers and unseen costume construction are inferred from a single front concept. Back views are generated interpretations, not reference-confirmed matches. Facial mouth/cheek controls, expression completeness and hair aging are not supplied by this body mesh; runtime eyelids are integrated separately.

Delivery validation reports no failures. Remaining warnings: CH_Saki_Body_LOD0: 3741 doubled vertices within 0.0001; CH_Saki_Body_LOD1: 12 edges shared by more than two faces; CH_Saki_Body_LOD2: 12 edges shared by more than two faces. These are retained as topology limitations, not treated as a watertightness pass.
