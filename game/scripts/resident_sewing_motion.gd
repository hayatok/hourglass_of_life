class_name ResidentSewingMotion
extends RefCounted

# Presentation reads a saved SewingWork pose. It never claims a tool, consumes
# cloth, advances a seam, or applies a result. The object view uses the same
# transforms as these hand targets, with real prop contact markers as inputs.
const WORKPIECE_PATH := "res://game/scenes/props/sewing_workpiece.tscn"
const SCISSORS_PATH := "res://game/scenes/props/sewing_scissors.tscn"
const NEEDLE_PATH := "res://game/scenes/props/sewing_needle.tscn"
const NEEDLE_RADIUS := .002
const CARRY_OFFSET := Vector3(0, 1.0, .30)
const OPEN_FINGERS := [.05, .08, .08, .08, .06]
const CLOTH_FINGERS := [.30, .36, .40, .42, .36]
const TOOL_FINGERS := [.64, .68, .62, .58, .48]
const NEEDLE_FINGERS := [.82, .80, .28, .24, .20]

static var _asset_contacts: Dictionary = {}
var _phase_token := ""
var _entry_hands: Dictionary = {}
var _entry_body := Transform3D.IDENTITY
var _scissors_grips: Dictionary = {}
var _scissors_skeleton_id := 0

func update(contacts: ResidentContacts, p: Dictionary, activity: Dictionary, pose: Dictionary, _delta: float, helper: RefCounted) -> Dictionary:
	if not is_instance_valid(contacts) or not is_instance_valid(contacts.skeleton): return {}
	var phase: String = pose.get("phase", "")
	var tool_phase: String = pose.get("tool_phase", "operate")
	var role: String = pose.get("role", "teacher")
	var progress := clampf(float(pose.get("phase_progress", 0.0)), 0, 1)
	var tool_progress := clampf(float(pose.get("tool_progress", progress)), 0, 1)
	var moving: bool = p.get("moving", false)
	var current: Vector3 = p.get("position", contacts.avatar.global_position)
	var item: Vector3 = pose.get("object_position", pose.get("target_position", current))
	var item_basis := Basis(Vector3.UP, float(pose.get("object_yaw", 0.0)))
	var item_frame := Transform3D(item_basis, item)
	var holder: String = pose.get("holder", "")
	if holder == str(p.get("id", "")):
		item_frame.origin += contacts.avatar.global_position - current
		if moving and phase in ["carry_to_table", "carry_to_store"]:
			var logical_yaw: float = pose.get("carry_yaw", contacts.avatar.visual.rotation.y)
			var displayed_yaw: float = contacts.avatar.visual.global_basis.get_euler().y
			item_frame.origin += Basis(Vector3.UP, displayed_yaw) * CARRY_OFFSET - Basis(Vector3.UP, logical_yaw) * CARRY_OFFSET
			item_frame.basis = Basis(Vector3.UP, float(pose.get("object_yaw", 0.0)) + wrapf(displayed_yaw - logical_yaw, -PI, PI))
	var heading := _heading(current, item_frame.origin, float(activity.get("yaw", pose.get("carry_yaw", PI))))
	var result := {"profile":"sewing", "phase":phase, "tool_phase":tool_phase, "role":role,
		"phase_progress":progress, "tool_progress":tool_progress,
		"clip":"walk" if moving else "idle", "grip_left":0.0, "grip_right":0.0,
		"fingers_left":OPEN_FINGERS.duplicate(), "fingers_right":OPEN_FINGERS.duplicate(),
		"gaze":item_frame.origin + Vector3.UP * .06, "lean":Vector3.ZERO,
		"surface_y":float(pose.get("target_position", item).y),
		"object_id":str(pose.get("object_id", "")), "object_transform":item_frame,
		"object_transforms":{}, "tool_visuals":{}, "prop_contact":false}
	var assets := _contacts()
	result.contact_data_source = assets.source
	if holder == str(p.get("id", "")) and not result.object_id.is_empty(): result.object_transforms[result.object_id] = item_frame
	var token := "%s:%s:%s:%s:%s" % [pose.get("id", ""), phase, tool_phase, role, contacts.skeleton.get_instance_id()]
	if token != _phase_token:
		_phase_token = token
		_entry_body = contacts.avatar.visual.global_transform
		_entry_hands.clear()
		for side in ["L", "R"]:
			var actual: Variant = contacts.observed.get("hand_pose" + side)
			_entry_hands[side] = actual if actual is Transform3D else helper.call("_current_hand", contacts, side)
	var tools: Dictionary = pose.get("tools", {})
	if phase in ["completed", "interrupted"]: return result
	if role != "maker": return _watch(contacts, p, pose, result, helper, heading)
	if phase == "to_source": return result
	if phase in ["cut", "sew"] and not moving:
		result.body_yaw = heading
		result.clip = "work"
		result.lean = Vector3(.54 if phase == "cut" else _reach_pitch(item_frame.origin, contacts.avatar.global_position), 0, 0)
		return _operate(contacts, p, pose, result, helper, assets, item_frame, tools, heading)
	if phase not in ["take", "carry_to_table", "place", "lift_show", "show", "lower", "take_store", "carry_to_store", "store"]:
		return result
	var stage: String = pose.get("item_stage", "fabric")
	var local: Dictionary = assets.stages.get(stage, assets.stages.fabric)
	result.palm_left = item_frame * local.grip_left
	result.palm_right = item_frame * local.grip_right
	result.palm_basis_left = item_frame.basis * _side_basis(-1)
	result.palm_basis_right = item_frame.basis * _side_basis(1)
	result.grip_left = .48;result.grip_right = .48
	result.fingers_left = CLOTH_FINGERS.duplicate();result.fingers_right = CLOTH_FINGERS.duplicate()
	result.prop_contact = true
	result.operation = "carry_workpiece"
	if not moving:
		result.body_yaw = float(pose.get("carry_yaw", heading)) if phase in ["show", "lift_show"] else heading
		result.lean = Vector3(_reach_pitch(item_frame.origin, contacts.avatar.global_position), 0, 0)
	if phase in ["take", "lift_show", "take_store"]:
		var reach := _ease(clampf(progress / .30, 0, 1))
		var close := _ease(clampf((progress - .16) / .14, 0, 1))
		result = helper.call("_with_wrists", contacts, result)
		for side in ["L", "R"]:
			var word := "left" if side == "L" else "right"
			var frame_delta: Transform3D = contacts.avatar.visual.global_transform * _entry_body.affine_inverse()
			var entry: Transform3D = frame_delta * _entry_hands[side]
			entry.basis = entry.basis.orthonormalized()
			_record_wrist(contacts, result, side, entry.interpolate_with(result[word], reach), helper)
			result["grip_" + word] *= close
			result["fingers_" + word] = _finger_blend(OPEN_FINGERS, CLOTH_FINGERS, close)
		result.reach_weight_sewing = reach;result.grasp_weight = close
		result.operation = "take_workpiece"
		return _elbows(contacts, result)
	if phase in ["place", "lower", "store"]:
		var release := clampf((progress - .75) / .25, 0, 1)
		var opening := _ease(clampf(release / .35, 0, 1))
		var clearing := _ease(clampf(release / .25, 0, 1))
		var withdraw := _ease(clampf((release - .20) / .80, 0, 1))
		for setting in [["L", "left", -1.0], ["R", "right", 1.0]]:
			var side: String = setting[0];var word: String = setting[1]
			var home: Transform3D = helper.call("_play_empty_hand_home", contacts, side)
			var clear: Vector3 = result["palm_" + word] + item_frame.basis * Vector3(float(setting[2]) * .010, .018, .008) * clearing
			result["palm_" + word] = clear.lerp(home.origin, withdraw)
			var basis: Basis = result["palm_basis_" + word]
			result["palm_basis_" + word] = basis.slerp(home.basis, withdraw)
			result["grip_" + word] *= 1.0 - opening
			result["fingers_" + word] = _finger_blend(CLOTH_FINGERS, OPEN_FINGERS, opening)
		result.release_weight = opening;result.withdraw_weight = withdraw
		result.operation = "place_workpiece"
	elif phase == "show":
		result.gaze = item_frame * Vector3(0, .18, .02)
		result.lean = Vector3(.035, 0, 0)
		result.operation = "show_finished_workpiece"
	return _elbows(contacts, helper.call("_with_wrists", contacts, result))

func _operate(contacts: ResidentContacts, p: Dictionary, pose: Dictionary, result: Dictionary, helper: RefCounted, assets: Dictionary, item_frame: Transform3D, tools: Dictionary, heading: float) -> Dictionary:
	var phase: String = result.phase
	var tool_phase: String = result.tool_phase
	var progress: float = result.tool_progress
	var stage: String = pose.get("item_stage", "fabric")
	var side_sign := -1.0 if (item_frame.affine_inverse() * p.position).x < 0 else 1.0
	var support_key := "support_left" if side_sign < 0 else "support_right"
	var stage_contacts: Dictionary = assets.stages.get(stage, {})
	var surface_available: bool = stage_contacts.get(support_key) is Vector3
	var surface: Vector3 = stage_contacts.get(support_key, Vector3(side_sign * .075, 0, .025))
	var support := surface + Vector3.UP * .012
	var support_weight := 1.0
	var on_support_surface := true
	result.support_mode = "brace_actual_surface"
	if phase == "sew" and stage == "cut":
		# Prepare the free hand for the raised folded seam while the needle is
		# being fetched. This is a transition, not contact with a future mesh.
		var future: Variant = assets.stages.get("sewing", {}).get(support_key)
		if future is Vector3:
			var prepare := _ease(clampf((progress - .40) / .60, 0, 1)) if tool_phase == "reach" else 1.0
			support = surface.lerp(future, prepare) + Vector3.UP * .012
			if prepare > 0:
				support_weight = 0.0;on_support_surface = false;result.support_mode = "prepare_folded_seam"
	if phase == "sew" and stage == "sewing" and tool_phase == "operate":
		# Clear the hand before the horizontal sewn body becomes an upright
		# pouch. It then releases during the tool return instead of jumping to
		# the taller product's top surface or passing through that new body.
		var clear := _ease(clampf((progress - .85) / .15, 0, 1))
		support += Vector3.UP * .10 * clear
		support_weight = 1.0 - clear
		if clear > 0: on_support_surface = false;result.support_mode = "clear_finished_shape"
	var facing := Basis(Vector3.UP, heading)
	result.palm_left = item_frame * support
	result.palm_basis_left = facing * Basis(Vector3.RIGHT, PI / 2)
	result.fingers_left = _finger_blend(OPEN_FINGERS, [.10, .15, .18, .18, .15], support_weight)
	result.grip_left = .18 * support_weight
	result.support_surface = item_frame * surface
	result.support_palm_offset = .012
	result.support_palm_target = item_frame * (surface + Vector3.UP * .012)
	result.support_contact_available = surface_available
	result.support_engaged = surface_available and on_support_surface and stage != "finished" and tool_phase != "reach"
	var home: Transform3D = helper.call("_play_empty_hand_home", contacts, "R")
	result.palm_right = home.origin;result.palm_basis_right = home.basis
	var key := "scissors" if phase == "cut" else "needle"
	var tool: Dictionary = tools.get(key, {})
	if tool.is_empty() or not tool.get("position") is Vector3:
		result.support_engaged = false
		result.prop_contact = false;result.operation = "waiting_for_real_tool"
		return _elbows(contacts, helper.call("_with_wrists", contacts, result))
	var tool_id: String = tool.get("id", "")
	var base := Transform3D(Basis(Vector3.UP, float(tool.get("yaw", 0.0))) * Basis(Vector3.RIGHT, float(tool.get("pitch", 0.0))), tool.position)
	var frame := base
	var held: bool = tool.get("holder", "") == p.id
	var open := .15
	if tool_phase == "operate" and held:
		var cycles := 5.0 if phase == "cut" else 8.0
		var cycle := TAU * progress * cycles
		if phase == "cut":
			frame.origin += item_frame.basis * Vector3(.085 * sin(TAU * progress), .003 * pow(maxf(0, sin(cycle)), 2), .006 * sin(cycle))
			frame.basis *= Basis(Vector3.UP, .035 * sin(cycle))
			open = .15 + .65 * (.5 - .5 * cos(cycle))
		else:
			frame.origin += item_frame.basis * Vector3(.008 * sin(cycle), .035 * (.5 - .5 * cos(cycle)), .016 * sin(PI * progress))
	if tool_phase == "reach": open = .15 * _ease(clampf((progress - .75) / .25, 0, 1)) if held else 0.0
	elif tool_phase == "return": open = .15 * (1.0 - _ease(clampf(progress / .75, 0, 1))) if held else 0.0
	if held: result.object_transforms[tool_id] = frame
	if phase == "cut":
		# A fixed set of actual scissors-opening samples bounds the pad solve
		# cache and keeps the rendered loops and contact points in agreement.
		open = float(roundi(open * 16.0)) / 16.0
		result.tool_visuals[tool_id] = {"open":open}
	if phase == "sew" and tool_phase == "operate" and held:
		var seam: Vector3 = stage_contacts.get("needle_point", Vector3(.070, .049, .010))
		var displacement := frame.origin - base.origin
		result.thread_anchor = item_frame * seam + Vector3(displacement.x, 0, displacement.z)
		result.thread_needle_eye = frame * assets.tools.needle.get("eye", Vector3(0, .041, 0))
		result.thread_active = true
	else: result.thread_active = false
	var tool_local: Dictionary = assets.tools[key]
	var grip_local: Vector3 = tool_local.grip_center
	var grip_point: Vector3 = frame * grip_local
	result.palm_right = grip_point
	result.palm_basis_right = frame.basis * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, PI / 2) if phase == "cut" else facing * Basis(Vector3.RIGHT, PI / 2)
	result.fingers_right = TOOL_FINGERS.duplicate() if phase == "cut" else NEEDLE_FINGERS.duplicate()
	result.grip_right = .68
	result.prop_contact = held
	result.operation = "cut_real_fabric" if phase == "cut" else "stitch_real_workpiece"
	result.active_tool_id = tool_id
	result.tool_grip_local = grip_local;result.tool_grip_world = grip_point
	result.tool_transform = frame
	if tool_local.has("tip"): result.tool_tip_world = frame * tool_local.tip
	result = helper.call("_with_wrists", contacts, result)
	if phase == "cut":
		_scissors_pinch(contacts, result, assets.tools.scissors, frame, open, helper)
	if phase == "sew":
		var grip: Dictionary = helper.call("_sewing_grip_solution", contacts, "R", NEEDLE_RADIUS)
		result.finger_pad_supported = grip.get("supported", false)
		result.finger_pad_reason = grip.get("reason", "")
		if grip.get("supported", false): _needle_pinch(contacts, result, grip, grip_point, facing, helper)
		else:
			# Do not silently substitute a hand-base point for missing pad data.
			result.operation = "unsupported_needle_grip"
	_prepare_support_stance(contacts, result, helper, heading)
	var reach := _ease(progress) if tool_phase == "reach" else 1.0
	var close := _ease(clampf((progress - .55) / .45, 0, 1)) if tool_phase == "reach" else 1.0
	if tool_phase == "reach":
		var delta_frame: Transform3D = contacts.avatar.visual.global_transform * _entry_body.affine_inverse()
		for side in ["L", "R"]:
			var word := "left" if side == "L" else "right"
			var entry: Transform3D = delta_frame * _entry_hands[side]
			entry.basis = entry.basis.orthonormalized()
			_record_wrist(contacts, result, side, entry.interpolate_with(result[word], reach), helper)
		result.fingers_right = _finger_blend(OPEN_FINGERS, result.fingers_right, close)
		_blend_explicit_fingers(result, "R", close)
		if result.has("pinch_local_right"): _record_wrist(contacts, result, "R", result.right, helper, result.pinch_local_right)
		result.reach_weight_sewing = reach;result.grasp_weight = close
	elif tool_phase == "return":
		var release := clampf((progress - .75) / .25, 0, 1)
		var opening := _ease(clampf(release / .35, 0, 1))
		var withdraw := _ease(clampf((release - .20) / .80, 0, 1))
		var offsets: Dictionary = helper.get("_palm_offsets")
		var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
		var resting := Transform3D(home.basis, home.origin - home.basis * (offsets.R * scale))
		var wrist: Transform3D = result.right
		wrist.origin += Vector3.UP * .015 * _ease(clampf(release / .25, 0, 1))
		_record_wrist(contacts, result, "R", wrist.interpolate_with(resting, withdraw), helper)
		result.fingers_right = _finger_blend(result.fingers_right, OPEN_FINGERS, opening)
		_blend_explicit_fingers(result, "R", 1.0 - opening)
		if result.has("pinch_local_right"): _record_wrist(contacts, result, "R", result.right, helper, result.pinch_local_right)
		result.release_weight = opening;result.withdraw_weight = withdraw
	if phase == "sew" and stage == "finished" and tool_phase == "return":
		_release_finished_support(contacts, result, helper, progress)
	return _elbows(contacts, result)

func _prepare_support_stance(contacts: ResidentContacts, result: Dictionary, helper: RefCounted, heading: float) -> void:
	var skeleton := contacts.skeleton
	var body: Transform3D = contacts.avatar.visual.global_transform
	var facing := Basis(Vector3.UP, heading)
	var target_body := Transform3D(facing * Basis.from_scale(body.basis.get_scale()), body.origin)
	var to_body: Transform3D = body.affine_inverse() * skeleton.global_transform
	var spine_a := skeleton.find_bone("DEF-spine_01")
	var spine_b := skeleton.find_bone("DEF-spine_02")
	var pitch := maxf(.54, float(result.lean.x))
	if spine_a >= 0 and spine_b >= 0:
		var pivot_a: Vector3 = target_body * (to_body * skeleton.get_bone_global_rest(spine_a).origin)
		var pivot_b: Vector3 = target_body * (to_body * skeleton.get_bone_global_rest(spine_b).origin)
		# Predict the two real spine rotations used by ResidentSocialMotion.
		# Find a comfortable reach with the measured arm lengths; never shorten
		# the contact or lengthen an arm to accommodate the displayed body.
		for candidate in range(21):
			var proposed := minf(.94, pitch + .02 * candidate)
			var lower := Basis(facing.x, proposed * .45)
			var upper := Basis(facing.x, proposed * .55)
			var raised_pivot := pivot_a + lower * (pivot_b - pivot_a)
			var reachable := true
			for setting in [["L", "left"], ["R", "right"]]:
				var side: String = setting[0];var word: String = setting[1]
				var bone := skeleton.find_bone("DEF-upper_arm." + side)
				if bone < 0 or not result.has("arm_length_" + word): continue
				var shoulder: Vector3 = target_body * (to_body * skeleton.get_bone_global_rest(bone).origin)
				shoulder = pivot_a + lower * (shoulder - pivot_a)
				shoulder = raised_pivot + upper * (shoulder - raised_pivot)
				var wrist: Transform3D = result[word]
				if shoulder.distance_to(wrist.origin) > float(result["arm_length_" + word]) * .94: reachable = false
			result.support_stance_reachable = reachable
			result.support_stance_pitch = proposed
			if reachable or proposed >= .94:
				pitch = proposed;break
	result.lean = Vector3(pitch, 0, 0)
	# A rebuilt avatar starts at its idle orientation even when the saved
	# operation is halfway through. Approach from that actual entry hand while
	# the body turns and bends; this interval does not brace a future surface.
	var yaw_error := absf(wrapf(body.basis.orthonormalized().get_euler().y - heading, -PI, PI))
	var lean_error := absf(contacts.social_motion.action_lean.x - pitch)
	var stance := minf(_ease(clampf((.65 - yaw_error) / .60, 0, 1)), _ease(clampf((.20 - lean_error) / .18, 0, 1)))
	result.support_stance_weight = stance
	if stance < 1.0:
		var entry: Transform3D = body * _entry_body.affine_inverse() * _entry_hands.L
		entry.basis = entry.basis.orthonormalized()
		var goal: Transform3D = result.left
		var wrist := entry.interpolate_with(goal, stance)
		_record_wrist(contacts, result, "L", wrist, helper)
		result.palm_basis_left = wrist.basis
		result.support_engaged = false
		result.support_mode = "align_body_and_reach_surface"

func _release_finished_support(contacts: ResidentContacts, result: Dictionary, helper: RefCounted, progress: float) -> void:
	var body: Transform3D = contacts.avatar.visual.global_transform
	var entry_frame: Transform3D = body * _entry_body.affine_inverse()
	var entry: Transform3D = entry_frame * _entry_hands.L
	entry.basis = entry.basis.orthonormalized()
	var basis := body.basis.orthonormalized() * Basis(Vector3.FORWARD, PI)
	var palm: Vector3 = body * Vector3(.16, contacts.rest_shoulder - .44, .04)
	var offsets: Dictionary = helper.get("_palm_offsets")
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	var resting := Transform3D(basis, palm - basis * (offsets.L * scale))
	var withdraw := _ease(clampf(progress / .85, 0, 1))
	var wrist := entry.interpolate_with(resting, withdraw)
	wrist.origin += Vector3.UP * .022 * sin(PI * withdraw)
	_record_wrist(contacts, result, "L", wrist, helper)
	result.grip_left = 0.0;result.fingers_left = OPEN_FINGERS.duplicate()
	result.support_mode = "release_finished_workpiece"
	result.support_engaged = false

func _scissors_pinch(contacts: ResidentContacts, result: Dictionary, contact_data: Dictionary, frame: Transform3D, opening: float, helper: RefCounted) -> void:
	var samples: Array = contact_data.get("samples", [])
	if samples.size() != 17:
		result.finger_pad_supported = false;result.finger_pad_reason = "Actual scissors-loop contact samples are unavailable."
		result.operation = "unsupported_scissors_grip"
		return
	var sample: Dictionary = samples[clampi(roundi(opening * 16), 0, 16)]
	var thumb: Vector3 = frame * sample.thumb_contact
	var index: Vector3 = frame * sample.finger_contact
	var local_axis: Vector3 = sample.finger_contact - sample.thumb_contact
	# Prop frames are rigid metre-space transforms. Read the radius from the
	# saved local sample so world-coordinate rounding cannot grow the cache.
	var radius := local_axis.length() * .5
	# Only the actual pad geometry/rest is needed here. A disc-grip failure at
	# this opening's radius must not prevent the scissors-specific search.
	var template: Dictionary = helper.call("_sewing_grip_solution", contacts, "R", NEEDLE_RADIUS)
	if template.get("pad_mode", "") == "index_side":
		# Both loop surfaces are real and symmetric. This anatomical grasp puts
		# the index's measured outward side against the other inner loop, rather
		# than making the scissors pass through the back of the finger.
		var old_thumb := thumb;thumb = index;index = old_thumb;local_axis = -local_axis
		result.scissors_pad_assignment = {"thumb":"finger_contact", "index":"thumb_contact"}
	var grip := _scissors_solution(contacts, template, radius, local_axis)
	result.finger_pad_supported = grip.get("supported", false)
	result.finger_pad_reason = grip.get("reason", "")
	if not grip.get("supported", false):
		result.operation = "unsupported_scissors_grip"
		return
	var basis: Basis = frame.basis * grip.basis_local
	result.tool_wrist_forward = grip.wrist_forward
	if grip.has("wrist_offset_tool_local"): result.tool_wrist_offset_local = grip.wrist_offset_tool_local
	var point := (thumb + index) * .5
	result.tool_grip_local = (sample.thumb_contact + sample.finger_contact) * .5
	result.tool_grip_world = point
	result.tool_contact_mode = "actual_inner_loop_finger_pads"
	_pad_grip(contacts, result, grip, point, basis, thumb, index, helper)

func _scissors_solution(contacts: ResidentContacts, template: Dictionary, radius: float, contact_axis: Vector3) -> Dictionary:
	if not template.get("supported", false): return template
	var skeleton_id := contacts.skeleton.get_instance_id()
	if skeleton_id != _scissors_skeleton_id:
		_scissors_skeleton_id = skeleton_id;_scissors_grips.clear()
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	var cache_key := "%s:%s:%s" % [radius, scale, contact_axis.normalized()]
	if _scissors_grips.has(cache_key): return _scissors_grips[cache_key]
	if template.get("pad_mode", "") == "index_side":
		var side_grip := _scissors_extended_solution(template, radius, contact_axis, scale)
		_scissors_grips[cache_key] = side_grip
		return side_grip
	var pads: Dictionary = template.pads
	var rest: Array = template.rest
	var initial: Array = [Quaternion(Vector3.RIGHT, NEEDLE_FINGERS[0] * .55), Quaternion(Vector3.RIGHT, NEEDLE_FINGERS[1] * .85)]
	var old_thumb: Vector3 = rest[0] * (initial[0] * pads.thumb)
	var old_index: Vector3 = rest[1] * (initial[1] * pads.index)
	var old_mid := (old_thumb + old_index) * .5
	var thumb_length: float = pads.thumb.length()
	var index_length: float = pads.index.length()
	var nominal := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, PI / 2)
	var desired_axis := contact_axis;desired_axis.y = 0
	desired_axis = desired_axis.normalized()
	var best: Dictionary = {}
	var best_score := INF
	# A disc grip can rotate freely. Scissor handles cannot: the wrist has to
	# remain behind the fingers, with fingers towards the blades. Choose from
	# the same bounded distal-pad sphere intersections with this extra posture
	# requirement, rather than turning an otherwise cheap grip backwards.
	for option in 72:
		var angle := TAU * float(option % 24) / 24.0
		var elevation: float = [-.5, 0.0, .5][int(option / 24)]
		var horizontal := sqrt(1.0 - elevation * elevation)
		var axis := Vector3(cos(angle) * horizontal, sin(angle) * horizontal, elevation)
		var scaled_axis := (axis * scale).normalized()
		var flat_axis := Vector3(axis.x * scale.x, axis.y * scale.y, 0).normalized()
		var correction := Quaternion(scaled_axis, flat_axis)
		var tilt := acos(clampf(scaled_axis.dot(flat_axis), -1, 1))
		var local_radius := radius / maxf(.001, (axis * scale).length())
		var sphere_thumb: Vector3 = rest[0].origin + axis * local_radius
		var sphere_index: Vector3 = rest[1].origin - axis * local_radius
		var line := sphere_index - sphere_thumb
		var distance := line.length()
		if distance < .00001 or distance > thumb_length + index_length or distance < absf(thumb_length - index_length): continue
		line /= distance
		var along := (thumb_length * thumb_length - index_length * index_length + distance * distance) / (2.0 * distance)
		var height := sqrt(maxf(0, thumb_length * thumb_length - along * along))
		var circle := sphere_thumb + line * along
		var radial := old_mid - circle;radial -= line * radial.dot(line)
		if radial.length_squared() < .00000001:
			radial = line.cross(Vector3.FORWARD)
			if radial.length_squared() < .00000001: radial = line.cross(Vector3.RIGHT)
		var center := circle + radial.normalized() * height
		var targets: Array = [center - axis * local_radius, center + axis * local_radius]
		var rotations: Array = [];var corrections: Array = []
		for finger in 2:
			var pad: Vector3 = pads.thumb if finger == 0 else pads.index
			var finger_rest: Transform3D = rest[finger]
			var target: Vector3 = finger_rest.basis.inverse() * (targets[finger] - finger_rest.origin)
			var start: Quaternion = initial[finger]
			var rotation := (Quaternion((start * pad).normalized(), target.normalized()) * start).normalized()
			rotations.append(rotation);corrections.append(start.angle_to(rotation))
		var maximum := maxf(float(corrections[0]), float(corrections[1]))
		if maximum > .85: continue
		var basis := nominal * Basis(correction)
		var current_axis: Vector3 = basis * (axis * scale);current_axis.y = 0
		if current_axis.length_squared() < .000001: continue
		basis = Basis(Vector3.UP, current_axis.normalized().signed_angle_to(desired_axis, Vector3.UP)) * basis
		var forward := basis.y.dot(Vector3.FORWARD)
		if forward < .5 or basis.z.dot(Vector3.DOWN) < .65: continue
		var score := maximum + .10 * (float(corrections[0]) + float(corrections[1])) + .30 * center.distance_to(old_mid) / maxf(thumb_length, index_length) + 2.0 * (1.0 - forward)
		if score < best_score:
			best_score = score
			best = {"supported":true, "center":center, "pads":pads, "rest":rest, "axis":axis,
				"rotations":rotations, "maximum_correction":maximum, "wrist_correction":correction,
				"wrist_tilt":tilt, "basis_local":basis, "wrist_forward":forward}
	if best.is_empty():
		best = _scissors_extended_solution(template, radius, contact_axis, scale, true)
	else:
		for finger in range(2, 5): best.rotations.append(Quaternion(Vector3.RIGHT, float(TOOL_FINGERS[finger]) * .85))
	_scissors_grips[cache_key] = best
	return best

func _scissors_extended_solution(template: Dictionary, radius: float, contact_axis: Vector3, scale: Vector3, dense: bool = false) -> Dictionary:
	var pads: Dictionary = template.pads
	var rest: Array = template.rest
	var initial: Array = [Quaternion(Vector3.RIGHT, NEEDLE_FINGERS[0] * .55), Quaternion(Vector3.RIGHT, NEEDLE_FINGERS[1] * .85)]
	var old_mid: Vector3 = ((rest[0] * (initial[0] * pads.thumb)) + (rest[1] * (initial[1] * pads.index))) * .5
	var thumb_length: float = pads.thumb.length();var index_length: float = pads.index.length()
	var side_contact: bool = template.get("pad_mode", "") == "index_side"
	var normal_data: Array = template.measurement.index.normal if side_contact else [0, 0, 0]
	var side_normal := Vector3(normal_data[0], normal_data[1], normal_data[2])
	var nominal := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, PI / 2)
	var desired_axis := Vector3(contact_axis.x, 0, contact_axis.z).normalized()
	var best: Dictionary = {};var best_score := INF
	var azimuths := 48 if dense else 24
	var elevations: Array = [-.75, -.5, -.25, 0.0, .25, .5, .75] if dense else [-.5, 0.0, .5]
	var circle_samples := 24 if dense else 12
	for option in azimuths * elevations.size():
		var angle := TAU * float(option % azimuths) / float(azimuths)
		var elevation: float = elevations[int(option / azimuths)]
		var horizontal := sqrt(1.0 - elevation * elevation)
		var axis := Vector3(cos(angle) * horizontal, sin(angle) * horizontal, elevation)
		var scaled_axis := (axis * scale).normalized()
		var flat_axis := Vector3(axis.x * scale.x, axis.y * scale.y, 0).normalized()
		var correction := Quaternion(scaled_axis, flat_axis)
		var local_radius := radius / maxf(.001, (axis * scale).length())
		var sphere_thumb: Vector3 = rest[0].origin + axis * local_radius
		var sphere_index: Vector3 = rest[1].origin - axis * local_radius
		var line := sphere_index - sphere_thumb;var distance := line.length()
		if distance < .00001 or distance > thumb_length + index_length or distance < absf(thumb_length - index_length): continue
		line /= distance
		var along := (thumb_length * thumb_length - index_length * index_length + distance * distance) / (2.0 * distance)
		var height := sqrt(maxf(0, thumb_length * thumb_length - along * along))
		var circle := sphere_thumb + line * along
		var radial := old_mid - circle;radial -= line * radial.dot(line)
		if radial.length_squared() < .00000001:
			radial = line.cross(Vector3.FORWARD)
			if radial.length_squared() < .00000001: radial = line.cross(Vector3.RIGHT)
		radial = radial.normalized()
		var tangent := line.cross(radial).normalized()
		var aligned := nominal * Basis(correction)
		var current_axis: Vector3 = aligned * (axis * scale);current_axis.y = 0
		if current_axis.length_squared() < .000001: continue
		aligned = Basis(Vector3.UP, current_axis.normalized().signed_angle_to(desired_axis, Vector3.UP)) * aligned
		for sample in circle_samples:
			var around := TAU * float(sample) / float(circle_samples)
			var center := circle + (radial * cos(around) + tangent * sin(around)) * height
			var targets: Array = [center - axis * local_radius, center + axis * local_radius]
			var rotations: Array = [];var corrections: Array = []
			for finger in 2:
				var pad: Vector3 = pads.thumb if finger == 0 else pads.index
				var finger_rest: Transform3D = rest[finger]
				var target: Vector3 = finger_rest.basis.inverse() * (targets[finger] - finger_rest.origin)
				var start: Quaternion = initial[finger]
				var rotation := (Quaternion((start * pad).normalized(), target.normalized()) * start).normalized()
				rotations.append(rotation);corrections.append(start.angle_to(rotation))
			var maximum := maxf(float(corrections[0]), float(corrections[1]))
			if maximum > .85: continue
			var actual_normal: Vector3 = rest[1].basis * (rotations[1] * side_normal)
			var normal_alignment := actual_normal.normalized().dot(-axis) if side_contact else 1.0
			if side_contact and normal_alignment < .60: continue
			# Rotate only around the actual two loop contacts. Their positions
			# remain exact while a modest wrist roll puts the wrist behind the
			# handles instead of 9 cm to one side on the older long-finger rigs.
			for turn in range(-4, 5):
				var basis := Basis(desired_axis, float(turn) * PI / 24.0) * aligned
				var forward := basis.y.dot(Vector3.FORWARD)
				if forward < .5 or basis.z.dot(Vector3.DOWN) < .65: continue
				var wrist_offset: Vector3 = -(basis * (center * scale))
				if wrist_offset.y < .005: continue
				var score := maximum + .10 * (float(corrections[0]) + float(corrections[1])) + .30 * center.distance_to(old_mid) / maxf(thumb_length, index_length) + 2.0 * (1.0 - forward) + 40.0 * absf(wrist_offset.x) + 10.0 * maxf(0, .025 - wrist_offset.z)
				if score < best_score:
					best_score = score
					best = {"supported":true, "center":center, "pads":pads, "rest":rest, "axis":axis,
						"rotations":rotations.duplicate(), "maximum_correction":maximum, "wrist_correction":correction,
						"wrist_tilt":acos(clampf(basis.z.dot(Vector3.DOWN), -1, 1)), "basis_local":basis, "wrist_forward":forward,
						"pad_mode":"index_side" if side_contact else "distal", "wrist_offset_tool_local":wrist_offset}
					if side_contact: best.index_normal_alignment = normal_alignment
					if template.has("measurement"): best.measurement = template.measurement
	if best.is_empty():
		if not dense: return _scissors_extended_solution(template, radius, contact_axis, scale, true)
		return {"supported":false, "reason":"No bounded skin grip keeps the wrist above and behind the scissors handles."}
	for finger in range(2, 5): best.rotations.append(Quaternion(Vector3.RIGHT, float(TOOL_FINGERS[finger]) * .85))
	return best

func _needle_pinch(contacts: ResidentContacts, result: Dictionary, grip: Dictionary, point: Vector3, facing: Basis, helper: RefCounted) -> void:
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	var basis := facing * Basis(Vector3.RIGHT, PI / 2) * Basis(grip.wrist_correction)
	var axis: Vector3 = (basis * (grip.axis * scale)).normalized()
	result.tool_contact_mode = "actual_needle_band_finger_pads"
	_pad_grip(contacts, result, grip, point, basis, point - axis * NEEDLE_RADIUS, point + axis * NEEDLE_RADIUS, helper)

func _pad_grip(contacts: ResidentContacts, result: Dictionary, grip: Dictionary, point: Vector3, basis: Basis, thumb: Vector3, index: Vector3, helper: RefCounted) -> void:
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	var wrist := Transform3D(basis, point - basis * (grip.center * scale))
	result.finger_rotations = {"R":grip.rotations.duplicate()}
	result.finger_pad_local_right = grip.pads.duplicate()
	result.finger_contact_rest_right = grip.rest.duplicate()
	result.pinch_source = "measured_sewing_side_mesh_surfaces" if grip.get("pad_mode", "") == "index_side" else "measured_distal_mesh_caps"
	if grip.has("measurement"): result.finger_pad_measurement_right = grip.measurement
	if grip.has("index_normal_alignment"): result.finger_pad_index_normal_alignment = grip.index_normal_alignment
	result.finger_opposition_max_rad = grip.maximum_correction
	result.finger_wrist_tilt_rad = grip.wrist_tilt
	result.finger_pad_target_right = {"thumb":thumb, "index":index}
	_record_wrist(contacts, result, "R", wrist, helper, grip.center)

func _blend_explicit_fingers(result: Dictionary, side: String, weight: float) -> void:
	if not result.get("finger_rotations", {}).has(side): return
	var rotations: Array = result.finger_rotations[side]
	for finger in rotations.size():
		var open := Quaternion(Vector3.RIGHT, float(OPEN_FINGERS[finger]) * (.55 if finger == 0 else .85))
		rotations[finger] = open.slerp(rotations[finger], weight)
	if result.has("finger_contact_rest_right") and side == "R":
		var rest: Array = result.finger_contact_rest_right
		var pads: Dictionary = result.finger_pad_local_right
		var thumb: Vector3 = rest[0] * (rotations[0] * pads.thumb)
		var index: Vector3 = rest[1] * (rotations[1] * pads.index)
		result.pinch_local_right = (thumb + index) * .5

func _record_wrist(contacts: ResidentContacts, result: Dictionary, side: String, wrist: Transform3D, helper: RefCounted, pinch_local: Vector3 = Vector3.ZERO) -> void:
	var word := "left" if side == "L" else "right"
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	var offsets: Dictionary = helper.get("_palm_offsets")
	result[word] = wrist
	result["palm_local_" + word] = offsets[side]
	result["palm_" + word] = wrist * (offsets[side] * scale)
	if pinch_local != Vector3.ZERO:
		result["pinch_local_" + word] = pinch_local
		result["pinch_" + word] = wrist * (pinch_local * scale)
	var upper := contacts.skeleton.find_bone("DEF-upper_arm." + side)
	var fore := contacts.skeleton.find_bone("DEF-forearm." + side)
	var hand := contacts.skeleton.find_bone("DEF-hand." + side)
	if upper >= 0 and fore >= 0 and hand >= 0:
		var shoulder: Vector3 = contacts.skeleton.get_bone_global_rest(upper).origin
		var elbow: Vector3 = contacts.skeleton.get_bone_global_rest(fore).origin
		var end: Vector3 = contacts.skeleton.get_bone_global_rest(hand).origin
		result["arm_length_" + word] = ((elbow - shoulder) * scale).length() + ((end - elbow) * scale).length()
		result["shoulder_distance_" + word] = contacts.point("upper_arm." + side).distance_to(wrist.origin)

func _watch(contacts: ResidentContacts, p: Dictionary, _pose: Dictionary, result: Dictionary, helper: RefCounted, heading: float) -> Dictionary:
	if p.get("moving", false): return result
	result.body_yaw = heading
	result.conversation_role = "listener"
	# Leave both arms on the authored idle pose while watching. A home-hand
	# IK target at every frame would lock the elbows wide instead of allowing
	# the resident to relax, breathe and acknowledge the maker naturally.
	if result.phase in ["cut", "sew"]:
		result.operation = "watch_sewing"
		result.lean = Vector3(.035, 0, 0)
		var progress: float = result.tool_progress
		if result.tool_phase == "operate" and progress > .08 and progress < .22:
			var gesture := sin(PI * clampf((progress - .08) / .14, 0, 1))
			var body: Transform3D = contacts.avatar.visual.global_transform
			var entry_frame: Transform3D = body * _entry_body.affine_inverse()
			var wrist: Transform3D = entry_frame * _entry_hands.R
			wrist.basis = wrist.basis.orthonormalized()
			wrist.origin += body.basis.orthonormalized() * Vector3(-.012, .065, .060) * gesture
			_record_wrist(contacts, result, "R", wrist, helper)
			result.elbow_right = body * Vector3(-.30, contacts.rest_shoulder - .33, .12)
			result.operation = "brief_instruction"
			if gesture > .1: result.conversation_role = "speaker"
	elif result.phase == "show":
		result.operation = "look_at_finished_workpiece"
		result.lean = Vector3(.035 * sin(PI * result.phase_progress), 0, 0)
	return result

func _elbows(contacts: ResidentContacts, result: Dictionary) -> Dictionary:
	var body: Transform3D = contacts.avatar.visual.global_transform
	result.elbow_left = body * Vector3(.24, contacts.rest_shoulder - .26, .10)
	result.elbow_right = body * Vector3(-.24, contacts.rest_shoulder - .26, .10)
	return result

static func _heading(origin: Vector3, target: Vector3, fallback: float) -> float:
	var toward := target - origin;toward.y = 0
	return atan2(toward.x, toward.z) if toward.length_squared() > .0001 else fallback

static func _reach_pitch(target: Vector3, origin: Vector3) -> float:
	var distance := Vector2(target.x - origin.x, target.z - origin.z).length()
	return lerpf(.08, .48, clampf((distance - .25) / .38, 0, 1))

static func _side_basis(side: float) -> Basis:
	return Basis(Vector3(0, side, 0), Vector3(0, 0, -1), Vector3(-side, 0, 0))

static func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)

static func _finger_blend(a: Array, b: Array, weight: float) -> Array:
	var values: Array = []
	for finger in 5: values.append(lerpf(float(a[finger]), float(b[finger]), weight))
	return values

static func _contacts() -> Dictionary:
	if not _asset_contacts.is_empty(): return _asset_contacts
	var data := {"source":"authored_contact_contract_fallback", "stages":{
		"fabric":{"grip_left":Vector3(-.140, .012, 0), "grip_right":Vector3(.140, .012, 0)},
		"cut":{"grip_left":Vector3(-.140, .003, 0), "grip_right":Vector3(.140, .003, 0)},
		"sewing":{"grip_left":Vector3(-.112, .027, 0), "grip_right":Vector3(.112, .027, 0)},
		"finished":{"grip_left":Vector3(-.108, .101, 0), "grip_right":Vector3(.108, .101, 0)}},
		"tools":{"scissors":{"grip_center":Vector3(0, .008, .055), "tip":Vector3(0, .008, -.055)},
		"needle":{"grip_center":Vector3(0, .029, 0), "tip":Vector3.ZERO, "eye":Vector3(0, .041, 0)}}}
	var complete := true
	if ResourceLoader.exists(WORKPIECE_PATH):
		var piece: Node = load(WORKPIECE_PATH).instantiate()
		if piece.has_method("local_contacts"):
			for stage in data.stages:
				var values: Variant = piece.call("local_contacts", stage)
				if values is Dictionary and values.get("grip_left") is Vector3 and values.get("grip_right") is Vector3:
					data.stages[stage] = values
					if not values.get("support_left") is Vector3 or not values.get("support_right") is Vector3: complete = false
				else: complete = false
		else: complete = false
		piece.free()
	else: complete = false
	for key in ["scissors", "needle"]:
		var path: String = SCISSORS_PATH if key == "scissors" else NEEDLE_PATH
		if not ResourceLoader.exists(path): complete = false;continue
		var tool: Node = load(path).instantiate()
		var grip := tool.find_child("GripCenter", true, false) as Node3D
		var tip := tool.find_child("CutPoint" if key == "scissors" else "TipCenter", true, false) as Node3D
		if is_instance_valid(grip): data.tools[key].grip_center = grip.position
		else: complete = false
		if is_instance_valid(tip): data.tools[key].tip = tip.position
		else: complete = false
		if key == "needle":
			var eye := tool.find_child("EyeCenter", true, false) as Node3D
			if is_instance_valid(eye): data.tools.needle.eye = eye.position
			else: complete = false
		elif tool.has_method("local_contacts") and tool.has_method("set_open"):
			var samples: Array = []
			for step in 17:
				tool.call("set_open", float(step) / 16.0)
				var sample: Dictionary = tool.call("local_contacts")
				if not sample.get("thumb_contact") is Vector3 or not sample.get("finger_contact") is Vector3: complete = false
				samples.append(sample)
			data.tools.scissors.samples = samples
		else: complete = false
		tool.free()
	if complete:
		data.source = "saved_prop_scene_contacts"
		_asset_contacts = data
	return data
