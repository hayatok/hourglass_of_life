class_name FoundationFurniturePose
extends FoundationLocomotionPose

# Furniture is the final skeletal-pose owner while enabled. The physical motor
# still owns every Node3D world transform. No animation changes life/task results.
const FURNITURE_FORMAT := 1
const PHASES := ["chair_pull","chair_push","sit_enter","sit_idle","chair_slide","sit_exit",
	"bed_seat","legs_in","lie_down","lie_idle","sit_up","legs_out","bed_stand","fixture_pull","fixture_push","step_back","step_forward"]
const STEP_PHASES := ["chair_pull","chair_push","fixture_pull","fixture_push","step_back","step_forward"]
const BACK_PHASES := ["chair_pull","fixture_pull","step_back"]
var _f_request: Dictionary = {}
var _f_enabled := false
var _f_serial := 0
var _f_applied := -1
var _f_sample_serial := -1
var _f_phase := ""
var _f_progress := 0.0
var _f_entry: Array = []
var _f_feet: Dictionary = {}
var _f_step := -1
var _f_swing := "L"
var _f_from := Transform3D.IDENTITY
var _f_goal := Transform3D.IDENTITY
var _f_start := Transform3D.IDENTITY
var _f_last_pose: Array = []
var _rendered_pose: Array = []
var _rendered_world := Transform3D.IDENTITY
var _rendered_serial := 0
var _skin_points: Dictionary = {"seat":[],"back":[],"head":[],"L":[],"R":[],"thumb.L":[],"thumb.R":[],"index.L":[],"index.R":[]}
var _palm_points: Dictionary = {}
var _handle_palms: Dictionary = {}
var _calibration: Dictionary = {}
var _f_observed: Dictionary = {}
var _f_profile: Dictionary = {}
var _f_static_key: Dictionary = {}
var _f_static_observed: Dictionary = {}
var _skin_seen: Dictionary = {}
var _skin_meshes: Array[WeakRef] = []
var _handle_finger_angles: Dictionary = {}
const HANDLE_FINGER_OPEN := .08
const HANDLE_FINGER_LIMIT := 1.35 # Single authored finger joint, under 80 degrees.

func configure(actor: Node3D, library: AnimationLibrary, contract: Dictionary, profile: Dictionary = {}) -> bool:
	if not super.configure(actor,library,contract,profile): return false
	for key in ["sit_enter","sit_idle","sit_exit"]:
		if not library.has_animation(key): return false
		var animation: Animation=library.get_animation(key)
		var tracks: Array=[]
		for index in animation.get_track_count():
			var path := animation.track_get_path(index)
			if path.get_subname_count()!=1: continue
			var bone: String=str(path.get_subname(0))
			if _bones.has(bone): tracks.append({"bone":_bones[bone],"track":index,"type":animation.track_get_type(index)})
		_tracks[key]=tracks
	if not _collect_skin(): return false
	var seated := _globals(_sample("sit_idle",0))
	var pelvis: Vector3=(_skeleton_in_actor*seated[_bones["DEF-pelvis"]]).origin
	var low := _skin_low("seat",seated)
	var low_actor := _actor.to_local(Vector3(_actor.global_position.x,low,_actor.global_position.z)).y
	_calibration={"seated_pelvis_actor":pelvis,"standing_pelvis_actor":(_skeleton_in_actor*_rest_globals[_bones["DEF-pelvis"]]).origin,
		"seat_pelvis_offset_y":pelvis.y-low_actor,"seat_support_vertices":_skin_points.seat.size(),
		"method":"actual sit_idle transforms and imported mesh/Skin butt-region vertices; no resident-ID offsets"}
	_calibration.seated_knee_above_support={}
	for side in SIDES:
		_calibration.seated_knee_above_support[side]=(_skeleton_in_actor*seated[_bones["DEF-shin."+side]]).origin.y-low_actor
	var skeleton := get_skeleton()
	if not skeleton.skeleton_updated.is_connected(_capture_rendered): skeleton.skeleton_updated.connect(_capture_rendered)
	return true

func calibration() -> Dictionary: return _calibration.duplicate(true)
func request_state() -> Dictionary: return _f_request.duplicate(true) if _f_enabled else {}
func handle_palm_local(side: String) -> Variant:
	if not _handle_palms.has(side):return null
	var point: Dictionary=_handle_palms[side]
	return Transform3D(point.basis,point.position)

func _hand_contact(side: String) -> Dictionary:
	return _handle_palms.get(side,{}) if _f_request.get("handle") is Dictionary else _palm_points.get(side,{})

func _actual_palm(side: String, point: Dictionary) -> Vector3:
	if not point.has("skin_records"):return _bone_world("DEF-hand."+side)*point.position
	var actual := Vector3.ZERO
	# Re-evaluate all three real deformed Skin vertices after Skeleton_updated.
	# This is a point on the imported triangle, not an unskinned rest landmark.
	for index in 3:actual+=_skin_point(point.skin_records[index])*float(point.barycentric[index])
	return actual

func present(request: Dictionary, _elapsed_delta: float = 0.0) -> bool:
	if not _configured or not _valid_request(request): return false
	_f_request=request.duplicate(true);_f_enabled=true;_f_serial+=1
	return true

func clear() -> void:
	_f_enabled=false;_f_request.clear();_f_phase="";_f_entry=[];_f_feet.clear();_f_last_pose=[]
	_f_observed.clear();_f_sample_serial=-1
	_f_static_key.clear();_f_static_observed.clear()

func contacts_ready() -> bool:
	return _f_enabled and _f_sample_serial==_f_serial and _f_observed.get("phase","") in ["sit_idle","lie_idle"] and _f_observed.get("supports_ready",false)

func telemetry() -> Dictionary: return _f_observed.duplicate(true)

func _capture_rendered() -> void:
	_rendered_pose=_read_locals();_rendered_world=get_skeleton().global_transform;_rendered_serial+=1
	if _f_enabled and _f_applied==_f_serial:
		_f_sample_serial=_f_serial;_f_observed["latest_sample_serial"]=_f_sample_serial
		for side in _f_observed.get("hands",{}):
			var record: Dictionary=_f_observed.hands[side]
			record.actual_palm=_actual_palm(side,_hand_contact(side))
			record.error_m=record.actual_palm.distance_to(record.target)
			if _f_request.get("handle") is Dictionary:record.fingers=_finger_contacts(side,_f_request.handle)

func _process_modification_with_delta(_skeleton_delta: float) -> void:
	if not _f_enabled or _f_request.is_empty(): return
	if _f_applied==_f_serial:
		if not _f_last_pose.is_empty(): _set_locals(_f_last_pose)
		return
	_f_applied=_f_serial
	var started := Time.get_ticks_usec()
	var phase: String=_f_request.phase
	var progress: float=clampf(float(_f_request.progress),0,1)
	# lie_idle has no time-driven source motion. Reapply the immutable solved
	# local pose on every actual skeleton update; solve it again only if the
	# support geometry, actor frame, or requested hand contacts really change.
	var static_key := {}
	if phase=="lie_idle":
		var mesh_frames := []
		for reference in _skin_meshes:
			var mesh: MeshInstance3D=reference.get_ref()
			mesh_frames.append(mesh.global_transform if mesh!=null else null)
		static_key={"bed":_f_request.bed,"actor":_actor.global_transform,"skeleton":get_skeleton().global_transform,"mesh_frames":mesh_frames,"hands":_f_request.get("hands",{}),"floor":_f_request.get("floor_y",0.0)}
		if static_key==_f_static_key and not _f_last_pose.is_empty() and not _f_static_observed.is_empty():
			_f_progress=progress
			_set_locals(_f_last_pose)
			_f_observed=_f_static_observed.duplicate(true)
			_f_observed.progress=progress;_f_observed.request_serial=_f_serial;_f_observed.latest_sample_serial=_f_sample_serial
			_f_observed.profile_usec={"total":Time.get_ticks_usec()-started,"body_branch":0,"final_feet":0,"static_pose_cache":true}
			return
	if phase!=_f_phase or progress<_f_progress-.000001: _begin_phase(phase)
	_f_progress=progress;_floor=float(_f_request.get("floor_y",0.0))
	var goals: Dictionary={}
	var branch_started := Time.get_ticks_usec()
	match phase:
		"chair_pull","chair_push","fixture_pull","fixture_push","step_back","step_forward": goals=_move_chair_pose(phase,progress)
		"chair_slide":
			_set_locals(_sample("sit_idle",float(_f_request.get("pose_seconds",0.0))))
			_neutral_toes()
			goals=_slide_chair_feet(progress)
			_support_seat(1.0)
			_solve_furniture_feet(goals,false)
			_support_seat(1.0)
		"legs_in","lie_down","lie_idle","sit_up","legs_out": goals=_bed_pose(phase,progress)
		_:
			var source := "sit_idle"
			if phase in ["sit_enter","bed_seat"]: source="sit_enter"
			elif phase in ["sit_exit","bed_stand"]: source="sit_exit"
			var time: float=float(_f_request.get("pose_seconds",0.0)) if source=="sit_idle" else progress*_library.get_animation(source).length
			var values := _sample(source,time)
			if source=="sit_enter": values=_blend(_f_entry,values,_ease(clampf(progress/.22,0,1)))
			if source=="sit_exit" and progress>.7: values=_blend(values,_standing_pose(time),_ease((progress-.7)/.3))
			_set_locals(values)
			var weight := 1.0
			if source=="sit_enter": weight=smoothstep(.5,.95,progress)
			elif source=="sit_exit": weight=1.0-smoothstep(0,.45,progress)
			_support_seat(weight)
			goals=_seated_feet(phase,progress)
			_solve_furniture_feet(goals,false)
			_support_seat(weight)
	var branch_usec := Time.get_ticks_usec()-branch_started
	var feet_started := Time.get_ticks_usec()
	var foot_result := _solve_furniture_feet(goals,phase in STEP_PHASES)
	var feet_usec := Time.get_ticks_usec()-feet_started
	var hand_result := _hands(phase,progress)
	_update_garment()
	_f_last_pose=_read_locals()
	var surface: float=float(_f_request.get("seat_point",Vector3.ZERO).y)
	var region := "seat"
	if phase=="lie_idle":
		region="back";surface=float(_f_request.bed.sheet_y)
	var skin_y := _skin_low(region)
	var support_error := absf(skin_y-surface)
	var ready: bool=phase in ["sit_idle","lie_idle"] and support_error<=.03 and foot_result.get("required_support_error_m",INF)<=.03 and foot_result.get("unreachable_peak_m",INF)<=.03 and foot_result.get("rail_penetration_m",0.0)<=.02
	var legs := {}
	for side in SIDES:
		legs[side]={"hip":_bone_world("DEF-thigh."+side).origin,"knee":_bone_world("DEF-shin."+side).origin,"ankle":_foot_world(side).origin,"lengths":_leg_lengths[side]}
	_f_profile={"total":Time.get_ticks_usec()-started,"body_branch":branch_usec,"final_feet":feet_usec,"static_pose_cache":false}
	_f_observed={"phase":phase,"progress":progress,"request_serial":_f_serial,"latest_sample_serial":_f_sample_serial,
		"support_surface_y":surface,"actual_support_min_y":skin_y,"body_support_error_m":support_error,
		"feet":foot_result,"hands":hand_result,"legs":legs,"profile_usec":_f_profile,"supports_ready":ready,"sample_method":"final skeletal pose plus actual imported Skin vertices",
		"sleep_source":"new authored full-body seat/legs/lie sequence; no sleeping clip exists in the source library" if phase in ["legs_in","lie_down","lie_idle","sit_up","legs_out"] else "Quaternius sitting/reverse-walk source plus physical target adaptation"}
	if phase in ["fixture_pull","fixture_push","step_back","step_forward"]:_f_observed.motion_source="authored two-step foot/support targets with Quaternius standing pose; motor owns the full physical root translation"
	if phase=="lie_idle": _f_static_key=static_key.duplicate(true);_f_static_observed=_f_observed.duplicate(true)
	else: _f_static_key.clear();_f_static_observed.clear()

func _begin_phase(phase: String) -> void:
	_f_phase=phase;_f_progress=0.0;_f_step=-1
	# The motor may have advanced several physical substeps before this first
	# rendered phase sample. Prefer its authoritative track start, rather than
	# treating the already-moving current transform as the phase origin.
	_f_start=_f_request.get("root_start",_rendered_world*_skeleton_in_actor.affine_inverse() if not _rendered_pose.is_empty() else _actor.global_transform)
	_f_entry=_rendered_pose.duplicate() if not _rendered_pose.is_empty() else _read_locals()
	var globals := _globals(_f_entry)
	var world := _rendered_world if not _rendered_pose.is_empty() else get_skeleton().global_transform
	_f_feet={}
	for side in SIDES:
		var transform: Transform3D=world*globals[_bones["DEF-foot."+side]]
		var key := "heel";var low := INF;var point := Vector3.ZERO
		for candidate in POINTS:
			var value := _point_at(side,candidate,globals,world)
			if value.y<low: low=value.y;key=candidate;point=value
		_f_feet[side]={"transform":transform,"point":key,"anchor":point}
	_f_swing="L"
	if phase in STEP_PHASES:
		var movement: Vector3=(_f_request.get("root_end",_f_start) as Transform3D).origin-_f_start.origin
		if movement.length()>.001:
			var left: float=(_f_feet.L.transform.origin-_f_start.origin).dot(movement)
			var right: float=(_f_feet.R.transform.origin-_f_start.origin).dot(movement)
			# Lift the trailing foot first; the leading planted shoe supports the
			# first half of the physical backward/forward translation.
			_f_swing="L" if left<=right else "R"
		for side in SIDES: _f_feet[side].first_swing=_f_swing
	if phase=="chair_slide":
		for side in SIDES:
			_f_feet[side].floor_start=_floor_seated_goal(side,_f_start) if not _f_request.get("footrest",{}).is_empty() else _f_feet[side].transform
			_f_feet[side].floor_mid=_floor_seated_goal(side,_chair_root_at(.60))
			_f_feet[side].floor_end=_floor_seated_goal(side,_chair_root_at(1.0))

func _seated_feet(phase: String, progress: float) -> Dictionary:
	var result := {}
	var supplied: Dictionary=_f_request.get("feet",{})
	var rail: Dictionary=_f_request.get("footrest",{})
	for side in SIDES:
		var start: Transform3D=_f_feet[side].transform
		if supplied.get(side) is Dictionary and supplied[side].get("ankle_transform") is Transform3D: start=supplied[side].ankle_transform
		var goal := start
		if not rail.is_empty(): goal=_rail_goal(side,rail)
		# An adult sofa may support the child's pelvis while its lower legs
		# hang freely. Decide from measured knee/sole height and real shin
		# length, never from an ID, stretched bones or a pretend floor contact.
		var free_feet := false
		if rail.is_empty() and bool(_f_request.get("allow_dangling_feet",false)) and phase in ["sit_enter","sit_idle"]:
			var floor_goal := _floor_seated_goal(side,_actor.global_transform)
			var knee_y: float=float(_f_request.seat_point.y)+float(_calibration.seated_knee_above_support[side])
			free_feet=knee_y-floor_goal.origin.y>_leg_lengths[side].y
			if free_feet:goal=_foot_world(side)
		var transfer := 1.0
		if phase in ["sit_enter","bed_seat"]: transfer=smoothstep(.30 if side=="L" else .53,.62 if side=="L" else .87,progress)
		elif phase in ["sit_exit","bed_stand"]:
			# Return each foot to the actual floor stance before the pelvis leaves.
			var floor_goal := _reference_foot("neutral",0,side,_actor.global_transform)
			goal=floor_goal;start=_f_feet[side].transform
			transfer=smoothstep(.05 if side=="L" else .2,.34 if side=="L" else .5,progress)
		var pose := _rigid_blend(start,goal,transfer)
		if transfer>0 and transfer<1: pose.origin.y+=sin(PI*transfer)*.055*float(_contract.get("translation_scale",1.0))
		if phase in ["sit_exit","bed_stand"]:
			# A foot that has left a rail and landed on the floor must be
			# observed against the real floor, not against the old rail height.
			var active_rail: Dictionary=rail if transfer<=.0001 else {}
			result[side]=_chair_foot_record(side,pose,transfer>=.999 or transfer<=.0001,float(rail.support_y) if not active_rail.is_empty() else _floor,active_rail,"floor_stand" if transfer>=.999 else "leave_seat")
		else:
			result[side]={"pose":pose,"required":transfer>=.999 and not free_feet,"surface_y":float(rail.get("support_y",_floor)) if not rail.is_empty() else _floor,"point":"ball" if not rail.is_empty() else str(_f_feet[side].point),"rail":rail if transfer>=.999 and not rail.is_empty() else {},"support_kind":"free" if free_feet else rail.get("support_kind","floor"),"weight_support":"seat" if free_feet else "floor"}
	return result

func _rail_goal(side: String, rail: Dictionary) -> Transform3D:
	var result := _foot_world(side)
	var yaw: float=float(rail.get("yaw",_actor.global_rotation.y))
	var right := Basis(Vector3.UP,yaw).x
	var offset: float=absf((_skeleton_in_actor*_rest_globals[_bones["DEF-foot."+side]]).origin.x)
	offset=minf(offset,maxf(0,float(rail.half_width)-.045))
	var target: Vector3=rail.center+right*offset*(1 if side=="L" else -1)
	target.y=float(rail.support_y)+.003
	var local_point := result.affine_inverse()*_point_world(side,"ball")
	result.origin=target-result.basis*local_point
	return result

func _support_seat(weight: float) -> void:
	if weight<=0 or not _f_request.get("seat_point") is Vector3: return
	var skeleton := get_skeleton();var index: int=_bones["DEF-pelvis"]
	var pose := _bone_world("DEF-pelvis")
	var desired: Vector3=_f_request.get("pelvis_target",_f_request.seat_point)
	pose.origin.x=lerpf(pose.origin.x,desired.x,weight);pose.origin.z=lerpf(pose.origin.z,desired.z,weight)
	pose.origin.y+=(float(_f_request.seat_point.y)-_skin_low("seat")) * weight
	skeleton.set_bone_global_pose(index,skeleton.global_transform.affine_inverse()*pose)

func _move_chair_pose(phase: String, progress: float) -> Dictionary:
	var motion := clampf((progress-.08)/.84,0,1)
	var source_phase: float=1.0-motion if phase in BACK_PHASES else motion
	var values := _standing_pose(source_phase*_walk_length)
	# Authored working posture keeps the target's standing centre of mass,
	# source breathing/arms and a small weight transfer. Reverse full-body
	# forward gait is not mislabeled as a captured backward walk.
	var pelvis: int=_bones["DEF-pelvis"]
	values[pelvis].origin.y=get_skeleton().get_bone_rest(pelvis).origin.y-.012-sin(PI*fposmod(motion*2,1.0))*.008
	values[pelvis].origin.z=get_skeleton().get_bone_rest(pelvis).origin.z
	values=_chair_working_posture(values)
	_set_locals(_blend(_f_entry,values,_ease(clampf(progress/.12,0,1))))
	_neutral_toes()
	if (_f_request.get("root_end",_f_start) as Transform3D).origin.distance_to(_f_start.origin)<.00001:
		# Reaching a fixed handle must not invent a standing foot-lift sequence.
		var stationary := {}
		for side in SIDES:stationary[side]=_chair_foot_record(side,_f_feet[side].transform,true,_floor,{},"stationary_floor_support")
		return stationary
	var step: int=mini(1,int(floor(motion*2)))
	var fraction: float=1.0 if motion>=1 else motion*2-step
	var first: String=_f_feet.L.first_swing
	_f_step=step;_f_swing=first if step==0 else _other(first)
	_f_from=_f_feet[_f_swing].transform
	_f_goal=_floor_chair_goal(_f_swing,_chair_root_at(1.0))
	var free := _rigid_blend(_f_from,_f_goal,_ease(fraction));free.origin.y+=sin(PI*fraction)*.045
	var result := {}
	for side in SIDES:
		var foot: Transform3D=free if side==_f_swing else (_floor_chair_goal(side,_chair_root_at(1.0)) if step==1 else _f_feet[side].transform)
		result[side]=_chair_foot_record(side,foot,side!=_f_swing or fraction>=.999,_floor,{},"standing_step" if side==_f_swing and fraction<.999 else "floor_support")
	return result

func _chair_working_posture(values: Array) -> Array:
	var requests: Dictionary=_f_request.get("hands",{})
	if requests.is_empty():requests=_f_request.get("working_hands",{})
	if requests.is_empty(): return values
	var globals := _globals(values)
	var world := get_skeleton().global_transform
	var pelvis: int=_bones["DEF-pelvis"]
	var pivot: Vector3=(world*globals[pelvis]).origin
	var best_score := INF;var chosen_angle := 0.0;var chosen_lower := 0.0
	# A tall adult bends from the hips to the real chair-back height; a child
	# can reach the same back with a smaller lean. Evaluate actual arm spans,
	# not named resident presets or longer arms. The foot solver then bends
	# the real knees to support the resulting centre of mass.
	for lean_index in 7:
		var angle: float=float(lean_index)*.15
		var lean := Basis(_actor.global_basis.x,angle)
		for lower_index in 7:
			var lower: float=float(lower_index)*.02
			var excess := 0.0
			for side in SIDES:
				if not requests.get(side) is Dictionary or not requests[side].get("palm_transform") is Transform3D: continue
				var shoulder: Vector3=(world*globals[_bones["DEF-upper_arm."+side]]).origin
				shoulder=pivot+lean*(shoulder-pivot)-Vector3.UP*lower
				var length: float=get_skeleton().get_bone_rest(_bones["DEF-forearm."+side]).origin.length()+get_skeleton().get_bone_rest(_bones["DEF-hand."+side]).origin.length()
				# Include the real hand-to-palm offset in reach, rather than
				# treating the visible contact vertex as the wrist joint.
				var target: Transform3D=requests[side].palm_transform
				var wrist: Vector3=target.origin
				var contact: Dictionary=_hand_contact(side)
				if not contact.is_empty():wrist-=(target.basis*contact.basis.inverse())*contact.position
				excess=maxf(excess,shoulder.distance_to(wrist)-length*.98)
			var score := maxf(0,excess)*100+angle*.025+lower*.10
			if score<best_score: best_score=score;chosen_angle=angle;chosen_lower=lower
	values[pelvis].origin.y-=chosen_lower
	values[pelvis].basis=Basis(Vector3.RIGHT,chosen_angle)*values[pelvis].basis
	return values

func _neutral_toes() -> void:
	for side in SIDES:
		var index: int=_bones["DEF-toe."+side]
		get_skeleton().set_bone_pose(index,get_skeleton().get_bone_rest(index))

func _chair_root_at(fraction: float) -> Transform3D:
	return _rigid_blend(_f_start,_f_request.get("root_end",_actor.global_transform),fraction)

func _floor_chair_goal(side: String, frame: Transform3D) -> Transform3D:
	return _reference_foot("neutral",0,side,frame)

func _floor_seated_goal(side: String, frame: Transform3D) -> Transform3D:
	var result := _floor_chair_goal(side,frame)
	var pelvis: Vector3=_calibration.seated_pelvis_actor
	var lengths: Vector2=_leg_lengths[side]
	# The actor's seated root lies behind its pelvis in the source clip. A
	# standing neutral foot at that root is too far ahead for a short seated
	# leg. Place the floor stance relative to the measured seated pelvis,
	# slightly ahead of its projection, with no hidden increase in leg reach.
	result.origin+=frame.basis*Vector3(pelvis.x,0,pelvis.z+(lengths.x+lengths.y)*.12)
	return result

func _chair_foot_record(side: String, foot: Transform3D, required: bool, surface: float, rail: Dictionary, task: String) -> Dictionary:
	var point := "ball" if not rail.is_empty() else "heel"
	if rail.is_empty():
		var low := INF
		var inverse := _foot_world(side).affine_inverse()
		for key in POINTS:
			var at: Vector3=foot*(inverse*_point_world(side,key))
			if at.y<low: low=at.y;point=key
	var target: Vector3=foot*(_foot_world(side).affine_inverse()*_point_world(side,point))
	return {"pose":foot,"required":required,"surface_y":surface,"point":point,"rail":rail,"task":task,"target_support_point":target}

func _chair_transfer(from: Transform3D, to: Transform3D, fraction: float, lift: float) -> Transform3D:
	var value := _rigid_blend(from,to,_ease(fraction))
	value.origin.y+=sin(PI*fraction)*lift
	return value

func _slide_chair_feet(progress: float) -> Dictionary:
	# Root/chair track contract: .00-.22 stationary to lower feet, .22-.74
	# moves, .74-1 stationary to put feet back. The seat bears body weight;
	# floor contacts push/replant. A rail never acts as a propulsion surface.
	var rail: Dictionary=_f_request.get("footrest",{})
	var result := {}
	for side in SIDES:
		var record: Dictionary=_f_feet[side]
		var floor_start: Transform3D=record.floor_start
		var middle: Transform3D=record.floor_mid
		var finish: Transform3D=record.floor_end
		var foot := floor_start
		var required := true
		var task := "floor_push"
		var active_rail := {}
		var surface := _floor
		if not rail.is_empty():
			var lower := smoothstep(0.0 if side=="L" else .08,.12 if side=="L" else .22,progress)
			foot=_chair_transfer(record.transform,floor_start,lower,.025)
			required=lower<=.0001 or lower>=.9999
			task="rail_rest" if lower<=.0001 else ("lower_to_floor" if lower<.9999 else "floor_push")
			if lower<=.0001: active_rail=rail;surface=float(rail.support_y)
		if side=="L" and progress>=.22:
			var fraction := clampf((progress-.22)/.14,0,1)
			foot=_chair_transfer(floor_start,middle,fraction,.035)
			required=fraction>=.9999;task="floor_replant" if not required else "floor_push"
			if progress>=.56:
				fraction=clampf((progress-.56)/.18,0,1)
				foot=_chair_transfer(middle,finish,fraction,.03)
				required=fraction>=.9999;task="floor_replant" if not required else "floor_push"
		elif side=="R" and progress>=.36:
			var fraction := clampf((progress-.36)/.20,0,1)
			foot=_chair_transfer(floor_start,finish,fraction,.035)
			required=fraction>=.9999;task="floor_replant" if not required else "floor_push"
		if not rail.is_empty() and progress>=.74:
			var restore := smoothstep(.74 if side=="L" else .86,.88 if side=="L" else 1.0,progress)
			foot=_chair_transfer(finish,_rail_goal(side,rail),restore,.035)
			required=restore<=.0001 or restore>=.9999
			task="rail_rest" if restore>=.9999 else ("return_to_rail" if restore>0 else "floor_push")
			if restore>=.9999: active_rail=rail;surface=float(rail.support_y)
		result[side]=_chair_foot_record(side,foot,required,surface,active_rail,task)
	return result

func _bed_pose(phase: String, progress: float) -> Dictionary:
	var bed: Dictionary=_f_request.bed
	var lift := progress if phase=="legs_in" else (1.0-progress if phase=="legs_out" else 1.0)
	var lie := progress if phase=="lie_down" else (1.0-progress if phase=="sit_up" else (1.0 if phase=="lie_idle" else 0.0))
	var seated := _sample("sit_idle",float(_f_request.get("pose_seconds",0)))
	var straight: Array[Transform3D]=[]
	for index in _parents.size(): straight.append(get_skeleton().get_bone_rest(index))
	var values := _blend(seated,straight,_ease(lie))
	if phase=="legs_in": values=_blend(_f_entry,values,_ease(clampf(progress/.2,0,1)))
	_set_locals(values)
	var head: Vector3=bed.head_direction.normalized();head.y=0;head=head.normalized()
	var up := Vector3.UP
	var lying := Basis(head.cross(up).normalized(),head,up).orthonormalized()
	var standing := _actor.global_basis.orthonormalized()
	var body_basis := Basis(standing.get_rotation_quaternion().slerp(lying.get_rotation_quaternion(),_ease(lie)).normalized())
	var pelvis: Vector3=bed.pelvis_point
	_orient_about_pelvis(body_basis,pelvis)
	if lie>0:
		var support := minf(_skin_low("back"),_skin_low("seat"))
		_shift_root(Vector3.UP*(float(bed.sheet_y)-support)*_ease(lie))
		_adjust_pillow(body_basis,lie,bed.pillow_point)
	var result := {}
	var right := lying.x
	for side in SIDES:
		var rest: Transform3D=_foot_world(side)
		var segments: Vector2=_leg_lengths[side]
		var local_point := rest.affine_inverse()*_point_world(side,"heel")
		# A supine shoe uses its actual rest orientation transformed with the
		# lying body, rather than the source sit's floor-foot orientation. The
		# heel extends beyond the ankle along the bed: subtracting that offset
		# from a guessed hip-to-heel length folded both knees across the body.
		var goal := Transform3D(lying*_rest_globals[_bones["DEF-foot."+side]].basis,Vector3.ZERO)
		var hip := _bone_world("DEF-thigh."+side).origin
		goal.origin.y=float(bed.sheet_y)+.003-(goal.basis*local_point).y
		var height := goal.origin.y-hip.y
		var reach := (segments.x+segments.y)*.998
		var horizontal := sqrt(maxf(0,reach*reach-height*height))
		goal.origin.x=hip.x-head.x*horizontal;goal.origin.z=hip.z-head.z*horizontal
		var amount := smoothstep(0,.65,lift) if side=="L" else smoothstep(.25,1,lift)
		var from: Transform3D=_f_feet[side].transform
		if phase=="legs_out": goal=_reference_foot("neutral",0,side,_actor.global_transform);amount=1-amount
		var target := _rigid_blend(from,goal,_ease(amount))
		if amount>0 and amount<1: target.origin.y+=sin(PI*amount)*.10
		result[side]={"pose":target,"required":phase=="lie_idle" or (amount>=.999 and lift>=.999),"surface_y":float(bed.sheet_y),"point":"heel","rail":{}}
	return result

func _orient_about_pelvis(world_basis: Basis, pelvis_world: Vector3) -> void:
	var skeleton := get_skeleton();var root: int=_bones["DEF-root"]
	var local_globals := _globals(_read_locals())
	var relative := local_globals[root].affine_inverse()*local_globals[_bones["DEF-pelvis"]].origin
	var world := Transform3D(world_basis,pelvis_world-world_basis*relative)
	skeleton.set_bone_pose(root,skeleton.global_transform.affine_inverse()*world)

func _shift_root(world_delta: Vector3) -> void:
	var skeleton := get_skeleton();var root: int=_bones["DEF-root"]
	var pose := skeleton.get_bone_pose(root)
	pose.origin+=skeleton.global_basis.inverse()*world_delta
	skeleton.set_bone_pose(root,pose)

func _adjust_pillow(body: Basis, weight: float, pillow: Vector3) -> void:
	# A supported pillow raises the upper back/neck together. It does not
	# translate the head off its neck or stretch a spine segment.
	var low := 0.0;var high := .45
	for ignored in 6:
		var angle := (low+high)*.5
		for pair in [["DEF-spine_01",.15],["DEF-spine_02",.4],["DEF-chest",.65],["DEF-neck",1.0],["DEF-head",.8]]:
			var index: int=_bones[pair[0]]
			var rotation := (Basis(body.x,angle*float(pair[1])*weight)*body*_rest_globals[index].basis).get_rotation_quaternion().normalized()
			_set_joint_world_rotation(index,rotation)
		if _skin_low("head")<pillow.y: low=angle
		else: high=angle

func _solve_furniture_feet(goals: Dictionary, allow_lowering: bool) -> Dictionary:
	if goals.is_empty(): return {"required_support_error_m":INF,"unreachable_peak_m":INF}
	if allow_lowering:
		var lower := 0.0
		for side in SIDES:
			var hip := _bone_world("DEF-thigh."+side).origin
			var point: Vector3=goals[side].pose.origin
			var lengths: Vector2=_leg_lengths[side]
			var horizontal := Vector2(hip.x-point.x,hip.z-point.z).length()
			lower=maxf(lower,hip.y-point.y-sqrt(maxf(0,pow(lengths.x+lengths.y,2)-horizontal*horizontal))+.001)
		if lower>0:
			var pelvis := _bone_world("DEF-pelvis");pelvis.origin.y-=minf(lower,.05)
			get_skeleton().set_bone_global_pose(_bones["DEF-pelvis"],get_skeleton().global_transform.affine_inverse()*pelvis)
	var peak := 0.0;var required := 0.0;var penetration := 0.0;var records := {}
	for side in SIDES:
		var goal: Transform3D=goals[side].pose
		var reach := _solve_supine_leg(side,goal) if _f_phase in ["legs_in","lie_down","lie_idle","sit_up","legs_out"] else _solve_leg(side,goal)
		peak=maxf(peak,reach)
		var point: Vector3=_point_world(side,str(goals[side].point))
		var error := absf(point.y-float(goals[side].surface_y)) if goals[side].required else 0.0
		if goals[side].required: required=maxf(required,error)
		var world_error: float=point.distance_to(goals[side].target_support_point) if goals[side].has("target_support_point") else 0.0
		var rail: Dictionary=goals[side].rail
		var rail_inside := true
		if not rail.is_empty():
			var inverse := Basis(Vector3.UP,float(rail.get("yaw",0))).inverse()
			var local: Vector3=inverse*(point-rail.center)
			rail_inside=absf(local.x)<=float(rail.half_width)+.01 and absf(local.z)<=float(rail.get("half_depth",.04))+.01
			if not rail_inside: required=maxf(required,.1)
			for skin_point in _skin_points[side]:
				var actual := _skin_point(skin_point)
				var at: Vector3=inverse*(actual-rail.center)
				if absf(at.x)<=float(rail.half_width) and absf(at.z)<=float(rail.get("half_depth",.04)):
					penetration=maxf(penetration,float(rail.support_y)-actual.y)
		records[side]={"ankle_world":_foot_world(side),"actual_support_point":point,"point":goals[side].point,"required":goals[side].required,"support_error_m":error,"reach_residual_m":reach,"rail_inside":rail_inside,
			"target_ankle_world":goal,"target_point_error_m":world_error,"contact_task":goals[side].get("task","rest"),"body_weight_support":goals[side].get("weight_support","seat" if _f_phase=="chair_slide" else "floor"),
			"support_kind":goals[side].get("support_kind",rail.get("support_kind","mattress_heel" if _f_phase in ["legs_in","lie_down","lie_idle","sit_up","legs_out"] else "floor")),"full_sole_support_claim":false}
	return {"required_support_error_m":required,"unreachable_peak_m":peak,"rail_penetration_m":maxf(0,penetration),"sides":records}

func _solve_supine_leg(side: String, target: Transform3D) -> float:
	# A lying knee flexes toward the ceiling. The walking solver's previous
	# bend plane becomes ambiguous at straight rest and folded the knees
	# laterally/down through the mattress while keeping the heels accurate.
	var hip := _bone_world("DEF-thigh."+side);var knee := _bone_world("DEF-shin."+side);var ankle := _foot_world(side)
	var lengths: Vector2=_leg_lengths[side]
	var offset := target.origin-hip.origin
	if offset.length()<.000001: return lengths.x+lengths.y
	var axis := offset.normalized()
	var distance := clampf(offset.length(),absf(lengths.x-lengths.y)+.00001,lengths.x+lengths.y-.00001)
	var pole := Vector3.UP-axis*axis.dot(Vector3.UP)
	if pole.length()<.00001: pole=_actor.global_basis.z-axis*axis.dot(_actor.global_basis.z)
	pole=pole.normalized()
	var along := (lengths.x*lengths.x+distance*distance-lengths.y*lengths.y)/(2*distance)
	var knee_goal := hip.origin+axis*along+pole*sqrt(maxf(0,lengths.x*lengths.x-along*along))
	var ankle_goal := hip.origin+axis*distance
	_set_joint_world_rotation(_bones["DEF-thigh."+side],(Quaternion((knee.origin-hip.origin).normalized(),(knee_goal-hip.origin).normalized())*hip.basis.get_rotation_quaternion()).normalized())
	_set_joint_world_rotation(_bones["DEF-shin."+side],(Quaternion((ankle.origin-knee.origin).normalized(),(ankle_goal-knee_goal).normalized())*knee.basis.get_rotation_quaternion()).normalized())
	_set_joint_world_rotation(_bones["DEF-foot."+side],target.basis.get_rotation_quaternion().normalized())
	return ankle_goal.distance_to(target.origin)

func _hands(phase: String, progress: float) -> Dictionary:
	var requests: Dictionary=_f_request.get("hands",{})
	var result := {};var weight := smoothstep(0,.15,progress) if phase in STEP_PHASES else 1.0
	if bool(_f_request.get("keep_hand_contact",false)):weight=1.0
	for side in SIDES:
		if not requests.get(side) is Dictionary: continue
		var record: Dictionary=requests[side]
		var palm: Dictionary=_hand_contact(side)
		if not record.get("palm_transform") is Transform3D or palm.is_empty(): continue
		var target: Transform3D=record.palm_transform
		var basis: Basis=target.basis*palm.basis.inverse()
		var wrist := Transform3D(basis,target.origin-basis*palm.position)
		wrist=_rigid_blend(_bone_world("DEF-hand."+side),wrist,weight)
		var error := _solve_arm(side,wrist)
		var actual: Vector3=_actual_palm(side,palm)
		result[side]={"actual_palm":actual,"target":target.origin,"error_m":actual.distance_to(target.origin),"reach_residual_m":error,"source_vertex":palm.vertex}
		if palm.has("skin_records"):
			result[side].source_contact={"method":"actual imported hand-only Skin triangle at 75% of the index base; final deformed barycentric measurement",
				"surface":palm.surface,"vertices":palm.vertices,"barycentric":palm.barycentric,"hand_local":Transform3D(palm.basis,palm.position)}
		var closure: float=clampf(float(record.get("grip",false)),0,1)
		for finger in 5:
			var index: int=_bones["DEF-finger%d.%s"%[finger,side]]
			var rest := get_skeleton().get_bone_rest(index).basis.get_rotation_quaternion()
			var closed := .35
			if finger<2 and _f_request.get("handle") is Dictionary and closure>0:
				closed=_fit_handle_finger(side,"thumb" if finger==0 else "index",_f_request.handle)
			get_skeleton().set_bone_pose_rotation(index,(rest*Quaternion(Vector3.RIGHT,lerpf(HANDLE_FINGER_OPEN,closed,closure))).normalized())
		if _f_request.get("handle") is Dictionary:result[side].fingers=_finger_contacts(side,_f_request.handle)
	return result

func _fit_handle_finger(side: String, label: String, handle: Dictionary) -> float:
	# Fit only a legal rest-relative joint rotation. Evaluate the imported Skin
	# surface against the real cylinder; never translate bones or move targets.
	# Relative hand/handle geometry is stable during a pull, so solve it once.
	var hand: Transform3D=_bone_world("DEF-hand."+side).affine_inverse()
	var a: Vector3=hand*handle.a;var b: Vector3=hand*handle.b
	var key: String=side+label+str(a.snapped(Vector3.ONE*.0001))+str(b.snapped(Vector3.ONE*.0001))+str(handle.radius)
	if _handle_finger_angles.has(key):return _handle_finger_angles[key]
	var bone: int=_bones["DEF-finger%d.%s"%[0 if label=="thumb" else 1,side]]
	var skeleton: Skeleton3D=get_skeleton();var poses: Array[Transform3D]=[]
	for index in skeleton.get_bone_count():poses.append(skeleton.get_bone_global_pose(index))
	var local: Transform3D=skeleton.get_bone_pose(bone)
	var rest: Quaternion=skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	var parent: int=skeleton.get_bone_parent(bone)
	var best := INF;var chosen := .35
	for step in 33:
		var angle: float=lerpf(.35,HANDLE_FINGER_LIMIT,float(step)/32)
		local.basis=Basis((rest*Quaternion(Vector3.RIGHT,angle)).normalized())
		poses[bone]=poses[parent]*local if parent>=0 else local
		var nearest := INF;var deepest := 0.0
		for point in _skin_points[label+"."+side]:
			var distance: float=_handle_signed_distance(_skin_point(point,poses),handle)
			nearest=minf(nearest,absf(distance));deepest=minf(deepest,distance)
		# A touching vertex must not conceal deep penetration of this finger.
		var score: float=nearest+maxf(0,-deepest-.002)*50+angle*.00001
		if score<best:best=score;chosen=angle
	if _handle_finger_angles.size()>=32:_handle_finger_angles.clear()
	_handle_finger_angles[key]=chosen
	return chosen

func _finger_contacts(side: String, handle: Dictionary) -> Dictionary:
	var result := {}
	for label in ["thumb","index"]:
		var closest: float=INF;var signed: float=INF;var deepest := 0.0;var observed: Dictionary={}
		for point in _skin_points[label+"."+side]:
			var actual: Vector3=_skin_point(point)
			var error: float=_handle_signed_distance(actual,handle)
			deepest=minf(deepest,error)
			if error<-.004:continue
			if absf(error)<closest:closest=absf(error);signed=error;observed={"actual":actual,"vertex":point.vertex,"surface":point.surface}
		var bone: int=_bones["DEF-finger%d.%s"%[0 if label=="thumb" else 1,side]]
		var angle: float=get_skeleton().get_bone_rest(bone).basis.get_rotation_quaternion().angle_to(get_skeleton().get_bone_pose_rotation(bone))
		observed.distance_m=closest;observed.signed_distance_m=signed;observed.penetration_m=maxf(0,-deepest);observed.observed_rotation=angle;observed.contact=closest<=.01 and deepest>=-.004 and angle>=.25
		result[label]=observed
	return result

static func _handle_signed_distance(point: Vector3, handle: Dictionary) -> float:
	var axis: Vector3=handle.b-handle.a
	var length: float=axis.length()
	var offset: Vector3=point-(handle.a+handle.b)*.5
	var along: float=offset.dot(axis/length)
	var radial: float=(offset-axis/length*along).length()
	var q := Vector2(radial-float(handle.radius),absf(along)-length*.5)
	return q.max(Vector2.ZERO).length()+minf(maxf(q.x,q.y),0)

func _solve_arm(side: String, target: Transform3D) -> float:
	var names := ["DEF-upper_arm."+side,"DEF-forearm."+side,"DEF-hand."+side]
	var a := _bone_world(names[0]);var b := _bone_world(names[1]);var c := _bone_world(names[2])
	var upper: float=get_skeleton().get_bone_rest(_bones[names[1]]).origin.length()
	var lower: float=get_skeleton().get_bone_rest(_bones[names[2]]).origin.length()
	var offset := target.origin-a.origin
	if offset.length()<.00001: return upper+lower
	var axis := offset.normalized();var distance := clampf(offset.length(),absf(upper-lower)+.00001,upper+lower-.00001)
	var bend := b.origin-a.origin;var old_axis := (c.origin-a.origin).normalized()
	bend-=old_axis*bend.dot(old_axis)
	if bend.length()<.00001: bend=_actor.global_basis.x*(1 if side=="L" else -1)
	bend=Quaternion(old_axis,axis)*bend.normalized()
	var along := (upper*upper+distance*distance-lower*lower)/(2*distance)
	var elbow := a.origin+axis*along+bend*sqrt(maxf(0,upper*upper-along*along))
	var end := a.origin+axis*distance
	_set_joint_world_rotation(_bones[names[0]],(Quaternion((b.origin-a.origin).normalized(),(elbow-a.origin).normalized())*a.basis.get_rotation_quaternion()).normalized())
	_set_joint_world_rotation(_bones[names[1]],(Quaternion((c.origin-b.origin).normalized(),(end-elbow).normalized())*b.basis.get_rotation_quaternion()).normalized())
	_set_joint_world_rotation(_bones[names[2]],target.basis.get_rotation_quaternion().normalized())
	return end.distance_to(target.origin)

func _point_at(side: String, key: String, globals: Array, world: Transform3D) -> Vector3:
	var result := Vector3.ZERO
	for record in _contacts[side][key]: result+=(world*globals[record.bone]*record.position)*float(record.weight)
	return result

func _skin_point(record: Dictionary, poses: Array = []) -> Vector3:
	var part: MeshInstance3D=record.mesh.get_ref()
	if part==null: return Vector3(INF,INF,INF)
	var result := Vector3.ZERO
	for influence_record in record.influences:
		var pose: Transform3D=poses[influence_record.bone] if not poses.is_empty() else get_skeleton().get_bone_global_pose(influence_record.bone)
		result+=(pose*influence_record.position)*float(influence_record.weight)
	return part.global_transform*result

func _skin_low(region: String, poses: Array = []) -> float:
	var low := INF
	var globals := poses if not poses.is_empty() else _globals(_read_locals())
	var frames := {}
	for record in _skin_points[region]:
		var mesh: MeshInstance3D=record.mesh.get_ref()
		if mesh==null: continue
		var id := mesh.get_instance_id()
		if not frames.has(id): frames[id]=mesh.global_transform
		var point := Vector3.ZERO
		for influence_record in record.influences: point+=(globals[influence_record.bone]*influence_record.position)*float(influence_record.weight)
		low=minf(low,(frames[id]*point).y)
	return low

func _add_skin_point(region: String, record: Dictionary) -> void:
	# Imported triangle soup repeats the same vertex at material/triangle
	# boundaries. Identical bind positions and full weight tuples deform to
	# the identical real point; keep one original vertex as its provenance.
	if not _skin_seen.has(region): _skin_seen[region]={}
	var key: String=record.identity
	if _skin_seen[region].has(key): return
	_skin_seen[region][key]=true;_skin_points[region].append(record)

func _collect_skin() -> bool:
	var skeleton := get_skeleton()
	var pelvis_rest: Transform3D=_rest_globals[_bones["DEF-pelvis"]]
	var scale: float=float(_contract.get("translation_scale",1.0))
	# The imported character's hip joint is not a skin landmark. In these rigs
	# the first visible upper-thigh ring can sit .18m below it; derive the
	# proximal-thigh region from the real bone length, rather than multiplying
	# a guessed centimetre box by the unrelated source-retarget ratio.
	var proximal_depth: float=minf(_leg_lengths.L.x,_leg_lengths.R.x)*.55
	var torso_height: float=(_rest_globals[_bones["DEF-chest"]].origin-pelvis_rest.origin).length()
	for key in _skin_points: _skin_points[key]=[]
	_skin_seen.clear()
	_skin_meshes.clear()
	_handle_finger_angles.clear()
	_handle_palms.clear()
	var palms := {"L":[],"R":[]}
	for node in _actor.find_children("*","MeshInstance3D",true,false):
		var part: MeshInstance3D=node
		if part.mesh==null or part.skin==null or part.get_node_or_null(part.skeleton)!=skeleton: continue
		_skin_meshes.append(weakref(part))
		var palette: Array[int]=[]
		for bind in part.skin.get_bind_count():
			var name: StringName=part.skin.get_bind_name(bind)
			palette.append(skeleton.find_bone(name) if not name.is_empty() else part.skin.get_bind_bone(bind))
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var joints: Variant=arrays[Mesh.ARRAY_BONES];var weights: Variant=arrays[Mesh.ARRAY_WEIGHTS]
			if positions.is_empty() or joints==null or weights==null: continue
			var count: int=joints.size()/positions.size()
			if count not in [4,8]: continue
			var hand_skin := {"L":{},"R":{}}
			for vertex in positions.size():
				var influences: Array=[];var groups := {};var rest := Vector3.ZERO
				for slot in count:
					var weight: float=weights[vertex*count+slot]
					if weight<=0: continue
					var bind: int=joints[vertex*count+slot];var bone: int=palette[bind]
					if bone<0: return false
					var position: Vector3=part.skin.get_bind_pose(bind)*positions[vertex]
					influences.append({"bone":bone,"position":position,"weight":weight})
					rest+=(_rest_globals[bone]*position)*weight
					groups[skeleton.get_bone_name(bone)]=float(groups.get(skeleton.get_bone_name(bone),0))+weight
				var identity := PackedFloat64Array([float(part.get_instance_id())])
				for entry in influences:
					identity.append_array(PackedFloat64Array([float(entry.bone),entry.position.x,entry.position.y,entry.position.z,float(entry.weight)]))
				var record := {"mesh":weakref(part),"surface":surface,"vertex":vertex,"influences":influences,"identity":identity.to_byte_array().hex_encode()}
				var rest_world := part.global_transform*rest
				var rest_skeleton := skeleton.global_transform.affine_inverse()*rest_world
				var local := pelvis_rest.affine_inverse()*rest_skeleton
				var pelvic: float=float(groups.get("DEF-pelvis",0))+float(groups.get("DEF-thigh.L",0))+float(groups.get("DEF-thigh.R",0))
				if pelvic>=.8 and absf(local.x)<.22*scale and local.y>=-proximal_depth and local.y<=torso_height*.5 and local.z<.04*scale: _add_skin_point("seat",record)
				var torso: float=float(groups.get("DEF-pelvis",0))+float(groups.get("DEF-spine_01",0))+float(groups.get("DEF-spine_02",0))+float(groups.get("DEF-chest",0))
				if torso>=.8 and local.z<0 and local.y>=-.08*scale: _add_skin_point("back",record)
				if float(groups.get("DEF-head",0))>=.95 and rest_skeleton.z<0: _add_skin_point("head",record)
				for side in SIDES:
					if float(groups.get("DEF-finger0."+side,0))>=.5:_add_skin_point("thumb."+side,record)
					if float(groups.get("DEF-finger1."+side,0))>=.5:_add_skin_point("index."+side,record)
					if float(groups.get("DEF-foot."+side,0))+float(groups.get("DEF-toe."+side,0))>=.99: _add_skin_point(side,record)
					if float(groups.get("DEF-hand."+side,0))>=.9999:
						var point: Vector3=_rest_globals[_bones["DEF-hand."+side]].affine_inverse()*rest_skeleton
						hand_skin[side][vertex]={"position":point,"record":record}
						if point.y>.005 and point.y<.06*scale: palms[side].append({"position":point,"vertex":vertex,"surface":surface})
			for side in SIDES:_collect_handle_triangles(side,hand_skin[side],arrays[Mesh.ARRAY_INDEX],positions.size(),surface)
	for side in SIDES:
		if palms[side].is_empty(): continue
		palms[side].sort_custom(func(a,b):return absf(a.position.y-.03*scale)-a.position.z<absf(b.position.y-.03*scale)-b.position.z)
		var selected: Dictionary=palms[side][0]
		_palm_points[side]={"position":selected.position,"basis":Basis.IDENTITY,"vertex":selected.vertex,"surface":selected.surface}
	return not _skin_points.seat.is_empty() and not _skin_points.back.is_empty() and not _skin_points.head.is_empty()

func _collect_handle_triangles(side: String, vertices: Dictionary, indices: Variant, vertex_count: int, surface: int) -> void:
	var hand: Transform3D=_rest_globals[_bones["DEF-hand."+side]]
	var index_base: Vector3=hand.affine_inverse()*_rest_globals[_bones["DEF-finger1."+side]].origin
	var plane: float=index_base.y*.75
	var count: int=indices.size() if indices!=null and not indices.is_empty() else vertex_count
	for offset in range(0,count-2,3):
		var ids: Array[int]=[]
		for corner in 3:ids.append(int(indices[offset+corner]) if indices!=null and not indices.is_empty() else offset+corner)
		if not vertices.has(ids[0]) or not vertices.has(ids[1]) or not vertices.has(ids[2]):continue
		var points: Array[Vector3]=[vertices[ids[0]].position,vertices[ids[1]].position,vertices[ids[2]].position]
		var hits: Array=[]
		for edge in 3:
			var next: int=(edge+1)%3;var a: Vector3=points[edge];var b: Vector3=points[next]
			if absf(a.y-b.y)<.00000001 or (a.y-plane)*(b.y-plane)>0:continue
			var t: float=(plane-a.y)/(b.y-a.y);var weights := Vector3.ZERO
			weights[edge]=1-t;weights[next]=t
			var position: Vector3=a.lerp(b,t)
			if not hits.is_empty() and position.distance_squared_to(hits[0].position)<.000000000001:continue
			hits.append({"position":position,"weights":weights})
		if hits.size()<2:continue
		var a: Dictionary=hits[0];var b: Dictionary=hits[1]
		var t: float=clampf(-a.position.x/(b.position.x-a.position.x),0,1) if absf(b.position.x-a.position.x)>.00000001 else 0
		var position: Vector3=a.position.lerp(b.position,t)
		if position.z<=0:continue
		var normal: Vector3=(points[1]-points[0]).cross(points[2]-points[0])
		if normal.length_squared()<.000000000001:continue
		normal=normal.normalized()
		if normal.z<0:normal=-normal
		var along: Vector3=Vector3.UP-normal*normal.y
		if along.length_squared()<.000001:continue
		along=along.normalized();var right: Vector3=along.cross(normal).normalized();along=normal.cross(right).normalized()
		var score: float=-position.z+absf(position.x)*.15
		if _handle_palms.has(side) and score>=float(_handle_palms[side].score):continue
		_handle_palms[side]={"position":position,"basis":Basis(right,along,normal),"vertex":ids[0],"vertices":ids,"surface":surface,
			"barycentric":a.weights.lerp(b.weights,t),"skin_records":[vertices[ids[0]].record,vertices[ids[1]].record,vertices[ids[2]].record],"score":score}

func snapshot() -> Dictionary:
	return {"version":FURNITURE_FORMAT,"target":_contract.get("target",""),"enabled":_f_enabled,"request":_encode(_f_request),"serial":_f_serial,"applied":_f_applied,"sample_serial":_f_sample_serial,
		"phase":_f_phase,"progress":_f_progress,"entry":_encode(_f_entry),"feet":_encode(_f_feet),"step":_f_step,"swing":_f_swing,"from":_encode(_f_from),"goal":_encode(_f_goal),"start":_encode(_f_start),
		"last_pose":_encode(_f_last_pose),"rendered_pose":_encode(_rendered_pose),"rendered_world":_encode(_rendered_world),"rendered_serial":_rendered_serial}

func can_restore(data: Variant) -> bool: return not _checked_furniture_restore(data).is_empty()

func restore(data: Variant) -> bool:
	var value := _checked_furniture_restore(data)
	if value.is_empty(): return false
	_f_enabled=data.enabled;_f_request=value.request;_f_serial=int(data.serial);_f_applied=int(data.applied);_f_sample_serial=-1
	_f_phase=data.phase;_f_progress=float(data.progress);_f_entry=value.entry;_f_feet=value.feet
	_f_step=int(data.step);_f_swing=data.swing;_f_from=value.from;_f_goal=value.goal;_f_start=value.start
	_f_last_pose=value.last_pose;_rendered_pose=value.rendered_pose;_rendered_world=value.rendered_world;_rendered_serial=int(data.rendered_serial)
	_f_observed.clear()
	_f_static_key.clear();_f_static_observed.clear()
	return true

func _checked_furniture_restore(data: Variant) -> Dictionary:
	if not _configured or not data is Dictionary or data.size()!=20 or data.get("version")!=FURNITURE_FORMAT or data.get("target")!=_contract.get("target","") or not data.get("enabled") is bool or not _finite_tree(data): return {}
	for key in ["serial","applied","sample_serial","step","rendered_serial"]:
		if not _finite_number(data.get(key)) or int(data[key])!=data[key]: return {}
	if data.serial<0 or data.applied>data.serial or data.sample_serial>data.serial or data.applied< -1 or data.sample_serial< -1 or data.step< -1 or data.step>1 or data.rendered_serial<0: return {}
	if data.get("phase") not in PHASES+[""] or data.get("swing") not in SIDES or not _finite_number(data.get("progress")) or data.progress<0 or data.progress>1: return {}
	var decoded: Variant=_decode(data)
	if not decoded is Dictionary or not decoded.request is Dictionary or (data.enabled and not _valid_request(decoded.request)): return {}
	for key in ["from","goal","start","rendered_world"]:
		if not _valid_transform(decoded[key]): return {}
	for key in ["entry","last_pose","rendered_pose"]:
		if not decoded[key] is Array or (not decoded[key].is_empty() and decoded[key].size()!=_parents.size()): return {}
		for pose in decoded[key]:
			if not _valid_transform(pose): return {}
	if not decoded.feet is Dictionary: return {}
	for side in decoded.feet:
		var foot: Variant=decoded.feet[side]
		if side not in SIDES or not foot is Dictionary or foot.get("point") not in POINTS or not _valid_transform(foot.get("transform")) or not foot.get("anchor") is Vector3: return {}
		for key in ["floor_start","floor_mid","floor_end"]:
			if foot.has(key) and not _valid_transform(foot[key]): return {}
			if data.phase=="chair_slide" and not foot.has(key): return {}
		if foot.has("first_swing") and foot.first_swing not in SIDES: return {}
		if data.phase in STEP_PHASES and not foot.has("first_swing"): return {}
	return decoded

static func _valid_request(value: Dictionary) -> bool:
	if value.get("phase") not in PHASES or not _finite_number(value.get("progress")) or value.progress<0 or value.progress>1: return false
	if not value.get("floor_y",0.0) is float and not value.get("floor_y",0.0) is int: return false
	if not is_finite(float(value.get("floor_y",0.0))): return false
	if value.has("pose_seconds") and (not _finite_number(value.pose_seconds) or value.pose_seconds<0): return false
	if value.has("allow_dangling_feet") and not value.allow_dangling_feet is bool:return false
	if value.has("keep_hand_contact") and not value.keep_hand_contact is bool:return false
	if value.phase in ["legs_in","lie_down","lie_idle","sit_up","legs_out"]:
		if not value.get("bed") is Dictionary: return false
		for key in ["pelvis_point","pillow_point","head_direction"]:
			if not value.bed.get(key) is Vector3 or not value.bed[key].is_finite(): return false
		if not _finite_number(value.bed.get("sheet_y")) or Vector2(value.bed.head_direction.x,value.bed.head_direction.z).length()<.5: return false
	elif value.phase not in ["step_back","step_forward"]:
		if not value.get("seat_point") is Vector3 or not value.seat_point.is_finite(): return false
	if value.has("root_end") and not _valid_transform(value.root_end): return false
	if value.has("root_start") and not _valid_transform(value.root_start): return false
	if not value.get("feet",{}) is Dictionary or not value.get("hands",{}) is Dictionary or not value.get("footrest",{}) is Dictionary: return false
	if not value.get("working_hands",{}) is Dictionary:return false
	for side in value.get("working_hands",{}):
		if side not in SIDES or not value.working_hands[side] is Dictionary or not _valid_transform(value.working_hands[side].get("palm_transform")):return false
	if value.phase in ["step_back","step_forward"] and not value.get("hands",{}).is_empty():return false
	if value.has("handle"):
		if not value.handle is Dictionary or not value.handle.get("a") is Vector3 or not value.handle.get("b") is Vector3 or not value.handle.a.is_finite() or not value.handle.b.is_finite() or value.handle.a.distance_to(value.handle.b)<.01 or not _finite_number(value.handle.get("radius")) or value.handle.radius<=0 or value.handle.radius>.1:return false
	if not value.get("footrest",{}).is_empty():
		var rail: Dictionary=value.footrest
		if not rail.get("center") is Vector3 or not rail.center.is_finite() or not _finite_number(rail.get("half_width")) or rail.half_width<=0 or not _finite_number(rail.get("support_y")): return false
	return true
