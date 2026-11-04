class_name FoundationHouseholdPose
extends FoundationLocomotionPose

# Last upper-body modifier after locomotion/furniture. The controller owns time,
# object ownership and work results; this provider only poses and observes skin.
const HANDS := preload("res://game/foundation/foundation_hand_contact.gd")
const HOUSEHOLD_FORMAT := 2
const ACTIONS := ["transfer","prepare","stir","eat","wash","fold","desk"]
const ACTION_PHASES := ["reach","grasp","lift","carry","lower","release","work","recover"]
const SOURCE_ACTIONS := ["pickup_table","interact","fixing_kneeling","push_loop"]
const PALM_CONTACT_TOLERANCE := .01
const UPPER := ["DEF-spine_01","DEF-spine_02","DEF-chest","DEF-neck","DEF-head","DEF-clavicle.L","DEF-clavicle.R","DEF-upper_arm.L","DEF-upper_arm.R","DEF-forearm.L","DEF-forearm.R","DEF-hand.L","DEF-hand.R"]
var _h_hands: FoundationHandContact
var _h_library: AnimationLibrary
var _h_contract: Dictionary = {}
var _h_tracks: Dictionary = {}
var _h_request: Dictionary = {}
var _h_enabled := false
var _h_serial := 0
var _h_applied := -1
var _h_sample := -1
var _h_action := ""
var _h_phase := ""
var _h_progress := 0.0
var _h_entry: Array = []
var _h_entry_palms: Dictionary = {}
var _h_home: Dictionary = {}
var _h_feet: Dictionary = {}
var _h_last: Array = []
var _h_rendered: Array = []
var _h_rendered_world := Transform3D.IDENTITY
var _h_had_grasp := false
var _h_grasp_item := ""
var _h_grasped_objects: Dictionary = {}
var _h_phase_item := ""
var _h_observed: Dictionary = {}
var _h_calibration: Dictionary = {}

func configure(actor: Node3D, library: AnimationLibrary, contract: Dictionary, profile: Dictionary = {}) -> bool:
	if not super.configure(actor,library,contract,profile):return false
	_h_hands=HANDS.new()
	if not _h_hands.configure(actor,get_skeleton()):return false
	_h_library=null;_h_contract.clear();_h_tracks.clear()
	var shoulders := Vector3.ZERO;var span := INF
	for side in SIDES:
		shoulders+=(_skeleton_in_actor*_rest_globals[_bones["DEF-upper_arm."+side]]).origin*.5
		span=minf(span,get_skeleton().get_bone_rest(_bones["DEF-forearm."+side]).origin.length()+get_skeleton().get_bone_rest(_bones["DEF-hand."+side]).origin.length())
	_h_calibration={"carry_grip_center_actor":Vector3(0,shoulders.y-span*.25,span*.50),"arm_span_min_m":span,
		"palm_L":_h_hands.provenance("L"),"palm_R":_h_hands.provenance("R"),"source":"actual rig rest shoulders/arm spans and imported Skin vertices"}
	_h_calibration["body_front_actor"]=_h_hands.torso_front_actor
	_h_calibration["body_front_vertex"]=_h_hands.torso_front_vertex.duplicate(true)
	_h_calibration["carry_anchor_method"]="authored comfortable hand midpoint from measured shoulders/arm span; prop bounds and source support constrain the actual controller frame"
	if not get_skeleton().skeleton_updated.is_connected(_household_sample):get_skeleton().skeleton_updated.connect(_household_sample)
	return true

func set_action_library(library: AnimationLibrary, contract: Dictionary = {}) -> bool:
	if not _configured or library==null or (contract.has("target") and contract.target!=_contract.get("target","")):return false
	for key in SOURCE_ACTIONS:
		if not library.has_animation(key):return false
	var mapped := {}
	for key in library.get_animation_list():
		var animation: Animation=library.get_animation(key);var tracks := []
		for index in animation.get_track_count():
			var path := animation.track_get_path(index)
			if path.get_subname_count()!=1:continue
			var name: String=str(path.get_subname(0))
			if _bones.has(name):tracks.append({"bone":_bones[name],"track":index,"type":animation.track_get_type(index)})
		var included := {}
		for record in tracks:included[record.bone]=true
		if included.size()!=_parents.size():return false
		mapped[key]=tracks
	_h_library=library;_h_contract=contract.duplicate(true);_h_tracks=mapped
	return true

func calibration() -> Dictionary:return _h_calibration.duplicate(true)
func request_state() -> Dictionary:return _h_request.duplicate(true) if _h_enabled else {}
func telemetry() -> Dictionary:return _h_observed.duplicate(true)

func can_present(request: Dictionary) -> bool:
	if not _configured or not _valid_household_request(request):return false
	# Another hand can continue holding a previously observed object. A request
	# alone never creates that grasp or proves that the source was picked up.
	for id in request.get("held_objects",{}):
		if not _h_grasped_objects.has(id) or _item_sides(request.held_objects[id])!=_h_grasped_objects[id]:return false
	var active_id: String=str(request.get("object",{}).get("id",""))
	var active_sides: Array=_item_sides(request.get("object",{}))
	for id in _h_grasped_objects:
		if id==active_id:continue
		if not request.get("held_objects",{}).has(id):return false
		for side in active_sides:
			if side in _h_grasped_objects[id]:return false
	return true

func present(request: Dictionary, delta: float = 0.0) -> bool:
	if not _finite_number(delta) or delta<0 or delta>1 or not can_present(request):return false
	_h_request=request.duplicate(true);_h_enabled=true;_h_serial+=1
	return true

func clear() -> void:
	_h_request.clear();_h_enabled=false;_h_action="";_h_phase="";_h_entry=[];_h_feet.clear();_h_home.clear();_h_entry_palms.clear();_h_last=[];_h_had_grasp=false;_h_grasp_item="";_h_grasped_objects.clear();_h_phase_item="";_h_observed.clear();_h_sample=-1

func grasped_objects() -> Dictionary:return _h_grasped_objects.duplicate(true)

func confirm_grasp(item_id: String) -> bool:
	# Observing a closed hand proposes a grasp. Only the material controller
	# commits ownership, so a save between render and step cannot claim a held
	# object in the body while the same object still rests in the Day ledger.
	if str(_h_request.get("object",{}).get("id",""))!=item_id or not transfer_ready("grasp"):return false
	var sides: Array=_item_sides(_h_request.object)
	_h_grasped_objects[item_id]=sides;_h_had_grasp=true;_h_grasp_item=item_id
	return true

func confirm_release(item_id: String) -> bool:
	# The resource controller calls this only after its own placement commit.
	# Keep the observed grasp until then so readiness survives the render/step
	# boundary and releasing one hand cannot discard a second held object.
	if str(_h_request.get("object",{}).get("id",""))!=item_id or not transfer_ready("release"):return false
	_h_grasped_objects.erase(item_id)
	_h_had_grasp=not _h_grasped_objects.is_empty()
	_h_grasp_item=str(_h_grasped_objects.keys()[0]) if _h_had_grasp else ""
	_h_observed.release_ready=false
	return true

func contacts_ready() -> bool:
	return _h_enabled and _h_sample==_h_serial and _h_observed.get("contacts_ready",false)

func transfer_ready(operation: String) -> bool:
	if not _h_enabled or _h_sample!=_h_serial:return false
	if operation=="grasp":return _h_request.phase=="grasp" and _h_observed.get("grasp_ready",false)
	if operation=="release":return _h_request.phase=="release" and _h_observed.get("release_ready",false)
	return false

func _household_sample() -> void:
	_h_rendered=_read_locals();_h_rendered_world=get_skeleton().global_transform
	if not _h_enabled or _h_applied!=_h_serial:return
	_h_sample=_h_serial;_h_observed["latest_sample_serial"]=_h_sample
	# Re-read the true final skin inside Skeleton3D.skeleton_updated. Transfer
	# readiness never relies only on a requested IK endpoint or pose weight.
	var peak := 0.0;var closed := 1.0;var opened := 0.0;var shift := Vector3.ZERO;var count := 0
	var item: Dictionary=_h_request.get("object",{})
	var active_sides: Array=_item_sides(item)
	var active_count := 0
	for side in _h_observed.get("hands",{}):
		var record: Dictionary=_h_observed.hands[side]
		var actual := _h_hands.palm(side)
		record.actual_palm=actual;record.error_m=actual.origin.distance_to(record.target.origin)
		peak=maxf(peak,float(record.error_m));shift+=actual.origin-record.target.origin;count+=1
		var amount := _observed_hand_closure(side)
		if side in active_sides:closed=minf(closed,amount);opened=maxf(opened,amount);active_count+=1
		record.actual_finger_closure=amount
	var semantic_ready: bool=_h_request.get("posture","stand")!="kneel" and not (_h_request.action=="eat" and _h_request.phase=="work" and not _h_request.get("mouth_palm_transform") is Transform3D)
	var ready: bool=count>0 and peak<=PALM_CONTACT_TOLERANCE and float(_h_observed.get("arm_reach_peak_m",INF))<=PALM_CONTACT_TOLERANCE and float(_h_observed.get("feet_reach_peak_m",INF))<=.03 and semantic_ready
	_h_observed.contact_error_peak_m=peak;_h_observed.contacts_ready=ready
	var item_id: String=str(item.get("id",""))
	_h_observed.grasp_ready=_h_request.phase=="grasp" and _h_request.progress>=.8 and active_count==active_sides.size() and active_count>0 and closed>=.7 and ready and not item_id.is_empty()
	# Release observes the current object's hand only, retaining another hand's
	# grasp. It never treats the other object's closed fingers as a failed release.
	var observed_grasp: bool=_h_grasped_objects.has(item_id)
	_h_observed.release_ready=active_count==active_sides.size() and active_count>0 and _h_request.phase=="release" and _h_request.progress>=.6 and opened<=.1 and ready and observed_grasp and _placement_support_error()<=.03
	_h_observed.grasped_objects=_h_grasped_objects.duplicate(true)
	_h_observed["sample_method"]="final_skeleton_updated_actual_imported_skin_and_finger_rotations"
	_h_observed["semantic_contacts_available"]=semantic_ready
	_h_observed["not_ready_reason"]="" if ready else ("semantic_tool_or_support_unavailable" if not semantic_ready else ("no_hand_contacts" if count==0 else ("actual_palm_or_arm_unreachable" if peak>PALM_CONTACT_TOLERANCE or float(_h_observed.get("arm_reach_peak_m",INF))>PALM_CONTACT_TOLERANCE else "stance_unreachable")))
	if count>0 and ready and item.get("world") is Transform3D and _h_request.phase in ["grasp","lift","carry","lower"]:
		var frame: Transform3D=item.world;frame.origin+=shift/count
		_h_observed.object_transforms={str(item.id):frame}
	else:_h_observed.object_transforms={}

func _process_modification_with_delta(_skeleton_delta: float) -> void:
	if not _h_enabled:return
	if _h_applied==_h_serial:
		if not _h_last.is_empty():
			if _h_request.phase=="carry" or _h_request.get("posture","stand")=="sit" or _h_request.get("preserve_lower_body",false):_write_upper(_h_last,true)
			else:_set_locals(_h_last)
		return
	_h_applied=_h_serial
	var started := Time.get_ticks_usec()
	var action: String=_h_request.action;var phase: String=_h_request.phase;var progress: float=_h_request.progress
	var incoming := _read_locals()
	if action!=_h_action or phase!=_h_phase or progress<_h_progress-.000001 or str(_h_request.get("object",{}).get("id",""))!=_h_phase_item:_begin_household_phase(action,phase)
	_h_progress=progress
	var preserve_lower: bool=phase=="carry" or _h_request.get("posture","stand")=="sit" or _h_request.get("preserve_lower_body",false)
	var source := _source_pose(action,phase,progress)
	var values: Array=source.values
	if preserve_lower:
		values=incoming.duplicate()
		for name in UPPER:
			if _bones.has(name) and (not _h_request.get("preserve_lower_body",false) or name.begins_with("DEF-clavicle") or name.begins_with("DEF-upper_arm") or name.begins_with("DEF-forearm") or name.begins_with("DEF-hand")):values[_bones[name]]=source.values[_bones[name]]
	elif phase=="recover":values=_blend(_h_entry,_standing_pose(float(_h_request.pose_seconds)),_ease(progress))
	else:values=_blend(_h_entry,values,_ease(clampf(progress/.18,0,1)) if phase=="reach" else 1.0)
	if preserve_lower:_write_upper(values,false)
	else:_set_locals(values)
	var targets := _household_targets()
	if phase=="carry" and not _h_request.get("preserve_lower_body",false):
		# The hips continue their real gait. Counterrotate the torso above the
		# pelvis to a source-neutral world orientation, as a person stabilises
		# a load, instead of forcing either wrist to absorb every hip swivel.
		var upright := _globals(_standing_pose(float(_h_request.pose_seconds)))
		for name in ["DEF-spine_01","DEF-spine_02","DEF-chest","DEF-neck","DEF-head"]:
			var rotation: Quaternion=(get_skeleton().global_basis*upright[_bones[name]].basis).get_rotation_quaternion().normalized()
			_set_joint_world_rotation(_bones[name],rotation)
		for side in SIDES:
			# The source casual idle retracts one clavicle by about fifty
			# degrees. A symmetric load needs both shoulders neutral before
			# bounded, target-driven protraction, rather than that idle gesture.
			var name: String="DEF-clavicle."+side
			var rotation: Quaternion=(get_skeleton().global_basis*_rest_globals[_bones[name]].basis).get_rotation_quaternion().normalized()
			_set_joint_world_rotation(_bones[name],rotation)
	if not preserve_lower:_fit_working_body(targets)
	_fit_shoulders(targets)
	_apply_gaze()
	var feet_reach := 0.0
	if not preserve_lower:
		for side in SIDES:
			# Retain the actual stance shoe's toe pose while feet are planted;
			# the source's unrelated toe-off must not tunnel into the floor.
			get_skeleton().set_bone_pose(_bones["DEF-toe."+side],_h_entry[_bones["DEF-toe."+side]])
			feet_reach=maxf(feet_reach,_solve_leg(side,_h_feet[side]))
	var records := {};var contact_peak := 0.0;var arm_peak := 0.0;var object_shift := Vector3.ZERO;var count := 0
	for side in SIDES:
		if not targets.has(side):continue
		var desired: Transform3D=targets[side].palm_transform
		var reach := _h_hands.solve(side,desired)
		_set_hand_shape(side,float(targets[side].get("grip",0.0)))
		var actual := _h_hands.palm(side)
		var error := actual.origin.distance_to(desired.origin)
		contact_peak=maxf(contact_peak,error);arm_peak=maxf(arm_peak,reach)
		object_shift+=actual.origin-desired.origin;count+=1
		records[side]={"target":desired,"actual_palm":actual,"error_m":error,"reach_residual_m":reach,"grip":targets[side].get("grip",0.0),"source":_h_hands.provenance(side),"shoulder":_bone_world("DEF-upper_arm."+side).origin,"clavicle":_bone_world("DEF-clavicle."+side).origin}
	if not preserve_lower:_update_garment()
	_h_last=_read_locals()
	var lower_unchanged := true
	if preserve_lower:
		for index in _parents.size():
			var name: String=get_skeleton().get_bone_name(index)
			if name not in UPPER and not name.begins_with("DEF-finger"):lower_unchanged=lower_unchanged and incoming[index]==_h_last[index]
	var ready: bool=count>0 and contact_peak<=PALM_CONTACT_TOLERANCE and arm_peak<=PALM_CONTACT_TOLERANCE and feet_reach<=.03
	var grasp: bool=phase=="grasp" and progress>=.8 and ready
	var placement := _placement_support_error()
	var release: bool=phase=="release" and progress>=.6 and _h_grasped_objects.has(str(_h_request.get("object",{}).get("id",""))) and placement<=.03
	var presentation := {}
	var item: Dictionary=_h_request.get("object",{})
	if item.has("id") and item.get("world") is Transform3D and count>0 and phase in ["grasp","lift","carry","lower"] and ready:
		var item_frame: Transform3D=item.world;item_frame.origin+=object_shift/count
		presentation={str(item.id):item_frame}
	_h_observed={"action":action,"phase":phase,"progress":progress,"request_serial":_h_serial,"latest_sample_serial":_h_sample,
		"hands":records,"contact_error_peak_m":contact_peak,"arm_reach_peak_m":arm_peak,"feet_reach_peak_m":feet_reach,"contacts_ready":ready,
		"grasp_ready":grasp,"release_ready":release,"placement_support_error_m":placement if is_finite(placement) else -1.0,"placement_support_available":is_finite(placement),"finger_shape":"authored rest-relative open/close only; fingertip/tool opposition is not yet accepted",
		"lower_body_preserved":preserve_lower,"lower_pose_unchanged":lower_unchanged,"source_clip":source.clip,"source_available":source.available,
		"authored_action_stage":_authored_stage(action,phase),"object_transforms":presentation,"world_transform_owner":"ResidentMotor; no provider Node3D writes",
		"elapsed_usec":Time.get_ticks_usec()-started,"quality_status":"whole-body prototype; source timing/object contact and ordinary-camera sequence review pending"}

func _begin_household_phase(action: String, phase: String) -> void:
	if action!=_h_action:
		_h_home.clear()
	_h_action=action;_h_phase=phase;_h_progress=0.0
	_h_phase_item=str(_h_request.get("object",{}).get("id",""))
	_h_entry=_h_rendered.duplicate() if not _h_rendered.is_empty() else _read_locals()
	var globals := _globals(_h_entry)
	var world := _h_rendered_world if not _h_rendered.is_empty() else get_skeleton().global_transform
	_h_feet.clear();_h_entry_palms.clear()
	for side in SIDES:
		_h_feet[side]=world*globals[_bones["DEF-foot."+side]]
		# The live preceding modifier already supplied this frame's lower body.
		# Skin palm observations from the previous final sample are retained at
		# the phase boundary, not an unmodified AnimationTree rest hand.
		var pad: Dictionary=_h_hands.pads[side]
		var hand: Transform3D=world*globals[_bones["DEF-hand."+side]]
		var palm := Transform3D(hand.basis*pad.basis_in_hand,hand*pad.local)
		_h_entry_palms[side]=palm
		if not _h_home.has(side):_h_home[side]=_actor.global_transform.affine_inverse()*palm

func _source_pose(action: String, phase: String, progress: float) -> Dictionary:
	if phase=="carry":
		return {"values":_standing_pose(float(_h_request.pose_seconds)),"clip":"authored_twohand_hold_on_source_idle; no dedicated carry source exists","available":true}
	var key := "pickup_table" if action=="transfer" else "interact"
	if _h_request.get("posture","")=="kneel":key="fixing_kneeling"
	elif action=="stir":key="push_loop"
	var fraction := .45
	if phase=="reach":fraction=progress*.50
	elif phase=="grasp":fraction=.50+progress*.10
	elif phase in ["lift","carry"]:fraction=.60+(.12*progress if phase=="lift" else .12)
	elif phase=="lower":fraction=lerpf(.72,.50,progress)
	elif phase=="recover":fraction=lerpf(.50,1.0,progress)
	if _h_request.has("source_fraction"):fraction=float(_h_request.source_fraction)
	var available: bool=_h_library!=null and _h_tracks.has(key)
	if not available:return {"values":_standing_pose(float(_h_request.pose_seconds)),"clip":"authored_fallback_on_source_idle","available":false}
	var animation: Animation=_h_library.get_animation(key)
	var result := []
	for index in _parents.size():result.append(get_skeleton().get_bone_rest(index))
	var time := clampf(fraction,0,1)*animation.length
	for record in _h_tracks[key]:
		match int(record.type):
			Animation.TYPE_POSITION_3D:result[record.bone].origin=animation.position_track_interpolate(record.track,time)
			Animation.TYPE_ROTATION_3D:result[record.bone].basis=Basis(animation.rotation_track_interpolate(record.track,time).normalized())
	if action=="transfer":
		# PickUp_Table is a one-handed source and twists the far shoulder away.
		# Reauthor the two-handed torso from the source idle's neutral/breathing
		# core, then fit its real hips/shoulders to both actual prop contacts.
		# This is declared adaptation, not a nonexistent two-hand source clip.
		var neutral := _standing_pose(float(_h_request.pose_seconds))
		for name in STANDING_CORE:result[_bones[name]].basis=neutral[_bones[name]].basis
		result[_bones["DEF-pelvis"]].origin=neutral[_bones["DEF-pelvis"]].origin
	return {"values":result,"clip":key,"available":true}

func _write_upper(values: Array, include_fingers: bool) -> void:
	# Do not even round-trip unchanged lower matrices through Skeleton3D's
	# decomposition. Locomotion/furniture remain their sole skeletal owners.
	for name in UPPER:get_skeleton().set_bone_pose(_bones[name],values[_bones[name]])
	if include_fingers:
		for name in _bones:
			if str(name).begins_with("DEF-finger"):get_skeleton().set_bone_pose(_bones[name],values[_bones[name]])

func _household_targets() -> Dictionary:
	var result: Dictionary=_h_request.get("targets",{}).duplicate(true)
	var item: Dictionary=_h_request.get("object",{})
	for side in SIDES:
		if not result.has(side) and item.get("grips",{}).get(side) is Transform3D:result[side]={"palm_transform":item.grips[side],"grip":1.0}
		elif not result.has(side) and item.get("world") is Transform3D and item.get("local_grips",{}).get(side) is Transform3D:result[side]={"palm_transform":item.world*item.local_grips[side],"grip":1.0}
	var phase: String=_h_request.phase;var p: float=_h_request.progress
	for side in result:
		var target: Transform3D=result[side].palm_transform
		var grip: float=clampf(float(result[side].get("grip",0.0)),0,1)
		if phase=="reach":
			var start: Transform3D=_h_entry_palms[side]
			if _h_request.has("reach_clearance_y"):
				var above_start: Transform3D=start;var above_target: Transform3D=target
				var top: float=maxf(float(_h_request.reach_clearance_y),maxf(start.origin.y,target.origin.y))
				above_start.origin.y=top;above_target.origin.y=top
				if p<.3:target=_rigid_blend(start,above_start,_ease(p/.3))
				elif p<.7:target=_rigid_blend(above_start,above_target,_ease((p-.3)/.4))
				else:target=_rigid_blend(above_target,target,_ease((p-.7)/.3))
			else:target=_rigid_blend(start,target,_ease(p))
			grip=0
		elif phase=="grasp":grip=_ease(p)
		elif phase=="release":grip=1-_ease(clampf(p/.6,0,1));target.origin.y+=.06*smoothstep(.70,1.0,p)
		elif phase=="recover":target=_rigid_blend(_h_entry_palms[side],_actor.global_transform*_h_home[side],_ease(p));grip=0
		elif phase=="work":
			if not _h_request.get("targets_authoritative",false):target=_work_target(side,target)
			grip=maxf(grip,.35)
		result[side]={"palm_transform":target,"grip":grip}
	# Secondary objects are kept rigid by the controller. Their hands do not
	# open/reach/recover just because the active hand changes its own object.
	for held in _h_request.get("held_objects",{}).values():
		for side in _item_sides(held):
			var target: Transform3D=held.grips[side] if held.get("grips",{}).has(side) else held.world*held.local_grips[side]
			result[side]={"palm_transform":target,"grip":1.0}
	return result

static func _item_sides(item: Dictionary) -> Array:
	var result: Array=[]
	for side in SIDES:
		if item.get("local_grips",{}).has(side) or item.get("grips",{}).has(side):result.append(side)
	return result

func _apply_gaze() -> void:
	if not _h_request.get("gaze_point") is Vector3:return
	var head: int=_bones["DEF-head"]
	var frame: Transform3D=_bone_world("DEF-head")
	var local: Vector3=_actor.global_basis.inverse()*(_h_request.gaze_point-frame.origin)
	if local.length()<.001:return
	var yaw: float=clampf(atan2(local.x,local.z),-.65,.65)
	var pitch: float=clampf(-atan2(local.y,Vector2(local.x,local.z).length()),-.4,.65)
	var turn: Basis=Basis(_actor.global_basis.y,yaw)*Basis(_actor.global_basis.x,pitch)
	_set_joint_world_rotation(head,(turn*frame.basis).get_rotation_quaternion())

func _work_target(side: String, target: Transform3D) -> Transform3D:
	var seconds: float=float(_h_request.pose_seconds)
	var yaw := _actor.global_basis.orthonormalized()
	match str(_h_request.action):
		"prepare":
			if side=="R":target.origin+=Vector3.UP*(.035*(.5-.5*cos(seconds*TAU*1.6)))
		"stir":
			if side=="R":target.origin+=yaw*Vector3(cos(seconds*TAU*.65)*.045,0,sin(seconds*TAU*.65)*.045)
		"wash":
			if side=="R":target.origin+=yaw*Vector3(cos(seconds*TAU*.8)*.055,sin(seconds*TAU*1.6)*.008,sin(seconds*TAU*.8)*.025)
		"fold":
			var cycle := fposmod(seconds/4.0,1.0)
			var fold := smoothstep(.2,.6,cycle)*(1-smoothstep(.82,1.0,cycle))
			target.origin+=yaw*Vector3((-.08 if side=="L" else .08)*fold,sin(PI*fold)*.045,-.13*fold)
		"desk":
			if side=="R":target.origin+=yaw*Vector3(sin(seconds*TAU*1.8)*.018,0,cos(seconds*TAU*.6)*.012)
		"eat":
			if side=="R" and _h_request.get("mouth_palm_transform") is Transform3D:
				var cycle := fposmod(seconds/3.6,1.0)
				var amount := smoothstep(.12,.42,cycle)*(1-smoothstep(.62,.94,cycle))
				target=_rigid_blend(target,_h_request.mouth_palm_transform,amount)
	return target

func _authored_stage(action: String, phase: String) -> String:
	if phase!="work":return phase
	if action=="eat" and not _h_request.get("mouth_palm_transform") is Transform3D:return "plate_preparation_only; utensil-to-mouth target absent"
	if action=="fold":
		var cycle := fposmod(float(_h_request.pose_seconds)/4.0,1.0)
		return "grasp_cloth_edge" if cycle<.2 else ("bring_edge_over" if cycle<.6 else ("press_fold" if cycle<.82 else "release_and_return"))
	return "authored_"+action+"_path; no dedicated source clip"

func _fit_working_body(targets: Dictionary) -> void:
	if targets.is_empty():return
	var pelvis: int=_bones["DEF-pelvis"]
	var globals := _globals(_read_locals());var world := get_skeleton().global_transform
	var original: Transform3D=world*globals[pelvis]
	var pivot: Vector3=original.origin
	var chosen := 0.0;var chosen_lower := 0.0;var best := INF
	# A low working surface needs a whole-body hinge and knee bend. Merely
	# rotating the clavicle cannot make an adult's real .44m arm reach .54m.
	# Candidates retain the captured stance and real thigh/shin lengths;
	# the subsequent leg solve bends the knees back onto those same feet.
	for index in 10:
		var angle: float=index*.12;var lean := Basis(_actor.global_basis.x,angle)
		for lower_index in 9:
			var lower: float=lower_index*.02
			var stance_possible := true
			for side in SIDES:
				var hip: Vector3=(world*globals[_bones["DEF-thigh."+side]]).origin
				hip=pivot+lean*(hip-pivot)-Vector3.UP*lower
				var lengths: Vector2=_leg_lengths[side]
				var reach: float=hip.distance_to(_h_feet[side].origin)
				if reach>lengths.x+lengths.y+.001 or reach<absf(lengths.x-lengths.y)+.01:stance_possible=false
			if not stance_possible:continue
			var excess := 0.0
			for side in targets:
				var shoulder: Vector3=(world*globals[_bones["DEF-upper_arm."+side]]).origin
				shoulder=pivot+lean*(shoulder-pivot)-Vector3.UP*lower
				var span: float=get_skeleton().get_bone_rest(_bones["DEF-forearm."+side]).origin.length()+get_skeleton().get_bone_rest(_bones["DEF-hand."+side]).origin.length()
				var target: Transform3D=targets[side].palm_transform
				var pad: Dictionary=_h_hands.pads[side]
				var wrist: Vector3=target.origin-(target.basis*pad.basis_in_hand.inverse())*pad.local
				excess=maxf(excess,shoulder.distance_to(wrist)-span*.98)
			var score := maxf(0,excess)*100+angle*.02+lower*.10
			if score<best:best=score;chosen=angle;chosen_lower=lower
	var fitted := Transform3D(Basis(_actor.global_basis.x,chosen)*original.basis,pivot-Vector3.UP*chosen_lower)
	get_skeleton().set_bone_global_pose(pelvis,get_skeleton().global_transform.affine_inverse()*fitted)

func _fit_shoulders(targets: Dictionary) -> void:
	# Protraction is a bounded real clavicle rotation, not arm-length scaling
	# or a translated wrist. It provides the normal shoulder reach for a load.
	for side in targets:
		var clavicle := _bone_world("DEF-clavicle."+side)
		var shoulder := _bone_world("DEF-upper_arm."+side)
		var pad: Dictionary=_h_hands.pads[side]
		var target: Transform3D=targets[side].palm_transform
		var wrist: Vector3=target.origin-(target.basis*pad.basis_in_hand.inverse())*pad.local
		var length: float=get_skeleton().get_bone_rest(_bones["DEF-forearm."+side]).origin.length()+get_skeleton().get_bone_rest(_bones["DEF-hand."+side]).origin.length()
		var chosen := 0.0;var best := INF
		for index in 9:
			var angle: float=index*.04
			var rotation := Basis(_actor.global_basis.y,-angle if side=="L" else angle)
			var at: Vector3=clavicle.origin+rotation*(shoulder.origin-clavicle.origin)
			var excess := maxf(0,at.distance_to(wrist)-length*.98)
			var score := excess*100+angle*.01
			if score<best:best=score;chosen=angle
		var result := Basis(_actor.global_basis.y,-chosen if side=="L" else chosen)*clavicle.basis
		_set_joint_world_rotation(_bones["DEF-clavicle."+side],result.get_rotation_quaternion().normalized())

func _set_hand_shape(side: String, amount: float) -> void:
	for finger in 5:
		var index: int=_bones["DEF-finger%d.%s"%[finger,side]]
		var rest := get_skeleton().get_bone_rest(index)
		get_skeleton().set_bone_pose_position(index,rest.origin);get_skeleton().set_bone_pose_scale(index,Vector3.ONE)
		get_skeleton().set_bone_pose_rotation(index,(rest.basis.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,.52*amount)).normalized())

func _observed_hand_closure(side: String) -> float:
	var amount := 0.0
	for finger in range(1,5):
		var index: int=_bones["DEF-finger%d.%s"%[finger,side]]
		var rest := get_skeleton().get_bone_rest(index).basis.get_rotation_quaternion()
		amount+=rest.angle_to(get_skeleton().get_bone_pose_rotation(index))/.52*.25
	return clampf(amount,0,1)

func _placement_support_error() -> float:
	var item: Dictionary=_h_request.get("object",{})
	if not item.get("world") is Transform3D or not item.get("support_local") is Vector3 or not _h_request.get("support_point") is Vector3:return INF
	return (item.world*item.support_local).distance_to(_h_request.support_point)

func snapshot() -> Dictionary:
	return {"version":HOUSEHOLD_FORMAT,"target":_contract.get("target",""),"enabled":_h_enabled,"request":_encode(_h_request),"serial":_h_serial,"applied":_h_applied,"sample":_h_sample,
		"action":_h_action,"phase":_h_phase,"progress":_h_progress,"entry":_encode(_h_entry),"entry_palms":_encode(_h_entry_palms),"home":_encode(_h_home),"feet":_encode(_h_feet),
		"last":_encode(_h_last),"rendered":_encode(_h_rendered),"rendered_world":_encode(_h_rendered_world),"had_grasp":_h_had_grasp,"grasp_item":_h_grasp_item,
		"grasped_objects":_h_grasped_objects.duplicate(true),"phase_item":_h_phase_item}

func can_restore(data: Variant) -> bool:return not _checked_household_restore(data).is_empty()

func restore(data: Variant) -> bool:
	var value := _checked_household_restore(data)
	if value.is_empty():return false
	_h_enabled=value.enabled;_h_request=value.request;_h_serial=int(value.serial);_h_applied=int(value.applied);_h_sample=-1
	_h_action=value.action;_h_phase=value.phase;_h_progress=float(value.progress);_h_entry=value.entry;_h_entry_palms=value.entry_palms;_h_home=value.home;_h_feet=value.feet
	_h_last=value.last;_h_rendered=value.rendered;_h_rendered_world=value.rendered_world;_h_had_grasp=value.had_grasp;_h_grasp_item=value.grasp_item;_h_observed.clear()
	_h_grasped_objects=value.grasped_objects.duplicate(true);_h_phase_item=value.phase_item
	return true

func _checked_household_restore(data: Variant) -> Dictionary:
	if not _configured or not data is Dictionary or data.size()!=21 or data.get("version")!=HOUSEHOLD_FORMAT or data.get("target")!=_contract.get("target","") or not data.get("enabled") is bool or not data.get("had_grasp") is bool or not data.get("grasp_item") is String or not data.get("phase_item") is String or not data.get("grasped_objects") is Dictionary or not _finite_tree(data):return {}
	for key in ["version","target","enabled","request","serial","applied","sample","action","phase","progress","entry","entry_palms","home","feet","last","rendered","rendered_world","had_grasp","grasp_item","grasped_objects","phase_item"]:
		if not data.has(key):return {}
	for key in ["serial","applied","sample"]:
		if not _finite_number(data.get(key)) or int(data[key])!=data[key]:return {}
	if data.serial<0 or data.applied< -1 or data.applied>data.serial or data.sample< -1 or data.sample>data.serial:return {}
	if data.had_grasp and data.grasp_item.is_empty():return {}
	if data.grasped_objects.size()>2 or bool(data.had_grasp)!=(not data.grasped_objects.is_empty()) or data.phase_item.length()>128:return {}
	if not data.grasp_item.is_empty() and not data.grasped_objects.has(data.grasp_item):return {}
	var claimed: Array=[]
	for id in data.grasped_objects:
		if not id is String or id.is_empty() or id.length()>128 or not data.grasped_objects[id] is Array or data.grasped_objects[id].is_empty():return {}
		var ordered: Array=[]
		for side in SIDES:
			if side in data.grasped_objects[id]:ordered.append(side)
		if ordered!=data.grasped_objects[id]:return {}
		for side in data.grasped_objects[id]:
			if side not in SIDES or side in claimed:return {}
			claimed.append(side)
	if data.get("action") not in ACTIONS+[""] or data.get("phase") not in ACTION_PHASES+[""] or not _finite_number(data.get("progress")) or data.progress<0 or data.progress>1:return {}
	var value: Variant=_decode(data)
	if not value is Dictionary or not value.request is Dictionary or (value.enabled and not _valid_household_request(value.request)):return {}
	for key in ["entry","last","rendered"]:
		if not value[key] is Array or (not value[key].is_empty() and value[key].size()!=_parents.size()):return {}
		for pose in value[key]:
			if not _valid_transform(pose):return {}
	for key in ["entry_palms","home","feet"]:
		if not value[key] is Dictionary:return {}
		if not value.entry.is_empty() and (not value[key].has("L") or not value[key].has("R")):return {}
		for side in value[key]:
			if side not in SIDES or not _valid_transform(value[key][side]):return {}
	if not _valid_transform(value.rendered_world):return {}
	return value

static func _valid_household_request(value: Dictionary) -> bool:
	if value.has("reach_clearance_y") and (not _finite_number(value.reach_clearance_y) or absf(value.reach_clearance_y)>1000):return false
	for key in ["preserve_lower_body","targets_authoritative"]:
		if value.has(key) and not value[key] is bool:return false
	if value.get("action") not in ACTIONS or value.get("phase") not in ACTION_PHASES or not _finite_number(value.get("progress")) or value.progress<0 or value.progress>1:return false
	if not _finite_number(value.get("pose_seconds")) or value.pose_seconds<0 or value.get("posture","stand") not in ["stand","sit","kneel"]:return false
	if not value.get("targets",{}) is Dictionary or not value.get("object",{}) is Dictionary or not value.get("held_objects",{}) is Dictionary:return false
	for side in value.get("targets",{}):
		var target: Variant=value.targets[side]
		if side not in SIDES or not target is Dictionary or not _valid_transform(target.get("palm_transform")):return false
		if not target.get("grip",0.0) is bool and (not _finite_number(target.get("grip",0.0)) or target.get("grip",0.0)<0 or target.get("grip",0.0)>1):return false
	var item: Dictionary=value.get("object",{})
	if item.has("id") and not item.id is String:return false
	if item.has("world") and not _valid_transform(item.world):return false
	if value.action=="transfer" and (not item.get("id") is String or item.id.is_empty() or not _valid_transform(item.get("world"))):return false
	if not item.get("grips",{}) is Dictionary:return false
	for side in item.get("grips",{}):
		if side not in SIDES or not _valid_transform(item.grips[side]):return false
	if not item.get("local_grips",{}) is Dictionary:return false
	for side in item.get("local_grips",{}):
		if side not in SIDES or not _valid_transform(item.local_grips[side]):return false
	for key in ["support_point","mouth_point","gaze_point"]:
		if value.has(key) and (not value[key] is Vector3 or not value[key].is_finite()):return false
	if item.has("support_local") and (not item.support_local is Vector3 or not item.support_local.is_finite()):return false
	if value.has("mouth_palm_transform") and not _valid_transform(value.mouth_palm_transform):return false
	for key in ["source_world","target_world"]:
		if value.has(key) and not _valid_transform(value[key]):return false
	if value.has("source_fraction") and (not _finite_number(value.source_fraction) or value.source_fraction<0 or value.source_fraction>1):return false
	if value.get("held_objects",{}).size()>2:return false
	var occupied: Array=_item_sides(item)
	for id in value.get("held_objects",{}):
		var held: Variant=value.held_objects[id]
		if not id is String or id.is_empty() or id.length()>128 or id==item.get("id") or not held is Dictionary or not _valid_transform(held.get("world")):return false
		if not held.get("local_grips",{}) is Dictionary or not held.get("grips",{}) is Dictionary or _item_sides(held).is_empty():return false
		for field in ["grips","local_grips"]:
			for side in held.get(field,{}):
				if side not in SIDES or not _valid_transform(held[field][side]):return false
		for side in _item_sides(held):
			if side in occupied:return false
			occupied.append(side)
			if not _valid_transform(held.get("grips",{}).get(side,held.world*held.get("local_grips",{}).get(side,Transform3D.IDENTITY))):return false
	return true
