class_name FoundationResident
extends ResidentMotor

# The motor owns world-space movement. This adapter only supplies the skeleton
# pose, using the stride measured from the transferred source animation.
signal action_finished(clip: String)

var resident_id := ""
var model: JrpgResidentModel
var animation_tree: AnimationTree
var motion_contract: Dictionary = {}
var motion_ready := false
var locomotion: FoundationLocomotionPose
var furniture_pose
var _furniture_request: Dictionary = {}
var household_pose
var _household_request: Dictionary = {}
var current_action := ""
var action_elapsed := 0.0
var _action_node: AnimationNodeAnimation
var _action_weight := 0.0
var _locomotion_weight := 0.0
var _action_duration := 0.0
var _action_loop := false
var _last_action_finished := false
var _visual_seconds := 0.0
var _name_tag: Label3D

func load_resident(id: String) -> bool:
	if is_instance_valid(model): return false
	var scene_path := "res://game/scenes/characters/"+id+".tscn"
	var motion_path := "res://game/assets/motion/foundation/"+id+".tres"
	var contract_path := "res://game/assets/motion/foundation/"+id+".contract.json"
	if not ResourceLoader.exists(scene_path) or not ResourceLoader.exists(motion_path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(contract_path))
	if not parsed is Dictionary: return false
	motion_contract=parsed
	var scene := load(scene_path) as PackedScene
	model=scene.instantiate() as JrpgResidentModel
	if model==null: return false
	add_child(model)
	if not is_instance_valid(model.animator) or not is_instance_valid(model.skeleton):
		model.queue_free();return false
	var animator: AnimationPlayer=model.animator
	animator.stop()
	var library := load(motion_path).duplicate(true) as AnimationLibrary
	var animation_root: Node=animator.get_node(animator.root_node)
	var skeleton_path: String=str(animation_root.get_path_to(model.skeleton))
	for key in library.get_animation_list():
		var clip: Animation=library.get_animation(key)
		for track in clip.get_track_count():
			var source_path: NodePath=clip.track_get_path(track)
			if source_path.get_subname_count()!=1: return false
			clip.track_set_path(track,NodePath(skeleton_path+":"+str(source_path.get_subname(0))))
	for key in ["idle","walk","sit_enter","sit_idle","sit_exit","talk"]:
		if not library.has_animation(key): return false
	animator.add_animation_library("foundation",library)
	resident_id=id
	_build_animation_tree(animator,animation_root)
	motion_ready=true
	return true

func enable_contact_locomotion() -> bool:
	if not motion_ready or is_instance_valid(locomotion):return false
	var candidate:=FoundationLocomotionPose.new();candidate.name="FoundationLocomotionPose"
	model.skeleton.add_child(candidate)
	if not candidate.configure(self,model.animator.get_animation_library("foundation"),motion_contract,snapshot().profile):
		candidate.queue_free();return false
	model.skeleton.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	locomotion=candidate
	return true

func body_is_settled() -> bool:
	return state()=="idle" and (not is_instance_valid(locomotion) or locomotion.is_settled())

func enable_furniture_poses() -> bool:
	if not motion_ready or is_instance_valid(furniture_pose):return false
	var path: String="res://game/foundation/foundation_furniture_pose.gd"
	if not ResourceLoader.exists(path):return false
	var factory: Script=load(path)
	var candidate=factory.new();candidate.name="FoundationFurniturePose"
	model.skeleton.add_child(candidate)
	if not candidate.configure(self,model.animator.get_animation_library("foundation"),motion_contract,snapshot().profile):
		candidate.queue_free();return false
	model.skeleton.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	furniture_pose=candidate
	return true

func furniture_calibration() -> Dictionary:
	return furniture_pose.calibration() if is_instance_valid(furniture_pose) else {}

func use_furniture_pose(request: Dictionary) -> bool:
	if not is_instance_valid(furniture_pose):return false
	_furniture_request=request.duplicate(true)
	return true

func clear_furniture_pose() -> void:
	_furniture_request.clear()
	if is_instance_valid(furniture_pose):furniture_pose.clear()

func furniture_contacts_ready() -> bool:
	return is_instance_valid(furniture_pose) and furniture_pose.contacts_ready()

func enable_household_poses() -> bool:
	if not motion_ready or is_instance_valid(household_pose):return false
	var base: String="res://game/assets/motion/household/"+resident_id
	if not ResourceLoader.exists(base+".tres"):return false
	var contract: Variant=JSON.parse_string(FileAccess.get_file_as_string(base+".contract.json"))
	if not contract is Dictionary:return false
	var factory: Script=load("res://game/foundation/foundation_household_pose.gd")
	var candidate=factory.new();candidate.name="FoundationHouseholdPose"
	model.skeleton.add_child(candidate)
	if not candidate.configure(self,model.animator.get_animation_library("foundation"),motion_contract,snapshot().profile) or not candidate.set_action_library(load(base+".tres"),contract):
		candidate.queue_free();return false
	model.skeleton.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	household_pose=candidate
	return true

func household_calibration() -> Dictionary:
	return household_pose.calibration() if is_instance_valid(household_pose) else {}

func use_household_pose(request: Dictionary) -> bool:
	if not is_instance_valid(household_pose) or not household_pose.can_present(request):return false
	_household_request=request.duplicate(true)
	return true

func clear_household_pose() -> void:
	_household_request.clear()
	if is_instance_valid(household_pose):household_pose.clear()

func household_contacts_ready() -> bool:
	return is_instance_valid(household_pose) and household_pose.contacts_ready()

func household_transfer_ready(operation: String) -> bool:
	return is_instance_valid(household_pose) and household_pose.transfer_ready(operation)

func confirm_household_grasp(item_id: String) -> bool:
	return is_instance_valid(household_pose) and household_pose.confirm_grasp(item_id)

func confirm_household_release(item_id: String) -> bool:
	return is_instance_valid(household_pose) and household_pose.confirm_release(item_id)

func household_grasped_objects() -> Dictionary:
	return household_pose.grasped_objects() if is_instance_valid(household_pose) else {}

func bind_name_tag(label: Label3D) -> bool:
	if not motion_ready or not is_instance_valid(label) or model.skeleton.find_bone("DEF-head")<0:return false
	_name_tag=label;_name_tag.top_level=true
	if not model.skeleton.skeleton_updated.is_connected(_place_name_tag):model.skeleton.skeleton_updated.connect(_place_name_tag)
	return true

func _place_name_tag() -> void:
	if not is_instance_valid(_name_tag):return
	# Read the final modified skeleton in its own signal, not the unmodified
	# base pose outside the callback. A lying person's label follows their head.
	var head: Transform3D=model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.skeleton.find_bone("DEF-head"))
	_name_tag.global_position=head.origin+Vector3.UP*.28

func _clip(key: String) -> AnimationNodeAnimation:
	var result := AnimationNodeAnimation.new()
	result.animation="foundation/"+key
	return result

func _build_animation_tree(animator: AnimationPlayer, animation_root: Node) -> void:
	animation_tree=AnimationTree.new();animation_tree.name="FoundationMotion"
	add_child(animation_tree)
	animation_tree.anim_player=animation_tree.get_path_to(animator)
	animation_tree.root_node=animation_tree.get_path_to(animation_root)
	animation_tree.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var blend := AnimationNodeBlendTree.new()
	blend.add_node("Idle",_clip("idle"))
	blend.add_node("Walk",_clip("walk"))
	blend.add_node("IdleSeek",AnimationNodeTimeSeek.new());blend.connect_node("IdleSeek",0,"Idle")
	blend.add_node("WalkSeek",AnimationNodeTimeSeek.new());blend.connect_node("WalkSeek",0,"Walk")
	blend.add_node("WalkRate",AnimationNodeTimeScale.new())
	blend.connect_node("WalkRate",0,"WalkSeek")
	blend.add_node("Locomotion",AnimationNodeBlend2.new())
	blend.connect_node("Locomotion",0,"IdleSeek");blend.connect_node("Locomotion",1,"WalkRate")
	_action_node=_clip("idle");blend.add_node("Action",_action_node)
	blend.add_node("ActionSeek",AnimationNodeTimeSeek.new());blend.connect_node("ActionSeek",0,"Action")
	blend.add_node("Pose",AnimationNodeBlend2.new())
	blend.connect_node("Pose",0,"Locomotion");blend.connect_node("Pose",1,"ActionSeek")
	blend.connect_node("output",0,"Pose")
	animation_tree.tree_root=blend
	animation_tree.active=true
	animation_tree.advance(0)

func tick_body(delta: float, moving: bool = true) -> bool:
	if not motion_ready or not is_finite(delta) or delta<0 or delta>1: return false
	if moving and not tick(delta): return false
	var speed: float=pose().speed
	# Blend only during departure/arrival, rather than reducing the full walk
	# amplitude in proportion to speed throughout a slow step.
	_locomotion_weight=move_toward(_locomotion_weight,1.0 if speed>.015 else 0.0,delta/.16)
	var stride_speed: float=float(motion_contract.get("clips",{}).get("walk",{}).get("authored_speed_mps",.975))
	_visual_seconds+=delta
	# Seek from authoritative travelled distance, including after a JSON resume.
	# A render-rate accumulator cannot gradually drift away from the motor.
	animation_tree.set("parameters/WalkRate/scale",0.0)
	animation_tree.set("parameters/WalkSeek/seek_request",fmod(float(pose().gait_distance)/maxf(.01,stride_speed),model.animator.get_animation("foundation/walk").length))
	animation_tree.set("parameters/IdleSeek/seek_request",fmod(_visual_seconds,model.animator.get_animation("foundation/idle").length))
	animation_tree.set("parameters/Locomotion/blend_amount",_locomotion_weight)
	_action_weight=move_toward(_action_weight,0.0 if current_action.is_empty() else 1.0,delta/.12)
	animation_tree.set("parameters/Pose/blend_amount",_action_weight)
	if is_instance_valid(locomotion):
		var gait: Dictionary=pose()
		if gait.state=="interaction":
			# Furniture root tracks are not forward walking. Disable walking IK
			# without feeding its state machine a fabricated walking velocity.
			gait.state="idle";gait.speed=0.0;gait.normalized_speed=0.0
		var walking_with_load: bool=_household_request.get("phase","")=="carry"
		locomotion.advance(gait,delta,_furniture_request.is_empty() and (_household_request.is_empty() or walking_with_load) and (current_action.is_empty() or current_action=="idle"))
	if is_instance_valid(furniture_pose) and not _furniture_request.is_empty():
		_furniture_request.pose_seconds=_visual_seconds
		furniture_pose.present(_furniture_request,delta)
	if is_instance_valid(household_pose) and not _household_request.is_empty():
		_household_request.pose_seconds=_visual_seconds
		household_pose.present(_household_request,delta)
	animation_tree.advance(delta)
	if is_instance_valid(locomotion) or is_instance_valid(furniture_pose) or is_instance_valid(household_pose):model.skeleton.advance(delta)
	if not current_action.is_empty():
		action_elapsed+=delta
		if not _action_loop and not _last_action_finished and action_elapsed>=_action_duration:
			_last_action_finished=true;action_finished.emit(current_action)
	return true

func play_action(clip: String) -> bool:
	if not motion_ready or not _furniture_request.is_empty() or not body_is_settled() or not model.animator.has_animation("foundation/"+clip): return false
	if current_action==clip: return true
	var animation: Animation=model.animator.get_animation("foundation/"+clip)
	current_action=clip;action_elapsed=0;_action_duration=animation.length
	_action_loop=animation.loop_mode!=Animation.LOOP_NONE;_last_action_finished=false
	_action_node.animation="foundation/"+clip
	animation_tree.set("parameters/ActionSeek/seek_request",0.0)
	return true

func clear_action() -> void:
	current_action="";action_elapsed=0;_last_action_finished=false

func action_is_finished() -> bool:
	return _last_action_finished

func motion_state() -> Dictionary:
	return {"schema":3,"resident_id":resident_id,"motor":snapshot(),"action":current_action,"action_elapsed":action_elapsed,
		"motion_ready":motion_ready,"locomotion_blend":_locomotion_weight,"action_blend":_action_weight,"visual_seconds":_visual_seconds,
		"locomotion":locomotion.snapshot() if is_instance_valid(locomotion) else {},
		"furniture":furniture_pose.snapshot() if is_instance_valid(furniture_pose) else {},
		"household":household_pose.snapshot() if is_instance_valid(household_pose) else {},
		"source":"Quaternius Universal Animation Library Standard, CC0"}

func can_restore_motion(data: Variant) -> bool:
	if not motion_ready or not data is Dictionary or data.get("schema")!=3 or data.get("resident_id")!=resident_id:return false
	if not data.get("motor") is Dictionary or ResidentMotor._checked_snapshot(data.motor).is_empty():return false
	if not data.get("action") is String or data.action.length()>48:return false
	if not data.action.is_empty() and not model.animator.has_animation("foundation/"+data.action):return false
	for key in ["action_elapsed","visual_seconds","locomotion_blend","action_blend"]:
		if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])) or data[key]<0:return false
	if data.locomotion_blend>1 or data.action_blend>1 or data.action_elapsed>100000000 or data.visual_seconds>100000000:return false
	if not data.get("locomotion") is Dictionary:return false
	if is_instance_valid(locomotion):
		if not locomotion.can_restore(data.locomotion):return false
	elif not data.locomotion.is_empty():return false
	if not data.get("furniture") is Dictionary:return false
	if is_instance_valid(furniture_pose):
		if not furniture_pose.can_restore(data.furniture):return false
	elif not data.furniture.is_empty():return false
	if not data.get("household") is Dictionary:return false
	if is_instance_valid(household_pose):
		if not household_pose.can_restore(data.household):return false
	elif not data.household.is_empty():return false
	return true

func restore_motion(data: Variant) -> bool:
	if not can_restore_motion(data):return false
	if not restore(data.motor):return false
	current_action="";_furniture_request.clear();_household_request.clear();_visual_seconds=float(data.visual_seconds)
	_locomotion_weight=float(data.locomotion_blend);_action_weight=float(data.action_blend)
	if not data.action.is_empty():
		# Saved bodies can be in a turn/arrival state. Restoration is distinct
		# from starting a new action, which still requires an idle motor.
		current_action=data.action
		var animation: Animation=model.animator.get_animation("foundation/"+current_action)
		_action_node.animation="foundation/"+current_action;_action_duration=animation.length
		_action_loop=animation.loop_mode!=Animation.LOOP_NONE
		action_elapsed=float(data.action_elapsed)
		_last_action_finished=not _action_loop and action_elapsed>=_action_duration
		animation_tree.set("parameters/ActionSeek/seek_request",fmod(action_elapsed,_action_duration) if _action_loop else minf(action_elapsed,_action_duration))
	else:action_elapsed=0;_last_action_finished=false
	tick_body(0,false)
	if is_instance_valid(locomotion):locomotion.restore(data.locomotion)
	if is_instance_valid(furniture_pose):
		furniture_pose.restore(data.furniture)
		_furniture_request=furniture_pose.request_state()
	if is_instance_valid(household_pose):
		household_pose.restore(data.household)
		_household_request=household_pose.request_state()
	return true
