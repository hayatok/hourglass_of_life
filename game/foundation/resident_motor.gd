class_name ResidentMotor
extends Node3D

# Metres and render seconds only. This controller owns the world transform;
# callers supply a walkable polyline, never a second position/lerp follower.
# The motor's global transform and pose.heading are world-space. A child visual
# inherits that transform; it must not apply the heading or position a second time.
# No gait, skeleton pose, contact or natural-looking motion is claimed here.
const FORMAT_VERSION := 2
const STEP_SECONDS := 1.0 / 120.0
const REPLANT_SECONDS := .12
const POSITION_EPSILON := .000001
const HEADING_EPSILON := .00001
const MAX_PATH_POINTS := 1024
const MAX_COORDINATE := 10000.0
const DEFAULT_PROFILE := {"walk_speed":1.1,"acceleration":1.8,"deceleration":2.2,"turn_speed":2.4,"arrival_radius":.04}
const STATES := ["idle","start","walk","turn","stop"]

var velocity: Vector3:
	get: return _direction * _speed
var heading: float:
	get: return _heading

var _profile: Dictionary = DEFAULT_PROFILE.duplicate()
var _path: Array[Vector3] = []
var _pending_path: Array[Vector3] = []
var _has_pending_path := false
var _stop_requested := false
var _segment_origin := Vector3.ZERO
var _direction := Vector3.ZERO
var _length := 0.0
var _progress := 0.0
var _speed := 0.0
var _heading := 0.0
var _goal_heading := 0.0
var _state := "idle"
var _state_elapsed := 0.0
var _turn_phase := "none"
var _turn_total_angle := 0.0
var _replant_remaining := 0.0
var _remainder := 0.0
var _gait_distance := 0.0
var _turn_only := false

func configure(profile: Dictionary) -> bool:
	var checked := _checked_profile(profile)
	if checked.is_empty() or _state!="idle": return false
	if not _valid_vector(global_position) or not is_finite(global_rotation.y): return false
	_profile = checked
	_heading = wrapf(global_rotation.y,-PI,PI)
	_goal_heading = _heading
	_segment_origin = global_position
	return true

func follow_path(points: Array) -> bool:
	var checked: Variant = _checked_path(points,false)
	if checked==null: return false
	if checked.is_empty(): stop();return true
	if _speed>0:
		_pending_path.assign(checked)
		_has_pending_path = true
		_stop_requested = true
		_set_state("stop")
	else:
		_start_path(checked)
	return true

func stop() -> void:
	_pending_path.clear();_has_pending_path = false
	if _speed>0:
		_stop_requested = true
		_set_state("stop")
	else:
		_finish_path()

func face_heading(angle: float) -> bool:
	# Furniture alignment uses the same controller as a path corner. Callers
	# cannot rotate the rendered model independently of its body.
	if _state!="idle" or not is_finite(angle): return false
	_goal_heading=wrapf(angle,-PI,PI)
	_turn_total_angle=absf(wrapf(_goal_heading-_heading,-PI,PI))
	if _turn_total_angle<=HEADING_EPSILON:return true
	_turn_only=true;_turn_phase="rotate";_set_state("turn")
	return true

func tick(delta: float) -> bool:
	# A bounded public tick also prevents malformed callers from creating an
	# unbounded catch-up loop. Normal render deltas and one-second tests fit.
	if not is_finite(delta) or delta<0 or delta>1.0: return false
	if delta==0: return true
	_remainder += delta
	var count := int(floor((_remainder + .0000000001) / STEP_SECONDS))
	_remainder -= float(count) * STEP_SECONDS
	if absf(_remainder)<.0000000001: _remainder = 0.0
	for ignored in count: _integrate(STEP_SECONDS)
	return true

func state() -> String: return _state

func pose() -> Dictionary:
	return {"speed":_speed,"normalized_speed":_speed / float(_profile.walk_speed),"heading":_heading,
		"turn_angle":wrapf(_goal_heading-_heading,-PI,PI),"state":_state,"state_elapsed":_state_elapsed,
		"gait_distance":_gait_distance,"turn_phase":_turn_phase,
		"turn_progress":1.0-clampf(absf(wrapf(_goal_heading-_heading,-PI,PI))/maxf(HEADING_EPSILON,_turn_total_angle),0,1) if _state=="turn" else 0.0}

func snapshot() -> Dictionary:
	# Plain arrays deliberately make the current format JSON-safe, independent
	# of any LifeSimulation encoder or minute clock.
	return {"version":FORMAT_VERSION,"profile":_profile.duplicate(),"position":_xyz(global_position),"velocity":_xyz(velocity),
		"heading":_heading,"goal_heading":_goal_heading,"state":_state,"state_elapsed":_state_elapsed,
		"path":_encoded_path(_path),"pending_path":_encoded_path(_pending_path),"has_pending_path":_has_pending_path,
		"stop_requested":_stop_requested,"segment_origin":_xyz(_segment_origin),"direction":_xyz(_direction),
		"length":_length,"progress":_progress,"speed":_speed,"turn_phase":_turn_phase,"turn_total_angle":_turn_total_angle,
		"replant_remaining":_replant_remaining,"remainder":_remainder,"gait_distance":_gait_distance,"turn_only":_turn_only}

func restore(data: Variant) -> bool:
	var checked := _checked_snapshot(data)
	if checked.is_empty(): return false
	# All validation precedes mutation, including transform and configuration.
	_profile = checked.profile
	_turn_only=data.turn_only
	_path.assign(checked.path);_pending_path.assign(checked.pending_path)
	_has_pending_path = data.has_pending_path;_stop_requested = data.stop_requested
	_segment_origin = checked.segment_origin;_direction = checked.direction
	_length = float(data.length);_progress = float(data.progress);_speed = float(data.speed)
	_heading = float(data.heading);_goal_heading = float(data.goal_heading)
	_state = data.state;_state_elapsed = float(data.state_elapsed)
	_turn_phase = data.turn_phase;_turn_total_angle = float(data.turn_total_angle)
	_replant_remaining = float(data.replant_remaining);_remainder = float(data.remainder);_gait_distance = float(data.gait_distance)
	global_position = checked.position
	global_rotation = Vector3(0,_heading,0)
	return true

func _integrate(delta: float) -> void:
	_state_elapsed += delta
	if _state=="idle": return
	if _state=="turn":
		if _turn_phase=="rotate":
			var error := wrapf(_goal_heading-_heading,-PI,PI)
			var change := clampf(error,-float(_profile.turn_speed)*delta,float(_profile.turn_speed)*delta)
			_heading = wrapf(_heading+change,-PI,PI)
			global_rotation = Vector3(0,_heading,0)
			if absf(wrapf(_goal_heading-_heading,-PI,PI))<=HEADING_EPSILON:
				_heading = _goal_heading;global_rotation = Vector3(0,_heading,0)
				_turn_phase = "replant";_replant_remaining = REPLANT_SECONDS
		else:
			_replant_remaining = maxf(0,_replant_remaining-delta)
			if _replant_remaining==0:
				if _turn_only:_finish_path()
				else:_turn_phase = "none";_set_state("start")
		return
	var limit := _length
	if _path.size()==1: limit = maxf(0,_length-float(_profile.arrival_radius))
	var remaining := maxf(0,limit-_progress)
	var deceleration: float = _profile.deceleration
	var next_speed := 0.0
	if _stop_requested:
		next_speed = maxf(0,_speed-deceleration*delta)
	else:
		# Three fixed substeps of lookahead make the braking envelope conservative
		# under trapezoidal integration, including very short final segments.
		var anticipation := 3.0 * deceleration * delta
		var safe_speed := maxf(0,sqrt(2.0*deceleration*remaining+anticipation*anticipation)-anticipation)
		var target := minf(float(_profile.walk_speed),safe_speed)
		var rate: float = _profile.acceleration if target>_speed else deceleration
		next_speed = move_toward(_speed,target,rate*delta)
	var travel := minf(remaining,(_speed+next_speed)*.5*delta)
	if not _stop_requested and remaining<=POSITION_EPSILON and _speed<=deceleration*delta:
		travel = remaining;next_speed = 0.0
	_progress += travel
	_gait_distance += travel
	global_position = _segment_origin + _direction * _progress
	var old_speed := _speed
	_speed = next_speed
	if _stop_requested:
		_set_state("stop")
		if _speed==0:
			if _has_pending_path:
				var next: Array[Vector3] = _pending_path.duplicate()
				_start_path(next)
			else: _finish_path()
		return
	if _speed==0 and limit-_progress<=POSITION_EPSILON:
		_path.pop_front()
		if _path.is_empty(): _finish_path()
		else: _begin_segment()
	elif _speed>old_speed+.0000001: _set_state("start")
	elif _speed<old_speed-.0000001: _set_state("stop")
	else: _set_state("walk" if _speed>=float(_profile.walk_speed)*.995 else "stop")

func _start_path(points: Array) -> void:
	_turn_only=false
	_path.clear();_pending_path.clear();_has_pending_path = false;_stop_requested = false
	var start := global_position
	for point in points:
		var previous: Vector3 = start if _path.is_empty() else _path[-1]
		if previous.distance_to(point)<=POSITION_EPSILON: continue
		# Only remove a point on the same straight segment. Curved and reversing
		# paths keep their exact corner, which will be reached before turning.
		if not _path.is_empty():
			var prior: Vector3 = start if _path.size()==1 else _path[-2]
			var incoming: Vector3 = previous-prior
			var outgoing: Vector3 = point-previous
			if incoming.normalized().dot(outgoing.normalized())>1.0-.0000001 and incoming.cross(outgoing).length()<=.0000001:
				_path.pop_back()
		_path.append(point)
	_speed = 0.0
	if _path.is_empty(): _finish_path()
	else: _begin_segment()

func _begin_segment() -> void:
	_state_elapsed = 0.0
	_segment_origin = global_position
	_progress = 0.0
	var toward: Vector3 = _path[0]-_segment_origin
	_length = toward.length();_direction = toward / _length
	var horizontal := Vector2(_direction.x,_direction.z)
	_goal_heading = wrapf(atan2(_direction.x,_direction.z),-PI,PI) if horizontal.length_squared()>.0000001 else _heading
	_turn_total_angle = absf(wrapf(_goal_heading-_heading,-PI,PI))
	_replant_remaining = 0.0
	if _turn_total_angle>HEADING_EPSILON:
		_turn_phase = "rotate";_set_state("turn")
	else:
		_turn_phase = "none";_set_state("start")

func _finish_path() -> void:
	_path.clear();_pending_path.clear();_has_pending_path = false;_stop_requested = false
	_segment_origin = global_position;_direction = Vector3.ZERO
	_length = 0.0;_progress = 0.0;_speed = 0.0
	_goal_heading = _heading;_turn_phase = "none";_turn_total_angle = 0.0;_replant_remaining = 0.0
	_turn_only=false
	_set_state("idle")

func _set_state(value: String) -> void:
	if _state!=value: _state=value;_state_elapsed=0.0

static func _checked_profile(data: Dictionary, complete: bool = false) -> Dictionary:
	if complete and data.size()!=DEFAULT_PROFILE.size(): return {}
	var checked := DEFAULT_PROFILE.duplicate()
	for key in data:
		if not checked.has(key) or not _number(data[key]): return {}
		checked[key] = float(data[key])
	if checked.walk_speed<=0 or checked.walk_speed>3.0 or checked.acceleration<=0 or checked.acceleration>50.0 or checked.deceleration<=0 or checked.deceleration>50.0: return {}
	if checked.turn_speed<=0 or checked.turn_speed>12.0 or checked.arrival_radius<0 or checked.arrival_radius>.1: return {}
	return checked

static func _checked_path(data: Variant, encoded: bool) -> Variant:
	if not data is Array or data.size()>MAX_PATH_POINTS: return null
	var result: Array[Vector3] = []
	for item in data:
		var value: Variant = _vector(item) if encoded else item
		if not value is Vector3 or not _valid_vector(value): return null
		result.append(value)
	return result

static func _checked_snapshot(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size()!=23 or not _number(data.get("version")) or data.version!=FORMAT_VERSION: return {}
	if not data.get("profile") is Dictionary: return {}
	var profile := _checked_profile(data.profile,true)
	if profile.is_empty(): return {}
	for key in ["length","progress","speed","state_elapsed","turn_total_angle","replant_remaining","remainder","gait_distance"]:
		if not _number(data.get(key)) or data[key]<0 or data[key]>1000000000.0: return {}
	for key in ["heading","goal_heading"]:
		if not _number(data.get(key)) or absf(float(data[key]))>PI+.0000001: return {}
	if data.get("state") not in STATES or data.get("turn_phase") not in ["none","rotate","replant"]: return {}
	if not data.get("has_pending_path") is bool or not data.get("stop_requested") is bool: return {}
	if not data.get("turn_only") is bool: return {}
	if data.turn_only and data.state!="turn":return {}
	if data.speed>profile.walk_speed+.000001 or data.remainder>=STEP_SECONDS or data.replant_remaining>REPLANT_SECONDS or data.turn_total_angle>PI+.0000001: return {}
	var result := {"profile":profile}
	for key in ["position","velocity","segment_origin","direction"]:
		var value: Variant = _vector(data.get(key))
		if value==null: return {}
		result[key] = value
	for key in ["path","pending_path"]:
		var values: Variant = _checked_path(data.get(key),true)
		if values==null: return {}
		result[key] = values
	if result.velocity.distance_to(result.direction*float(data.speed))>.00001: return {}
	if bool(data.has_pending_path)!=(not result.pending_path.is_empty()) or (data.has_pending_path and not data.stop_requested): return {}
	if data.stop_requested and (data.state!="stop" or data.speed<=0): return {}
	if data.state=="idle":
		if not result.path.is_empty() or data.speed!=0 or data.turn_phase!="none" or data.stop_requested or data.length!=0 or data.progress!=0 or result.direction!=Vector3.ZERO: return {}
		if result.position.distance_to(result.segment_origin)>.00001 or absf(wrapf(float(data.goal_heading)-float(data.heading),-PI,PI))>HEADING_EPSILON or data.turn_total_angle!=0: return {}
	elif data.turn_only:
		if not result.path.is_empty() or data.length!=0 or data.progress!=0 or result.direction!=Vector3.ZERO or result.position.distance_to(result.segment_origin)>.00001: return {}
	else:
		if result.path.is_empty(): return {}
		for index in range(1,result.path.size()):
			if result.path[index].distance_to(result.path[index-1])<=POSITION_EPSILON: return {}
		var delta: Vector3 = result.path[0]-result.segment_origin
		if delta.length()<=POSITION_EPSILON or absf(delta.length()-float(data.length))>.00001 or result.direction.distance_to(delta.normalized())>.00001: return {}
		if data.progress>data.length+.000001 or result.position.distance_to(result.segment_origin+result.direction*float(data.progress))>.00002: return {}
		var angle := atan2(delta.x,delta.z) if Vector2(result.direction.x,result.direction.z).length_squared()>.0000001 else float(data.heading)
		if absf(wrapf(angle-float(data.goal_heading),-PI,PI))>.00001: return {}
		var available: float = float(data.length)-float(data.progress)
		if result.path.size()==1: available = maxf(0,available-float(profile.arrival_radius))
		if float(data.speed)*float(data.speed)/(2.0*float(profile.deceleration))>available+.00002: return {}
	if data.state=="turn":
		if data.speed!=0 or data.progress!=0 or data.turn_phase=="none" or data.stop_requested: return {}
		var error := absf(wrapf(float(data.goal_heading)-float(data.heading),-PI,PI))
		if error>float(data.turn_total_angle)+HEADING_EPSILON: return {}
		if data.turn_phase=="rotate" and (data.replant_remaining!=0 or error<=HEADING_EPSILON): return {}
		if data.turn_phase=="replant" and (error>HEADING_EPSILON or data.replant_remaining<=0): return {}
	elif data.turn_phase!="none" or data.replant_remaining!=0: return {}
	return result

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _valid_vector(value: Vector3) -> bool:
	return value.is_finite() and maxf(absf(value.x),maxf(absf(value.y),absf(value.z)))<=MAX_COORDINATE

static func _vector(value: Variant) -> Variant:
	if not value is Array or value.size()!=3: return null
	for coordinate in value:
		if not _number(coordinate): return null
	var result := Vector3(value[0],value[1],value[2])
	return result if _valid_vector(result) else null

static func _xyz(value: Vector3) -> Array: return [value.x,value.y,value.z]
static func _encoded_path(values: Array[Vector3]) -> Array:
	var result: Array = []
	for value in values: result.append(_xyz(value))
	return result
