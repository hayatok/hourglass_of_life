class_name ResidentInteractionMotion
extends RefCounted

# Presentation only. These transforms never write positions, phase progress, or
# outcomes back to Sim. The object view and both palms share this bottom-centre
# transform; a wrist target is offset by the measured palm length of each rig.
const CARRY_OFFSET := Vector3(0, .98, .34)
const RADIO_LEFT := Vector3(-.195, .115, 0)
const RADIO_RIGHT := Vector3(.195, .115, 0)
const RADIO_DIAL := Vector3(.112, .08, .112)
const CARRY_FINGERS := [.60, .68, .72, .75, .65]
const OPEN_FINGERS := [.05, .08, .08, .08, .06]
const PLAY_CLOSED_FINGERS := [.82, .80, .48, .50, .46]
const PLAY_PIECE_RADIUS := .018

static var _play_pad_data: Dictionary = {}
static var _play_grip_cache: Dictionary = {}
static var _sewing_side_pad_data: Dictionary = {}
static var _sewing_grip_cache: Dictionary = {}

var object_transform := Transform3D.IDENTITY
var object_active := false
var object_id := ""
var last_result: Dictionary = {}
var sewing_motion := ResidentSewingMotion.new()

var _phase_token := ""
var _entry_hands: Dictionary = {}
var _palm_offsets: Dictionary = {}
var _skeleton_id := 0
var _play_hand_token := ""
var _play_hand := "R"
var _play_phase_token := ""
var _play_entry_hands: Dictionary = {}
var _play_entry_visual := Transform3D.IDENTITY

static func radio_grips() -> Dictionary:
	# Radio front is +Z; during transport it faces the carrier. Consequently the
	# carrier's left hand contacts the radio's negative-X side.
	return {"L": RADIO_LEFT, "R": RADIO_RIGHT}

func update(contacts: ResidentContacts, p: Dictionary, activity: Dictionary, pose: Dictionary, _delta: float) -> Dictionary:
	object_active = false
	object_id = ""
	last_result = {}
	if not is_instance_valid(contacts) or not is_instance_valid(contacts.skeleton):
		_phase_token = ""
		return last_result
	_cache_palms(contacts)
	if pose.get("key", "") == "radio" and pose.get("object_position") is Vector3 and not str(pose.get("object_id", "")).is_empty():
		last_result = _radio(contacts, p, activity, pose)
	elif pose.get("key", "") == "sewing":
		_phase_token = ""
		last_result = sewing_motion.update(contacts,p,activity,pose,_delta,self)
	elif pose.get("key", "") == "four_in_row":
		_phase_token = ""
		last_result = _play(contacts, p, pose)
	else:
		_phase_token = ""
		var working_action: bool = p.get("action", "") in ["work", "hobby", "chores", "joint_work"]
		if working_action and not p.get("moving", false) and activity.get("pose", "") == "work" and activity.get("hand_left") is Vector3 and activity.get("hand_right") is Vector3:
			var profile := activity_profile(str(activity.get("group", "")), activity, contacts.time)
			if not profile.is_empty():
				last_result = _with_wrists(contacts, profile)
	return last_result

func _play(contacts: ResidentContacts, p: Dictionary, pose: Dictionary) -> Dictionary:
	var phase := str(pose.get("phase", ""))
	var role := str(pose.get("role", "observer"))
	var progress := clampf(float(pose.get("phase_progress", 0)), 0, 1)
	var board: Vector3 = pose.get("board_origin", Vector3.ZERO)
	var board_yaw := float(pose.get("board_yaw", 0))
	var facing := Basis(Vector3.UP, board_yaw + PI)
	var result := {"profile": "four_in_row", "phase": phase, "role": role, "phase_progress": progress,
		"clip": "walk" if p.get("moving", false) else "idle", "grip_left": 0.0, "grip_right": 0.0,
		"fingers_left": OPEN_FINGERS.duplicate(), "fingers_right": OPEN_FINGERS.duplicate(),
		"lean": Vector3.ZERO, "grasp_weight": 0.0, "gaze": board + Vector3.UP * .04,
		"surface_y": board.y + .025}
	var selected := int(pose.get("selected_cell", -1))
	var cells: Array = pose.get("cell_centers", [])
	var destination: Vector3 = cells[selected] if selected >= 0 and selected < cells.size() else board
	if selected >= 0:
		result.gaze = destination + Vector3.UP * .025
	object_id = str(pose.get("object_id", ""))
	object_active = not object_id.is_empty() and pose.get("object_position") is Vector3
	if object_active:
		object_transform = Transform3D(Basis(Vector3.UP, float(pose.get("object_yaw", 0))), pose.object_position)
		# Only the real holder may correct for the displayed root's interpolation.
		# ObjectView consumes exactly this transform, as does the pinch target.
		if str(pose.get("holder", "")) == str(p.get("id", "")):
			var logical: Vector3 = p.get("position", contacts.avatar.global_position)
			object_transform.origin += contacts.avatar.global_position - logical
		result.object_id = object_id
		result.object_transform = object_transform
		if phase in ["reach", "place", "cleanup"]:
			result.gaze = object_transform * Vector3(0, .008, 0)
	if phase == "align" and role == "active" and not p.get("moving", false) and object_active:
		# Prepare the upper body while the other resident clears the front,
		# before an arm begins its reach towards the selected real piece.
		result.body_yaw = board_yaw + PI
		result.lean = Vector3(_play_reach_pitch(object_transform.origin, contacts.avatar.global_position), 0, 0)
	if phase in ["travel", "align", "completed", "interrupted"] or p.get("moving", false):
		return result
	result.body_yaw = board_yaw + PI
	if phase == "think":
		# Examine real cells rather than staring at a point in empty space.
		if not cells.is_empty():
			var scan := int(floor(contacts.time * .7)) % cells.size()
			result.gaze = cells[scan] + Vector3.UP * .025
		result.lean = Vector3(.10 if role == "active" else .045, 0, 0)
	if role != "active" or phase in ["think", "react", "switch_turn"]:
		return _play_reaction(contacts, p, pose, result, facing)
	if phase not in ["reach", "place", "cleanup"] or not object_active:
		return result
	var source: Vector3 = pose.get("piece_source_position", object_transform.origin)
	var hand := _play_choose_hand(contacts, p, pose, source, destination)
	result.active_hand = hand
	var token := "%s:%s:%s:%s:%s" % [pose.get("id", ""), object_id, selected, phase, contacts.skeleton.get_instance_id()]
	if token != _play_phase_token:
		_play_phase_token = token
		_play_entry_hands = {"L": _current_hand(contacts, "L"), "R": _current_hand(contacts, "R")}
		_play_entry_visual = contacts.avatar.visual.global_transform
	_play_home_hands(contacts, result)
	var grip := _play_grip_solution(contacts, hand)
	var pinch_local: Vector3 = grip.center
	result.finger_pad_supported = grip.supported
	result.pinch_source = "measured_distal_mesh_caps" if grip.supported else "unsupported_distal_contact"
	result.finger_pad_reason = grip.get("reason", "")
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	# The midpoint of two measured, closed distal finger pads reaches the disc
	# centre. The thumb/index base points are not contact sensors.
	var pinch := object_transform * Vector3(0, .008, 0)
	var basis := facing * Basis(Vector3.RIGHT, PI / 2)
	if grip.supported:
		# Level the line between the real pads with the flat disc. This small
		# wrist tilt avoids forcing unequal thumb/index lengths into one plane.
		basis *= Basis(grip.wrist_correction)
	var wrist := Transform3D(basis, pinch - basis * (pinch_local * scale))
	var closed := 1.0
	var withdraw := 0.0
	var reach := 1.0
	if phase in ["reach", "cleanup"]:
		reach = _ease(clampf(progress / .30, 0, 1))
		closed = _ease(clampf((progress - .16) / .14, 0, 1))
		# Preserve the start pose in the body's frame while the child steps up
		# or the resident finishes turning. A world-fixed entry would pull the
		# wrist down behind the rising shoulder before the grasp even begins.
		var entry_frame: Transform3D = contacts.avatar.visual.global_transform * _play_entry_visual.affine_inverse()
		var entry: Transform3D = entry_frame * _play_entry_hands[hand]
		entry.basis = entry.basis.orthonormalized()
		result.reach_entry_wrist = entry
		result.reach_entry_body_delta = contacts.avatar.visual.global_position - _play_entry_visual.origin
		wrist = entry.interpolate_with(wrist, reach)
	if phase in ["place", "cleanup"]:
		var release := clampf((progress - .75) / .25, 0, 1)
		var opening := _ease(clampf(release / .35, 0, 1))
		withdraw = _ease(clampf((release - .20) / .80, 0, 1))
		closed *= 1.0 - opening
		var home := _play_empty_hand_home(contacts, hand)
		var home_wrist := Transform3D(home.basis, home.origin - home.basis * (_palm_offsets[hand] * scale))
		# Lift clear of the flat token before withdrawing, leaving the same
		# physical piece on the board or tray when the controller releases it.
		wrist.origin += Vector3.UP * .020 * _ease(clampf(release / .25, 0, 1))
		wrist = wrist.interpolate_with(home_wrist, withdraw)
		result.release_weight = opening
	result.reach_weight_play = reach
	result.withdraw_weight = withdraw
	result.grasp_weight = closed
	var suffix := "left" if hand == "L" else "right"
	result["grip_" + suffix] = .70 * closed
	result["fingers_" + suffix] = _finger_blend(OPEN_FINGERS, PLAY_CLOSED_FINGERS, closed)
	var pitch := _play_reach_pitch(object_transform.origin, contacts.avatar.global_position)
	# Do not ramp the body on the same late curve as the hand. Contact is
	# reached at 30%, so the supporting posture must already be established.
	result.lean = Vector3(lerpf(pitch, .07, withdraw), 0, 0)
	result.operation = "place_token" if phase == "place" else ("return_token" if phase == "cleanup" else "take_token")
	var current_pinch := pinch_local
	if grip.supported:
		var rotations: Array = []
		for finger in 5:
			var open := Quaternion(Vector3.RIGHT, float(OPEN_FINGERS[finger]) * (.55 if finger == 0 else .85))
			var shut: Quaternion = grip.rotations[finger]
			rotations.append(open.slerp(shut, closed))
		result.finger_rotations = {hand: rotations}
		result["finger_pad_local_" + suffix] = grip.pads.duplicate()
		var thumb: Vector3 = grip.rest[0] * (rotations[0] * grip.pads.thumb)
		var index: Vector3 = grip.rest[1] * (rotations[1] * grip.pads.index)
		current_pinch = (thumb + index) * .5
		var contact_axis: Vector3 = (basis * (grip.axis * scale)).normalized()
		result["finger_pad_target_" + suffix] = {"thumb": pinch - contact_axis * PLAY_PIECE_RADIUS,
			"index": pinch + contact_axis * PLAY_PIECE_RADIUS}
		result.finger_opposition_max_rad = grip.maximum_correction
		result.finger_wrist_tilt_rad = grip.wrist_tilt
	_play_record_hand(contacts, result, hand, wrist, current_pinch)
	return result

func _play_reach_pitch(target: Vector3, root: Vector3) -> float:
	var distance := target - root
	distance.y = 0
	return lerpf(.18, .54, clampf((distance.length() - .28) / .20, 0, 1))

func _play_choose_hand(contacts: ResidentContacts, p: Dictionary, pose: Dictionary, source: Vector3, destination: Vector3) -> String:
	var token := "%s:%s:%s:%s" % [pose.get("id", ""), pose.get("object_id", ""), pose.get("selected_cell", -1), contacts.skeleton.get_instance_id()]
	if token == _play_hand_token:
		return _play_hand
	_play_hand_token = token
	var preferred := str(pose.get("preferred_hand", ""))
	if preferred in ["L", "R"]:
		_play_hand = preferred
		return _play_hand
	# Use the actual rig's rest shoulders in the final facing frame. Reading
	# current animated shoulders here would make a reload choose another hand.
	var to_body: Transform3D = contacts.avatar.visual.global_transform.affine_inverse() * contacts.skeleton.global_transform
	var facing := Basis(Vector3.UP, float(pose.get("board_yaw", 0)) + PI)
	var body_scale: Vector3 = contacts.avatar.visual.scale
	var position: Vector3 = p.get("position", contacts.avatar.global_position)
	var best := INF
	for side in ["L", "R"]:
		var index := contacts.skeleton.find_bone("DEF-upper_arm." + side)
		var shoulder_local: Vector3 = to_body * contacts.skeleton.get_bone_global_rest(index).origin
		var shoulder: Vector3 = position + facing * (shoulder_local * body_scale)
		var source_distance: float = shoulder.distance_to(source)
		var destination_distance: float = shoulder.distance_to(destination)
		var score: float = maxf(source_distance, destination_distance) + .10 * (source_distance + destination_distance)
		if score < best:
			best = score
			_play_hand = side
	return _play_hand

func _play_grip_solution(contacts: ResidentContacts, side: String, radius_override: float = PLAY_PIECE_RADIUS) -> Dictionary:
	var unsupported := {"supported": false, "center": Vector3(0, .055, 0), "reason": "No measured distal finger contacts for this model."}
	if _play_pad_data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/finger-pad-contacts.json"))
		if parsed is Dictionary:
			_play_pad_data = parsed.get("models", {})
	var source := ""
	for child in contacts.model.get_children():
		if child.scene_file_path.ends_with(".glb"):
			source = child.scene_file_path
			break
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	var key := "%s:%s:%s:%s" % [source, side, scale, radius_override]
	if _play_grip_cache.has(key):
		return _play_grip_cache[key]
	var measured: Dictionary = _play_pad_data.get(source, {}).get("hands", {}).get(side, {})
	var pads := {}
	var rest: Array = []
	var hand := contacts.skeleton.find_bone("DEF-hand." + side)
	if hand < 0:
		return unsupported
	var to_hand := contacts.skeleton.get_bone_global_rest(hand).affine_inverse()
	for setting in [[0, "thumb"], [1, "index"]]:
		var name: String = setting[1]
		var data: Dictionary = measured.get(name, {})
		var bone := contacts.skeleton.find_bone("DEF-finger%d.%s" % [setting[0], side])
		if bone < 0 or not data.get("supported", false):
			return unsupported
		var point: Array = data.get("point", [])
		if point.size() != 3:
			return unsupported
		pads[name] = Vector3(point[0], point[1], point[2])
		rest.append(to_hand * contacts.skeleton.get_bone_global_rest(bone))
	var initial: Array = [Quaternion(Vector3.RIGHT, PLAY_CLOSED_FINGERS[0] * .55),
		Quaternion(Vector3.RIGHT, PLAY_CLOSED_FINGERS[1] * .85)]
	var base_thumb: Vector3 = rest[0].origin
	var base_index: Vector3 = rest[1].origin
	var old_thumb: Vector3 = rest[0] * (initial[0] * pads.thumb)
	var old_index: Vector3 = rest[1] * (initial[1] * pads.index)
	var old_mid := (old_thumb + old_index) * .5
	var thumb_length: float = pads.thumb.length()
	var index_length: float = pads.index.length()
	var best: Dictionary = {}
	var best_score := INF
	# Each distal point stays on the sphere defined by its actual bone-local
	# length. Search 24 directions at three wrist elevations; do not stretch fingers,
	# move the game piece, or accept a base-point proxy when no solution exists.
	for option in 72:
		var angle := TAU * float(option % 24) / 24.0
		var elevation: float = [-.5, 0.0, .5][int(option / 24)]
		var horizontal := sqrt(1.0 - elevation * elevation)
		var axis := Vector3(cos(angle) * horizontal, sin(angle) * horizontal, elevation)
		var scaled_axis := (axis * scale).normalized()
		var flat_axis := Vector3(axis.x * scale.x, axis.y * scale.y, 0).normalized()
		var wrist_correction := Quaternion(scaled_axis, flat_axis)
		var wrist_tilt := acos(clampf(scaled_axis.dot(flat_axis), -1, 1))
		var radius := radius_override / maxf(.001, (axis * scale).length())
		var sphere_thumb := base_thumb + axis * radius
		var sphere_index := base_index - axis * radius
		var line := sphere_index - sphere_thumb
		var distance := line.length()
		if distance < .00001 or distance > thumb_length + index_length or distance < absf(thumb_length - index_length):
			continue
		line /= distance
		var along := (thumb_length * thumb_length - index_length * index_length + distance * distance) / (2.0 * distance)
		var height := sqrt(maxf(0, thumb_length * thumb_length - along * along))
		var circle := sphere_thumb + line * along
		var radial := old_mid - circle
		radial -= line * radial.dot(line)
		if radial.length_squared() < .00000001:
			radial = line.cross(Vector3.FORWARD)
			if radial.length_squared() < .00000001:
				radial = line.cross(Vector3.RIGHT)
		var center := circle + radial.normalized() * height
		var targets: Array = [center - axis * radius, center + axis * radius]
		var rotations: Array = []
		var corrections: Array = []
		for finger in 2:
			var pad: Vector3 = pads.thumb if finger == 0 else pads.index
			var finger_rest: Transform3D = rest[finger]
			var target: Vector3 = finger_rest.basis.inverse() * (targets[finger] - finger_rest.origin)
			var start: Quaternion = initial[finger]
			var correction := Quaternion((start * pad).normalized(), target.normalized())
			var rotation := (correction * start).normalized()
			rotations.append(rotation)
			corrections.append(start.angle_to(rotation))
		var maximum := maxf(float(corrections[0]), float(corrections[1]))
		if maximum > .85:
			continue
		var score := maximum + .10 * (float(corrections[0]) + float(corrections[1])) + .30 * center.distance_to(old_mid) / maxf(thumb_length, index_length) + .15 * wrist_tilt
		if score < best_score:
			best_score = score
			best = {"supported": true, "center": center, "pads": pads, "rest": rest, "axis": axis,
				"rotations": rotations, "maximum_correction": maximum,
				"wrist_correction": wrist_correction, "wrist_tilt": wrist_tilt}
	if best.is_empty():
		unsupported.reason = "No bounded finger-base opposition can place both measured pads on the real disc."
		_play_grip_cache[key] = unsupported
		return unsupported
	for finger in range(2, 5):
		best.rotations.append(Quaternion(Vector3.RIGHT, float(PLAY_CLOSED_FINGERS[finger]) * .85))
	_play_grip_cache[key] = best
	return best

func _sewing_grip_solution(contacts: ResidentContacts, side: String, radius_override: float) -> Dictionary:
	# Keep the existing distal grip for rigs that can naturally pinch a thin
	# needle. Older single-bone index fingers use their real side skin for both
	# sewing tools; their distant tips cannot oppose the thumb without folding
	# the whole finger backwards. Board grips never call this helper.
	var thin: Dictionary = _play_grip_solution(contacts, side, .002)
	if thin.get("supported", false): return _play_grip_solution(contacts, side, radius_override)
	var source := ""
	for child in contacts.model.get_children():
		if child.scene_file_path.ends_with(".glb"): source = child.scene_file_path;break
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	var cache_key := "%s:%s:%s:%s" % [source, side, scale, radius_override]
	if _sewing_grip_cache.has(cache_key): return _sewing_grip_cache[cache_key]
	if _sewing_side_pad_data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sewing-finger-pad-contacts.json"))
		if parsed is Dictionary: _sewing_side_pad_data = parsed.get("models", {})
	var surface: Dictionary = _sewing_side_pad_data.get(source, {}).get("hands", {}).get(side, {})
	var measured: Dictionary = _play_pad_data.get(source, {}).get("hands", {}).get(side, {})
	var unsupported := {"supported":false, "reason":"No measured, fully weighted index-side surface for this sewing rig."}
	if not surface.get("supported", false) or float(surface.get("minimum_skin_weight", 0)) < .999: return unsupported
	var hand := contacts.skeleton.find_bone("DEF-hand." + side)
	if hand < 0: return unsupported
	var to_hand := contacts.skeleton.get_bone_global_rest(hand).affine_inverse()
	var pads := {};var rest: Array = []
	for setting in [[0, "thumb"], [1, "index"]]:
		var data: Dictionary = measured.get(setting[1], {}) if setting[0] == 0 else surface
		var point: Array = data.get("point", [])
		var bone := contacts.skeleton.find_bone("DEF-finger%d.%s" % [setting[0], side])
		if bone < 0 or not data.get("supported", false) or point.size() != 3: return unsupported
		pads[setting[1]] = Vector3(point[0], point[1], point[2])
		rest.append(to_hand * contacts.skeleton.get_bone_global_rest(bone))
	var initial: Array = [Quaternion(Vector3.RIGHT, PLAY_CLOSED_FINGERS[0] * .55), Quaternion(Vector3.RIGHT, PLAY_CLOSED_FINGERS[1] * .85)]
	var old_mid: Vector3 = ((rest[0] * (initial[0] * pads.thumb)) + (rest[1] * (initial[1] * pads.index))) * .5
	var thumb_length: float = pads.thumb.length();var index_length: float = pads.index.length()
	var normal_data: Array = surface.get("normal", [])
	if normal_data.size() != 3: return unsupported
	var side_normal := Vector3(normal_data[0], normal_data[1], normal_data[2])
	var best: Dictionary = {};var best_score := INF
	for option in 72:
		var angle := TAU * float(option % 24) / 24.0
		var elevation: float = [-.5, 0.0, .5][int(option / 24)]
		var horizontal := sqrt(1.0 - elevation * elevation)
		var axis := Vector3(cos(angle) * horizontal, sin(angle) * horizontal, elevation)
		var scaled_axis := (axis * scale).normalized()
		var flat_axis := Vector3(axis.x * scale.x, axis.y * scale.y, 0).normalized()
		var correction := Quaternion(scaled_axis, flat_axis)
		var tilt := acos(clampf(scaled_axis.dot(flat_axis), -1, 1))
		var radius := radius_override / maxf(.001, (axis * scale).length())
		var sphere_thumb: Vector3 = rest[0].origin + axis * radius
		var sphere_index: Vector3 = rest[1].origin - axis * radius
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
		for sample in 12:
			var around := TAU * float(sample) / 12.0
			var center := circle + (radial * cos(around) + tangent * sin(around)) * height
			var targets: Array = [center - axis * radius, center + axis * radius]
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
			var normal_alignment := actual_normal.normalized().dot(-axis)
			if normal_alignment < .60: continue
			var score := maximum + .10 * (float(corrections[0]) + float(corrections[1])) + .30 * center.distance_to(old_mid) / maxf(thumb_length, index_length) + .15 * tilt
			if score < best_score:
				best_score = score
				best = {"supported":true, "center":center, "pads":pads, "rest":rest, "axis":axis,
					"rotations":rotations, "maximum_correction":maximum, "wrist_correction":correction, "wrist_tilt":tilt,
					"pad_mode":"index_side", "index_normal_alignment":normal_alignment, "measurement":{"index":surface.duplicate(true), "thumb":measured.thumb.duplicate(true)}}
	if best.is_empty(): unsupported.reason = "No bounded sewing opposition reaches the measured index-side skin and thumb pad."
	else:
		for finger in range(2, 5): best.rotations.append(Quaternion(Vector3.RIGHT, float(PLAY_CLOSED_FINGERS[finger]) * .85))
	_sewing_grip_cache[cache_key] = best if not best.is_empty() else unsupported
	return _sewing_grip_cache[cache_key]

func _play_home_hands(contacts: ResidentContacts, result: Dictionary) -> void:
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	for side in ["L", "R"]:
		var home := _play_empty_hand_home(contacts, side)
		var wrist := Transform3D(home.basis, home.origin - home.basis * (_palm_offsets[side] * scale))
		_play_record_hand(contacts, result, side, wrist)

func _play_empty_hand_home(contacts: ResidentContacts, side: String) -> Transform3D:
	if contacts.avatar.displayed_model != "rin":
		return _empty_hand_home(contacts, side)
	# The child's actual arm is shorter. Scale only the free-hand offsets, not
	# its rig, reach limit, or the world-space contact on the real game piece.
	var ratio: float = contacts.model.rest_height / 1.71
	var sign_x := 1.0 if side == "L" else -1.0
	var body: Transform3D = contacts.avatar.visual.global_transform
	var palm: Vector3 = body * Vector3(sign_x * .26 * ratio, contacts.rest_shoulder - .40 * ratio, .12 * ratio)
	var basis: Basis = body.basis.orthonormalized() * Basis(Vector3.FORWARD, PI)
	return Transform3D(basis, palm)

func _play_record_hand(contacts: ResidentContacts, result: Dictionary, side: String, wrist: Transform3D, pinch_local: Vector3 = Vector3.ZERO) -> void:
	var suffix := "left" if side == "L" else "right"
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	var palm_local: Vector3 = _palm_offsets[side]
	result[suffix] = wrist
	result["palm_local_" + suffix] = palm_local
	result["palm_" + suffix] = wrist * (palm_local * scale)
	if pinch_local != Vector3.ZERO:
		result["pinch_local_" + suffix] = pinch_local
		result["pinch_" + suffix] = wrist * (pinch_local * scale)
		result.piece_grip_local = Vector3(0, .008, 0)
		result.piece_grip_world = object_transform * Vector3(0, .008, 0)
	var upper := contacts.skeleton.find_bone("DEF-upper_arm." + side)
	var fore := contacts.skeleton.find_bone("DEF-forearm." + side)
	var hand := contacts.skeleton.find_bone("DEF-hand." + side)
	if upper >= 0 and fore >= 0 and hand >= 0:
		var shoulder := contacts.skeleton.get_bone_global_rest(upper).origin
		var elbow := contacts.skeleton.get_bone_global_rest(fore).origin
		var end := contacts.skeleton.get_bone_global_rest(hand).origin
		result["arm_length_" + suffix] = ((elbow - shoulder) * scale).length() + ((end - elbow) * scale).length()
		result["shoulder_distance_" + suffix] = contacts.point("upper_arm." + side).distance_to(wrist.origin)

func _play_reaction(contacts: ResidentContacts, _p: Dictionary, pose: Dictionary, result: Dictionary, facing: Basis) -> Dictionary:
	_play_home_hands(contacts, result)
	var phase: String = result.phase
	var progress: float = result.phase_progress
	var role: String = result.role
	var pulse := sin(PI * progress)
	if phase == "react":
		var outcome := "acknowledge"
		if pose.get("draw", false):
			outcome = "draw"
		elif int(pose.get("winner", 0)) != 0:
			var pieces: Dictionary = pose.get("pieces", {})
			var selected: Dictionary = pieces.get(str(pose.get("object_id", "")), {})
			var color := int(selected.get("color", 0))
			var own_color := color if role == "active" else 3 - color
			outcome = "win" if own_color == int(pose.winner) else "loss"
		result.reaction = outcome
		result.lean = Vector3(.035 * pulse if outcome in ["win", "acknowledge"] else .09 * pulse, 0, 0)
		var side := "L" if role == "observer" else "R"
		var home := _play_empty_hand_home(contacts, side)
		home.origin += Vector3.UP * (.14 if outcome == "win" else .07) * pulse
		home.origin += facing * Vector3(0, 0, .045 * pulse)
		home.basis = home.basis.slerp(facing * Basis(Vector3.RIGHT, PI / 2), .45 * pulse)
		var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
		_play_record_hand(contacts, result, side, Transform3D(home.basis, home.origin - home.basis * (_palm_offsets[side] * scale)))
	elif role == "observer":
		# A short body acknowledgement accompanies the real selected cell. No
		# board move, token, or result is invented by the reaction layer.
		result.lean = Vector3(.025 * sin(PI * progress), 0, 0)
	return result

func _radio(contacts: ResidentContacts, p: Dictionary, activity: Dictionary, pose: Dictionary) -> Dictionary:
	object_active = true
	object_id = str(pose.object_id)
	object_transform = Transform3D(Basis(Vector3.UP, float(pose.get("object_yaw", 0))), pose.object_position)
	var phase := str(pose.get("phase", ""))
	var role := str(pose.get("role", "support"))
	var progress := clampf(float(pose.get("phase_progress", 0)), 0, 1)
	var moving_phase := phase in ["carry_to_target", "carry_to_source"]
	if moving_phase and pose.get("carry", false):
		# Sim advances at minute boundaries, whereas the displayed resident root
		# interpolates every frame. Correct the single shared object transform,
		# rather than smoothing palms and object independently.
		var carry_yaw := float(pose.get("carry_yaw", PI))
		var shown_yaw: float = contacts.avatar.visual.global_basis.get_euler().y
		var logical_position: Vector3 = p.get("position", contacts.avatar.global_position)
		object_transform.origin += contacts.avatar.global_position - logical_position
		object_transform.origin += Basis(Vector3.UP, shown_yaw) * CARRY_OFFSET - Basis(Vector3.UP, carry_yaw) * CARRY_OFFSET
		object_transform.basis = Basis(Vector3.UP, float(pose.get("object_yaw", carry_yaw + PI)) + wrapf(shown_yaw - carry_yaw, -PI, PI))
	var token := "%s:%s:%s" % [pose.get("id", ""), phase, role]
	if token != _phase_token:
		_phase_token = token
		_entry_hands = {"L": _current_hand(contacts, "L"), "R": _current_hand(contacts, "R")}
	var result := {"profile": "radio", "phase": phase, "role": role, "phase_progress": progress,
		"object_id": object_id, "object_transform": object_transform, "grip_left": 0.0, "grip_right": 0.0,
		"fingers_left": OPEN_FINGERS.duplicate(), "fingers_right": OPEN_FINGERS.duplicate(),
		"gaze": object_transform * Vector3(.04, .15, .08), "lean": Vector3.ZERO, "grasp_weight": 0.0}
	if phase in ["completed", "interrupted", "reserved"]:
		return result
	result.clip = "walk" if p.get("moving", false) else "idle"
	if phase == "working":
		result.clip = "work"
		result.body_yaw = float(activity.get("yaw", pose.get("carry_yaw", PI)))
		result.lean = Vector3(.16, 0, 0)
		if role == "operator":
			_operator(result, contacts.time, p)
		else:
			_support(result, p)
		return _with_wrists(contacts, result)
	# The waiting partner watches the real object without reaching across the
	# carrier or pretending to hold a radio that is in somebody else's hands.
	if role != "carrier":
		return result
	if phase == "to_source":
		return result
	if phase not in ["take", "take_return", "carry_to_target", "carry_to_source", "place", "return"]:
		return result
	var left_basis := _side_basis(-1)
	var right_basis := _side_basis(1)
	result.palm_left = object_transform * RADIO_LEFT
	result.palm_right = object_transform * RADIO_RIGHT
	result.palm_basis_left = object_transform.basis * left_basis
	result.palm_basis_right = object_transform.basis * right_basis
	result.grip_left = .75
	result.grip_right = .75
	result.fingers_left = CARRY_FINGERS.duplicate()
	result.fingers_right = CARRY_FINGERS.duplicate()
	result.grasp_weight = 1.0
	result.lean = Vector3(.10, 0, 0)
	if not moving_phase:
		result.body_yaw = float(pose.get("carry_yaw", PI))
	if phase in ["take", "take_return"]:
		# Controller keeps the object still for the first 30%, then lifts it.
		# During the reach the palms travel to it; only then do fingers close.
		var reach := _ease(clampf(progress / .30, 0, 1))
		var close := _ease(clampf((progress - .16) / .14, 0, 1))
		result.reach_weight = reach
		result.grasp_weight = close
		result.grip_left *= close
		result.grip_right *= close
		result.fingers_left = _finger_blend(OPEN_FINGERS, CARRY_FINGERS, close)
		result.fingers_right = _finger_blend(OPEN_FINGERS, CARRY_FINGERS, close)
		if phase == "take_return":
			# The far-side grip at the table needs a deeper forward reach than
			# the shelf. Keep it while the case is still forward; recover only
			# after lifting it most of the way towards the chest.
			var recover := _ease(clampf((progress - .65) / .35, 0, 1))
			result.lean = Vector3(lerpf(lerpf(.16, .40, reach), .10, recover), 0, 0)
		else:
			result.lean = Vector3(lerpf(.05, .22, reach) * (1.0 - .45 * _ease(clampf((progress - .30) / .70, 0, 1))), 0, 0)
	elif phase in ["place", "return"]:
		# The first 75% lowers the canonical object, the final 25% releases it.
		var release := clampf((progress - .75) / .25, 0, 1)
		var opening := _ease(clampf(release / .35, 0, 1))
		var clearing := _ease(clampf(release / .25, 0, 1))
		var withdraw := _ease(clampf((release - .20) / .80, 0, 1))
		result.release_weight = opening
		result.withdraw_weight = withdraw
		for setting in [["L", "left", -1.0], ["R", "right", 1.0]]:
			var side: String = setting[0]
			var key: String = setting[1]
			var outward: float = setting[2]
			# Clear the edge with open fingers, then return towards the body.
			# Continuing to spread the hands at the table would make the far
			# arm longer rather than letting go of an already seated radio.
			var clear: Vector3 = result["palm_" + key] + object_transform.basis * Vector3(outward * .012, .015, .012) * clearing
			var home := _empty_hand_home(contacts, side)
			result["palm_" + key] = clear.lerp(home.origin, withdraw)
			var grip_basis: Basis = result["palm_basis_" + key]
			result["palm_basis_" + key] = grip_basis.slerp(home.basis, withdraw)
		result.grasp_weight = 1.0 - opening
		result.grip_left *= 1.0 - opening
		result.grip_right *= 1.0 - opening
		result.fingers_left = _finger_blend(CARRY_FINGERS, OPEN_FINGERS, opening)
		result.fingers_right = _finger_blend(CARRY_FINGERS, OPEN_FINGERS, opening)
		result.lean = Vector3(.20 * (1.0 - .65 * withdraw), 0, 0)
	# A near-body, low elbow plane supports the weight without abducting both
	# upper arms into the sides of the jacket. Contact targets remain unchanged.
	# Working uses its existing pole until its own pose is visually evaluated.
	var elbow_frame: Transform3D = contacts.avatar.visual.global_transform
	result.elbow_left = elbow_frame * Vector3(.20, contacts.rest_shoulder - .28, .07)
	result.elbow_right = elbow_frame * Vector3(-.20, contacts.rest_shoulder - .28, .07)
	return _with_wrists(contacts, result)

func _empty_hand_home(contacts: ResidentContacts, side: String) -> Transform3D:
	var sign_x := 1.0 if side == "L" else -1.0
	var body: Transform3D = contacts.avatar.visual.global_transform
	var palm := body * Vector3(sign_x * .26, contacts.rest_shoulder - .40, .12)
	# Fingers hang down in the resident's own frame, with the palm forward.
	var basis := body.basis.orthonormalized() * Basis(Vector3.FORWARD, PI)
	return Transform3D(basis, palm)

func _operator(result: Dictionary, clock: float, p: Dictionary) -> void:
	# One broad supporting palm; the other pinches the actual front dial. A
	# turn/release/reset cycle changes wrist orientation, not the radio position.
	var cycle := fposmod(clock, 2.8) / 2.8
	var turn := 0.0
	var pinch := 1.0
	if cycle < .60:
		turn = lerpf(-.30, .30, _ease(cycle / .60))
	elif cycle < .78:
		turn = .30
		pinch = 1.0 - _ease((cycle - .60) / .18)
	else:
		turn = lerpf(.30, -.30, _ease((cycle - .78) / .22))
		pinch = _ease((cycle - .78) / .22)
	var position: Vector3 = p.get("position", object_transform.origin)
	var local_position := object_transform.affine_inverse() * position
	var side := -1.0 if local_position.x < 0 else 1.0
	result.palm_left = object_transform * Vector3(side * .195, .115, .025)
	result.palm_right = object_transform * (RADIO_DIAL + Vector3(0, 0, .018 * (1.0 - pinch)))
	result.palm_basis_left = object_transform.basis * _side_basis(side)
	result.palm_basis_right = object_transform.basis * Basis(Vector3.FORWARD, turn) * Basis(Vector3.RIGHT, PI)
	result.grip_left = .40
	result.grip_right = .75 * pinch
	result.fingers_left = [.25, .32, .40, .42, .34]
	result.fingers_right = [.72 * pinch, .80 * pinch, .22, .15, .12]
	result.grasp_weight = 1.0
	result.gaze = object_transform * RADIO_DIAL
	result.operation = "dial_turn"

func _support(result: Dictionary, p: Dictionary) -> void:
	# Stay on the participant's own side instead of both partners reaching for
	# the same dial. The two contacts brace different points of the actual case.
	var position: Vector3 = p.get("position", object_transform.origin)
	var local_position := object_transform.affine_inverse() * position
	var side := -1.0 if local_position.x < 0 else 1.0
	result.palm_left = object_transform * Vector3(side * .195, .115, -.035)
	result.palm_right = object_transform * Vector3(side * .195, .105, .050)
	result.palm_basis_left = object_transform.basis * _side_basis(side)
	result.palm_basis_right = object_transform.basis * _side_basis(side)
	result.grip_left = .45
	result.grip_right = .45
	result.fingers_left = [.30, .38, .45, .46, .40]
	result.fingers_right = [.30, .38, .45, .46, .40]
	result.grasp_weight = 1.0
	result.operation = "case_support"

func activity_profile(group: String, activity: Dictionary, clock: float) -> Dictionary:
	# All coordinates below refer to existing scene hand markers. The profile
	# does not create a recorder, screwdriver, camera, sheet, or other held prop.
	# Where the current scene has no tool, open-hand planning gestures are used.
	if group not in ["radio", "model", "bread", "photo", "music", "craft"]:
		return {}
	if not activity.get("hand_left") is Vector3 or not activity.get("hand_right") is Vector3:
		return {}
	var facing := Basis(Vector3.UP, float(activity.get("yaw", 0)))
	var left: Vector3 = activity.hand_left
	var right: Vector3 = activity.hand_right
	var cycle := clock * 2.2
	var result := {"profile": group, "phase": "activity", "role": "participant", "clip": "work",
		"body_yaw": float(activity.get("yaw", 0)), "palm_left": left, "palm_right": right,
		"palm_basis_left": facing * Basis(Vector3.RIGHT, PI / 2),
		"palm_basis_right": facing * Basis(Vector3.RIGHT, PI / 2),
		"grip_left": 0.0, "grip_right": 0.0, "fingers_left": OPEN_FINGERS.duplicate(),
		"fingers_right": OPEN_FINGERS.duplicate(), "gaze": (left + right) * .5,
		"lean": Vector3(.10, 0, 0), "grasp_weight": 0.0, "prop_contact": false}
	match group:
		"radio":
			# Full dial contact requires a real interaction pose. With no radio at
			# this station the resident can point/explain, but does not grip air.
			result.palm_right += facing * Vector3(.015 * sin(cycle), .025, .012 * cos(cycle))
			result.operation = "explain_adjustment"
		"model":
			# Brace the existing model-house board, then place/align with the other
			# hand. No imaginary brush, glue bottle, or separate part is attached.
			var lift := pow(maxf(0, sin(cycle)), 2)
			result.palm_right += facing * Vector3(.035 * sin(cycle * .5), .015 + .055 * lift, .025 * cos(cycle))
			result.fingers_left = [.15, .22, .28, .28, .23]
			result.fingers_right = [.30, .35, .25, .20, .18]
			result.operation = "brace_and_align"
			result.prop_contact = true
		"bread":
			var press := .5 + .5 * sin(cycle)
			var fold := .5 + .5 * sin(cycle + PI / 2)
			result.palm_left += facing * Vector3(0, .010 + .035 * (1.0 - press), .045 * press)
			result.palm_right += facing * Vector3(0, .010 + .035 * (1.0 - press), .045 * press)
			result.palm_basis_left *= Basis(Vector3.RIGHT, .12 * fold)
			result.palm_basis_right *= Basis(Vector3.RIGHT, .12 * fold)
			result.lean = Vector3(.12 + .07 * press, 0, 0)
			result.operation = "two_palm_press"
			result.prop_contact = true
		"photo":
			result.palm_left += facing * Vector3(.02 * sin(cycle * .5), .025, 0)
			result.palm_right += facing * Vector3(.060 * sin(cycle * .65), .045, .025 * cos(cycle * .65))
			result.operation = "discuss_composition"
		"music":
			# Count a phrase with an open hand; there is currently no recorder on
			# the music table, so this is not presented as pressing its buttons.
			result.palm_left += facing * Vector3(0, .020, 0)
			result.palm_right += facing * Vector3(.025 * sin(cycle), .06 + .045 * sin(cycle * 2), 0)
			result.operation = "count_phrase"
		"craft":
			result.palm_left += facing * Vector3(-.025 * sin(cycle * .45), .025, .015)
			result.palm_right += facing * Vector3(.025 * sin(cycle * .45), .025, -.015)
			result.operation = "measure_layout"
	return result

func _cache_palms(contacts: ResidentContacts) -> void:
	var id := contacts.skeleton.get_instance_id()
	if id == _skeleton_id:
		return
	_skeleton_id = id
	_phase_token = ""
	_palm_offsets.clear()
	for side in ["L", "R"]:
		var hand_index := contacts.skeleton.find_bone("DEF-hand." + side)
		var finger_index := contacts.skeleton.find_bone("DEF-finger2." + side)
		var local_palm := Vector3(0, .035, 0)
		if hand_index >= 0 and finger_index >= 0:
			var hand_rest := contacts.skeleton.get_bone_global_rest(hand_index)
			var finger_rest := contacts.skeleton.get_bone_global_rest(finger_index)
			local_palm = (hand_rest.affine_inverse() * finger_rest.origin) * .5
		_palm_offsets[side] = local_palm

func _with_wrists(contacts: ResidentContacts, result: Dictionary) -> Dictionary:
	var scale: Vector3 = contacts.skeleton.global_basis.get_scale()
	for setting in [["L", "left"], ["R", "right"]]:
		var side: String = setting[0]
		var key: String = setting[1]
		var local_palm: Vector3 = _palm_offsets[side]
		var basis: Basis = result["palm_basis_" + key]
		basis = basis.orthonormalized()
		var wrist := Transform3D(basis, result["palm_" + key] - basis * (local_palm * scale))
		if result.has("reach_weight") and _entry_hands.has(side):
			var start: Transform3D = _entry_hands[side]
			wrist = start.interpolate_with(wrist, float(result.reach_weight))
		result[key] = wrist
		result["palm_local_" + key] = local_palm
		result["palm_" + key] = wrist * (local_palm * scale)
		# A diagnostic only: do not move a contact away from the real object to
		# make an unreachable pose appear to pass a hand-contact check.
		var upper := contacts.skeleton.find_bone("DEF-upper_arm." + side)
		var fore := contacts.skeleton.find_bone("DEF-forearm." + side)
		var hand := contacts.skeleton.find_bone("DEF-hand." + side)
		if upper >= 0 and fore >= 0 and hand >= 0:
			var shoulder := contacts.skeleton.get_bone_global_rest(upper).origin
			var elbow := contacts.skeleton.get_bone_global_rest(fore).origin
			var end := contacts.skeleton.get_bone_global_rest(hand).origin
			var arm_length := ((elbow - shoulder) * scale).length() + ((end - elbow) * scale).length()
			result["arm_length_" + key] = arm_length
			result["shoulder_distance_" + key] = contacts.point("upper_arm." + side).distance_to(wrist.origin)
	return result

func _current_hand(contacts: ResidentContacts, side: String) -> Transform3D:
	var index := contacts.skeleton.find_bone("DEF-hand." + side)
	var hand := contacts.skeleton.global_transform * contacts.skeleton.get_bone_global_pose(index)
	hand.basis = hand.basis.orthonormalized()
	return hand

static func _side_basis(side: float) -> Basis:
	# Bone +Y follows fingers away from the carrier, along radio -Z. Bone +Z
	# remains the inward palm normal; the wrist is behind the contact, not below.
	return Basis(Vector3(0, side, 0), Vector3(0, 0, -1), Vector3(-side, 0, 0))

static func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)

static func _finger_blend(a: Array, b: Array, weight: float) -> Array:
	var result: Array = []
	for finger in 5:
		result.append(lerpf(float(a[finger]), float(b[finger]), weight))
	return result
