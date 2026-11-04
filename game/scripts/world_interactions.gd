class_name WorldInteractions
extends RefCounted

# Simulation-owned object location, reservation and workflow. Rendering only reads
# this state; a hidden actor, skipped clip or LOD swap cannot create an effect.
const ACTIVE_PHASES := ["to_source","take","carry_to_target","place","working","take_return","carry_to_source","return"]
const PHASES := ["to_source","take","carry_to_target","place","working","take_return","carry_to_source","return","completed","interrupted"]
const HISTORY_LIMIT := 64
var sim
var config: Dictionary
var objects: Dictionary = {}
var sessions: Dictionary = {}

func _init(simulation) -> void:
	sim = simulation
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/world-interactions.json")).radio
	for key in ["source_position","source_approach","target_position","carry_offset"]:
		var xyz: Array = config[key]
		config[key] = Vector3(xyz[0],xyz[1],xyz[2])

func reset() -> void:
	sessions.clear()
	objects = {config.object_id:{"id":config.object_id,"kind":"radio","position":config.source_position,
		"yaw":float(config.source_yaw),"owner":config.owner,"holder":"","container":config.source_container,
		"reserved_by":"","state":"stored","work_progress":0.0}}

func supports(meeting: Dictionary) -> bool:
	return meeting.get("mode","")=="project" and meeting.get("project",{}).get("key","")=="radio"

func available() -> bool:
	return objects.has(config.object_id) and objects[config.object_id].reserved_by.is_empty()

func begin(meeting: Dictionary) -> bool:
	if not supports(meeting): return true
	if sessions.has(meeting.get("interaction_id","")): return true
	if not available() or not sim.activities.walkable(config.site,config.source_approach): return false
	var a: Dictionary = sim.person(meeting.a)
	var b: Dictionary = sim.person(meeting.b)
	if not sim.life.is_alive(a) or not sim.life.is_alive(b): return false
	# Current small-child rigs cannot reach this shelf. They may collaborate at
	# the workbench with the existing step, while the taller participant carries.
	var carrier: Dictionary = a if int(a.age)>=int(config.minimum_carrier_age) else b
	if int(carrier.age)<int(config.minimum_carrier_age): return false
	var destinations := {}
	for p in [a,b]:
		var spot: Dictionary = sim.activities.for_person(p)
		if spot.get("group","")!="radio" or not sim.activities.walkable(config.site,spot.approach): return false
		destinations[p.id] = {"position":spot.approach,"spot":spot.id}
	var id: String = "interaction_"+meeting.id
	var teacher: String = meeting.project.get("teacher",meeting.a)
	if teacher not in [meeting.a,meeting.b]: teacher = meeting.a
	var session := {"id":id,"meeting":meeting.id,"key":"radio","object_id":config.object_id,
		"a":meeting.a,"b":meeting.b,"carrier":carrier.id,"operator":teacher,
		"phase":"to_source","phase_started":int(sim.elapsed),"started":int(sim.elapsed),"finished":-1,
		"worked_minutes":0,"required_work":int(meeting.remaining),"targets":destinations,
		"reason":"","effects":[],"travel_distance":0.0,
		"carry_yaw":PI,"phase_carry_yaw":PI,
		"phase_object_position":objects[config.object_id].position,"phase_object_yaw":objects[config.object_id].yaw}
	sessions[id] = session
	meeting.interaction_id = id
	meeting.work_completed = false
	objects[config.object_id].reserved_by = id
	# Keep the allocated work slot while fetching the object; ActivityPlaces uses
	# activity_spot for real exclusivity even when its owner is still travelling.
	_route(carrier,config.source_approach,destinations[carrier.id].spot)
	session.travel_distance = _distance(carrier)
	for p in [a,b]: p.reason = "棚のラジオを取りに向かっている" if p.id==carrier.id else "相手がラジオを運ぶ間、作業台で準備する"
	_trim()
	return true

func _meeting(id: String) -> Dictionary:
	for meeting in sim.meetings:
		if meeting.id==id: return meeting
	return {}

func tick() -> void:
	# Life-course removal can erase meetings before the normal meeting loop runs.
	for session in sessions.values():
		if session.phase not in ACTIVE_PHASES: continue
		var meeting := _meeting(session.meeting)
		var unavailable := meeting.is_empty()
		for id in [session.a,session.b]:
			var p: Dictionary = sim.person(id)
			unavailable = unavailable or not sim.life.is_alive(p) or p.get("meeting_id","")!=session.meeting
			unavailable = unavailable or (not p.get("moving",false) and p.get("place","").begins_with("off_map_")) or p.get("destination","").begins_with("off_map_")
		if unavailable: cancel(session.id,"参加者が退場したため、道具を安全に保管した")

func advance(meeting: Dictionary) -> String:
	var session: Dictionary = sessions.get(meeting.get("interaction_id",""),{})
	if session.is_empty(): return "interrupted"
	if session.phase in ["completed","interrupted"]: return session.phase
	if sim.elapsed-session.started>int(config.timeout_minutes):
		cancel(session.id,"道具の準備や返却に時間がかかった")
		return "interrupted"
	var carrier: Dictionary = sim.person(session.carrier)
	var object: Dictionary = objects[session.object_id]
	_sync_held(session,carrier)
	match session.phase:
		"to_source":
			if _arrived(carrier,config.source_approach): _phase(session,"take")
		"take":
			var lift := clampf((_progress(session)-.3)/.7,0,1)
			if _progress(session)>=.3: _claim(session,carrier)
			object.position = config.source_position.lerp(_held_position(carrier,PI),lift)
			object.yaw = float(config.source_yaw)
			if _progress(session)>=1:
				var target: Dictionary = session.targets[carrier.id]
				_route(carrier,target.position,target.spot)
				_phase(session,"carry_to_target")
				session.travel_distance = _distance(carrier)
		"carry_to_target":
			if _arrived(carrier,session.targets[carrier.id].position): _phase(session,"place")
		"place":
			var lower := clampf(_progress(session)/.75,0,1)
			session.carry_yaw = lerp_angle(float(session.phase_carry_yaw),PI,lower)
			object.position = session.phase_object_position.lerp(config.target_position,lower)
			object.yaw = lerp_angle(float(session.phase_object_yaw),float(config.target_yaw),lower)
			if _progress(session)>=.75:
				object.holder = "";object.container = config.target_container;object.state = "on_table"
			if _progress(session)>=1 and _all_at_table(session) and sim.elapsed>=int(meeting.get("not_before",0)):
				object.holder = "";object.container = config.target_container
				object.position = config.target_position;object.yaw = float(config.target_yaw);object.state = "on_table"
				_phase(session,"working")
				for id in [session.a,session.b]: sim.person(id).reason = "ラジオを支え、相手と確かめながら調整している"
		"working":
			return "working"
		"take_return":
			session.carry_yaw = PI
			var lift := clampf((_progress(session)-.3)/.7,0,1)
			if _progress(session)>=.3: _claim(session,carrier)
			object.position = config.target_position.lerp(_held_position(carrier,PI),lift)
			object.yaw = float(config.target_yaw)
			if _progress(session)>=1:
				_route(carrier,config.source_approach,session.targets[carrier.id].spot)
				_phase(session,"carry_to_source")
				session.travel_distance = _distance(carrier)
		"carry_to_source":
			if _arrived(carrier,config.source_approach): _phase(session,"return")
		"return":
			var lower := clampf(_progress(session)/.75,0,1)
			session.carry_yaw = lerp_angle(float(session.phase_carry_yaw),PI,lower)
			object.position = session.phase_object_position.lerp(config.source_position,lower)
			object.yaw = lerp_angle(float(session.phase_object_yaw),float(config.source_yaw),lower)
			if _progress(session)>=.75:
				object.holder = "";object.container = config.source_container;object.state = "stored"
			if _progress(session)>=1:
				_store(session)
				_phase(session,"completed");session.finished = int(sim.elapsed)
				return "completed"
	return "pending"

func worked(meeting: Dictionary) -> void:
	var session: Dictionary = sessions.get(meeting.get("interaction_id",""),{})
	if session.is_empty() or session.phase!="working": return
	session.worked_minutes += 1
	if meeting.remaining<=0:
		meeting.work_completed = true
		if "result" not in session.effects:
			session.effects.append("result")
			_phase(session,"take_return")
			sim.work_family.finish_project(meeting)
			objects[session.object_id].work_progress = sim.work_family.projects.radio
		for id in [session.a,session.b]: sim.person(id).reason = "調整したラジオを確かめ、棚に戻している"

func cancel(id: String, reason: String) -> void:
	var session: Dictionary = sessions.get(id,{})
	if session.is_empty() or session.phase not in ACTIVE_PHASES: return
	_store(session)
	session.phase = "interrupted";session.reason = reason;session.finished = int(sim.elapsed)
	# No actor animation or reachable exit is required for forced safe storage.
	var carrier: Dictionary = sim.person(session.carrier)
	if carrier.get("meeting_id","")==session.meeting and carrier.get("destination","")==config.site:
		carrier.path = [];carrier.moving = false;carrier.target = carrier.position

func end(meeting: Dictionary, completed: bool) -> void:
	var id: String = meeting.get("interaction_id","")
	if not completed: cancel(id,"予定や本人の事情が変わったため、ラジオを保管した")

func _store(session: Dictionary) -> void:
	var object: Dictionary = objects[session.object_id]
	object.position = config.source_position;object.yaw = float(config.source_yaw)
	object.holder = "";object.container = config.source_container;object.reserved_by = "";object.state = "stored"
	for id in [session.a,session.b]:
		var p: Dictionary = sim.person(id)
		if p.get("meeting_id","")==session.meeting or (p.get("meeting_id","").is_empty() and p.get("activity_spot","")==session.targets[id].spot): p.activity_spot = ""

func _claim(session: Dictionary, carrier: Dictionary) -> void:
	var object: Dictionary = objects[session.object_id]
	object.holder = carrier.id;object.container = "";object.state = "held"
	session.carry_yaw = PI

func _sync_held(session: Dictionary, carrier: Dictionary) -> void:
	var object: Dictionary = objects[session.object_id]
	if object.holder!=carrier.id: return
	if carrier.moving and session.phase in ["carry_to_target","carry_to_source"]:
		var next: Vector3 = carrier.path[0] if not carrier.path.is_empty() else carrier.target
		var direction: Vector3 = next-carrier.position
		if direction.length_squared()>.0001: session.carry_yaw = atan2(direction.x,direction.z)
		object.yaw = float(session.carry_yaw)+PI
		object.position = _held_position(carrier,float(session.carry_yaw))

func _held_position(p: Dictionary, yaw: float) -> Vector3:
	return p.position+Basis(Vector3.UP,yaw)*config.carry_offset

func _route(p: Dictionary, target: Vector3, spot: String) -> void:
	p.target = target;p.destination = config.site;p.activity_spot = spot
	p.path = sim.route(p.position,p.place,target,config.site)
	p.moving = not p.path.is_empty()
	if not p.moving: p.place = config.site

func _arrived(p: Dictionary, target: Vector3) -> bool:
	return not p.moving and p.place==config.site and p.position.distance_to(target)<.12

func _all_at_table(session: Dictionary) -> bool:
	for id in [session.a,session.b]:
		if not _arrived(sim.person(id),session.targets[id].position): return false
	return true

func _distance(p: Dictionary) -> float:
	var result := 0.0
	var point: Vector3 = p.position
	for next in p.path: result += point.distance_to(next);point = next
	return result

func _phase(session: Dictionary, phase: String) -> void:
	session.phase = phase;session.phase_started = int(sim.elapsed)
	session.phase_object_position = objects[session.object_id].position
	session.phase_object_yaw = objects[session.object_id].yaw
	session.phase_carry_yaw = session.carry_yaw

func _progress(session: Dictionary, visual: bool = false) -> float:
	if session.phase in ["to_source","carry_to_target","carry_to_source"]:
		var carrier: Dictionary = sim.person(session.carrier)
		return clampf(1-_distance(carrier)/maxf(.001,float(session.travel_distance)),0,1)
	if session.phase=="working": return clampf(float(session.worked_minutes)/maxi(1,int(session.required_work)),0,1)
	var duration: float = config.phase_minutes.get(session.phase,1)
	return clampf((float(sim.elapsed)-float(session.phase_started)+(float(sim.minute_remainder) if visual else 0.0))/duration,0,1)

func pose_for(id: String) -> Dictionary:
	for session in sessions.values():
		if session.phase not in ACTIVE_PHASES or id not in [session.a,session.b]: continue
		var object: Dictionary = objects[session.object_id]
		var role := "operator" if id==session.operator else "support"
		if session.phase!="working": role = "carrier" if id==session.carrier else "support"
		return {"id":session.id,"key":"radio","phase":session.phase,"phase_progress":_progress(session,true),"role":role,
			"object_id":session.object_id,"object_position":object.position,"object_yaw":object.yaw,"carry_yaw":session.carry_yaw,
			"carry":object.holder==id,"work_progress":clampf(float(session.worked_minutes)/maxi(1,int(session.required_work)),0,1),
			"source_position":config.source_position,"target_position":config.target_position}
	return {}

func _trim() -> void:
	while sessions.size()>HISTORY_LIMIT:
		# JSON may reorder dictionary keys; prune by saved time and ID instead.
		var oldest := ""
		for id in sessions:
			if sessions[id].phase in ACTIVE_PHASES: continue
			if oldest.is_empty() or int(sessions[id].finished)<int(sessions[oldest].finished) or (sessions[id].finished==sessions[oldest].finished and str(id)<oldest): oldest = id
		if oldest.is_empty(): break
		sessions.erase(oldest)

func serialize() -> Dictionary:
	return {"version":1,"objects":objects.duplicate(true),"sessions":sessions.duplicate(true)}

func restore(data: Dictionary) -> void:
	if data.is_empty(): reset();return
	objects = data.objects.duplicate(true);sessions = data.sessions.duplicate(true)
