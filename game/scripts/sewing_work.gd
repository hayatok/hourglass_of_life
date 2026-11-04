class_name SewingWork
extends RefCounted

# Authoritative materials, tools and work. The renderer never consumes cloth,
# completes a stitch, teaches a skill or creates a second copy of an item.
const ACTIVE := ["to_source","take","carry_to_table","place","cut","sew","lift_show","show","lower","take_store","carry_to_store","store"]
const PHASES := ["to_source","take","carry_to_table","place","cut","sew","lift_show","show","lower","take_store","carry_to_store","store","completed","interrupted"]
const STAGES := ["fabric","cut","sewing","finished"]
const HISTORY_LIMIT := 64
const RULES_PATH := "res://data/sewing-work.json"

var sim
var config: Dictionary = {}
var objects: Dictionary = {}
var sessions: Dictionary = {}
var serial: int = 0

func _init(owner_sim) -> void:
	sim = owner_sim
	config = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	for key in ["source_position","source_approach","target_position","carry_offset","show_offset"]:
		config[key] = _vector(config[key])
	for index in config.storage_slots.size(): config.storage_slots[index] = _vector(config.storage_slots[index])
	for tool in config.tools.values(): tool.position = _vector(tool.position)

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func reset() -> void:
	objects.clear();sessions.clear();serial = 0
	for ordinal in range(1,int(config.piece_count)+1):
		var id: String = "sewing_cloth_%02d"%ordinal
		objects[id] = {"id":id,"kind":"fabric","ordinal":ordinal,"owner":"town","holder":"","container":"sewing_stock",
			"reserved_by":"","state":"stored","stage":"fabric","position":_storage_position({"ordinal":ordinal}),"yaw":float(config.source_yaw),"pitch":0.0,
			"material_used":false,"cut_minutes":0,"sew_minutes":0,"result_recorded":false,"shown_to":[]}
	for kind in config.tools:
		var setting: Dictionary = config.tools[kind]
		objects[setting.id] = {"id":setting.id,"kind":kind,"ordinal":0,"owner":"town","holder":"","container":"sewing_table",
			"reserved_by":"","state":"on_table","stage":"tool","position":setting.position,"yaw":float(setting.yaw),"pitch":float(setting.get("pitch",0)),
			"material_used":false,"cut_minutes":0,"sew_minutes":0,"result_recorded":false,"shown_to":[]}

func supports(meeting: Dictionary) -> bool:
	return meeting.get("mode","")=="project" and meeting.get("project") is Dictionary and meeting.project.get("key","")=="craft"

func active_session() -> Dictionary:
	for session in sessions.values():
		if session.phase in ACTIVE: return session
	return {}

func available(a: Dictionary, b: Dictionary, project: Dictionary = {}) -> bool:
	return not selection(a,b,project).is_empty()

func material_cost(a: Dictionary, b: Dictionary, project: Dictionary) -> float:
	var chosen: Dictionary = selection(a,b,project)
	return float(chosen.remaining_cost) if not chosen.is_empty() else 0.0

func planned_minutes(a: Dictionary, b: Dictionary, project: Dictionary) -> int:
	var chosen: Dictionary = selection(a,b,project)
	var processing: int = maxi(0,int(project.get("duration",45)))
	if not chosen.is_empty():
		var item: Dictionary = chosen.item
		processing = maxi(0,int(config.cut_minutes)+int(config.sew_minutes)-int(item.cut_minutes)-int(item.sew_minutes))
	return maxi(1,processing+maxi(0,int(project.get("setup_minutes",75))))

func selection(a: Dictionary, b: Dictionary, project: Dictionary = {}) -> Dictionary:
	# Queries return copies and never reserve a table, charge, consume a cloth,
	# draw random values, or change which person owns an existing workpiece.
	if not _record(a,["id"],["age"]) or not _record(b,["id"],["age"]) or a.id==b.id: return {}
	if not _whole(a.age) or not _whole(b.age) or not sim.life.is_alive(a) or not sim.life.is_alive(b): return {}
	if not active_session().is_empty() or not _tools_free(): return {}
	var order: Array = _maker_order(a,b,project)
	if order.is_empty(): return {}
	for maker_id in order:
		var owned: Dictionary = _owned_piece(maker_id)
		if not owned.is_empty(): return _selection_result(maker_id,owned,project)
	for ordinal in range(int(config.piece_count),0,-1):
		var item: Dictionary = objects["sewing_cloth_%02d"%ordinal]
		if not item.material_used and item.reserved_by.is_empty(): return _selection_result(order[0],item,project)
	return {}

func _selection_result(maker_id: String, item: Dictionary, project: Dictionary) -> Dictionary:
	var cost: float = 0.0
	if not item.material_used:
		if not _number(project.get("cost",0.0)) or float(project.get("cost",0.0))<0: return {}
		cost = float(project.get("cost",0.0))
	return {"maker":maker_id,"id":item.id,"item":item.duplicate(true),"remaining_cost":cost}

func _tools_free() -> bool:
	for setting in config.tools.values():
		if not objects.has(setting.id) or not objects[setting.id].reserved_by.is_empty(): return false
	return true

func _maker_order(a: Dictionary, b: Dictionary, project: Dictionary) -> Array:
	var result: Array = []
	for candidate in [project.get("learner",""),a.id,b.id]:
		for person in [a,b]:
			if candidate==person.id and int(person.age)>=int(config.minimum_maker_age) and person.id not in result:
				result.append(person.id)
	return result

func _owned_piece(owner_id: String) -> Dictionary:
	# A stable ID order also survives JSON key reordering. An unshown completed
	# item takes priority over starting or continuing another item for its owner.
	for finished in [true,false]:
		for ordinal in range(1,int(config.piece_count)+1):
			var item: Dictionary = objects["sewing_cloth_%02d"%ordinal]
			if item.owner!=owner_id or not item.material_used or not item.reserved_by.is_empty(): continue
			if finished and item.stage=="finished" and item.shown_to.is_empty(): return item
			if not finished and item.stage!="finished": return item
	return {}

func begin(meeting: Dictionary) -> bool:
	if not supports(meeting): return true
	var existing: Dictionary = sessions.get(meeting.get("sewing_id",""),{})
	if not existing.is_empty(): return existing.phase in ACTIVE
	var a: Dictionary = sim.person(meeting.get("a",""));var b: Dictionary = sim.person(meeting.get("b",""))
	var chosen: Dictionary = selection(a,b,meeting.project)
	if chosen.is_empty(): return false
	var maker: Dictionary = sim.person(chosen.maker)
	var item: Dictionary = objects[chosen.id]
	var targets: Dictionary = {}
	for person in [a,b]:
		var spot: Dictionary = sim.activities.for_person(person)
		var expected: Array = config.slots.get(spot.get("id",""),[])
		if spot.get("group","")!=config.group or spot.get("site","")!=config.site or expected.size()!=3: return false
		if spot.approach.distance_to(_vector(expected))>.001: return false
		targets[person.id] = {"spot":spot.id,"position":spot.approach}
	if targets[a.id].spot==targets[b.id].spot: return false
	serial += 1
	var id: String = "sewing_%d"%serial
	var resumed_finished: bool = item.stage=="finished"
	var session: Dictionary = {"id":id,"meeting":meeting.id,"recipe":config.recipe,"a":a.id,"b":b.id,"maker":maker.id,
		"viewer":b.id if maker.id==a.id else a.id,"object_id":item.id,"phase":"to_source","started":int(sim.elapsed),
		"phase_started":int(sim.elapsed),"finished":-1,"targets":targets,"source_position":item.position,
		"cut_at_start":int(item.cut_minutes),"sew_at_start":int(item.sew_minutes),"worked_minutes":0,
		"required_work":int(config.cut_minutes)+int(config.sew_minutes)-int(item.cut_minutes)-int(item.sew_minutes),
		"carry_yaw":PI,"show_yaw":PI,"travel_distance":0.0,"phase_object_position":item.position,
		"phase_object_yaw":float(item.yaw),"phase_carry_yaw":PI,"reason":"","shown":false,"resume_finished":resumed_finished,
		"source_approach":Vector3(item.position.x,0,config.source_approach.z),"tool_phase":"none","tool_started":int(sim.elapsed)}
	sessions[id] = session
	meeting.sewing_id = id;meeting.sewing_resume_finished = resumed_finished;meeting.sewing_presented = false
	meeting.remaining = int(session.required_work)
	meeting.materials_ready = bool(item.material_used)
	meeting.project_result_recorded = bool(item.result_recorded)
	meeting.work_completed = resumed_finished
	item.reserved_by = id
	for setting in config.tools.values(): objects[setting.id].reserved_by = id
	_route(maker,session.source_approach,targets[maker.id].spot)
	session.travel_distance = _distance(maker)
	for person in [a,b]: person.reason = "作りかけの巾着を取りに行く" if item.material_used else "巾着に使う布を取りに行く"
	_trim()
	return true

func _meeting(id: String) -> Dictionary:
	for meeting in sim.meetings:
		if meeting.id==id: return meeting
	return {}

func _interruption(session: Dictionary) -> String:
	var meeting: Dictionary = _meeting(session.meeting)
	if meeting.is_empty(): return "制作の予定が終了したため、物を保管した"
	for id in [session.a,session.b]:
		var person: Dictionary = sim.person(id)
		if not sim.life.is_alive(person) or person.get("meeting_id","")!=session.meeting: return "参加者が退場したため、物を保管した"
		if person.get("destination","").begins_with("off_map_"): return "町を離れるため、作りかけを保管した"
		if not sim.work_family.meeting_compatible(person,meeting): return "次の予定のため、作りかけを保管した"
		if float(person.get("hunger",0))>.78 or float(person.get("fatigue",0))>.90: return "食事や休息を先にするため、作りかけを保管した"
	if sim.elapsed-int(session.started)>int(config.timeout_minutes): return "制作の時間が長くなったため、物を保管した"
	return ""

func tick() -> void:
	for session in sessions.values():
		if session.phase not in ACTIVE: continue
		var reason: String = _interruption(session)
		if not reason.is_empty(): _cancel(session,reason)

func advance(meeting: Dictionary) -> String:
	var session: Dictionary = sessions.get(meeting.get("sewing_id",""),{})
	if session.is_empty(): return "interrupted"
	if session.phase in ["completed","interrupted"]: return session.phase
	var reason: String = _interruption(session)
	if not reason.is_empty(): _cancel(session,reason);return "interrupted"
	var maker: Dictionary = sim.person(session.maker)
	var item: Dictionary = objects[session.object_id]
	var progress: float = _progress(session)
	_sync_held(session,maker)
	match session.phase:
		"to_source":
			if _arrived(maker,session.source_approach): _phase(session,"take")
		"take":
			if progress>=.3: _claim(item,maker)
			item.position = session.source_position.lerp(_held_position(maker,float(session.carry_yaw)),clampf((progress-.3)/.7,0,1))
			if progress>=1:
				_route(maker,session.targets[maker.id].position,session.targets[maker.id].spot)
				_phase(session,"carry_to_table");session.travel_distance = _distance(maker)
		"carry_to_table":
			if _arrived(maker,session.targets[maker.id].position): _phase(session,"place")
		"place":
			_lower_to(item,session,config.target_position,"sewing_table",progress)
			if progress>=1 and _all_at_table(session) and sim.elapsed>=int(meeting.get("not_before",0)):
				_phase(session,"lift_show" if item.stage=="finished" else ("cut" if item.cut_minutes<int(config.cut_minutes) else "sew"))
		"cut", "sew":
			_update_tools(session)
			if session.tool_phase=="reach" and _tool_progress(session)>=1:
				_tool_phase(session,"operate");_update_tools(session)
			elif session.tool_phase=="return" and _tool_progress(session)>=1:
				_phase(session,"sew" if session.phase=="cut" else "lift_show")
				return "pending"
			if session.tool_phase=="operate" and _all_at_table(session): return "working"
		"lift_show":
			var viewer: Dictionary = sim.person(session.viewer)
			var direction: Vector3 = viewer.position-maker.position
			if direction.length_squared()>.0001: session.show_yaw = atan2(direction.x,direction.z)
			session.carry_yaw = session.show_yaw
			if progress>=.3: _claim(item,maker)
			item.position = config.target_position.lerp(_show_position(maker,float(session.show_yaw)),clampf((progress-.3)/.7,0,1))
			item.yaw = lerp_angle(float(config.target_yaw),float(session.show_yaw)+PI,progress)
			if progress>=1: _phase(session,"show")
		"show":
			item.position = _show_position(maker,float(session.show_yaw));item.yaw = float(session.show_yaw)+PI
			if progress>=1 and _all_at_table(session):
				_show(session)
				_phase(session,"lower")
		"lower":
			_lower_to(item,session,config.target_position,"sewing_table",progress)
			if progress>=1: _phase(session,"take_store")
		"take_store":
			session.carry_yaw = PI
			if progress>=.3: _claim(item,maker)
			item.position = config.target_position.lerp(_held_position(maker,PI),clampf((progress-.3)/.7,0,1))
			if progress>=1:
				_route(maker,session.source_approach,session.targets[maker.id].spot)
				_phase(session,"carry_to_store");session.travel_distance = _distance(maker)
		"carry_to_store":
			if _arrived(maker,session.source_approach): _phase(session,"store")
		"store":
			_lower_to(item,session,_storage_position(item),"sewing_storage",progress)
			if progress>=1:
				_store(session);_phase(session,"completed");session.finished = int(sim.elapsed)
				return "completed"
	return "pending"

func work_remaining(meeting: Dictionary) -> int:
	var session: Dictionary = sessions.get(meeting.get("sewing_id",""),{})
	if session.is_empty(): return 0
	var item: Dictionary = objects[session.object_id]
	return maxi(0,int(config.cut_minutes)+int(config.sew_minutes)-int(item.cut_minutes)-int(item.sew_minutes))

func remaining_minutes(meeting: Dictionary) -> int:
	# Calendar time includes handling the real object after its last stitch.
	# Read existing paths and public routes without reserving or moving anything.
	var session: Dictionary = sessions.get(meeting.get("sewing_id",""),{})
	if session.is_empty():
		if not supports(meeting): return 0
		return planned_minutes(sim.person(meeting.a),sim.person(meeting.b),meeting.project)
	if session.phase not in ACTIVE: return 0
	var item: Dictionary = objects[session.object_id]
	var maker: Dictionary = sim.person(session.maker)
	var first: int = ACTIVE.find(session.phase)
	var remaining: int = 0
	for index in range(first,ACTIVE.size()):
		var phase: String = ACTIVE[index]
		var current_phase: bool = index==first
		if phase in ["cut","sew"]:
			var processing: int = maxi(0,int(config[phase+"_minutes"])-int(item[phase+"_minutes"]))
			if not current_phase and processing==0: continue
			if current_phase:
				remaining += processing
				if session.tool_phase=="reach": remaining += _tool_remaining(session)+int(config.tool_minutes["return"])
				elif session.tool_phase=="return": remaining += _tool_remaining(session)
				else: remaining += int(config.tool_minutes["return"])
			else:
				remaining += processing+int(config.tool_minutes.reach)+int(config.tool_minutes["return"])
		elif phase in ["to_source","carry_to_table","carry_to_store"]:
			var target: Vector3 = session.targets[session.maker].position if phase=="carry_to_table" else session.source_approach
			if current_phase:
				remaining += _journey_remaining(maker,target,session)
			else:
				var origin: Vector3 = session.source_approach if phase=="carry_to_table" else session.targets[session.maker].position
				remaining += _route_minutes(origin,target,session)
		else:
			var duration: int = int(config.phase_minutes[phase])
			remaining += maxi(0,duration-maxi(0,int(sim.elapsed)-int(session.phase_started))) if current_phase else duration
		# Each transition is observed on an integer simulation tick. In particular,
		# arriving or finishing a return never starts the next handling phase early.
		remaining += 1
	if first<=ACTIVE.find("place"):
		var viewer: Dictionary = sim.person(session.viewer)
		remaining += _journey_remaining(viewer,session.targets[session.viewer].position,session)
		remaining += maxi(0,int(meeting.get("not_before",0))-int(sim.elapsed))
	elif not _all_at_table(session) and first<ACTIVE.find("take_store"):
		# An externally disturbed participant cannot be assumed to teleport back.
		remaining = maxi(remaining,_timeout_remaining(session))
	return maxi(1,remaining)

func _tool_remaining(session: Dictionary) -> int:
	return maxi(0,int(config.tool_minutes[session.tool_phase])-maxi(0,int(sim.elapsed)-int(session.tool_started)))

func _timeout_remaining(session: Dictionary) -> int:
	return maxi(1,int(session.started)+int(config.timeout_minutes)+1-int(sim.elapsed))

func _journey_remaining(person: Dictionary, target: Vector3, session: Dictionary) -> int:
	if _arrived(person,target): return 0
	if not person.moving or person.path.is_empty() or person.path[-1].distance_to(target)>.03: return _timeout_remaining(session)
	return ceili(_distance(person)/float(sim.WALK_METERS_PER_MINUTE))

func _route_minutes(origin: Vector3, target: Vector3, session: Dictionary) -> int:
	if origin.distance_to(target)<.03: return 0
	var path: Array = sim.route(origin,config.site,target,config.site)
	if path.is_empty() or path[-1].distance_to(target)>.03: return _timeout_remaining(session)
	var distance: float = 0.0
	var previous: Vector3 = origin
	for point: Vector3 in path:
		distance += previous.distance_to(point);previous = point
	return ceili(distance/float(sim.WALK_METERS_PER_MINUTE))

func worked(meeting: Dictionary) -> void:
	var session: Dictionary = sessions.get(meeting.get("sewing_id",""),{})
	if session.is_empty() or session.phase not in ["cut","sew"] or session.tool_phase!="operate" or not _all_at_table(session): return
	var item: Dictionary = objects[session.object_id]
	if item.result_recorded: return
	if session.phase=="cut":
		item.material_used = true;item.owner = session.maker;item.stage = "cut"
		item.cut_minutes = mini(int(config.cut_minutes),int(item.cut_minutes)+1)
		if item.cut_minutes>=int(config.cut_minutes): _tool_phase(session,"return")
	else:
		item.stage = "sewing";item.sew_minutes = mini(int(config.sew_minutes),int(item.sew_minutes)+1)
	session.worked_minutes = int(item.cut_minutes)+int(item.sew_minutes)-int(session.cut_at_start)-int(session.sew_at_start)
	if item.cut_minutes==int(config.cut_minutes) and item.sew_minutes==int(config.sew_minutes):
		item.kind = "pouch";item.stage = "finished";item.result_recorded = true
		meeting.work_completed = true
		sim.work_family.finish_project(meeting)
		_tool_phase(session,"return")
		for id in [session.a,session.b]: sim.person(id).reason = "できあがった巾着を相手に見せたい"
	_update_tools(session)

func _show(session: Dictionary) -> void:
	var item: Dictionary = objects[session.object_id]
	if item.stage!="finished": return
	var maker: Dictionary = sim.person(session.maker);var viewer: Dictionary = sim.person(session.viewer)
	if not _all_at_table(session) or not sim.life.is_alive(viewer): return
	session.shown = true
	var meeting: Dictionary = _meeting(session.meeting)
	if not meeting.is_empty(): meeting.sewing_presented = true
	if viewer.id in item.shown_to: return
	item.shown_to.append(viewer.id)
	sim._remember(maker,viewer.id,"巾着を見せた","できあがった小さな巾着を、%sさんに見てもらった。"%viewer.name,"creation_shown")
	maker.memories[-1].object_id = item.id
	sim._remember(viewer,maker.id,"巾着を見せてもらった","%sさんが作った小さな巾着を、そばで見せてもらった。"%maker.name,"seen_creation")
	viewer.memories[-1].object_id = item.id
	for pair in [[maker,viewer],[viewer,maker]]:
		var relation: Dictionary = sim._relation(pair[0],pair[1].id)
		relation.familiarity = minf(1,float(relation.familiarity)+.008)
		relation.ease = minf(1,float(relation.ease)+.006)

func end(meeting: Dictionary, completed: bool) -> void:
	var session: Dictionary = sessions.get(meeting.get("sewing_id",""),{})
	if session.is_empty(): return
	if not completed and session.phase in ACTIVE: _cancel(session,"予定や本人の事情が変わったため、作りかけを保管した")

func _cancel(session: Dictionary, reason: String) -> void:
	_store(session);_phase(session,"interrupted");session.reason = reason;session.finished = int(sim.elapsed)

func _store(session: Dictionary) -> void:
	var item: Dictionary = objects[session.object_id]
	item.position = _storage_position(item)
	item.yaw = float(config.source_yaw);item.holder = "";item.reserved_by = "";item.state = "stored"
	item.container = "sewing_storage" if item.material_used else "sewing_stock"
	_reset_tools(session)
	for setting in config.tools.values(): objects[setting.id].reserved_by = ""
	for id in [session.a,session.b]:
		var person: Dictionary = sim.person(id)
		if person.get("meeting_id","")==session.meeting or (person.get("meeting_id","").is_empty() and person.get("activity_spot","")==session.targets[id].spot):
			person.activity_spot = ""
			if person.get("destination","")==config.site:
				person.path = [];person.moving = false;person.target = person.position

func _storage_position(item: Dictionary) -> Vector3:
	return config.storage_slots[int(item.ordinal)-1]

func _claim(item: Dictionary, maker: Dictionary) -> void:
	item.holder = maker.id;item.container = "";item.state = "held"

func _lower_to(item: Dictionary, session: Dictionary, target: Vector3, container: String, progress: float) -> void:
	item.position = session.phase_object_position.lerp(target,clampf(progress/.75,0,1))
	item.yaw = lerp_angle(float(session.phase_object_yaw),float(config.target_yaw),clampf(progress/.75,0,1))
	if progress>=.75:
		item.holder = "";item.container = container;item.state = "stored" if container=="sewing_storage" else "on_table"

func _held_position(maker: Dictionary, yaw: float) -> Vector3:
	return maker.position+Basis(Vector3.UP,yaw)*config.carry_offset

func _show_position(maker: Dictionary, yaw: float) -> Vector3:
	return maker.position+Basis(Vector3.UP,yaw)*config.show_offset

func _sync_held(session: Dictionary, maker: Dictionary) -> void:
	var item: Dictionary = objects[session.object_id]
	if item.holder!=maker.id: return
	if session.phase in ["carry_to_table","carry_to_store"]:
		if maker.moving:
			var next: Vector3 = maker.path[0] if not maker.path.is_empty() else maker.target
			var direction: Vector3 = next-maker.position
			if direction.length_squared()>.0001: session.carry_yaw = atan2(direction.x,direction.z)
		item.position = _held_position(maker,float(session.carry_yaw));item.yaw = float(session.carry_yaw)+PI

func _reset_tools(_session: Dictionary) -> void:
	for setting in config.tools.values():
		var tool: Dictionary = objects[setting.id]
		tool.position = setting.position;tool.yaw = float(setting.yaw);tool.pitch = float(setting.get("pitch",0));tool.holder = "";tool.container = "sewing_table";tool.state = "on_table"

func _tool_phase(session: Dictionary, phase: String) -> void:
	session.tool_phase = phase;session.tool_started = int(sim.elapsed)

func _tool_progress(session: Dictionary, visual: bool = false) -> float:
	if session.tool_phase=="operate": return _progress(session,visual)
	if session.tool_phase=="none": return 0.0
	var duration: float = float(config.tool_minutes.get(session.tool_phase,4))
	return clampf((float(sim.elapsed)-float(session.tool_started)+(float(sim.minute_remainder) if visual else 0.0))/duration,0,1)

func _operation_position(session: Dictionary) -> Vector3:
	var kind: String = "scissors" if session.phase=="cut" else "needle"
	var offset: Vector3 = _vector(config.tool_operation_offsets[kind])
	if kind=="scissors": offset.x = absf(offset.x)*(-1.0 if _operation_yaw(session)<0 else 1.0)
	return config.target_position+offset

func _operation_yaw(session: Dictionary) -> float:
	if session.phase!="cut": return float(config.tool_operation_yaws.needle)
	var target: Vector3 = session.targets[session.maker].position
	return -PI*.5 if target.x<float(config.target_position.x) else PI*.5

func _tool_pose(session: Dictionary, visual: bool = false) -> Dictionary:
	# This only calculates a transform. Visual reads may use the fractional
	# minute, but neither a tool's holder nor the authoritative world changes.
	var kind: String = "scissors" if session.phase=="cut" else "needle"
	var setting: Dictionary = config.tools[kind]
	var progress: float = _tool_progress(session,visual)
	var operating: Vector3 = _operation_position(session)
	var position: Vector3 = operating
	var pose_weight: float = 1.0
	if session.tool_phase=="reach":
		pose_weight = clampf((progress-.75)/.25,0,1)
		position = setting.position.lerp(operating,pose_weight)
	elif session.tool_phase=="return":
		pose_weight = 1-clampf(progress/.75,0,1)
		position = operating.lerp(setting.position,1-pose_weight)
	return {"position":position,"yaw":lerp_angle(float(setting.yaw),_operation_yaw(session),pose_weight),
		"pitch":lerpf(float(setting.get("pitch",0)),0.0,pose_weight)}

func _update_tools(session: Dictionary) -> void:
	_reset_tools(session)
	if session.phase not in ["cut","sew"]: return
	var kind: String = "scissors" if session.phase=="cut" else "needle"
	var setting: Dictionary = config.tools[kind]
	var tool: Dictionary = objects[setting.id]
	var progress: float = _tool_progress(session)
	var held: bool = session.tool_phase=="operate" or (session.tool_phase=="reach" and progress>=.75) or (session.tool_phase=="return" and progress<.75)
	var transform: Dictionary = _tool_pose(session)
	tool.position = transform.position;tool.yaw = transform.yaw;tool.pitch = transform.pitch
	if held:
		tool.holder = session.maker;tool.container = "";tool.state = "held"

func _route(person: Dictionary, target: Vector3, spot: String) -> void:
	person.target = target;person.destination = config.site;person.activity_spot = spot
	person.path = sim.route(person.position,person.place,target,config.site)
	person.moving = not person.path.is_empty()
	if not person.moving: person.place = config.site

func _arrived(person: Dictionary, target: Vector3) -> bool:
	return not person.moving and person.position.distance_to(target)<.03

func _all_at_table(session: Dictionary) -> bool:
	for id in [session.a,session.b]:
		if not _arrived(sim.person(id),session.targets[id].position): return false
	return true

func _distance(person: Dictionary) -> float:
	var distance: float = 0.0;var point: Vector3 = person.position
	for next in person.path:
		distance += point.distance_to(next);point = next
	return distance

func _phase(session: Dictionary, phase: String) -> void:
	session.phase = phase;session.phase_started = int(sim.elapsed)
	var item: Dictionary = objects[session.object_id]
	session.phase_object_position = item.position;session.phase_object_yaw = float(item.yaw);session.phase_carry_yaw = float(session.carry_yaw)
	_reset_tools(session)
	_tool_phase(session,"reach" if phase in ["cut","sew"] else "none")

func _progress(session: Dictionary, visual: bool = false) -> float:
	if session.phase in ["to_source","carry_to_table","carry_to_store"]:
		return clampf(1-_distance(sim.person(session.maker))/maxf(.001,float(session.travel_distance)),0,1)
	var item: Dictionary = objects[session.object_id]
	var work_fraction: float = float(sim.minute_remainder) if visual and session.tool_phase=="operate" else 0.0
	if session.phase=="cut": return clampf((float(item.cut_minutes)+work_fraction)/float(config.cut_minutes),0,1)
	if session.phase=="sew": return clampf((float(item.sew_minutes)+work_fraction)/float(config.sew_minutes),0,1)
	var duration: float = float(config.phase_minutes.get(session.phase,1))
	var fraction: float = float(sim.minute_remainder) if visual else 0.0
	return clampf((float(sim.elapsed)-float(session.phase_started)+fraction)/duration,0,1)

func pose_for(resident_id: String) -> Dictionary:
	for session in sessions.values():
		if session.phase not in ACTIVE or resident_id not in [session.a,session.b]: continue
		var item: Dictionary = objects[session.object_id]
		var tools: Dictionary = {}
		for kind in config.tools: tools[kind] = objects[config.tools[kind].id].duplicate(true)
		if session.phase in ["cut","sew"] and session.tool_phase in ["reach","return"]:
			var active_tool_kind: String = "scissors" if session.phase=="cut" else "needle"
			var transform: Dictionary = _tool_pose(session,true)
			for key in ["position","yaw","pitch"]: tools[active_tool_kind][key] = transform[key]
		return {"key":"sewing","id":session.id,"phase":session.phase,"phase_progress":_progress(session,true),
			"role":"maker" if resident_id==session.maker else "viewer","maker":session.maker,"viewer":session.viewer,
			"object_id":item.id,"object_position":item.position,"object_yaw":item.yaw,"holder":item.holder,"item_stage":item.stage,
			"carry":item.holder==resident_id,"carry_yaw":session.carry_yaw,"show_yaw":session.show_yaw,
			"source_position":session.source_position,"source_approach":session.source_approach,"target_position":config.target_position,
			"tool_phase":session.tool_phase,"tool_progress":_tool_progress(session,true),
			"stage_progress":_progress(session,true) if session.phase in ["cut","sew"] else float(item.sew_minutes)/float(config.sew_minutes),
			"tools":tools,"material_used":item.material_used,"result_recorded":item.result_recorded}
	return {}

func _trim() -> void:
	while sessions.size()>HISTORY_LIMIT:
		var oldest: String = ""
		for id in sessions:
			if sessions[id].phase in ACTIVE: continue
			if oldest.is_empty() or int(sessions[id].finished)<int(sessions[oldest].finished) or (sessions[id].finished==sessions[oldest].finished and str(id)<oldest): oldest = id
		if oldest.is_empty(): break
		sessions.erase(oldest)

func serialize() -> Dictionary:
	return {"version":1,"serial":serial,"objects":objects.duplicate(true),"sessions":sessions.duplicate(true)}

func restore(data: Dictionary) -> void:
	serial = int(data.serial);objects = data.objects.duplicate(true);sessions = data.sessions.duplicate(true)
	for item in objects.values():
		for key in ["ordinal","cut_minutes","sew_minutes"]: item[key] = int(item[key])
	for session in sessions.values():
		for key in ["started","phase_started","finished","cut_at_start","sew_at_start","worked_minutes","required_work","tool_started"]: session[key] = int(session[key])

static func valid_save(data: Variant, raw: Dictionary, definitions: Dictionary) -> bool:
	return _valid_save(data,raw,definitions)

static func _valid_save(data: Variant, raw: Dictionary, definitions: Dictionary) -> bool:
	# Validation works on the encoded JSON, before the live town or its RNG is changed.
	if not raw.get("people") is Array or not raw.get("meetings") is Array or not _whole(raw.get("elapsed")): return false
	if not data is Dictionary or data.get("version")!=1 or not _whole(data.get("serial")): return false
	if not data.get("objects") is Dictionary or data.objects.size()!=9 or not data.get("sessions") is Dictionary or data.sessions.size()>HISTORY_LIMIT: return false
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	var meetings: Dictionary = {};var people: Dictionary = {}
	for meeting in raw.meetings:
		if not _record(meeting,["id","a","b"],["remaining"]) or meetings.has(meeting.id): return false
		if meeting.has("project"):
			if not meeting.project is Dictionary: return false
			if meeting.project.has("key") and not meeting.project.key is String: return false
		meetings[meeting.id] = meeting
	for person in raw.people:
		if not _record(person,["id","meeting_id"],["age"]) or not _whole(person.age) or people.has(person.id): return false
		people[person.id] = person
	var active: Dictionary = {}
	for id in data.sessions:
		var session = data.sessions[id]
		if not id is String or not _record(session,["id","meeting","recipe","a","b","maker","viewer","object_id","phase","reason"],["started","phase_started","finished","cut_at_start","sew_at_start","worked_minutes","required_work","carry_yaw","show_yaw","travel_distance","phase_object_yaw","phase_carry_yaw"]): return false
		if session.id!=id or not id.begins_with("sewing_"): return false
		var suffix: String = id.trim_prefix("sewing_")
		if not suffix.is_valid_int() or suffix.length()>9 or int(suffix)<1 or int(suffix)>data.serial or str(int(suffix))!=suffix or session.recipe!=rules.recipe: return false
		if not definitions.has(session.a) or not definitions.has(session.b) or not people.has(session.a) or not people.has(session.b) or session.a==session.b or session.maker not in [session.a,session.b] or session.viewer not in [session.a,session.b] or session.viewer==session.maker: return false
		if int(people[session.maker].age)<int(rules.minimum_maker_age) or session.phase not in PHASES or session.object_id not in ["sewing_cloth_01","sewing_cloth_02","sewing_cloth_03","sewing_cloth_04","sewing_cloth_05","sewing_cloth_06"]: return false
		if not _encoded_position(session.get("source_position")) or not _encoded_position(session.get("phase_object_position")) or not session.get("shown") is bool or not session.get("resume_finished") is bool or not _encoded_position(session.get("source_approach")): return false
		if session.get("tool_phase") not in ["none","reach","operate","return"] or not _whole(session.get("tool_started")) or session.tool_started>raw.elapsed: return false
		if (session.phase in ["cut","sew"])!=(session.tool_phase!="none") or session.tool_started<session.phase_started: return false
		var material_ordinal: int = int(session.object_id.right(2))
		var expected_source: Vector3 = _vector(rules.storage_slots[material_ordinal-1])
		if _encoded_vector(session.source_position).distance_to(expected_source)>.001 or _encoded_vector(session.source_approach).distance_to(Vector3(expected_source.x,0,rules.source_approach[2]))>.001: return false
		for field in ["started","phase_started","cut_at_start","sew_at_start","worked_minutes","required_work"]:
			if not _whole(session[field]): return false
		if session.started>session.phase_started or session.phase_started>raw.elapsed or session.travel_distance<0: return false
		if session.resume_finished!=(session.cut_at_start==rules.cut_minutes and session.sew_at_start==rules.sew_minutes): return false
		if session.cut_at_start>rules.cut_minutes or session.sew_at_start>rules.sew_minutes or session.required_work!=rules.cut_minutes+rules.sew_minutes-session.cut_at_start-session.sew_at_start or session.worked_minutes>session.required_work: return false
		if not session.get("targets") is Dictionary or session.targets.size()!=2: return false
		var assigned: Array = []
		for person_id in [session.a,session.b]:
			var target = session.targets.get(person_id)
			if not _record(target,["spot"],[]) or not rules.slots.has(target.spot) or target.spot in assigned or not _encoded_position(target.get("position")): return false
			if _encoded_vector(target.position).distance_to(_vector(rules.slots[target.spot]))>.001: return false
			assigned.append(target.spot)
		if session.phase in ACTIVE:
			if not active.is_empty() or session.finished!=-1 or not meetings.has(session.meeting): return false
			active = session
			var meeting: Dictionary = meetings[session.meeting]
			if meeting.get("sewing_id","")!=id or meeting.get("project",{}).get("key","")!="craft" or meeting.a!=session.a or meeting.b!=session.b: return false
			for person_id in [session.a,session.b]:
				if not people[person_id].get("alive",true) or people[person_id].meeting_id!=session.meeting or people[person_id].get("activity_spot","")!=session.targets[person_id].spot: return false
		else:
			if not _whole(session.finished) or session.finished<session.started or session.finished>raw.elapsed: return false
			if session.phase=="completed" and not session.shown: return false
	for ordinal in range(1,int(rules.piece_count)+1):
		var id: String = "sewing_cloth_%02d"%ordinal
		var item = data.objects.get(id)
		if not _valid_object(item,definitions) or item.id!=id or item.ordinal!=ordinal or item.stage not in STAGES or item.kind!=("pouch" if item.stage=="finished" else "fabric"): return false
		if item.cut_minutes>rules.cut_minutes or item.sew_minutes>rules.sew_minutes or (item.sew_minutes>0 and item.cut_minutes!=rules.cut_minutes): return false
		if item.material_used!=(item.cut_minutes>0) or item.result_recorded!=(item.cut_minutes==rules.cut_minutes and item.sew_minutes==rules.sew_minutes): return false
		if (item.stage=="fabric")!=(not bool(item.material_used)) or (item.stage=="finished")!=item.result_recorded: return false
		if absf(float(item.pitch))>.0001: return false
		if item.material_used and not definitions.has(item.owner): return false
		if not item.material_used and (item.owner!="town" or not item.shown_to.is_empty()): return false
		if not item.result_recorded and not item.shown_to.is_empty(): return false
		if not _valid_location(item,active): return false
		if item.reserved_by.is_empty():
			var expected: Vector3 = _vector(rules.storage_slots[ordinal-1])
			if item.container!=("sewing_storage" if item.material_used else "sewing_stock") or item.state!="stored" or _encoded_vector(item.position).distance_to(expected)>.001: return false
	for kind in rules.tools:
		var setting: Dictionary = rules.tools[kind]
		var tool = data.objects.get(setting.id)
		if not _valid_object(tool,definitions) or tool.id!=setting.id or tool.kind!=kind or tool.stage!="tool" or tool.owner!="town" or tool.ordinal!=0 or tool.material_used or tool.result_recorded or tool.cut_minutes!=0 or tool.sew_minutes!=0 or not tool.shown_to.is_empty(): return false
		if not _valid_location(tool,active): return false
		if not _valid_tool(tool,kind,setting,active,data.objects,rules,raw.elapsed): return false
	if not active.is_empty():
		var item: Dictionary = data.objects[active.object_id]
		var meeting: Dictionary = meetings[active.meeting]
		for flag in ["work_completed","project_result_recorded","materials_ready","sewing_presented","sewing_resume_finished"]:
			if not meeting.get(flag) is bool: return false
		if bool(meeting.sewing_resume_finished)!=bool(active.resume_finished): return false
		if item.reserved_by!=active.id or active.worked_minutes!=item.cut_minutes+item.sew_minutes-active.cut_at_start-active.sew_at_start: return false
		if not _whole(meeting.remaining) or meeting.remaining!=active.required_work-active.worked_minutes: return false
		if bool(meeting.get("work_completed",false))!=bool(item.result_recorded) or bool(meeting.get("project_result_recorded",false))!=bool(item.result_recorded) or bool(meeting.get("materials_ready",false))!=bool(item.material_used): return false
		if item.material_used and item.owner!=active.maker: return false
		if not _valid_active_piece(item,active,rules,raw.elapsed): return false
		if active.shown!=(active.viewer in item.shown_to) or bool(meeting.get("sewing_presented",false))!=bool(active.shown): return false
		for setting in rules.tools.values():
			if data.objects[setting.id].reserved_by!=active.id: return false
	for meeting in raw.meetings:
		if meeting.get("project",{}).get("key","")!="craft": continue
		if active.is_empty() or meeting.get("sewing_id","")!=active.id or meeting.id!=active.meeting: return false
	return true

static func _valid_object(value: Variant, definitions: Dictionary) -> bool:
	if not _record(value,["id","kind","owner","holder","container","reserved_by","state","stage"],["ordinal","yaw","pitch","cut_minutes","sew_minutes"]): return false
	if not _encoded_position(value.get("position")) or not _whole(value.ordinal) or not _whole(value.cut_minutes) or not _whole(value.sew_minutes): return false
	if not value.get("material_used") is bool or not value.get("result_recorded") is bool or not _strings(value.get("shown_to"),definitions.size()): return false
	var seen: Dictionary = {}
	for id in value.shown_to:
		if not definitions.has(id) or seen.has(id) or id==value.owner: return false
		seen[id] = true
	if not value.holder.is_empty() and not definitions.has(value.holder): return false
	return value.state in ["stored","held","on_table"] and value.container in ["","sewing_stock","sewing_storage","sewing_table"]

static func _valid_location(item: Dictionary, active: Dictionary) -> bool:
	if item.reserved_by.is_empty(): return item.holder.is_empty()
	if active.is_empty() or item.reserved_by!=active.id: return false
	if item.kind in ["fabric","pouch"] and item.id!=active.object_id: return false
	if not item.holder.is_empty() and item.holder!=active.maker: return false
	return (item.state=="held")==(not item.holder.is_empty()) and (item.state=="held")==(item.container.is_empty())

static func _encoded_vector(value: Dictionary) -> Vector3:
	return _vector(value.__vector3)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _whole(value: Variant, minimum: int = 0) -> bool:
	return _number(value) and value>=minimum and value<=1000000000 and value==int(value)

static func _record(value: Variant, text_keys: Array, numeric_keys: Array) -> bool:
	if not value is Dictionary: return false
	for key in text_keys:
		if not value.get(key) is String: return false
	for key in numeric_keys:
		if not _number(value.get(key)): return false
	return true

static func _strings(value: Variant, limit: int) -> bool:
	if not value is Array or value.size()>limit: return false
	for item in value:
		if not item is String or item.is_empty(): return false
	return true

static func _encoded_position(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=1 or not value.get("__vector3") is Array or value.__vector3.size()!=3: return false
	for coordinate in value.__vector3:
		if not _number(coordinate) or absf(float(coordinate))>1000: return false
	return true

static func _valid_active_piece(item: Dictionary, session: Dictionary, rules: Dictionary, elapsed: float) -> bool:
	var phase: String = session.phase
	var progress: float = clampf((elapsed-float(session.phase_started))/float(rules.phase_minutes.get(phase,1)),0,1)
	var held: bool = phase in ["carry_to_table","show","carry_to_store"] or (phase in ["take","lift_show","take_store"] and progress>=.3) or (phase in ["place","lower","store"] and progress<.75)
	var on_table: bool = phase in ["cut","sew"] or (phase=="place" and progress>=.75) or (phase=="lift_show" and progress<.3) or (phase=="lower" and progress>=.75) or (phase=="take_store" and progress<.3)
	var expected_container: String = "" if held else ("sewing_table" if on_table else ("sewing_storage" if item.material_used else "sewing_stock"))
	if item.holder!=(session.maker if held else "") or item.state!=("held" if held else ("on_table" if on_table else "stored")) or item.container!=expected_container: return false
	var position: Vector3 = _encoded_vector(item.position)
	if phase in ["cut","sew"] and position.distance_to(_vector(rules.target_position))>.001: return false
	if phase=="to_source" and position.distance_to(_encoded_vector(session.source_position))>.001: return false
	if phase in ["lift_show","show","lower","take_store","carry_to_store","store"] and not item.result_recorded: return false
	if phase=="sew" and item.cut_minutes!=rules.cut_minutes: return false
	if phase=="cut" and item.sew_minutes!=0: return false
	return true

static func _valid_tool(tool: Dictionary, kind: String, setting: Dictionary, session: Dictionary, _objects_data: Dictionary, rules: Dictionary, elapsed: float) -> bool:
	var expected_position: Vector3 = _vector(setting.position)
	var held: bool = false
	var maker: String = ""
	var expected_yaw: float = float(setting.yaw)
	var expected_pitch: float = float(setting.get("pitch",0))
	if not session.is_empty() and session.phase in ["cut","sew"] and kind==("scissors" if session.phase=="cut" else "needle"):
		maker = session.maker
		var operation_yaw: float = float(rules.tool_operation_yaws.needle)
		var offset: Vector3 = _vector(rules.tool_operation_offsets[kind])
		if session.phase=="cut":
			operation_yaw = -PI*.5 if _encoded_vector(session.targets[session.maker].position).x<float(rules.target_position[0]) else PI*.5
			offset.x = absf(offset.x)*(-1.0 if operation_yaw<0 else 1.0)
		var operating: Vector3 = _vector(rules.target_position)+offset
		var duration: float = float(rules.tool_minutes.get(session.tool_phase,4))
		var progress: float = clampf((elapsed-float(session.tool_started))/duration,0,1)
		held = session.tool_phase=="operate" or (session.tool_phase=="reach" and progress>=.75) or (session.tool_phase=="return" and progress<.75)
		if session.tool_phase=="reach": expected_position = expected_position.lerp(operating,clampf((progress-.75)/.25,0,1))
		elif session.tool_phase=="return": expected_position = operating.lerp(expected_position,clampf(progress/.75,0,1))
		else: expected_position = operating
		var pose_weight: float = 1.0
		if session.tool_phase=="reach": pose_weight = clampf((progress-.75)/.25,0,1)
		elif session.tool_phase=="return": pose_weight = 1-clampf(progress/.75,0,1)
		expected_yaw = lerp_angle(float(setting.yaw),operation_yaw,pose_weight)
		expected_pitch = lerpf(float(setting.get("pitch",0)),0.0,pose_weight)
	if tool.holder!=(maker if held else "") or tool.container!=("" if held else "sewing_table") or tool.state!=("held" if held else "on_table"): return false
	return _encoded_vector(tool.position).distance_to(expected_position)<.001 and absf(wrapf(float(tool.yaw)-expected_yaw,-PI,PI))<.001 and absf(float(tool.pitch)-expected_pitch)<.001
