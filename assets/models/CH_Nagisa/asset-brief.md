# CH_Nagisa — 渚の制作基準

ASSET      CH_Nagisa 小川渚

CATEGORY   character / biped, human, original Japanese anime JRPG style

VIEWS      `ref/turnaround.png` (1774×887): front box (150,0,650,887), right-side box (650,0,1150,887), back box (1120,0,1620,887). Drawn orthographic A-pose, azimuth 0/90/180°, elevation 0°, lens 0. Top y≈28, sole y≈858: 830 px or 93.6% of image height, floor 3.3% from bottom. `ref/cast.png` is a perspective likeness/costume reference, not a dimension sheet. Cropped images share scale; paper and floor shadows are excluded from their alpha mattes. The side drawing has overlapping arms and a modestly different stance; this must remain a reported reference conflict if it limits comparison.

SCALE      1 Blender unit = 1 m; authored adult height 1.65 m including hair and shoes (inferred, this cast has no canonical real dimensions). 830 image pixels = 1.65 m, or 0.001987952 m/px. Z up, front −Y, origin at floor below body center. No gameplay movement scaling change.

PROPORTIONS Hair-to-sole 1.00; hair-to-chin about .16 (6.2 heads); hair max width .155; shoulder width .17; waist width .115; apron hem width .24; sole-to-apron-hem .33; sole-to-waist .65; sole-to-shoulder .80; sole-to-wrist .48; full A-pose finger width .44; shoe length .14 (side); hair depth .15 (side). Exact band profiles are measured by the reference and world gates, not read from the perspective lineup.

PARTS      Underlying complete skin body retained in HIGH; LOW delivery face/ears/neck and uncovered arms/hands, blouse with rolled sleeves and collar, cropped trousers with cuffs, leather shoes, front apron bib and lower panel, two pockets, crossing back straps, waist belt/tie. Each independently shading layer starts as a separate mesh. Face includes shaped jaw, small nose, inset anime eyes, iris, brows, upper lashes and mouth; hair is a bob shell with overlapping tapered locks. Deforming cloth/skin attach to one humanoid skeleton; rigid face/hair features to head, shoes to feet. Apron secondary bones have controlled pose motion rather than cloth simulation.

SILHOUETTE Dark chin-length bob with parted fringe; rolled sage sleeves; terracotta apron with flared knee-length hem and waist bow; pale cropped trousers and brown low shoes. Retain slender adult proportions and warm mature expression.

MATERIALS  Skin warm peach, roughness .7–.85; hair dark chestnut with restrained copper highlight bands, .6–.8; sage woven blouse .85–1; terracotta woven apron .85–1; ivory trousers .85–1; brown leather shoes .5–.7; brass small fasteners .3–.45 metallic .7. Original palette atlas, sRGB base color; neutral normals and role-based roughness, no baked directional lighting. Eye whites warm ivory, amber iris, dark upper lash. Opaque surfaces; avoid layered transparency.

ARTICULATION Humanoid A-pose: root/pelvis/spines/chest/neck/head, clavicles, upper/lower arms, hands/fingers, thighs/shins/feet/toes, apron hem. Hand, head, chest and foot sockets. In-place idle, walk, talk, joint work, sit/talk, eat, rest/sleep, wave. Expressions and gaze must be usable in Godot. Keep controls in source and export only deformation skeleton.

INFERRED   Real height, body depth under clothing, anatomy hidden under apron, exact blouse seam construction, palms/finger contours, underside of shoes, face depth and eye curvature, garment thickness, material response and all animation. Front and back drawings differ in arm and hem contours; use the front for primary proportions and record the back-view discrepancy. No claim that the drawn references are exact engineering blueprints.

TARGET     Godot 4.7 Compatibility, GLB; Mac M5 desktop target 60 fps, 8 residents; standard character tier: LOD0 ≤35k tris, LOD1 ≤15k, LOD2 ≤5k, 1–3 material groups, shared 1–2k texture family. Three-quarter overhead game camera fov48°, normal distance ≈22 m; model height roughly60–100 px, close view128–300 px. Check both small gameplay silhouette and close view face. One category representative passes its measured gates before expanding the cast.
