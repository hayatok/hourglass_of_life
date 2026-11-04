class_name ResidentContacts
extends Node3D

var avatar: Node3D
var model: JrpgResidentModel
var skeleton: Skeleton3D
var pose_samples: Dictionary = {}
var rest_feet: Dictionary = {}
var rest_shoulder := 1.30
var hand_ik: Dictionary = {}
var foot_ik: Dictionary = {}
var hand_targets: Dictionary = {}
var foot_targets: Dictionary = {}
var poles: Dictionary = {}
var wrists: ContactRotation
var look: LookAtModifier3D
var look_target: Node3D
var step: Node3D
var mug: Node3D
var greeting := 0.0
var time := 0.0
var observed: Dictionary = {}
var foot_plant: ResidentFootPlant
var social_motion: ResidentSocialMotion
var interaction_motion
var interaction_result: Dictionary = {}

func _node(name: String) -> Node3D:
	var node := Node3D.new();node.name = name;add_child(node)
	return node

func point(bone: String, local: Vector3 = Vector3.ZERO) -> Vector3:
	return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("DEF-"+bone))*local

func _sample(clip: String) -> Dictionary:
	model.animator.play(clip,0);model.animator.seek(.6,true);model.animator.advance(0)
	var to_model := model.global_transform.affine_inverse()
	return {"pelvis":to_model*point("pelvis"),"head":to_model*point("head",Vector3(0,.12,0))}

func bind_model(owner_avatar: Node3D, resident_model: JrpgResidentModel) -> void:
	avatar = owner_avatar;model = resident_model;skeleton = model.skeleton
	interaction_motion = ResidentInteractionMotion.new()
	pose_samples.seat = _sample("sit_talk");pose_samples.bed = _sample("sleep")
	model.animator.play("idle",0);model.animator.seek(0,true);model.animator.advance(0)
	var to_model := model.global_transform.affine_inverse()*skeleton.global_transform
	for side in ["L","R"]:
		var rest := to_model*skeleton.get_bone_global_rest(skeleton.find_bone("DEF-foot."+side))
		rest_feet[side] = rest
	rest_shoulder = (to_model*skeleton.get_bone_global_rest(skeleton.find_bone("DEF-upper_arm.L"))).origin.y
	social_motion = ResidentSocialMotion.new();social_motion.name = "ConversationPosture";skeleton.add_child(social_motion)
	look_target = _node("AttentionTarget")
	look = LookAtModifier3D.new();look.name = "Attention"
	skeleton.add_child(look);look.bone_name = "DEF-head";look.target_node = look.get_path_to(look_target)
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look.use_angle_limitation = true;look.symmetry_limitation = true
	look.primary_limit_angle = .80;look.secondary_limit_angle = .55;look.duration = .25;look.active = false
	foot_plant = ResidentFootPlant.new();foot_plant.name = "WalkingSupport"
	foot_plant.contacts = self;skeleton.add_child(foot_plant)
	for side in ["L","R"]:
		hand_targets[side] = _node("HandTarget"+side)
		foot_targets[side] = _node("FootTarget"+side)
		poles["hand"+side] = _node("Elbow"+side)
		poles["foot"+side] = _node("Knee"+side)
		hand_ik[side] = _ik("Hand"+side,"upper_arm."+side,"forearm."+side,"hand."+side,hand_targets[side],poles["hand"+side])
		foot_ik[side] = _ik("Foot"+side,"thigh."+side,"shin."+side,"foot."+side,foot_targets[side],poles["foot"+side])
	wrists = ContactRotation.new();wrists.name = "ContactOrientation";skeleton.add_child(wrists)
	skeleton.skeleton_updated.connect(_observe)
	step = preload("res://game/assets/furniture/PR_Footstool.glb").instantiate();step.name = "ChildStep";add_child(step);step.hide()
	mug = preload("res://game/assets/furniture/PR_Mug.glb").instantiate();mug.name = "HeldMug";add_child(mug);mug.hide()

func _ik(name: String, root: String, middle: String, end: String, target: Node3D, pole: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new();ik.name = name;skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0,"DEF-"+root);ik.set_middle_bone_name(0,"DEF-"+middle);ik.set_end_bone_name(0,"DEF-"+end)
	ik.set_target_node(0,ik.get_path_to(target));ik.set_pole_node(0,ik.get_path_to(pole))
	ik.set_pole_direction(0,SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z)
	ik.active = false
	return ik

func detach() -> void:
	for nodes in [hand_ik,foot_ik]:
		for node in nodes.values(): node.free()
	if is_instance_valid(look): look.free()
	if is_instance_valid(wrists): wrists.free()
	if is_instance_valid(foot_plant): foot_plant.free()
	if is_instance_valid(social_motion): social_motion.free()

func greet() -> void: greeting = 1.8

func prepare_motion(p: Dictionary, activity: Dictionary, pose: Dictionary, delta: float) -> Dictionary:
	interaction_result = interaction_motion.update(self,p,activity,pose,delta)
	return interaction_result

func update_contact(p: Dictionary, activity: Dictionary, clip: String, attention: Vector3, attend: bool, delta: float) -> void:
	time += delta*model.animator.speed_scale
	greeting = maxf(0,greeting-delta*model.animator.speed_scale)
	var active: bool = not activity.is_empty() and not p.moving
	var seat: bool = active and activity.pose=="seat"
	var bed: bool = active and activity.pose=="bed"
	var work: bool = active and activity.pose=="work" and clip=="work"
	var tabletop_standing: bool = not p.moving and interaction_result.get("profile","")=="four_in_row" and interaction_result.get("phase","") not in ["travel","align","completed","interrupted"]
	var sewing_standing: bool = not p.moving and interaction_result.get("profile","")=="sewing" and interaction_result.get("phase","") not in ["to_source","carry_to_table","carry_to_store"]
	var child: bool = avatar.displayed_model=="rin"
	var body_scale: Vector3 = avatar.visual.scale
	var scale_y: float = body_scale.y
	var yaw: float = interaction_result.get("body_yaw",activity.yaw if active else avatar.visual.rotation.y)
	var facing := Basis(Vector3.UP,yaw)
	var root_target: Vector3 = avatar.global_position
	var rise := 0.0
	if seat:
		# Inferred hip padding is separate from the measured animated pelvis position.
		root_target = activity.contact+Vector3.UP*(.095*model.rest_height/1.65*scale_y)-facing*(pose_samples.seat.pelvis*body_scale)
		if child: root_target += facing*Vector3(0,0,.10)
	elif bed:
		root_target = activity.contact-facing*(pose_samples.bed.head*body_scale)
		root_target.y = activity.contact.y+.11*scale_y-pose_samples.bed.pelvis.y*scale_y
	elif (work or tabletop_standing or sewing_standing) and child:
		var surface_y: float = interaction_result.get("surface_y",activity.get("hand_left",Vector3.ZERO).y)
		rise = clampf(surface_y+.14-rest_shoulder*scale_y-avatar.global_position.y,0,.23)
		root_target += Vector3.UP*rise+facing*Vector3(0,0,.08)
	if active: avatar.visual.rotation.y = lerp_angle(avatar.visual.rotation.y,yaw,minf(1,delta*10))
	avatar.visual.position = avatar.visual.position.lerp(root_target-avatar.global_position,minf(1,delta*12))
	step.visible = child and (seat or work or tabletop_standing or sewing_standing)
	if step.visible:
		step.global_basis = facing
		if work or tabletop_standing or sewing_standing:
			step.scale.y = maxf(.1,rise/.23);step.global_position = root_target-Vector3.UP*rise
		else:
			var feet := (point("foot.L")+point("foot.R"))*.5
			step.global_position = Vector3(feet.x,avatar.global_position.y,feet.z)-facing*Vector3(0,0,.10)
			step.scale.y = 1
	look.active = not bed and (attend or work)
	if look.active: look_target.global_position = attention if attend else (activity.hand_left+activity.hand_right)*.5
	social_motion.update(avatar,attention,attend and not bed and not work,avatar.conversation_role=="listener",time,delta)
	wrists.targets.clear();wrists.eating = clip=="eat" and seat
	wrists.finger_curls = {"L":.12,"R":.12} if clip=="walk" else {}
	wrists.finger_rotations = interaction_result.get("finger_rotations",{})
	social_motion.action_lean = social_motion.action_lean.lerp(interaction_result.get("lean",Vector3.ZERO),minf(1,delta*10))
	foot_plant.walking = clip=="walk" and p.moving
	if not foot_plant.walking: foot_plant.reset()
	mug.visible = wrists.eating
	for side in ["L","R"]:
		var sign_x := 1.0 if side=="L" else -1.0
		var reaching: bool = work or (seat and clip=="eat")
		var hand: Node3D = hand_targets[side]
		if reaching:
			hand.global_position = activity.hand_left if side=="L" else activity.hand_right
			hand.global_basis = facing*Basis(Vector3.RIGHT,PI/2)
			if work: hand.global_position += Vector3.UP*(.025+.012*sin(time*3.1+sign_x))
			if clip=="eat" and side=="R":
				var phase := model.animator.current_animation_position/maxf(.01,model.animator.current_animation_length)
				var sip := pow(sin(PI*phase),4)
				var mouth := point("head",Vector3(0,.033,.105))
				var near_mouth := mouth+facing*Vector3(-.09,-.065,.035)
				hand.global_position = hand.global_position.lerp(near_mouth,sip)
				hand.global_basis = facing
			wrists.targets["DEF-hand."+side] = hand
		if greeting>0 and side=="L" and not work and not bed:
			var ramp := minf(1,minf((1.8-greeting)/.25,greeting/.25))
			var raised := point("head",Vector3(0,.12,0))+facing*Vector3(.23,.12,.08+.04*sin(time*15))
			hand.global_position = point("hand.L").lerp(raised,ramp)
			reaching = true;wrists.targets.erase("DEF-hand.L")
		hand_ik[side].active = reaching
		poles["hand"+side].global_position = avatar.visual.global_transform*Vector3(sign_x*.55,1.0,-.18)
		foot_ik[side].active = seat
		if seat:
			var foot: Node3D = foot_targets[side]
			var pos := point("foot."+side)
			pos.y = avatar.global_position.y+(.12 if child else 0.0)+rest_feet[side].origin.y*scale_y
			foot.global_position = pos;foot.global_basis = facing*rest_feet[side].basis.orthonormalized()
			poles["foot"+side].global_position = avatar.visual.global_transform*Vector3(sign_x*.12,.45,.9)
			wrists.targets["DEF-foot."+side] = foot
		var word := "left" if side=="L" else "right"
		if interaction_result.has(word):
			hand.global_transform = interaction_result[word]
			hand_ik[side].active = true
			wrists.targets["DEF-hand."+side] = hand
			poles["hand"+side].global_position = avatar.visual.global_transform*Vector3(sign_x*.32,rest_shoulder-.24,.12)
			if interaction_result.has("elbow_"+word): poles["hand"+side].global_position = interaction_result["elbow_"+word]
		if interaction_result.has("fingers_"+word):
			wrists.finger_curls[side] = interaction_result["fingers_"+word]
		elif interaction_result.has("grip_"+word):
			wrists.finger_curls[side] = interaction_result["grip_"+word]

func _observe() -> void:
	# A queued skeleton update can outlive removal during a town rebuild or body swap.
	if not is_inside_tree() or not is_instance_valid(skeleton) or not skeleton.is_inside_tree(): return
	observed.clear()
	for side in ["L","R"]:
		observed["hand"+side] = point("hand."+side)
		observed["hand_pose"+side] = skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("DEF-hand."+side))
		var word := "left" if side=="L" else "right"
		if interaction_result.has("palm_local_"+word): observed["palm"+side] = point("hand."+side,interaction_result["palm_local_"+word])
		if interaction_result.has("pinch_local_"+word): observed["pinch"+side] = point("hand."+side,interaction_result["pinch_local_"+word])
		if interaction_result.has("finger_pad_local_"+word):
			var pads: Dictionary = interaction_result["finger_pad_local_"+word]
			var actual_pads := {"thumb":point("finger0."+side,pads.thumb),"index":point("finger1."+side,pads.index)}
			observed["finger_pad"+side] = actual_pads
			observed["pinch"+side] = (actual_pads.thumb+actual_pads.index)*.5
			var finger_poses := {};var finger_rotations := {}
			for entry in [["thumb",0],["index",1]]:
				var bone := skeleton.find_bone("DEF-finger%d.%s"%[entry[1],side])
				finger_poses[entry[0]] = skeleton.global_transform*skeleton.get_bone_global_pose(bone)
				finger_rotations[entry[0]] = skeleton.get_bone_pose_rotation(bone)
			observed["finger_pose"+side] = finger_poses
			observed["finger_rotation"+side] = finger_rotations
		observed["foot"+side] = point("foot."+side)
		if hand_ik.has(side) and hand_ik[side].active:
			observed["hand_error"+side] = observed["hand"+side].distance_to(hand_targets[side].global_position)
		if foot_ik.has(side) and foot_ik[side].active:
			observed["foot_error"+side] = observed["foot"+side].distance_to(foot_targets[side].global_position)
	observed.pelvis = point("pelvis")
	observed.head = point("head",Vector3(0,.12,0))
	var head_pose := skeleton.get_bone_global_pose(skeleton.find_bone("DEF-head"))
	observed.head_forward = (skeleton.global_basis*head_pose.basis.z).normalized()
	observed.mouth = point("head",Vector3(0,.033,.105))
	if is_instance_valid(mug) and mug.visible:
		var facing := Basis(Vector3.UP,avatar.visual.rotation.y)
		mug.global_transform = Transform3D(facing*Basis(Vector3.UP,PI),observed.handR+facing*Vector3(.09,-.04,0))
