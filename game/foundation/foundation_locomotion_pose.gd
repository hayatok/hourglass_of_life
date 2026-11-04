class_name FoundationLocomotionPose
extends SkeletonModifier3D

# This modifier owns the final locomotion pose after AnimationTree. ResidentMotor
# alone owns world translation/yaw. Source clips supply the complete body pose;
# exact target bone lengths solve to world shoe contacts and visible swing steps.
# Flat floor only: no collision/step-height/terrain claim is made here.
const FORMAT := 1
const SIDES := ["L", "R"]
const POINTS := ["heel", "ball", "toe"]
const MODES := ["idle", "start", "walk", "stop", "turn"]
const STANDING_CORE := ["DEF-pelvis","DEF-spine_01","DEF-spine_02","DEF-chest","DEF-neck","DEF-head"]
const FLOOR_CLEARANCE := .005

var _actor: Node3D
var _library: AnimationLibrary
var _contract: Dictionary = {}
var _profile := {"walk_speed":1.1,"acceleration":1.8,"deceleration":2.2}
var _bones: Dictionary = {}
var _parents: Array[int] = []
var _order: Array[int] = []
var _tracks: Dictionary = {}
var _contacts: Dictionary = {}
var _rest_globals: Array[Transform3D] = []
var _idle_reference: Array[Transform3D] = []
var _leg_lengths: Dictionary = {}
var _skeleton_in_actor := Transform3D.IDENTITY
var _stride := 1.0
var _walk_length := 1.0
var _floor := 0.0
var _configured := false
var _enabled := true
var _input: Dictionary = {}
var _delta := 0.0
var _serial := 0
var _applied := -1
var _m: Dictionary = {}
var _observations: Dictionary = {}

func configure(actor: Node3D, library: AnimationLibrary, contract: Dictionary, profile: Dictionary = {}) -> bool:
	var skeleton := get_skeleton()
	if skeleton==null or actor==null or library==null: return false
	for key in ["idle","walk"]:
		if not library.has_animation(key): return false
	var contact_data: Variant=contract.get("contact_geometry",{})
	if not contact_data is Dictionary: return false
	var geometry: Variant = contact_data.get("feet",{})
	if not geometry is Dictionary: return false
	var contacts := {}
	for side in SIDES:
		if not geometry.get(side) is Dictionary: return false
		var points: Variant = geometry[side].get("points")
		if not points is Dictionary: return false
		contacts[side] = {}
		for point in POINTS:
			if not points.get(point) is Dictionary: return false
			var record: Dictionary = points[point]
			if not record.get("influences") is Array or record.influences.is_empty(): return false
			var influences: Array = [];var total := 0.0
			for influence_record in record.influences:
				if not influence_record is Dictionary: return false
				var bone: int = skeleton.find_bone(str(influence_record.get("bone","")))
				var position: Variant = _vec(influence_record.get("bone_local_position"))
				var weight: Variant = influence_record.get("weight")
				if bone<0 or position==null or not _finite_number(weight) or weight<=0: return false
				# A rigid ankle translation must translate every influence. Contacts
				# containing thigh/other-body weights cannot silently use this solver.
				if str(influence_record.bone) not in ["DEF-foot."+side,"DEF-toe."+side]: return false
				influences.append({"bone":bone,"position":position,"weight":float(weight)})
				total+=float(weight)
			if absf(total-1.0)>.0001: return false
			contacts[side][point] = influences
	var merged := _profile.duplicate()
	for key in merged:
		if profile.has(key):
			if not _finite_number(profile[key]) or profile[key]<=0: return false
			merged[key]=float(profile[key])
	_actor=actor;_library=library;_contract=contract;_profile=merged;_contacts=contacts
	_skeleton_in_actor=actor.global_transform.affine_inverse()*skeleton.global_transform
	_floor=actor.global_position.y
	_stride=float(contract.get("clips",{}).get("walk",{}).get("authored_stride_m",0))
	_walk_length=library.get_animation("walk").length
	if _stride<=0 or _walk_length<=0: return false
	_bones.clear();_parents.clear();_order.clear();_tracks.clear()
	for index in skeleton.get_bone_count():
		_bones[skeleton.get_bone_name(index)]=index
		_parents.append(skeleton.get_bone_parent(index));_order.append(index)
	for side in SIDES:
		for part in ["thigh","shin","foot","toe"]:
			if not _bones.has("DEF-"+part+"."+side): return false
	for part in ["DEF-pelvis","DEF-chest","DEF-head"]:
		if not _bones.has(part): return false
	_order.sort_custom(func(a,b): return _depth(a)<_depth(b))
	for key in ["idle","walk"]:
		var animation: Animation=library.get_animation(key)
		var tracks: Array = []
		for index in animation.get_track_count():
			var path := animation.track_get_path(index)
			if path.get_subname_count()!=1: continue
			var name: String=str(path.get_subname(0))
			if _bones.has(name): tracks.append({"bone":_bones[name],"track":index,"type":animation.track_get_type(index)})
		_tracks[key]=tracks
	_rest_globals.clear()
	for index in skeleton.get_bone_count(): _rest_globals.append(skeleton.get_bone_global_rest(index))
	_idle_reference=_globals(_sample("idle",0))
	_leg_lengths.clear()
	for side in SIDES:
		_leg_lengths[side]=Vector2(skeleton.get_bone_rest(_bones["DEF-shin."+side]).origin.length(),skeleton.get_bone_rest(_bones["DEF-foot."+side]).origin.length())
	_m={"mode":"idle","last_motor":"idle","phase":0.0,"distance_origin":0.0,"phase_offset":0.0,
		"clock":0.0,"duration":1.0,"swing":"L","from":Transform3D.IDENTITY,"goal":Transform3D.IDENTITY,
		"feet":{},"turn_start":0.0,"turn_total":0.0,"turn_sign":1.0,"turn_steps":2,"turn_step":-1,
		"entry":[],"last_pose":[],"stop_stage":0,"source_phase":0.0,"settle_clock":0.0,"initialized":false}
	_serial=0;_applied=-1;_input.clear();_configured=true
	return true

func advance(motor_pose: Dictionary, delta: float, locomotion_enabled: bool = true) -> bool:
	if not _configured or not _finite_number(delta) or delta<0 or delta>1: return false
	if not _valid_input(motor_pose): return false
	var pending_delta: float=_delta+delta if _applied!=_serial and _enabled and locomotion_enabled else delta
	if pending_delta>1: return false
	_input=motor_pose.duplicate(true);_delta=pending_delta;_enabled=locomotion_enabled;_serial+=1
	return true

func is_settled() -> bool:
	return _m.get("mode","idle")=="idle"

func telemetry() -> Dictionary:
	return _observations.duplicate(true)

func _process_modification_with_delta(_skeleton_delta: float) -> void:
	if not _configured or _input.is_empty(): return
	if not _enabled:
		_m.initialized=false;_m.last_pose=[];_m.mode="idle";_applied=_serial
		return
	if _applied==_serial:
		if not _m.last_pose.is_empty(): _set_locals(_m.last_pose)
		return
	_applied=_serial
	if not _m.initialized:
		_initialize_feet()
		_m.distance_origin=float(_input.gait_distance);_m.initialized=true
	var motor_state: String=_input.state
	if motor_state=="turn" and _m.mode!="turn": _begin_turn()
	elif motor_state=="start" and _m.mode=="idle": _begin_start()
	elif motor_state=="stop" and _m.mode in ["walk","start"]: _begin_stop()
	elif motor_state=="walk" and _m.mode=="idle":
		_m.mode="walk";_m.distance_origin=float(_input.gait_distance)
	_m.clock=float(_m.clock)+_delta
	var goals: Dictionary = {}
	match str(_m.mode):
		"turn": goals=_turn_pose()
		"start": goals=_start_pose()
		"stop": goals=_stop_pose()
		"walk": goals=_walk_pose()
		_:
			_set_locals(_standing_pose(float(_m.clock)))
			goals=_idle_goals()
	_apply_goals(goals)
	_m.last_motor=motor_state
	_m.last_pose=_read_locals()
	_observations["mode"]=_m.mode;_observations["motor_state"]=motor_state
	_observations["source_phase"]=_m.source_phase;_observations["turn_step"]=_m.turn_step
	_observations["swing_side"]=_m.swing

func _initialize_feet() -> void:
	_m.feet={}
	for side in SIDES:
		var neutral := _reference_foot("neutral",0,side,_actor.global_transform)
		_m.feet[side]={"transform":neutral,"anchor":Vector3.ZERO,"point":"heel","locked":true}
		_land(side,neutral)
	_m.entry=_read_locals()

func _begin_start() -> void:
	_m.mode="start";_m.clock=0.0;_m.duration=float(_profile.walk_speed)/float(_profile.acceleration)
	_m.entry=_prior_pose();_m.swing=_other(_departure_support())
	_m.from=_m.feet[_m.swing].transform
	var future := _actor.global_transform
	future.origin+=future.basis.z*(float(_profile.walk_speed)*float(_m.duration)*.5)
	var landing_phase := 1.0 if _m.swing=="L" else .5
	_m.goal=_reference_foot("walk",landing_phase*_walk_length,str(_m.swing),future)
	_m.feet[_m.swing].locked=false

func _start_pose() -> Dictionary:
	var progress := clampf(float(_m.clock)/maxf(.001,float(_m.duration)),0,1)
	var phase := (.5 if _m.swing=="L" else 0.0)+.5*progress
	_m.source_phase=phase
	var pose := _sample("walk",phase*_walk_length)
	_set_locals(_blend_entry(pose,progress/.45))
	var goals := _step_goals(progress,str(_m.swing),true)
	if progress>=1:
		_land(str(_m.swing),_m.goal)
		_m.mode="walk";_m.distance_origin=float(_input.gait_distance);_m.phase_offset=fposmod(phase,1.0)
	if _input.state=="idle" and progress<1: _begin_stop()
	return goals

func _walk_pose() -> Dictionary:
	var phase := fposmod((float(_input.gait_distance)-float(_m.distance_origin))/_stride+float(_m.phase_offset),1.0)
	_m.phase=phase;_m.source_phase=phase
	_set_locals(_sample("walk",phase*_walk_length))
	var goals := {}
	for side in SIDES:
		var relative_phase := fposmod(phase+(.5 if side=="R" else 0.0),1.0)
		if relative_phase>=.62:
			_m.feet[side].locked=false;goals[side]=_ground_safe(_foot_world(side),side)
			continue
		var point: String="heel" if relative_phase<.11 else ("ball" if relative_phase<.43 else "toe")
		if not _m.feet[side].locked:
			_m.feet[side].point=point;_m.feet[side].anchor=_point_world(side,point)
			_m.feet[side].anchor.y=_floor+FLOOR_CLEARANCE;_m.feet[side].locked=true
		elif point!=_m.feet[side].point:
			# Roll from the old material support to the next only when that
			# actual point reaches the floor. Native/raw ankle position is not
			# the constrained shoe position and must not replace the world anchor.
			var held := _locked_goal(side,false)
			var local_point := _foot_world(side).affine_inverse()*_point_world(side,point)
			var candidate := held*local_point
			if candidate.y<=_floor+FLOOR_CLEARANCE+.006:
				_m.feet[side].point=point;_m.feet[side].anchor=Vector3(candidate.x,_floor+FLOOR_CLEARANCE,candidate.z)
		goals[side]=_locked_goal(side,false)
	if _input.state=="idle": _begin_stop()
	return goals

func _begin_stop() -> void:
	_m.mode="stop";_m.clock=0.0;_m.stop_stage=0;_m.entry=_prior_pose()
	var support := _best_support()
	_m.swing=_other(support);_m.source_phase=float(_m.get("phase",0.0))
	_m.from=_m.feet[_m.swing].transform
	_m.duration=maxf(.16,float(_input.speed)/float(_profile.deceleration))
	var stopping := _actor.global_transform
	stopping.origin+=stopping.basis.z*(float(_input.speed)*float(_input.speed)/(2.0*float(_profile.deceleration)))
	_m.goal=_reference_foot("neutral",0.0,str(_m.swing),stopping)
	_m.feet[_m.swing].locked=false

func _stop_pose() -> Dictionary:
	var progress := clampf(float(_m.clock)/maxf(.001,float(_m.duration)),0,1)
	var phase: float=float(_m.source_phase)+float(_input.speed)*_delta/_stride
	_m.source_phase=phase
	var walk_pose := _sample("walk",fposmod(phase,1.0)*_walk_length)
	var idle_pose := _standing_pose(0)
	var body_weight := _ease(progress*.7) if _m.stop_stage==0 else .7+.3*_ease(progress)
	_set_locals(_blend(walk_pose,idle_pose,body_weight))
	var goals := _step_goals(progress,str(_m.swing),true)
	if progress>=1:
		_land(str(_m.swing),_m.goal)
		if _m.stop_stage==0:
			# The old support foot also closes visibly. This can continue after
			# the motor is at rest, so an action waits for is_settled().
			_m.stop_stage=1;_m.clock=0.0;_m.duration=.28;_m.swing=_other(str(_m.swing))
			_m.from=_m.feet[_m.swing].transform
			_m.goal=_reference_foot("neutral",0,str(_m.swing),_actor.global_transform)
			_m.feet[_m.swing].locked=false
		else:
			_m.mode="idle";_m.clock=0.0
	return goals

func _begin_turn() -> void:
	var prior_swing: String=str(_m.swing)
	var continuing_step: bool=_m.mode in ["start","stop"]
	_m.mode="turn";_m.entry=_prior_pose();_m.clock=0.0
	var progress: float=clampf(float(_input.turn_progress),0,.999999)
	_m.turn_total=absf(float(_input.turn_angle))/maxf(.000001,1.0-progress)
	_m.turn_sign=1.0 if float(_input.turn_angle)>=0 else -1.0
	_m.turn_start=float(_input.heading)-float(_m.turn_sign)*float(_m.turn_total)*progress
	_m.turn_steps=2 if float(_m.turn_total)<=PI*.5+.01 else 4
	_m.turn_step=-1;_m.settle_clock=0.0
	_m.swing=prior_swing if continuing_step else ("L" if _m.turn_sign>0 else "R")

func _turn_pose() -> Dictionary:
	var progress: float=clampf(float(_input.turn_progress),0,1) if _input.state=="turn" else 1.0
	var scaled := progress*int(_m.turn_steps)
	var step: int=mini(int(_m.turn_steps)-1,int(floor(scaled)))
	var fraction := 1.0 if progress>=1 else scaled-float(step)
	if step!=int(_m.turn_step):
		if int(_m.turn_step)>=0: _land(str(_m.swing),_m.goal);_m.swing=_other(str(_m.swing))
		_m.turn_step=step;_m.from=_m.feet[_m.swing].transform
		var quarter: int=step/2+1
		var desired_yaw: float=float(_m.turn_start)+float(_m.turn_sign)*minf(float(_m.turn_total),float(quarter)*PI*.5)
		var root := Transform3D(Basis(Vector3.UP,desired_yaw),_actor.global_position)
		_m.goal=_reference_foot("neutral",0,str(_m.swing),root)
		_m.feet[_m.swing].locked=false
	var phase: float=(.5 if _m.swing=="L" else 0.0)+fraction*.5
	_m.source_phase=phase
	var body := _blend_entry(_sample("walk",phase*_walk_length),float(_m.clock)/.15)
	if progress>.85:
		body=_blend(body,_standing_pose(0),_ease(clampf((progress-.85)/.15,0,1)))
	if progress>=1:
		_m.settle_clock=float(_m.settle_clock)+_delta
		body=_blend(body,_standing_pose(0),_ease(clampf(float(_m.settle_clock)/.12,0,1)))
	_set_locals(body)
	# Source torso/pelvis/arms keep their whole-body weight transfer. Head and
	# chest add a small local look lead; world heading is never changed here.
	_look_lead(float(_input.turn_angle))
	var goals := _step_goals(fraction,str(_m.swing),true)
	if fraction>=1 and step==int(_m.turn_steps)-1:
		_land(str(_m.swing),_m.goal)
		if _input.state!="turn":
			_m.mode="idle";_m.clock=0.0
	return goals

func _step_goals(progress: float, swing: String, hold_orientation: bool) -> Dictionary:
	var goals := {};var support := _other(swing)
	goals[support]=_locked_goal(support,hold_orientation)
	var goal := _rigid_blend(_m.from,_m.goal,_ease(progress))
	# This is a newly authored short foot trajectory. Leg rotations are solved
	# at real length; no limb-angle amplitude multiplier is applied.
	goal.origin.y+=sin(PI*progress)*clampf(.055*float(_contract.get("translation_scale",1.0)),.035,.07)
	goals[swing]=goal
	return goals

func _idle_goals() -> Dictionary:
	var result := {}
	for side in SIDES: result[side]=_locked_goal(side,true)
	return result

func _land(side: String, pose: Transform3D) -> void:
	_m.feet[side].transform=pose
	# Landing captures the selected real surface point after the intended ankle
	# displacement, not a newly invented ankle-to-ground constant.
	var point := "heel";var low := INF;var local_point := Vector3.ZERO
	var prior: Array=_m.last_pose if not _m.last_pose.is_empty() else _read_locals()
	var globals := _globals(prior)
	var ankle: Transform3D=globals[_bones["DEF-foot."+side]]
	for key in POINTS:
		var position := Vector3.ZERO
		for record in _contacts[side][key]: position+=(globals[record.bone]*record.position)*float(record.weight)
		var candidate := ankle.affine_inverse()*position
		if (pose*candidate).y<low:
			low=(pose*candidate).y;point=key;local_point=candidate
	_m.feet[side].point=point;_m.feet[side].anchor=pose*local_point
	_m.feet[side].anchor.y=_floor+FLOOR_CLEARANCE;_m.feet[side].locked=true

func _locked_goal(side: String, hold_orientation: bool) -> Transform3D:
	var raw := _foot_world(side)
	var point := _point_world(side,str(_m.feet[side].point))
	var result := raw
	if hold_orientation: result.basis=(_m.feet[side].transform as Transform3D).basis
	var local_point := raw.affine_inverse()*point
	result.origin=(_m.feet[side].anchor as Vector3)-result.basis*local_point
	return result

func _ground_safe(raw: Transform3D, side: String) -> Transform3D:
	var low := INF
	for key in POINTS: low=minf(low,_point_world(side,key).y)
	if low<_floor+FLOOR_CLEARANCE: raw.origin.y+=_floor+FLOOR_CLEARANCE-low
	return raw

func _apply_goals(goals: Dictionary) -> void:
	var skeleton := get_skeleton()
	var pelvis: int=_bones["DEF-pelvis"]
	var pelvis_pose := skeleton.global_transform*skeleton.get_bone_global_pose(pelvis)
	# Reach feasibility moves the posed pelvis a little, never the motor or bones.
	var lower := 0.0
	for side in SIDES:
		var hip := _bone_world("DEF-thigh."+side).origin
		var segments: Vector2=_leg_lengths[side]
		var length := segments.x+segments.y
		var goal: Transform3D=goals[side]
		var horizontal := Vector2(hip.x-goal.origin.x,hip.z-goal.origin.z).length()
		var max_height := sqrt(maxf(0,length*length-horizontal*horizontal))
		lower=maxf(lower,hip.y-goal.origin.y-max_height+.001)
	if lower>0:
		pelvis_pose.origin.y-=minf(lower,.06)
		skeleton.set_bone_global_pose(pelvis,skeleton.global_transform.affine_inverse()*pelvis_pose)
	var errors := {};var reach := {};var actual_points := {}
	for side in SIDES:
		reach[side]=_solve_leg(side,goals[side])
		_m.feet[side].transform=_foot_world(side)
		if _m.feet[side].locked:
			errors[side]=_point_world(side,str(_m.feet[side].point)).distance_to(_m.feet[side].anchor)
		actual_points[side]={}
		for point in POINTS: actual_points[side][point]=_point_world(side,point)
	_update_garment()
	_observations={"support_errors_m":errors,"unreachable_ankle_residual_m":reach,"pelvis_lowering_m":minf(lower,.06),"support":_m.feet.duplicate(true),"actual_shoe_points_world":actual_points}

func _solve_leg(side: String, target: Transform3D) -> float:
	var skeleton := get_skeleton()
	var hip_index: int=_bones["DEF-thigh."+side];var knee_index: int=_bones["DEF-shin."+side];var ankle_index: int=_bones["DEF-foot."+side]
	var hip := _bone_world("DEF-thigh."+side);var knee := _bone_world("DEF-shin."+side);var ankle := _foot_world(side)
	var segments: Vector2=_leg_lengths[side]
	var upper := segments.x;var lower := segments.y
	var toward := target.origin-hip.origin
	if toward.length()<.000001: return upper+lower
	var distance := clampf(toward.length(),absf(upper-lower)+.00001,upper+lower-.00001)
	var axis := toward.normalized()
	var raw_axis := (ankle.origin-hip.origin).normalized()
	var bend := knee.origin-hip.origin
	bend-=raw_axis*bend.dot(raw_axis)
	if bend.length()<.00001:
		bend=_actor.global_basis.z-raw_axis*raw_axis.dot(_actor.global_basis.z)
	bend=Quaternion(raw_axis,axis)*bend.normalized()
	var along := (upper*upper+distance*distance-lower*lower)/(2*distance)
	var knee_goal := hip.origin+axis*along+bend*sqrt(maxf(0,upper*upper-along*along))
	var ankle_goal := hip.origin+axis*distance
	var hip_q := (Quaternion((knee.origin-hip.origin).normalized(),(knee_goal-hip.origin).normalized())*hip.basis.get_rotation_quaternion()).normalized()
	var knee_q := (Quaternion((ankle.origin-knee.origin).normalized(),(ankle_goal-knee_goal).normalized())*knee.basis.get_rotation_quaternion()).normalized()
	# Keep the actual local rest offsets/scales exactly. Writing independently
	# computed world knee/ankle origins back through several inverse transforms
	# needlessly perturbs those physical offsets near a straight leg.
	_set_joint_world_rotation(hip_index,hip_q)
	_set_joint_world_rotation(knee_index,knee_q)
	_set_joint_world_rotation(ankle_index,target.basis.get_rotation_quaternion().normalized())
	return ankle_goal.distance_to(target.origin)

func _set_joint_world_rotation(index: int, world_rotation: Quaternion) -> void:
	var skeleton := get_skeleton()
	var parent: int=_parents[index]
	var parent_world: Transform3D=skeleton.global_transform
	if parent>=0: parent_world*=skeleton.get_bone_global_pose(parent)
	var local_rotation := parent_world.basis.get_rotation_quaternion().normalized().inverse()*world_rotation
	skeleton.set_bone_pose_position(index,skeleton.get_bone_rest(index).origin)
	skeleton.set_bone_pose_scale(index,Vector3.ONE)
	skeleton.set_bone_pose_rotation(index,local_rotation.normalized())

func _look_lead(remaining: float) -> void:
	var skeleton := get_skeleton()
	var entry_weight := _ease(clampf(float(_m.clock)/.15,0,1))
	for pair in [["DEF-chest",.12],["DEF-head",.32]]:
		var index: int=_bones[pair[0]]
		var pose := skeleton.get_bone_global_pose(index)
		pose.basis=Basis(Vector3.UP,clampf(remaining*float(pair[1]),-.3,.3)*entry_weight)*pose.basis
		skeleton.set_bone_global_pose(index,pose)

func _standing_pose(seconds: float) -> Array[Transform3D]:
	# The source casual idle lowers/leans the pelvis and places a foot 25cm
	# behind. Neutral stance reauthors COM and torso at the target's standing
	# rest height; source breathing/acting deltas and the natural arm poses stay.
	var result := _sample("idle",seconds)
	var raw := _globals(result)
	var rotations: Array[Quaternion] = [];rotations.resize(_parents.size())
	for index in _order:
		var name: String=get_skeleton().get_bone_name(index)
		var desired := raw[index].basis.get_rotation_quaternion()
		if name in STANDING_CORE:
			var breath := desired*_idle_reference[index].basis.get_rotation_quaternion().inverse()
			desired=breath*_rest_globals[index].basis.get_rotation_quaternion()
		desired=desired.normalized();rotations[index]=desired
		var local_rotation := desired if _parents[index]<0 else rotations[_parents[index]].inverse()*desired
		result[index].basis=Basis(local_rotation.normalized())
	var pelvis: int=_bones["DEF-pelvis"]
	result[pelvis].origin=get_skeleton().get_bone_rest(pelvis).origin
	return result

func _update_garment() -> void:
	if not _bones.has("DEF-apron_front") or not _bones.has("DEF-apron_back"): return
	var skeleton := get_skeleton()
	var pelvis: Transform3D=skeleton.get_bone_global_pose(_bones["DEF-pelvis"])
	var rest_pelvis: Transform3D=_rest_globals[_bones["DEF-pelvis"]]
	var anterior := 0.0;var posterior := 0.0
	for side in SIDES:
		var thigh: Transform3D=skeleton.get_bone_global_pose(_bones["DEF-thigh."+side])
		var shin: Transform3D=skeleton.get_bone_global_pose(_bones["DEF-shin."+side])
		var leg := pelvis.basis.inverse()*(shin.origin-thigh.origin)
		var angle := atan2(leg.z,-leg.y)
		anterior=maxf(anterior,angle);posterior=maxf(posterior,-angle)
	for pair in [["DEF-apron_front",-anterior],["DEF-apron_back",posterior]]:
		var index: int=_bones[pair[0]]
		var pose := skeleton.get_bone_global_pose(index)
		var base := pelvis.basis*rest_pelvis.basis.inverse()*_rest_globals[index].basis
		pose.basis=Basis(pelvis.basis.x.normalized(),float(pair[1]))*base
		skeleton.set_bone_global_pose(index,pose)

func _best_support() -> String:
	if _m.feet.L.locked and not _m.feet.R.locked: return "L"
	if _m.feet.R.locked and not _m.feet.L.locked: return "R"
	return "L" if fposmod(float(_m.phase),1.0)<.5 else "R"

func _departure_support() -> String:
	# A casual idle may have one foot far behind the pelvis. Holding that rear
	# shoe for the complete first step exceeds leg reach. Use the actual forward
	# planted shoe, not a stale phase from the journey before the turn.
	var forward := _actor.global_basis.z
	var left: float=((_m.feet.L.transform as Transform3D).origin-_actor.global_position).dot(forward)
	var right: float=((_m.feet.R.transform as Transform3D).origin-_actor.global_position).dot(forward)
	return "L" if left>=right else "R"

func _reference_foot(key: String, time: float, side: String, actor_transform: Transform3D) -> Transform3D:
	var globals: Array[Transform3D]=[]
	if key=="neutral":
		for index in _parents.size(): globals.append(get_skeleton().get_bone_global_rest(index))
	else: globals=_globals(_sample(key,time))
	var skeleton_transform := actor_transform*_skeleton_in_actor
	var result: Transform3D=skeleton_transform*globals[_bones["DEF-foot."+side]]
	var low := INF
	for point in POINTS:
		var position := Vector3.ZERO
		for influence_record in _contacts[side][point]: position+=(skeleton_transform*globals[influence_record.bone]*influence_record.position)*float(influence_record.weight)
		low=minf(low,position.y)
	result.origin.y+=_floor+FLOOR_CLEARANCE-low
	return result

func _sample(key: String, seconds: float) -> Array[Transform3D]:
	var skeleton := get_skeleton()
	var result: Array[Transform3D] = []
	for index in skeleton.get_bone_count(): result.append(skeleton.get_bone_rest(index))
	var animation: Animation=_library.get_animation(key)
	var time := fposmod(seconds,animation.length) if seconds!=animation.length else seconds
	for record in _tracks[key]:
		var index: int=record.bone;var track: int=record.track
		match int(record.type):
			Animation.TYPE_POSITION_3D: result[index].origin=animation.position_track_interpolate(track,time)
			Animation.TYPE_ROTATION_3D: result[index].basis=Basis(animation.rotation_track_interpolate(track,time).normalized())
			Animation.TYPE_SCALE_3D: pass # Delivered target bones retain real lengths and unit scale.
	return result

func _globals(locals: Array) -> Array[Transform3D]:
	var result: Array[Transform3D] = [];result.assign(locals)
	for index in _order:
		if _parents[index]>=0: result[index]=result[_parents[index]]*result[index]
	return result

func _set_locals(values: Array) -> void:
	var skeleton := get_skeleton()
	for index in values.size(): skeleton.set_bone_pose(index,values[index])

func _read_locals() -> Array[Transform3D]:
	var skeleton := get_skeleton();var values: Array[Transform3D] = []
	for index in skeleton.get_bone_count(): values.append(skeleton.get_bone_pose(index))
	return values

func _prior_pose() -> Array:
	return _m.last_pose.duplicate() if not _m.last_pose.is_empty() else _read_locals()

func _blend_entry(values: Array, weight: float) -> Array[Transform3D]:
	return _blend(_m.entry,values,_ease(clampf(weight,0,1)))

func _blend(a: Array, b: Array, weight: float) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for index in a.size(): result.append(_rigid_blend(a[index],b[index],clampf(weight,0,1)))
	return result

static func _rigid_blend(a: Transform3D, b: Transform3D, weight: float) -> Transform3D:
	# Interpolated quaternions must remain unit rotations. Do not let tiny basis
	# scale from repeated blending alter a limb's physical length or shoe shape.
	var rotation := a.basis.get_rotation_quaternion().normalized().slerp(b.basis.get_rotation_quaternion().normalized(),weight).normalized()
	return Transform3D(Basis(rotation),a.origin.lerp(b.origin,weight))

func _bone_world(name: String) -> Transform3D:
	return get_skeleton().global_transform*get_skeleton().get_bone_global_pose(_bones[name])

func _foot_world(side: String) -> Transform3D: return _bone_world("DEF-foot."+side)

func _point_world(side: String, point: String) -> Vector3:
	var skeleton := get_skeleton();var result := Vector3.ZERO
	for record in _contacts[side][point]: result+=(skeleton.global_transform*skeleton.get_bone_global_pose(record.bone)*record.position)*float(record.weight)
	return result

func _lowest_point(side: String) -> String:
	var result := "heel";var low := INF
	for key in POINTS:
		var height := _point_world(side,key).y
		if height<low: low=height;result=key
	return result

func _depth(index: int) -> int:
	var result := 0
	while _parents[index]>=0: result+=1;index=_parents[index]
	return result

func snapshot() -> Dictionary:
	return {"version":FORMAT,"target":_contract.get("target",""),"bones":_parents.size(),"machine":_encode(_m),
		"input":_input.duplicate(true),"delta":_delta,"enabled":_enabled,"serial":_serial,"applied":_applied,"floor":_floor}

func restore(data: Variant) -> bool:
	var checked := _checked_restore(data)
	if checked.is_empty(): return false
	_m=checked.machine;_input=data.input.duplicate(true);_delta=data.delta;_enabled=data.enabled
	_serial=int(data.serial);_applied=int(data.applied);_floor=float(data.floor)
	_observations.clear()
	return true

func can_restore(data: Variant) -> bool:
	return not _checked_restore(data).is_empty()

func _checked_restore(data: Variant) -> Dictionary:
	if not _configured or not data is Dictionary or data.size()!=10 or data.get("version")!=FORMAT or data.get("target")!=_contract.get("target","") or data.get("bones")!=_parents.size(): return {}
	if not _finite_tree(data) or not data.get("input") is Dictionary or not data.get("enabled") is bool: return {}
	for key in ["serial","applied","delta","floor"]:
		if not _finite_number(data.get(key)): return {}
	if data.serial<0 or int(data.serial)!=data.serial or int(data.applied)!=data.applied or data.applied>data.serial or data.applied< -1 or data.delta<0 or data.delta>1 or absf(float(data.floor))>10000: return {}
	var decoded: Variant=_decode(data.get("machine"))
	if not _valid_machine(decoded): return {}
	if not data.input.is_empty():
		if not _valid_input(data.input): return {}
	return {"machine":decoded}

func _valid_machine(data: Variant) -> bool:
	if not data is Dictionary or data.keys().size()!=_m.keys().size() or data.get("mode") not in MODES or data.get("last_motor") not in MODES or data.get("swing") not in SIDES or not data.get("initialized") is bool: return false
	for key in _m:
		if not data.has(key): return false
	for key in ["phase","distance_origin","phase_offset","clock","duration","turn_start","turn_total","turn_sign","turn_steps","turn_step","stop_stage","source_phase","settle_clock"]:
		if not _finite_number(data[key]) or absf(float(data[key]))>1000000000.0: return false
	if data.clock<0 or data.duration<=0 or data.turn_total<0 or data.turn_total>PI+.001 or int(data.turn_steps)!=data.turn_steps or int(data.turn_steps) not in [2,4] or float(data.turn_sign) not in [-1.0,1.0] or int(data.stop_stage)!=data.stop_stage or int(data.stop_stage) not in [0,1]: return false
	if data.turn_step< -1 or data.turn_step>=data.turn_steps or int(data.turn_step)!=data.turn_step or data.phase<0 or data.phase>=1 or data.phase_offset<0 or data.phase_offset>=1: return false
	if data.settle_clock<0 or not _valid_transform(data.from) or not _valid_transform(data.goal) or not data.feet is Dictionary: return false
	for key in ["entry","last_pose"]:
		if not data[key] is Array or (data[key].size()!=_parents.size() and not data[key].is_empty()): return false
		for pose in data[key]:
			if not _valid_transform(pose): return false
	if data.initialized and data.feet.is_empty(): return false
	if not data.feet.is_empty():
		if data.feet.size()!=2: return false
		for side in SIDES:
			if not data.feet.get(side) is Dictionary: return false
			var foot: Dictionary=data.feet[side]
			if foot.size()!=4 or not _valid_transform(foot.get("transform")) or not foot.get("anchor") is Vector3 or not foot.get("locked") is bool or foot.get("point") not in POINTS: return false
	return true

static func _valid_input(value: Dictionary) -> bool:
	if value.get("state") not in MODES: return false
	for key in ["speed","normalized_speed","heading","turn_angle","turn_progress","gait_distance"]:
		if not _finite_number(value.get(key)): return false
	return value.speed>=0 and value.speed<=3.001 and value.gait_distance>=0 and value.gait_distance<=1000000000.0 and value.normalized_speed>=0 and value.normalized_speed<=1.001 and value.turn_progress>=0 and value.turn_progress<=1 and absf(float(value.turn_angle))<=PI+.001

static func _valid_transform(value: Variant) -> bool:
	if not value is Transform3D or not value.is_finite(): return false
	var basis: Basis=value.basis
	return absf(basis.determinant()-1.0)<.002 and absf(basis.x.length()-1)<.001 and absf(basis.y.length()-1)<.001 and absf(basis.z.length()-1)<.001

static func _other(side: String) -> String: return "R" if side=="L" else "L"
static func _ease(value: float) -> float: return value*value*(3.0-2.0*value)
static func _finite_number(value: Variant) -> bool: return (value is float or value is int) and is_finite(float(value))
static func _vec(value: Variant) -> Variant:
	if not value is Array or value.size()!=3: return null
	for number in value:
		if not _finite_number(number): return null
	var result := Vector3(value[0],value[1],value[2])
	return result if result.is_finite() and maxf(absf(result.x),maxf(absf(result.y),absf(result.z)))<=10000 else null

static func _encode(value: Variant) -> Variant:
	if value is Transform3D: return {"$transform":[value.basis.x.x,value.basis.x.y,value.basis.x.z,value.basis.y.x,value.basis.y.y,value.basis.y.z,value.basis.z.x,value.basis.z.y,value.basis.z.z,value.origin.x,value.origin.y,value.origin.z]}
	if value is Vector3: return {"$vector":[value.x,value.y,value.z]}
	if value is Dictionary:
		var result := {}
		for key in value: result[key]=_encode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(_encode(item))
		return result
	return value

static func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.size()==1 and value.has("$vector"): return _vec(value["$vector"])
		if value.size()==1 and value.has("$transform"):
			var data: Variant=value["$transform"]
			if not data is Array or data.size()!=12: return null
			for number in data:
				if not _finite_number(number): return null
			return Transform3D(Basis(Vector3(data[0],data[1],data[2]),Vector3(data[3],data[4],data[5]),Vector3(data[6],data[7],data[8])),Vector3(data[9],data[10],data[11]))
		var result := {}
		for key in value: result[key]=_decode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(_decode(item))
		return result
	return value

static func _finite_tree(value: Variant, depth: int = 0) -> bool:
	if depth>20: return false
	if value is float or value is int: return _finite_number(value)
	if value is Array:
		if value.size()>10000: return false
		for item in value:
			if not _finite_tree(item,depth+1): return false
	if value is Dictionary:
		if value.size()>1000: return false
		for item in value.values():
			if not _finite_tree(item,depth+1): return false
		return true
	if value is Array: return true
	return value==null or value is String or value is bool
