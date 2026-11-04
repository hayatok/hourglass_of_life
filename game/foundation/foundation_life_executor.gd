class_name FoundationLifeExecutor
extends RefCounted

# Connects life intentions to actual bodies and the actual house. This is an
# integration layer, not a second simulation clock or a visual position follower.
var home: LivingHouse
var life: HouseholdDay
var occupancy: HomeOccupancy
var navigation: HomeNavigation
var actors: Dictionary = {}
var execution: Dictionary = {}
var doors_in_use: Dictionary = {}
var furniture: Dictionary = {}
var _fixtures: Dictionary = {}
var _room_bounds: Dictionary = {}
var _retry_elapsed := 0.0
var _decision_minutes := 0.0
var _render_contacts: Dictionary = {}
const BODY_RADIUS := .24
const MAX_STEP := 1.0/30.0

func configure(house: LivingHouse, household: HouseholdDay, room_occupancy: HomeOccupancy, paths: HomeNavigation, residents: Dictionary) -> bool:
	if house==null or household==null or room_occupancy==null or paths==null or residents.size()!=household.people.size():return false
	home=house;life=household;occupancy=room_occupancy;navigation=paths;actors=residents
	for id in life.people:
		if not actors.get(id) is FoundationResident or not actors[id].motion_ready:return false
	for item in home.definition.fixtures:_fixtures[item.id]=item
	for room in home.definition.rooms+home.definition.external_zones:
		var b: Array=room.bounds;_room_bounds[room.id]=Rect2(b[0],b[1],b[2],b[3])
	for id in actors:
		var use:=FoundationFurnitureUse.new()
		if not use.configure(home,navigation,occupancy,actors[id]):return false
		furniture[id]=use
		execution[id]={"task":"","phase":-1,"state":"choose","reason":"","retry":0.0,"door":"","target":[0,0,0],"offsite":false,"current_room":room_at(actors[id].global_position)}
		life.set_position(id,actors[id].global_position)
		var room:=room_at(actors[id].global_position)
		if not room.is_empty():occupancy.reserve_room(room,id)
	return true

func room_at(point: Vector3) -> String:
	for id in _room_bounds:
		var bounds: Rect2=_room_bounds[id]
		if bounds.has_point(Vector2(point.x,point.z)):return id
	return ""

func step(seconds: float, minutes: float) -> bool:
	if not is_finite(seconds) or not is_finite(minutes) or seconds<0 or seconds>1 or minutes<0 or minutes>1:return false
	if seconds==0:return minutes==0
	_render_contacts.clear()
	for id in actors:_render_contacts[id]=actors[id].furniture_contacts_ready()
	var steps: int=maxi(1,int(ceil(seconds/MAX_STEP)))
	for ignored in steps:
		var delta: float=seconds/steps
		var clock_delta: float=minutes/steps
		life.advance_time(clock_delta)
		_decision_minutes+=clock_delta
		if _decision_minutes>=1:
			_decision_minutes=fmod(_decision_minutes,1)
			for id in actors:life.request(id)
		for id in actors:_step_actor(id,delta,clock_delta)
		_update_private_use(delta)
	return true

func _update_private_use(delta: float) -> void:
	for id in actors:
		var task: Dictionary=life.task_for(id)
		var private_use: bool=execution[id].state=="use" and (task.get("kind")=="toilet" or task.get("room")=="bathroom" or task.get("fixture")=="changing_space")
		# Private routines are shown through room/door occupancy and before/after
		# activity. They do not expose bodies when the camera cuts a wall away.
		actors[id].model.visible=not private_use
		for label in actors[id].find_children("*","Label3D",true,false):label.visible=not private_use
		if not private_use:continue
		for key in home.doors:
			var door: Dictionary=home.doors[key]
			if door.definition.kind=="opening" or task.room not in [door.definition.room_a,door.definition.room_b]:continue
			if doors_in_use.get(key,id)!=id:continue
			home.set_door_fraction(key,maxf(0,float(door.get("open_fraction",0))-delta/.6))

func _step_actor(id: String, delta: float, minutes: float) -> void:
	var actor: FoundationResident=actors[id]
	var entry: Dictionary=execution[id]
	entry.retry=maxf(0,float(entry.retry)-delta)
	var task: Dictionary=life.task_for(id)
	var use: FoundationFurnitureUse=furniture[id]
	if use.active():
		_step_furniture(id,task,delta,minutes)
		return
	actor.model.sleeping=false
	if task.is_empty():
		if actor.state()!="idle":actor.stop();actor.tick_body(delta);return
		if entry.retry>0:actor.tick_body(delta);return
		var reply: Dictionary=life.request(id)
		task=reply.task
		if task.is_empty():entry.state="wait";entry.reason=reply.reason;entry.retry=1;actor.tick_body(delta);return
	if entry.task!=task.id or int(entry.phase)!=int(task.phase_index):
		actor.clear_action();actor.stop()
		_release_doors(id)
		entry.task=task.id;entry.phase=task.phase_index;entry.state="plan";entry.reason="";entry.retry=0
		entry.target=[task.target.x,task.target.y,task.target.z]
	if task.status in ["completed","cancelled"]:
		entry.state="choose";entry.task="";actor.clear_action();_release_doors(id);actor.tick_body(delta);return
	match str(entry.state):
		"plan","wait":
			if not actor.body_is_settled():actor.tick_body(delta);return
			if entry.retry<=0:_plan(id,task)
		"walk":
			if not _prepare_door(id,delta):actor.stop();entry.state="door"
			elif _collision_ahead(id,delta):actor.stop();entry.state="yield";entry.reason="通路を譲っている"
			actor.tick_body(delta)
			life.set_position(id,actor.global_position)
			_sync_room(id)
			_release_passed_doors(id)
			if entry.state=="walk" and actor.state()=="idle":_align(id,task)
		"yield":
			actor.tick_body(delta);life.set_position(id,actor.global_position);_sync_room(id)
			if actor.state()=="idle":entry.state="wait";entry.retry=.6
		"door":
			actor.tick_body(delta);life.set_position(id,actor.global_position);_sync_room(id)
			if _prepare_door(id,delta) and actor.state()=="idle":entry.state="plan"
		"align":
			actor.tick_body(delta)
			if actor.body_is_settled():
				var reply: Dictionary=life.arrive(id,task.id)
				if reply.status=="entering":
					if use.begin(task,_obstacles(id)):entry.state="enter";entry.reason="家具を使う支度をしている"
					else:entry.state="wait";entry.reason=use.reason;entry.retry=.5
				elif reply.status=="arrived":entry.state="use";entry.reason="";actor.play_action(_motion_for(task))
				elif reply.status=="phase_ready":_finish_phase(id,task.id)
				elif reply.status=="redirected":entry.state="plan"
				else:entry.state="wait";entry.reason=reply.reason;entry.retry=1
		"settle":
			actor.tick_body(delta)
			if actor.body_is_settled():_align(id,task)
		"use":
			actor.tick_body(delta)
			life.set_position(id,actor.global_position)
			var reply: Dictionary=life.perform(id,task.id,minutes)
			if reply.status=="phase_ready":
				_finish_phase(id,task.id)
			elif reply.status in ["blocked","occupied","not_arrived"]:
				actor.clear_action();entry.state="wait";entry.reason=reply.reason;entry.retry=1
	# Offsite work and school are explicit boundary abstractions in this first
	# house; they are not presented as simulated shop/school interiors.
	if task.room=="outside" and task.kind in ["work","school","shop","wait_outside"] and entry.state=="use":
		actor.visible=false;entry.offsite=true

func _step_furniture(id: String, task: Dictionary, delta: float, minutes: float) -> void:
	var actor: FoundationResident=actors[id]
	var entry: Dictionary=execution[id]
	var use: FoundationFurnitureUse=furniture[id]
	# The previous rendered pose is observed before submitting the next request;
	# a newly requested but unapplied SkeletonModifier pose is never evidence.
	var contact_ready: bool=use.ready() and bool(_render_contacts.get(id,false))
	var task_id: String=use.session.task
	if task.is_empty() or task.get("id")!=task_id or task.get("status")=="exiting":
		use.begin_exit();entry.state="exit"
	if actor.state() in ["start","walk","stop"] and _collision_ahead(id,delta):actor.stop()
	if not use.advance(delta,_obstacles(id)):
		entry.reason="家具との動作を続けられない";return
	actor.model.sleeping=task.get("kind")=="sleep" and use.active() and use.session.phase in ["lie_down","ready"] and not use.session.leaving
	life.set_position(id,actor.global_position);_sync_room(id)
	if use.exit_ready():
		var ended: Dictionary=life.end_use(id,task_id,actor.global_position)
		if ended.status=="phase_ready":use.finalize_exit();_finish_phase(id,task_id)
		elif ended.status=="cancelled":use.finalize_exit();entry.state="choose";entry.task=""
		else:entry.state="exit";entry.reason=ended.reason;entry.retry=.5
		return
	if use.session.leaving:entry.state="exit";return
	if not use.ready():entry.state="enter";entry.reason=use.reason;return
	if task.get("status")=="entering":
		if not contact_ready:return
		var began: Dictionary=life.begin_use(id,task_id,actor.global_position,use.posture())
		if began.status!="arrived":entry.reason=began.reason;return
		entry.state="use";entry.reason=""
		return # Entering time is not backfilled as food, sleep or project work.
	if task.get("status") in ["arrived","working"]:
		entry.state="use"
		if not contact_ready:entry.reason="姿勢と家具の接触を整えている";return
		var worked: Dictionary=life.perform(id,task_id,minutes)
		if worked.status=="phase_ready":
			life.begin_exit(id,task_id);use.begin_exit();entry.state="exit"
		elif worked.status in ["blocked","occupied","not_arrived","not_in_usage"]:
			life.cancel(id,task_id,worked.reason);use.begin_exit();entry.state="exit"
	elif task.get("status")=="phase_ready":
		life.begin_exit(id,task_id);use.begin_exit();entry.state="exit"

func _finish_phase(id: String, task_id: String) -> void:
	var finished: Dictionary=life.finish(id,task_id)
	_sync_room(id);actors[id].clear_action();_release_doors(id)
	execution[id].state="plan" if finished.status=="next_phase" else "choose"
	if finished.status=="completed":execution[id].task=""

func _obstacles(id: String) -> Array:
	var result: Array=[]
	for other in actors:
		if other!=id and actors[other].visible:
			var at: Vector3=actors[other].global_position;at.y=0
			result.append({"position":at,"radius":BODY_RADIUS})
		if other!=id and furniture.has(other):
			var workspace: Dictionary=furniture[other].workspace()
			if not workspace.is_empty():result.append(workspace)
	return result

func _plan(id: String, task: Dictionary) -> void:
	var actor: FoundationResident=actors[id]
	var entry: Dictionary=execution[id]
	if entry.offsite:
		if task.room=="outside" and actor.global_position.distance_to(task.target)<.18:
			_align(id,task);return
		for other in actors:
			if other!=id and actors[other].visible and actors[other].global_position.distance_to(actor.global_position)<BODY_RADIUS*2+.12:
				entry.state="wait";entry.reason="玄関前が空くのを待っている";entry.retry=.5;return
	var route: Dictionary=navigation.route(actor.global_position,task.target,id,occupancy,_obstacles(id))
	if route.status!="ready":entry.state="wait";entry.reason=route.reason;entry.retry=1;return
	entry.doors=route.doors;entry.state="walk";entry.reason="移動中"
	actor.visible=true;entry.offsite=false
	if route.points.is_empty():_align(id,task)
	elif not actor.follow_path(route.points):entry.state="wait";entry.reason="経路を開始できない";entry.retry=1

func _align(id: String, task: Dictionary) -> void:
	var actor: FoundationResident=actors[id]
	if not actor.body_is_settled():execution[id].state="settle";return
	var heading: float=actor.heading
	if _fixtures.has(task.fixture):
		var fixture: Dictionary=_fixtures[task.fixture]
		heading=deg_to_rad(float(fixture.get("use_facing",fixture.facing)))
	if actor.face_heading(heading):execution[id].state="align"

func _sync_room(id: String) -> void:
	var room:=room_at(actors[id].global_position)
	if room.is_empty():return
	var reply: Dictionary=occupancy.reserve_room(room,id)
	if reply.status!="ready":return
	var entry: Dictionary=execution[id]
	var prior: String=entry.current_room
	if prior!=room:
		for key in entry.get("doors",[]).duplicate():
			var definition: Dictionary=home.doors[key].definition
			if prior in [definition.room_a,definition.room_b] and room in [definition.room_a,definition.room_b]:entry.doors.erase(key)
	entry.current_room=room

func _motion_for(task: Dictionary) -> String:
	# Actual household-specific hand/tool motion and seat entry are subsequent
	# adapter work. Idle makes this integration gap explicit, not old FK work.
	return "talk" if task.kind=="care" else "idle"

func _prepare_door(id: String, delta: float) -> bool:
	var entry: Dictionary=execution[id]
	var actor: FoundationResident=actors[id]
	for key in entry.get("doors",[]):
		var door: Dictionary=home.doors[key]
		if door.definition.kind=="opening":continue
		var center: Vector3=LivingHousePoint(door.definition.center)
		if actor.global_position.distance_to(center)>1.35:continue
		var origin: String=entry.current_room
		if origin not in [door.definition.room_a,door.definition.room_b]:continue
		var destination: String=door.definition.room_b if origin==door.definition.room_a else door.definition.room_a
		if not occupancy.can_enter(destination,id):entry.reason="部屋を使う人が出るのを待っている";return false
		if doors_in_use.get(key,id)!=id:entry.reason="扉を通る人を待っている";return false
		doors_in_use[key]=id
		if not door.opened:
			var amount: float=minf(1,float(door.get("open_fraction",0))+delta/.6)
			home.set_door_fraction(key,amount);entry.reason="扉を開けている"
			if amount<1:return false
	return true

func _release_passed_doors(id: String) -> void:
	for key in doors_in_use.keys():
		if doors_in_use[key]!=id:continue
		var door: Dictionary=home.doors[key]
		var center: Vector3=LivingHousePoint(door.definition.center)
		if key not in execution[id].get("doors",[]) and actors[id].global_position.distance_to(center)>.5:doors_in_use.erase(key)

func _release_doors(id: String) -> void:
	for key in doors_in_use.keys():
		if doors_in_use[key]==id:doors_in_use.erase(key)

func _collision_ahead(id: String, delta: float) -> bool:
	var actor: FoundationResident=actors[id]
	var speed: float=actor.velocity.length()
	var direction: Vector3=actor.velocity.normalized()
	if speed<.001:return false
	var braking: float=speed*speed/(2*float(actor.snapshot().profile.deceleration))
	var segment: Vector3=direction*(braking+speed*delta+.14)
	for index in range(1,maxi(2,int(ceil(segment.length()/.05)))+1):
		var sample: Vector3=actor.global_position+segment*float(index)/float(maxi(2,int(ceil(segment.length()/.05))))
		var next_room:=room_at(sample)
		if not next_room.is_empty() and not occupancy.can_enter(next_room,id):return true
	for obstacle in _obstacles(id):
		var point: Vector3=obstacle.position-actor.global_position
		# Use exactly the same safe box as dynamic navigation. Stopping at a
		# circle boundary could leave two bodies inside each other's planning
		# boxes, unable to plan their next step despite not visually overlapping.
		var extent: float=BODY_RADIUS+float(obstacle.radius)+.06
		var low:=0.0;var high:=1.0;var intersects:=true
		for axis in [0,2]:
			if absf(segment[axis])<.00001:
				if absf(point[axis])>=extent:intersects=false;break
			else:
				var first: float=(point[axis]-extent)/segment[axis]
				var last: float=(point[axis]+extent)/segment[axis]
				low=maxf(low,minf(first,last));high=minf(high,maxf(first,last))
				if low>high:intersects=false;break
		if intersects:return true
	return false

static func LivingHousePoint(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func snapshot() -> Dictionary:
	var uses: Dictionary={}
	for id in furniture:uses[id]=furniture[id].snapshot()
	return {"schema":2,"execution":execution.duplicate(true),"doors_in_use":doors_in_use.duplicate(),"decision_minutes":_decision_minutes,"furniture":uses}

func can_restore(data: Variant, restored_life: HouseholdDay, body_states: Dictionary) -> bool:
	if not data is Dictionary or data.get("schema")!=2 or not data.get("execution") is Dictionary or not data.get("doors_in_use") is Dictionary or not data.get("furniture") is Dictionary or data.furniture.size()!=actors.size():return false
	if not (data.get("decision_minutes") is float or data.get("decision_minutes") is int) or not is_finite(float(data.decision_minutes)) or data.decision_minutes<0 or data.decision_minutes>=1:return false
	if data.execution.size()!=actors.size():return false
	for id in actors:
		if not furniture[id].can_restore(data.furniture.get(id)):return false
		var entry: Variant=data.execution.get(id)
		if not entry is Dictionary or entry.get("state") not in ["choose","plan","wait","walk","align","use","door","yield","settle","enter","exit"]:return false
		if not entry.get("task") is String or not entry.get("reason") is String or entry.reason.length()>512 or not entry.get("current_room") is String or not _room_bounds.has(entry.current_room):return false
		if not entry.task.is_empty() and (not restored_life.tasks.has(entry.task) or restored_life.tasks[entry.task].actor!=id):return false
		if not (entry.get("phase") is int or entry.get("phase") is float) or entry.phase!=int(entry.phase) or entry.phase< -1 or entry.phase>20:return false
		if not entry.get("offsite") is bool or not (entry.get("retry") is int or entry.get("retry") is float) or not is_finite(float(entry.retry)) or entry.retry<0 or entry.retry>10:return false
		if not entry.get("target") is Array or entry.target.size()!=3:return false
		for coordinate in entry.target:
			if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or absf(float(coordinate))>1000:return false
		if not entry.get("doors",[]) is Array or entry.get("doors",[]).size()>home.doors.size():return false
		for key in entry.get("doors",[]):
			if not key is String or not home.doors.has(key):return false
		if not body_states.get(id) is Dictionary or not body_states[id].get("motor") is Dictionary:return false
		if not furniture[id].can_restore_transaction(data.furniture[id],restored_life.task_for(id),entry,body_states[id]):return false
	for key in data.doors_in_use:
		if not home.doors.has(key) or not data.doors_in_use[key] is String or not actors.has(data.doors_in_use[key]):return false
	return true

func restore(data: Variant, restored_life: HouseholdDay, body_states: Dictionary) -> bool:
	if not can_restore(data,restored_life,body_states):return false
	execution=data.execution.duplicate(true);doors_in_use=data.doors_in_use.duplicate();_decision_minutes=float(data.decision_minutes)
	for id in furniture:furniture[id].restore(data.furniture[id])
	for id in actors:
		actors[id].visible=not execution[id].offsite
		var task: Dictionary=restored_life.task_for(id)
		var use: FoundationFurnitureUse=furniture[id]
		actors[id].model.sleeping=task.get("kind")=="sleep" and use.active() and use.session.phase in ["lie_down","ready"] and not use.session.leaving
	_update_private_use(0)
	return true
