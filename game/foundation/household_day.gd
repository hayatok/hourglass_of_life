class_name HouseholdDay
extends RefCounted

# Intentions are not effects. Only arrived, elapsed, explicitly performed work
# may consume supplies, relieve needs or produce household outcomes.
const RULES := "res://data/foundation/daily-life.json"
const NEEDS := ["hunger","fatigue","hygiene","bladder","quiet"]
const TERMINAL := ["completed","cancelled"]
const BATCH_KINDS := ["cook","serve","eat","wash_dishes","bath","shop","laundry","hang_laundry","fold_laundry"]
const USE_TYPES := ["chair","dining_seat","sofa","bed"]
var plan: Dictionary = {}
var rules: Dictionary = {}
var people: Dictionary = {}
var inventory: Dictionary = {}
var tasks: Dictionary = {}
var jobs: Dictionary = {}
var machines: Dictionary = {}
var results: Array = []
var elapsed: float = 0.0
var start_minute: int = 240
var weekday: int = 0
var cash: float = 35.0
var serial: int = 0
var occupancy
var family_history: FamilyHistory = FamilyHistory.new()
var _fixtures: Dictionary = {}
var _rooms: Dictionary = {}
var _resident_places: Dictionary = {}
var _claims: Dictionary = {}
var _supports: Dictionary = {}
var _support_containers: Dictionary = {}
var _usage_regions: Dictionary = {}

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES))
	if parsed is Dictionary:
		rules=parsed
		# A mandatory physical safety action, not a new authored daily preference.
		rules.actions.put_down={"label":"持っている物を安全な台へ置く","min_age":0,"phases":[{"name":"持っている物を置く","fixture":"prep","minutes":1}]}

func configure(home_plan: Dictionary, authored_people: Array = [], room_occupancy = null) -> bool:
	if rules.is_empty() or not home_plan.get("fixtures") is Array or not home_plan.get("residents") is Array: return false
	plan=home_plan.duplicate(true);occupancy=room_occupancy
	_fixtures.clear();_rooms.clear();_resident_places.clear();_supports.clear();_support_containers.clear();_usage_regions.clear()
	for item in plan.fixtures: _fixtures[item.id]=item.duplicate(true)
	for fixture in _fixtures:
		var support: Dictionary = _support_definition(fixture)
		if not support.is_empty(): _supports[fixture]=support.position;_support_containers[fixture]=support.container
		if _valid_region(_fixtures[fixture].get("usage_region")): _usage_regions[fixture]=_fixtures[fixture].usage_region.duplicate(true)
	for room in plan.get("rooms",[]): _rooms[room.id]=room.duplicate(true)
	for zone in plan.get("external_zones",[]):
		var room: Dictionary = zone.duplicate(true);room.private_scope="public";room.allowed_residents=[];_rooms[room.id]=room
	for resident in plan.residents: _resident_places[resident.id]=resident.duplicate(true)
	var source: Array = authored_people
	if source.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(rules.resident_source))
		if not parsed is Dictionary or not parsed.get("residents") is Array: return false
		source=parsed.residents
	people.clear();tasks.clear();jobs.clear();machines.clear();results.clear();_claims.clear()
	elapsed=0;serial=0;start_minute=int(rules.start_minute);weekday=int(rules.weekday);cash=float(rules.initial_cash)
	inventory=rules.initial_inventory.duplicate(true)
	inventory.washing_laundry=0;inventory.drying_laundry=0;inventory.dry_laundry=0
	for record in source:
		if not _resident_places.has(record.get("id","")): continue
		var id: String = record.id
		var p: Dictionary = {"id":id,"name":record.get("name",id),"age":int(record.get("age",record.get("age_years",30))),
			"skills":record.get("skills",{}).duplicate(true),"routines":record.get("routines",[]).duplicate(true),
			"position":_point(_fixtures[_resident_places[id].bed].interaction_point),"at_home":true,"return_after":0.0,"active_task":"",
			"care_invitation":{},"care_accepted":"","care_cooldown":0.0,"history":{"minutes":{},"completed":{},"last_finished":{}},"actual_minutes":{},"earned":0.0}
		for routine in p.routines:
			var days: Array = []
			for day in routine.on_days: days.append(int(day))
			routine.on_days=days
		for key in NEEDS: p[key]=float(record.get(key,rules.initial_needs[key]))
		if not family_history.attach(p,start_minute): return false
		people[id]=p
	return people.size()==_resident_places.size() and not people.is_empty()

func person(actor: String) -> Dictionary:
	return people.get(actor,{})

func minute_of_day() -> int:
	return posmod(start_minute+int(floor(elapsed)),1440)

func set_position(actor: String, position: Vector3) -> bool:
	if not people.has(actor) or not position.is_finite(): return false
	people[actor].position=position
	for job in jobs.values():
		if job.get("holder","")==actor: job.position=_carry_position(actor)
	return true

func batch_locations() -> Array:
	var rows: Array = []
	var keys: Array = jobs.keys();keys.sort()
	for key in keys:
		if int(jobs[key].quantity)>0: rows.append(batch_location(key))
	return rows

func batch_location(job_key: String) -> Dictionary:
	if not jobs.has(job_key) or int(jobs[job_key].quantity)<=0: return {}
	var row: Dictionary = jobs[job_key].duplicate(true)
	row.job_key=job_key
	return row

func _held_job(actor: String) -> String:
	for key in jobs:
		if int(jobs[key].quantity)>0 and jobs[key].get("holder","")==actor: return str(key)
	return ""

func _carry_position(actor: String) -> Vector3:
	# Coarse body-relative batch location; exact hand contacts are a render concern.
	return people[actor].position+Vector3(0,1,0)

func _surface_position(fixture: String, actor: String = "") -> Vector3:
	if fixture.begins_with("$"): return people[actor].position if people.has(actor) else Vector3.ZERO
	# Unknown support is never used for a positive batch: _requirement rejects
	# that action. Zero is only a harmless no-object fallback for qty0 records.
	return _supports.get(fixture,Vector3.ZERO)

func _support_definition(id: String, seen: Array = []) -> Dictionary:
	if id in seen or not _fixtures.has(id): return {}
	var visited: Array = seen.duplicate();visited.append(id)
	var fixture: Dictionary = _fixtures[id]
	if fixture.has("support_fixture"):
		if not fixture.support_fixture is String: return {}
		return _support_definition(fixture.support_fixture,visited)
	var authored: Variant = fixture.get("support_point")
	if authored!=null:
		if not authored is Array or authored.size()!=3: return {}
		for value in authored:
			if not _number(value,-1000,1000): return {}
		return {"position":_point(authored),"container":id}
	if fixture.has("serves"):
		var table: Dictionary = _fixtures.get(fixture.serves,{})
		if table.get("type","") in ["prep","dining_table","desk"]: return _support_definition(fixture.serves,visited)
	# These simple solids have a real authored horizontal top. Tall storage,
	# racks, tubs, seats and appliances do not imply a shelf at an invented y.
	if fixture.get("type","") not in ["prep","dining_table","desk"]: return {}
	if not fixture.get("position") is Array or fixture.position.size()!=3 or not fixture.get("size") is Array or fixture.size.size()!=3: return {}
	for value in fixture.position+fixture.size:
		if not _number(value,-1000,1000): return {}
	var position: Vector3 = _point(fixture.position)
	position.y+=float(fixture.size[1])
	return {"position":position,"container":id}

func _batch_container(fixture: String) -> String:
	return str(_support_containers.get(fixture,fixture))

func _requires_usage(fixture: String) -> bool:
	return _fixtures.get(fixture,{}).get("type","") in USE_TYPES

func _inside_usage(fixture: String, position: Vector3) -> bool:
	if not _usage_regions.has(fixture) or not position.is_finite(): return false
	var region: Dictionary = _usage_regions[fixture]
	var offset: Vector3 = (position-_point(region.center)).abs()
	var half: Vector3 = _point(region.half_extents)
	return offset.x<=half.x and offset.y<=half.y and offset.z<=half.z

func _claim_held(actor: String, task: Dictionary) -> bool:
	if _claims.get(actor,"")!=task.fixture: return false
	if occupancy==null: return true
	var state: Dictionary = occupancy.snapshot()
	return actor in state.get("fixture_users",{}).get(task.fixture,[]) and actor in state.get("room_users",{}).get(task.room,[]) and _status(actor,task.fixture,task.room).status=="ready"

static func _valid_region(value: Variant) -> bool:
	if not value is Dictionary: return false
	for field in ["center","half_extents"]:
		if not value.get(field) is Array or value[field].size()!=3: return false
		for number in value[field]:
			if not _number(number,.000001 if field=="half_extents" else -1000,3 if field=="half_extents" else 1000): return false
	if not value.get("postures") is Array or value.postures.is_empty() or value.postures.size()>2: return false
	for posture in value.postures:
		if posture not in ["sit","lie"]: return false
	return true

func _safe_fixture(actor: String, job: Dictionary) -> String:
	var best: String = ""
	var distance: float = INF
	var options: Array = _fixtures.keys();options.sort()
	for id in options:
		var allowed: Variant = _fixtures[id].get("put_down_kinds",[])
		if not allowed is Array or str(job.kind) not in allowed or not _supports.has(id) or _status(actor,id,_fixtures[id].room).status!="ready": continue
		var value: float = people[actor].position.distance_squared_to(_point(_fixtures[id].interaction_point))
		if value<distance: distance=value;best=str(id)
	return best

func _take_batch(job_key: String, actor: String) -> void:
	var job: Dictionary = jobs[job_key]
	if int(job.quantity)<=0: return
	job.container="";job.holder=actor;job.reserved_by=actor;job.position=_carry_position(actor)

func _place_batch(job_key: String, fixture: String, actor: String) -> void:
	var job: Dictionary = jobs[job_key]
	var container: String = _batch_container(fixture)
	job.container=container;job.last_fixture=container;job.source_fixture=container
	job.holder="";job.position=_surface_position(fixture,actor)

func _work_phase(task: Dictionary) -> int:
	return int(task.phases[int(task.phase_index)].get("work_phase",task.phase_index))

func _resumption(actor: String, kind: String, job: Dictionary) -> Dictionary:
	var phases: Array = _phases(actor,kind)
	var index: int = int(job.get("phase_index",0))
	var progress: float = float(job.get("phase_progress",0))
	if not job.is_empty() and int(job.quantity)>0 and str(job.holder).is_empty() and index<phases.size() and job.container!=_batch_container(phases[index].fixture):
		var source: String = job.container
		if _fixtures.has(source):
			phases.insert(index,{"name":"途中の物を取り上げる","fixture":source,"room":_fixtures[source].room,
				"target":_point(_fixtures[source].interaction_point),"minutes":1.0,"transport":"pickup","work_phase":index})
			progress=0
	return {"phases":phases,"index":index,"progress":progress}

func set_stock(key: String, count: int) -> bool:
	if not inventory.has(key) or count<0 or count>10000: return false
	inventory[key]=count
	return true

func set_return_after(actor: String, at_elapsed: float) -> bool:
	if not people.has(actor) or people[actor].at_home or not is_finite(at_elapsed) or at_elapsed<elapsed: return false
	people[actor].return_after=at_elapsed
	return true

func set_commitment_deadline(actor: String, commitment_id: String, due_elapsed: float) -> bool:
	return people.has(actor) and family_history.set_deadline(people[actor],commitment_id,due_elapsed)

func advance_time(minutes: float) -> bool:
	if not is_finite(minutes) or minutes<0 or minutes>1440: return false
	elapsed+=minutes
	for p in people.values():
		for key in NEEDS: p[key]=clampf(float(p[key])+float(rules.passive_per_minute[key])*minutes,0,1)
	# Physical cycles only run after actual loading/hanging. No resident action,
	# physiological relief or practice is attributed to an unattended machine.
	for key in machines.keys():
		var cycle: Dictionary = machines[key]
		if elapsed<float(cycle.ready_at): continue
		inventory[cycle.output]=int(inventory[cycle.output])+int(cycle.quantity)
		inventory["wet_towels" if key=="wash_cycle" else "dry_towels"]+=int(cycle.get("towels",0))
		inventory[cycle.inflight]=int(inventory[cycle.inflight])-int(cycle.quantity)
		_record("",key,"process_ready",{"quantity":cycle.quantity})
		machines.erase(key)
	return true

func _routine(p: Dictionary, at_elapsed: float = -1.0) -> Dictionary:
	var now: float = start_minute+(elapsed if at_elapsed<0 else at_elapsed)
	var day: int = int(floor(now/1440.0))
	for offset in [-1,0]:
		var current_day: int = day+offset
		for routine in p.routines:
			if not routine.on_days.any(func(value):return int(value)==posmod(weekday+current_day,7)):continue
			var begin: float = current_day*1440+float(routine.start_minute)
			var end: float = begin+float(routine.duration_minutes)
			if now>=begin and now<end:
				var result: Dictionary = routine.duplicate(true)
				result.kind=rules.routine_actions.get(routine.id,routine.get("action","quiet"))
				result.ends=end-start_minute
				return result
	return {}

func _free_minutes(p: Dictionary) -> float:
	var current: Dictionary = _routine(p)
	if not current.is_empty() and current.kind in ["work","school","sleep"]: return 0
	var now: float = start_minute+elapsed
	var best: float = 1440.0
	for day in range(int(floor(now/1440.0)),int(floor(now/1440.0))+2):
		for routine in p.routines:
			if posmod(weekday+day,7) not in routine.on_days or rules.routine_actions.get(routine.id,"") not in ["work","school"]: continue
			var begin: float = day*1440+float(routine.start_minute)
			if begin>now: best=minf(best,begin-now)
	return best

func _children_here() -> bool:
	for p in people.values():
		if int(p.age)<13 and p.at_home: return true
	return false

func _household_hunger() -> float:
	var value: float = 0.0
	for p in people.values():
		if p.at_home: value=maxf(value,float(p.hunger))
	return value

func _meal_window() -> bool:
	for window in rules.meal_windows:
		if minute_of_day()>=int(window[0]) and minute_of_day()<int(window[1]): return true
	return false

func _job_key(actor: String, kind: String) -> String:
	return kind if bool(rules.actions[kind].get("shared",false)) else kind+":"+actor

func _personal_fixture(actor: String, selector: String, routine: Dictionary) -> String:
	var places: Dictionary = _resident_places[actor]
	match selector:
		"$bed": return places.bed
		"$dining_seat": return places.dining_seat
		"$outside": return "$outside"
		"$entrance": return "$entrance"
		"$work":
			if routine.get("place","")!="home": return "$outside"
			for f in _fixtures.values():
				if f.type=="desk" and f.get("owner","")==actor: return f.get("use_via",f.id)
			return ""
		"$quiet":
			for f in _fixtures.values():
				if f.type=="desk" and f.get("owner","")==actor: return f.get("use_via",f.id)
			return "sofa"
		"$drying_rack":
			for f in _fixtures.values():
				if f.type=="drying_rack": return f.id
			return ""
	return selector

func _phases(actor: String, kind: String) -> Array:
	var phases: Array = []
	var routine: Dictionary = _routine(people[actor])
	for authored in rules.actions[kind].phases:
		var phase: Dictionary = authored.duplicate(true)
		var id: String = _personal_fixture(actor,phase.fixture,routine)
		if kind=="put_down":
			var held: String = _held_job(actor)
			id=_safe_fixture(actor,jobs[held]) if not held.is_empty() else ""
		phase.fixture=id
		phase.work_phase=phases.size()
		if id in ["$outside","$entrance"]:
			var found: bool = false
			for door in plan.doors:
				if door.room_a=="outside" or door.room_b=="outside":
					phase.room="outside" if id=="$outside" else "entrance"
					phase.target=_point(door.approaches[phase.room]);found=true;break
			if not found: return []
		elif not _fixtures.has(id): return []
		else:
			phase.room=_fixtures[id].room;phase.target=_point(_fixtures[id].interaction_point)
			if _fixtures[id].type=="sofa":
				var ids: Array = people.keys();ids.sort()
				var slot: int = ids.find(actor)
				phase.target.x+=(float(slot)-float(people.size()-1)*.5)*.6
		if kind in ["work","school","sleep"] and not routine.is_empty() and routine.kind==kind:
			# A shift, school day or night's sleep is one continuous use. A
			# sixty-minute work chunk must not make people leave/re-enter hourly.
			phase.minutes=float(routine.ends)-elapsed;phase.scheduled_end=float(routine.ends)
		if kind=="personal_project": phase.minutes=maxf(1,minf(float(phase.minutes),family_history.project_remaining(people[actor])))
		phases.append(phase)
	return phases

func _status(actor: String, fixture: String, room: String) -> Dictionary:
	if fixture.begins_with("$"): return {"status":"ready","reason":""}
	if occupancy!=null: return occupancy.fixture_status(fixture,actor)
	var definition: Dictionary = _rooms.get(room,{})
	if definition.get("private_scope","")!="public" and actor not in definition.get("allowed_residents",[]): return {"status":"private","reason":"この部屋を使う許可がない"}
	var users: int = 0
	for id in _claims:
		if id==actor: continue
		var other_fixture: String = _claims[id]
		if other_fixture==fixture: users+=1
		if str(other_fixture).begins_with("$"): continue
		if _fixtures[other_fixture].room==room and (definition.get("private_scope","")=="exclusive_when_occupied" or fixture=="changing_space" or other_fixture=="changing_space"): return {"status":"occupied","reason":"ほかの人が使い終わるのを待つ"}
	if users>=int(_fixtures[fixture].get("capacity",1)): return {"status":"occupied","reason":"ほかの人が使っている"}
	return {"status":"ready","reason":""}

func _requirement(actor: String, kind: String, work_started_at: float = -1.0) -> String:
	var p: Dictionary = people[actor]
	if int(p.age)<int(rules.actions[kind].min_age): return "年齢に合った別の行動をする"
	for phase in _phases(actor,kind):
		if _requires_usage(phase.fixture) and not _usage_regions.has(phase.fixture): return "家具の実使用位置がまだ定義されていない"
	if kind in BATCH_KINDS:
		for phase in _phases(actor,kind):
			if not bool(phase.get("keep_carried",false)) and not str(phase.fixture).begins_with("$") and not _supports.has(phase.fixture): return "工程の物を置く実支持面がまだない"
	var key: String = _job_key(actor,kind)
	if jobs.has(key):
		if jobs[key].get("reserved_by","") not in ["",actor]: return "別の人が途中の作業を進めている"
		return ""
	match kind:
		"put_down":
			if _held_job(actor).is_empty(): return "今は物を持っていない"
		"cook":
			if int(inventory.prepared_servings)+int(inventory.table_servings)>0: return "先に出来ている料理を食卓へ運ぶ"
			if int(inventory.ingredients)<int(rules.recipe_servings): return "食材が足りない"
		"serve":
			if int(inventory.prepared_servings)<1: return "まだ料理が出来ていない"
			if int(inventory.clean_dishes)<1: return "先に食器を洗う"
		"eat":
			if int(inventory.table_servings)<1: return "まだ食卓に料理がない"
		"wash_dishes":
			if int(inventory.dirty_dishes)<1: return "洗う食器がない"
		"bath":
			if int(inventory.clean_towels)<1 or int(inventory.clean_laundry)<1: return "清潔なタオルが必要"
		"care":
			if elapsed<float(p.care_cooldown): return "誘い直す前に相手の時間を置く"
			if not _children_here(): return "一緒に過ごす子どもがまだ帰っていない"
		"family_time":
			if not _invitation_valid(p): return "家族の誘いをまだ受けていない"
		"personal_project":
			var project: Dictionary = family_history.project_for(p)
			if project.is_empty() or p.life_history.projects[project.id].completed: return "今の個人制作は一区切りついている"
		"tidy_tools":
			if not p.life_history.tools_out: return "自分が使って出した道具はまだない"
		"work","school":
			var routine: Dictionary = _routine(p,work_started_at)
			if routine.is_empty() or routine.kind!=kind: return "今はその予定の時間ではない"
		"return_home":
			if p.at_home: return "すでに家にいる"
			if elapsed<float(p.return_after): return "帰宅が遅れている"
		"shop":
			if int(inventory.ingredients)>=int(rules.recipe_servings): return "今は食材が足りている"
			if cash<float(rules.shopping_cost): return "買い足す資金が足りない"
		"laundry":
			if int(inventory.dirty_laundry)<1: return "洗濯物がない"
			if machines.has("wash_cycle"): return "洗濯機は運転中"
		"hang_laundry":
			if int(inventory.wet_laundry)<1: return "干す洗濯物がまだない"
		"fold_laundry":
			if int(inventory.dry_laundry)<1: return "まだ乾いた洗濯物がない"
	return ""

func candidates(actor: String) -> Array:
	if not people.has(actor): return []
	var p: Dictionary = people[actor]
	var routine: Dictionary = _routine(p)
	var hunger: float = _household_hunger()
	var context: Dictionary = family_history.context_for(actor,people,tasks,elapsed,weekday)
	var held: String = _held_job(actor)
	var carrying_active: bool = not held.is_empty() and tasks.get(p.active_task,{}).get("job_key","")==held
	var rows: Array = []
	for kind in rules.actions:
		var score: float = -1.0
		match kind:
			"toilet": score=.3+float(p.bladder)*.9 if float(p.bladder)>.45 else -.5
			"eat": score=.15+float(p.hunger)*.95 if float(p.hunger)>.32 else -.5
			"cook": score=.3+hunger*.5+(.12 if _meal_window() else 0)+float(p.skills.get("baking",0))*.1-float(p.fatigue)*.15
			"serve": score=.45+hunger*.45
			"wash_dishes": score=.3+minf(.3,float(inventory.dirty_dishes)*.06)+(.2 if inventory.clean_dishes==0 else 0)
			"bath": score=.15+float(p.hygiene)*.65+(.12 if minute_of_day()>1080 else 0) if float(p.hygiene)>.4 else -.5
			"hygiene": score=.15+float(p.hygiene)*.5 if float(p.hygiene)>.25 else -.5
			"sleep": score=.9 if routine.get("kind","")=="sleep" else (.7+float(p.fatigue)*.2 if float(p.fatigue)>.72 else -.5)
			"quiet": score=.17+float(p.quiet)*.25+(.2 if routine.get("kind","")=="quiet" else 0)
			"care": score=.75 if routine.get("kind","")=="care" else .2+float(p.skills.get("care",0))*.1
			"family_time": score=.8 if _invitation_valid(p) and routine.get("kind","") not in ["work","school","sleep"] else -.5
			"work","school": score=.86 if routine.get("kind","")==kind else -.5
			"return_home": score=1.1 if not p.at_home and routine.get("kind","") not in ["work","school"] else -.5
			"wait_outside": score=1.0 if not p.at_home and elapsed<float(p.return_after) else -.5
			"shop": score=.45+hunger*.4 if inventory.ingredients<int(rules.recipe_servings) else -.5
			"laundry": score=.22+minf(.25,float(inventory.dirty_laundry)*.04)
			"hang_laundry": score=.5
			"fold_laundry": score=.35
			"personal_project": score=.25
			"tidy_tools": score=.25
			"put_down": score=1.3 if not held.is_empty() and not carrying_active else -.5
		var personal: Dictionary = family_history.choice(p,kind,context)
		score+=float(personal.score_delta)
		if bool(rules.actions[kind].get("shared",false)):
			score-=minf(.25,float(p.history.minutes.get(kind,0))*.0015)
		var reason: String = _requirement(actor,kind)
		if not held.is_empty() and not carrying_active and kind!="put_down": reason="先に持っている物を安全な台へ置く"
		if reason.is_empty() and not p.at_home and kind not in ["work","school","return_home","wait_outside","shop"]: reason="先に帰宅する"
		var phases: Array = _phases(actor,kind)
		var key: String = _job_key(actor,kind)
		if jobs.has(key) and reason.is_empty(): score=maxf(score,.68)
		var phase_index: int = int(jobs.get(key,{}).get("phase_index",0))
		if phases.is_empty(): reason="使う設備がまだない"
		elif phase_index<phases.size() and reason.is_empty():
			var status: Dictionary = _status(actor,phases[phase_index].fixture,phases[phase_index].room)
			if status.status!="ready": reason=status.reason
		if kind in ["cook","shop","laundry"] and not jobs.has(key) and _free_minutes(p)<_duration(phases)+5 and hunger<.85 and reason.is_empty(): reason="次の予定までに一区切りつけられない"
		var label: String = str(family_history.project_for(p).get("label",rules.actions[kind].label)) if kind=="personal_project" else str(rules.actions[kind].label)
		rows.append({"kind":kind,"label":label,"activity":personal.activity,"project_id":personal.project_id,"choice_reason":personal.choice_reason,"score":score,"status":"ready" if reason.is_empty() and score>=0 else "unavailable","reason":reason if not reason.is_empty() else "今は別のことを優先する"})
	rows.sort_custom(func(a,b):return float(a.score)>float(b.score) if not is_equal_approx(float(a.score),float(b.score)) else str(a.kind)<str(b.kind))
	return rows

func request(actor: String, preferred: String = "") -> Dictionary:
	if not people.has(actor): return _reply("invalid","住民がいない")
	var p: Dictionary = people[actor]
	var active: Dictionary = tasks.get(p.active_task,{})
	if active.get("status","")=="exiting": return _reply("leaving","先に家具から安全に離れる",active)
	if p.active_task.is_empty() and not _held_job(actor).is_empty(): preferred="put_down"
	var choices: Array = candidates(actor)
	var best: Dictionary = {}
	for option in choices:
		if option.status=="ready" and (preferred.is_empty() or preferred==option.kind): best=option;break
	var current: Dictionary = tasks.get(p.active_task,{})
	if not current.is_empty() and current.status not in TERMINAL:
		if current.status=="phase_ready": return _reply(current.status,current.reason,current)
		var routine: Dictionary = _routine(p)
		var duty: bool = routine.get("kind","") in ["work","school"] and current.kind!=routine.kind and current.get("routine_when_chosen","")!=routine.get("id","")
		var lost_partner: bool = current.kind=="family_time" and not _invitation_valid(p) and str(p.care_accepted).is_empty()
		var waited_out: bool = current.kind in ["care","family_time"] and (float(current.get("waiting_since",-1))>=0 and elapsed-float(current.waiting_since)>30 or float(current.performed)==0 and elapsed-float(current.requested_at)>45 or current.kind=="care" and _all_declined(current))
		var other_ready: bool = not best.is_empty() and best.kind!=current.kind
		var critical: bool = float(p.bladder)>.9 or float(p.hunger)>.9 or float(p.fatigue)>.96
		var better_urgent: bool = other_ready and critical and float(best.score)>float(current.get("priority_on_choice",0))+.03 and best.kind in ["toilet","eat","sleep"]
		var should_switch: bool = other_ready and (better_urgent or duty or current.status=="blocked" or not preferred.is_empty())
		if not lost_partner and not waited_out and not should_switch:
			if current.status=="blocked" and not best.is_empty() and best.kind==current.kind: current.status="requested";current.reason="使えるようになったので続ける"
			return _reply(current.status,current.reason,current)
		var cancellation: Dictionary = cancel(actor,current.id,"相手の応答を待って別のことをする" if waited_out or lost_partner else "必要や予定を見直して、途中の物を残した")
		if cancellation.status=="leaving": return cancellation
		if not _held_job(actor).is_empty(): preferred="put_down"
		choices=candidates(actor)
	for candidate in choices:
		if candidate.status!="ready" or not preferred.is_empty() and candidate.kind!=preferred: continue
		serial+=1
		var kind: String = candidate.kind
		var key: String = _job_key(actor,kind)
		var job: Dictionary = jobs.get(key,{})
		var resume: Dictionary = _resumption(actor,kind,job)
		var task: Dictionary = {"id":"task_%d"%serial,"actor":actor,"kind":kind,"label":candidate.label,"activity":candidate.activity,"project_id":candidate.project_id,"choice_reason":candidate.choice_reason,"status":"requested","reason":candidate.choice_reason,
			"phases":resume.phases,"phase_index":resume.index,"phase_progress":resume.progress,"performed":0.0,"priority_on_choice":float(candidate.score),"waiting_since":-1.0,
			"routine_when_chosen":_routine(p).get("id",""),"requested_at":elapsed,"arrived_at":-1.0,"last_performed_at":elapsed,"finished_at":-1.0,"started_effects":bool(job.get("started_effects",false)),"job_key":key,"result":{},"declined_by":[]}
		task.carried_job=_held_job(actor) if kind=="put_down" else ""
		task.pending_cancel_reason=""
		if kind!="family_time" and _invitation_valid(p):
			var invitation_id: String = p.care_invitation.task
			if tasks.has(invitation_id) and actor not in tasks[invitation_id].declined_by: tasks[invitation_id].declined_by.append(actor)
			family_history.declined(p,invitation_id,task,elapsed)
			p.care_invitation={};p.care_accepted=""
		tasks[task.id]=task;p.active_task=task.id;_update_target(task)
		if kind=="care":
			for child in people.values():
				if int(child.age)<13 and child.at_home: child.care_invitation={"from":actor,"task":task.id,"until":elapsed+30}
		if kind=="family_time": p.care_accepted=p.care_invitation.task
		return _reply("requested",task.reason,task)
	return _reply("unavailable","必要な資源・設備・予定が整うまで別の行動を考える")

func task_for(actor: String) -> Dictionary:
	return tasks.get(people.get(actor,{}).get("active_task",""),{}).duplicate(true)

func _fit_scheduled_use(task: Dictionary) -> Dictionary:
	var phase: Dictionary=task.phases[int(task.phase_index)]
	if not phase.has("scheduled_end"):return {}
	var remaining: float=float(phase.scheduled_end)-elapsed
	if remaining<=.000001:return cancel(task.actor,task.id,"予定の時間が終わったので、次の暮らしへ移る")
	phase.minutes=float(task.phase_progress)+remaining;task.phase_minutes=phase.minutes
	return {}

func arrive(actor: String, task_id: String) -> Dictionary:
	var task: Dictionary = _owned(actor,task_id)
	if task.is_empty() or task.status in TERMINAL: return _reply("invalid","進行中の本人の行動ではない")
	var key: String = task.job_key
	if jobs.has(key) and jobs[key].get("reserved_by","") not in ["",actor]: task.status="blocked";return _reply("occupied","別の人がこの作業を進めている",task)
	if jobs.has(key) and task.phases[int(task.phase_index)].get("transport","")!="pickup" and (_work_phase(task)!=jobs[key].phase_index or not is_equal_approx(float(task.phase_progress),float(jobs[key].phase_progress))):
		var resume: Dictionary = _resumption(actor,task.kind,jobs[key])
		task.phases=resume.phases;task.phase_index=resume.index;task.phase_progress=resume.progress;task.started_effects=jobs[key].started_effects;_update_target(task)
		return _reply("redirected","途中の物がある場所へ向かう",task)
	if people[actor].position.distance_to(task.target)>float(rules.arrival_distance): return _reply("not_arrived","まだ使う場所に到着していない",task)
	var status: Dictionary = _status(actor,task.fixture,task.room)
	if status.status!="ready": task.status="blocked";task.reason=status.reason;return _reply(status.status,status.reason,task)
	if occupancy!=null and not str(task.fixture).begins_with("$"):
		status=occupancy.reserve_fixture(task.fixture,actor)
		if status.status!="ready": task.status="blocked";task.reason=status.reason;return _reply(status.status,status.reason,task)
	_claims[actor]=task.fixture
	if jobs.has(key): jobs[key].reserved_by=actor
	if not task.usage.required:
		var fitted: Dictionary=_fit_scheduled_use(task)
		if not fitted.is_empty():return fitted
	task.status="entering" if task.usage.required else ("phase_ready" if float(task.phase_progress)>=float(task.phase_minutes)-.00000001 else "arrived")
	if task.usage.required: task.usage.state="entering"
	task.arrived_at=elapsed;task.last_performed_at=elapsed
	people[actor].at_home=task.fixture!="$outside"
	return _reply(task.status,"使う場所に実際に到着した",task)

func begin_use(actor: String, task_id: String, position: Vector3, posture: String) -> Dictionary:
	var task: Dictionary = _owned(actor,task_id)
	if task.is_empty() or not task.usage.required or task.status not in ["entering","arrived","working","phase_ready"]: return _reply("not_ready","先に家具の入口へ到着して予約する",task)
	if not position.is_finite() or position.distance_to(people[actor].position)>.01 or not _inside_usage(task.fixture,position) or posture not in _usage_regions[task.fixture].postures: return _reply("not_in_usage","実際の姿勢と身体位置が家具の使用領域に合っていない",task)
	if not _claim_held(actor,task): return _reply("occupied","家具と部屋の本人の使用権が必要",task)
	if task.usage.state=="using": return _reply(task.status,"すでに実使用中",task)
	var fitted: Dictionary=_fit_scheduled_use(task)
	if not fitted.is_empty():return fitted
	task.usage.state="using";task.usage.anchor_position=[position.x,position.y,position.z];task.usage.posture=posture;task.usage.entered_at=elapsed
	task.last_performed_at=elapsed
	task.status="phase_ready" if float(task.phase_progress)>=float(task.phase_minutes)-.00000001 else "arrived"
	return _reply(task.status,"実際の家具使用姿勢が成立した",task)

func begin_exit(actor: String, task_id: String) -> Dictionary:
	var task: Dictionary = _owned(actor,task_id)
	if task.is_empty() or not task.usage.required or task.status in TERMINAL: return _reply("not_ready","使用中の家具がない",task)
	if task.status=="exiting": return _reply("leaving","家具から安全に離れている",task)
	if task.status!="phase_ready" and task.pending_cancel_reason.is_empty(): return _reply("not_ready","実作業の終了か中断の意思を確かめる",task)
	if not _claim_held(actor,task): return _reply("occupied","退場が終わるまで本人の占有を維持する",task)
	task.status="exiting";task.usage.state="exiting";task.usage.exit_started_at=elapsed;task.last_performed_at=elapsed
	return _reply("leaving","実作業を止め、家具から安全に離れる",task)

func end_use(actor: String, task_id: String, position: Vector3, posture: String = "stand") -> Dictionary:
	var task: Dictionary = _owned(actor,task_id)
	if task.is_empty() or task.status!="exiting" or not task.usage.required: return _reply("not_ready","先に家具から離れる動作を始める",task)
	if not position.is_finite() or position.distance_to(people[actor].position)>.01 or position.distance_to(task.target)>float(rules.arrival_distance) or posture!="stand": return _reply("not_at_exit","実際に歩ける入口位置へ戻ってから終える",task)
	if not _claim_held(actor,task): return _reply("occupied","退場完了までの使用権が必要",task)
	task.usage.state="exited";task.usage.exited_at=elapsed;task.last_performed_at=elapsed
	task.status="phase_ready" if float(task.phase_progress)>=float(task.phase_minutes)-.00000001 else "arrived"
	if not task.pending_cancel_reason.is_empty(): return _cancel_now(actor,task,task.pending_cancel_reason)
	return _reply(task.status,"家具から実際に離れた。完了処理まで占有を保つ",task)

func perform(actor: String, task_id: String, minutes: float) -> Dictionary:
	var task: Dictionary = _owned(actor,task_id)
	if task.is_empty() or task.status not in ["arrived","working"]: return _reply("not_ready","到着してから実際に行う")
	if not is_finite(minutes) or minutes<=0: return _reply("invalid","実作業時間が必要",task)
	if task.usage.required:
		if task.usage.state!="using" or not _inside_usage(task.fixture,people[actor].position) or not _claim_held(actor,task):
			task.last_performed_at=elapsed
			return _reply("not_in_usage","実際の家具使用姿勢になってから行う",task)
	elif people[actor].position.distance_to(task.target)>float(rules.arrival_distance) or _claims.get(actor,"")!=task.fixture: return _reply("not_arrived","使用位置から離れている",task)
	if occupancy!=null and not str(task.fixture).begins_with("$") and occupancy.fixture_status(task.fixture,actor).status!="ready": return _reply("occupied","使用権を確認してから行う",task)
	if task.kind in ["care","family_time"] and not _care_ready(actor,task):
		task.last_performed_at=elapsed
		if float(task.waiting_since)<0: task.waiting_since=elapsed
		return _reply("waiting_for_partner","相手が受諾して同じ場に来てから一緒に過ごす",task)
	var phase: Dictionary = task.phases[task.phase_index]
	var start: float=maxf(float(task.last_performed_at),elapsed-minutes)
	var end: float=minf(elapsed,float(phase.get("scheduled_end",elapsed)))
	var amount: float=minf(maxf(0,end-start),float(phase.minutes)-float(task.phase_progress))
	if phase.has("scheduled_end") and elapsed>=float(phase.scheduled_end):
		# Count only overlap with the actual performed interval before the end.
		# A late callback/contact recovery cannot backfill an unattended shift.
		var total: float=float(task.phase_progress)+amount
		if total<=.000001:return cancel(actor,task.id,"予定の時間を過ぎたので、実行していない時間を付けずに終える")
		phase.minutes=total;task.phase_minutes=total
		if amount<=.00000001:
			task.status="phase_ready";return _reply("phase_ready","実際に行った時間で予定の区切りを終える",task)
	if amount<=.00000001: return _reply("waiting_for_time","同じ時刻の作業は重ねて数えない",task)
	if not task.started_effects:
		var reason: String = _requirement(actor,task.kind,start if phase.has("scheduled_end") else -1.0)
		if not reason.is_empty(): task.status="blocked";task.reason=reason;return _reply("blocked",reason,task)
		_start_effect(task)
	task.last_performed_at=elapsed;task.phase_progress+=amount;task.performed+=amount;task.status="working";task.waiting_since=-1.0
	if task.kind=="put_down":
		if jobs.has(task.carried_job) and task.phase_progress>=float(phase.minutes)-.00000001:
			_place_batch(task.carried_job,task.fixture,actor);jobs[task.carried_job].reserved_by=""
	elif jobs.has(task.job_key) and jobs[task.job_key].get("holder","")==actor and phase.get("transport","")!="pickup" and not bool(phase.get("keep_carried",false)) and task.phase_progress>=minf(1,float(phase.minutes)):
		_place_batch(task.job_key,task.fixture,actor)
	var p: Dictionary = people[actor]
	for key in phase.get("need_delta",{}): p[key]=clampf(float(p[key])+float(phase.need_delta[key])*amount,0,1)
	p.actual_minutes[task.kind]=float(p.actual_minutes.get(task.kind,0))+amount
	p.history.minutes[task.kind]=float(p.history.minutes.get(task.kind,0))+amount
	family_history.performed(p,task,amount,elapsed)
	if task.kind=="work": p.earned+=amount*.035;cash+=amount*.035
	_sync_job(task)
	if task.phase_progress>=float(phase.minutes)-.00000001: task.status="phase_ready"
	return _reply(task.status,"実際に行った時間だけ進んだ",task)

func finish(actor: String, task_id: String) -> Dictionary:
	var task: Dictionary = _owned(actor,task_id)
	if task.is_empty(): return _reply("invalid","本人の行動ではない")
	if task.status=="completed": return _reply("completed","すでに完了している",task)
	if task.status!="phase_ready": return _reply("not_ready","この工程の実作業が終わっていない",task)
	if task.usage.required and task.usage.state!="exited": return begin_exit(actor,task_id)
	var phase: Dictionary = task.phases[int(task.phase_index)]
	if jobs.has(task.job_key) and int(jobs[task.job_key].quantity)>0:
		if phase.get("transport","")=="pickup" or task.phase_index+1<task.phases.size() and task.phases[int(task.phase_index)+1].fixture!=task.fixture:
			_take_batch(task.job_key,actor)
	_release(actor)
	if task.phase_index+1<task.phases.size():
		task.phase_index+=1;task.phase_progress=0.0;task.status="requested";task.arrived_at=-1.0;task.last_performed_at=elapsed
		if phase.get("transport","")=="pickup" and jobs.has(task.job_key): task.phase_progress=float(jobs[task.job_key].phase_progress)
		_sync_job(task);_update_target(task)
		return _reply("next_phase","次の場所で続ける",task)
	_complete_effect(task)
	task.status="completed";task.finished_at=elapsed
	task.result={"kind":task.kind,"actual_minutes":task.performed,"at":elapsed,"effects_recorded":true}
	var p: Dictionary = people[actor]
	p.active_task="";p.history.completed[task.kind]=int(p.history.completed.get(task.kind,0))+1;p.history.last_finished[task.kind]=elapsed
	family_history.completed(p,task,elapsed)
	jobs.erase(task.job_key)
	if task.kind=="family_time": p.care_accepted="";p.care_invitation={}
	_record(actor,task.kind,"completed",task.result)
	return _reply("completed","実際の工程が終わった",task)

func cancel(actor: String, task_id: String, reason: String = "本人の予定が変わった") -> Dictionary:
	var task: Dictionary = _owned(actor,task_id)
	if task.is_empty(): return _reply("invalid","本人の行動ではない")
	if task.status in TERMINAL: return _reply(task.status,task.reason,task)
	if task.usage.required and task.usage.state in ["entering","using","exiting"]:
		task.pending_cancel_reason=reason
		return begin_exit(actor,task_id)
	return _cancel_now(actor,task,reason)

func _cancel_now(actor: String, task: Dictionary, reason: String) -> Dictionary:
	var task_id: String = task.id
	_sync_job(task)
	if jobs.has(task.job_key):
		if int(jobs[task.job_key].quantity)==0: jobs.erase(task.job_key)
		else: jobs[task.job_key].reserved_by=jobs[task.job_key].holder
	_release(actor);task.status="cancelled";task.reason=reason;task.finished_at=elapsed
	if people[actor].active_task==task_id: people[actor].active_task=""
	if task.kind=="care":
		people[actor].care_cooldown=elapsed+30
		for child in people.values():
			if child.care_accepted==task.id: child.care_accepted=""
			if child.care_invitation.get("task","")==task.id: child.care_invitation={}
	if task.kind=="family_time": people[actor].care_accepted="";people[actor].care_invitation={}
	_record(actor,task.kind,"cancelled",{"reason":reason,"actual_minutes":task.performed,"job_key":task.job_key})
	return _reply("cancelled",reason,task)

func _start_effect(task: Dictionary) -> void:
	if task.kind=="put_down": task.started_effects=true;return
	var count: int = 0
	var towels: int = 0
	match task.kind:
		"cook": count=int(rules.recipe_servings);inventory.ingredients-=count
		"serve": count=mini(int(rules.recipe_servings),mini(int(inventory.prepared_servings),int(inventory.clean_dishes)));inventory.prepared_servings-=count;inventory.clean_dishes-=count
		"eat": count=1;inventory.table_servings-=1
		"wash_dishes": count=mini(3,int(inventory.dirty_dishes));inventory.dirty_dishes-=count
		"bath": count=1;inventory.clean_towels-=1;inventory.clean_laundry-=1
		"shop": count=int(rules.shopping_units);cash-=float(rules.shopping_cost)
		"laundry":
			count=mini(3,int(inventory.dirty_laundry));towels=mini(count,int(inventory.dirty_towels));inventory.dirty_laundry-=count;inventory.dirty_towels-=towels
		"hang_laundry": count=int(inventory.wet_laundry);towels=int(inventory.wet_towels);inventory.wet_laundry-=count;inventory.wet_towels-=towels
		"fold_laundry": count=int(inventory.dry_laundry);towels=int(inventory.dry_towels);inventory.dry_laundry-=count;inventory.dry_towels-=towels
	task.started_effects=true
	var container: String = _batch_container(task.fixture) if count>0 else str(task.fixture)
	jobs[task.job_key]={"kind":task.kind,"quantity":count,"towels":towels,"phase_index":_work_phase(task),"phase_progress":task.phase_progress,"started_effects":true,"reserved_by":task.actor,
		"batch_id":"batch:"+str(task.id),"container":container,"last_fixture":container,"source_fixture":container,"holder":"","position":_surface_position(task.fixture,task.actor) if count>0 else people[task.actor].position}

func _sync_job(task: Dictionary) -> void:
	if not jobs.has(task.job_key): return
	var job: Dictionary = jobs[task.job_key]
	if task.phases[int(task.phase_index)].get("transport","")=="pickup": return
	job.phase_index=_work_phase(task);job.phase_progress=task.phase_progress

func _complete_effect(task: Dictionary) -> void:
	var job: Dictionary = jobs.get(task.job_key,{"quantity":0})
	var count: int = int(job.quantity)
	match task.kind:
		"cook": inventory.prepared_servings+=count
		"serve": inventory.table_servings+=count
		"eat": inventory.dirty_dishes+=count
		"wash_dishes": inventory.clean_dishes+=count
		"bath": inventory.dirty_laundry+=count;inventory.dirty_towels+=count
		"shop": inventory.ingredients+=count
		"laundry":
			inventory.washing_laundry+=count
			machines.wash_cycle={"quantity":count,"towels":int(job.get("towels",0)),"ready_at":elapsed+float(rules.wash_cycle_minutes),"inflight":"washing_laundry","output":"wet_laundry"}
		"hang_laundry":
			inventory.drying_laundry+=count
			machines.dry_cycle={"quantity":count,"towels":int(job.get("towels",0)),"ready_at":elapsed+float(rules.drying_minutes),"inflight":"drying_laundry","output":"dry_laundry"}
		"fold_laundry": inventory.clean_laundry+=count;inventory.clean_towels+=int(job.get("towels",0))

func _invitation_valid(p: Dictionary) -> bool:
	var invitation: Dictionary = p.care_invitation
	var task: Dictionary = tasks.get(invitation.get("task",""),{})
	return not task.is_empty() and task.status not in TERMINAL and float(invitation.get("until",-1))>=elapsed and p.at_home

func _all_declined(task: Dictionary) -> bool:
	if task.get("declined_by",[]).is_empty(): return false
	for p in people.values():
		if int(p.age)>=13 or not p.at_home: continue
		if p.care_accepted==task.id or p.care_invitation.get("task","")==task.id: return false
	return true

func _care_ready(actor: String, task: Dictionary) -> bool:
	if task.kind=="care":
		for child in people.values():
			if child.care_accepted!=task.id or not child.at_home: continue
			var other: Dictionary = tasks.get(child.active_task,{})
			if other.get("kind","")=="family_time" and other.get("status","") in ["arrived","working","phase_ready"] and _use_ready(other) and child.position.distance_to(people[actor].position)<=1.5: return true
		return false
	var parent: Dictionary = tasks.get(people[actor].care_accepted,{})
	if parent.is_empty() or parent.kind!="care" or parent.status=="cancelled": return false
	if parent.status=="completed" and not is_equal_approx(float(parent.finished_at),elapsed): return false
	return people[parent.actor].at_home and people[parent.actor].position.distance_to(people[actor].position)<=1.5 and _use_ready(parent) and parent.status in ["arrived","working","phase_ready","completed"]

func _use_ready(task: Dictionary) -> bool:
	return not bool(task.get("usage",{}).get("required",false)) or task.usage.state=="using"

func _owned(actor: String, id: String) -> Dictionary:
	var task: Dictionary = tasks.get(id,{})
	return task if not task.is_empty() and task.actor==actor and people.has(actor) else {}

func _update_target(task: Dictionary) -> void:
	var phase: Dictionary = task.phases[task.phase_index]
	task.fixture=phase.fixture;task.room=phase.room;task.target=phase.target;task.phase_name=phase.name;task.phase_minutes=phase.minutes
	task.usage={"required":_requires_usage(task.fixture),"state":"approach" if _requires_usage(task.fixture) else "none",
		"anchor_position":[],"posture":"","entered_at":-1.0,"exit_started_at":-1.0,"exited_at":-1.0}

func _release(actor: String) -> void:
	_claims.erase(actor)
	if occupancy!=null: occupancy.release_person(actor)

func _record(actor: String, kind: String, status: String, details: Dictionary) -> void:
	results.append({"actor":actor,"kind":kind,"status":status,"at":elapsed,"details":details.duplicate(true)})
	if results.size()>512: results.pop_front()

func _reply(status: String, reason: String, task: Dictionary = {}) -> Dictionary:
	return {"status":status,"reason":reason,"task":task.duplicate(true)}

func _duration(phases: Array) -> float:
	var amount: float = 0.0
	for phase in phases: amount+=float(phase.minutes)
	return amount

func snapshot() -> Dictionary:
	return _encode({"schema":1,"house_id":plan.get("house",{}).get("id",""),"elapsed":elapsed,"start_minute":start_minute,"weekday":weekday,"serial":serial,"cash":cash,
		"people":people,"inventory":inventory,"tasks":tasks,"jobs":jobs,"machines":machines,"claims":_claims,"results":results,
		"occupancy":occupancy.snapshot() if occupancy!=null else {}})

func restore(saved: Dictionary) -> bool:
	var decoded: Variant = _decode(saved)
	if not decoded is Dictionary or not _valid_snapshot(decoded): return false
	if occupancy!=null and not occupancy.restore(decoded.occupancy): return false
	elapsed=float(decoded.elapsed);serial=int(decoded.serial);cash=float(decoded.cash)
	people=decoded.people.duplicate(true);inventory=decoded.inventory.duplicate(true);tasks=decoded.tasks.duplicate(true);jobs=decoded.jobs.duplicate(true)
	for p in people.values():
		for routine in p.routines:
			var days: Array = []
			for day in routine.on_days: days.append(int(day))
			routine.on_days=days
	machines=decoded.machines.duplicate(true);_claims=decoded.claims.duplicate(true);results=decoded.results.duplicate(true)
	return true

func _valid_snapshot(s: Dictionary) -> bool:
	if s.get("schema")!=1 or s.get("house_id")!=plan.get("house",{}).get("id","") or s.get("start_minute")!=start_minute or s.get("weekday")!=weekday: return false
	if not _number(s.get("elapsed"),0,10000000) or not _whole(s.get("serial"),0,1000000) or not _number(s.get("cash"),0,1000000): return false
	for key in ["people","inventory","tasks","jobs","machines","claims","occupancy"]:
		if not s.get(key) is Dictionary: return false
	if not s.get("results") is Array or s.results.size()>512 or s.people.size()!=people.size() or s.inventory.size()!=inventory.size() or s.tasks.size()>10000: return false
	for key in inventory:
		if not _whole(s.inventory.get(key),0,10000): return false
	for pair in [["clean_towels","clean_laundry"],["dirty_towels","dirty_laundry"],["wet_towels","wet_laundry"],["dry_towels","dry_laundry"]]:
		if s.inventory[pair[0]]>s.inventory[pair[1]]: return false
	for id in people:
		if not s.people.get(id) is Dictionary: return false
		var p: Dictionary = s.people[id]
		if p.get("id")!=id or not _whole(p.get("age"),0,120) or not p.get("position") is Vector3 or not p.position.is_finite() or p.position.length()>1000: return false
		if not p.get("at_home") is bool or not p.get("active_task") is String or not _number(p.get("return_after"),0,10000000) or not _number(p.get("earned"),0,1000000): return false
		for key in NEEDS:
			if not _number(p.get(key),0,1): return false
		if not p.get("care_invitation") is Dictionary or not p.get("care_accepted") is String or not _number(p.get("care_cooldown"),0,10000000): return false
		if not p.care_invitation.is_empty() and (not p.care_invitation.get("from") is String or not p.care_invitation.get("task") is String or not _number(p.care_invitation.get("until"),0,10000000)): return false
		for key in ["skills","history","actual_minutes"]:
			if not p.get(key) is Dictionary: return false
		if not p.get("routines") is Array or not _same(p.routines,people[id].routines): return false
		for key in p.skills:
			if not _number(p.skills[key],0,1): return false
		for key in ["minutes","completed","last_finished"]:
			if not p.history.get(key) is Dictionary: return false
			for value in p.history[key].values():
				if not _number(value,0,10000000): return false
		for value in p.actual_minutes.values():
			if not _number(value,0,10000000): return false
		if not family_history.valid_person(p,float(s.elapsed)) or p.life_history.start_minute!=start_minute: return false
		for progress in p.life_history.projects.values():
			if not _fixtures.has(progress.fixture): return false
		if p.life_history.tools_out and not _fixtures.has(p.life_history.tools_fixture): return false
		if not p.active_task.is_empty() and (not s.tasks.get(p.active_task) is Dictionary or s.tasks[p.active_task].get("actor")!=id or s.tasks[p.active_task].get("status") in TERMINAL): return false
	for id in s.tasks:
		if not id is String or not id.begins_with("task_") or id.length()>14 or not id.trim_prefix("task_").is_valid_int(): return false
		if int(id.trim_prefix("task_"))>int(s.serial): return false
		if not s.tasks[id] is Dictionary: return false
		var t: Dictionary = s.tasks[id]
		if t.get("id")!=id or not people.has(t.get("actor")) or not rules.actions.has(t.get("kind")) or t.get("status") not in ["requested","entering","arrived","working","phase_ready","exiting","blocked","completed","cancelled"]: return false
		if not t.get("pending_cancel_reason") is String or t.pending_cancel_reason.length()>512: return false
		for key in ["activity","project_id","choice_reason"]:
			if not t.get(key) is String or t[key].length()>256: return false
		if not t.get("carried_job") is String: return false
		if t.kind=="put_down" and t.status not in TERMINAL and not s.jobs.has(t.carried_job): return false
		if t.kind!="put_down" and not t.carried_job.is_empty(): return false
		var project: Dictionary = s.people[t.actor].biography.project
		if t.kind=="personal_project":
			if t.project_id!=project.id or t.activity!=project.activity: return false
		elif t.kind=="tidy_tools":
			if t.project_id!=project.id or t.activity!="tidy_personal_tools": return false
		elif t.activity!=t.kind or not t.project_id.is_empty(): return false
		if not t.get("declined_by") is Array or t.declined_by.size()>people.size(): return false
		for declined in t.declined_by:
			if not people.has(declined): return false
		if not t.get("phases") is Array or t.phases.is_empty() or not _whole(t.get("phase_index"),0,t.phases.size()-1) or not t.get("started_effects") is bool or not t.get("result") is Dictionary: return false
		for phase in t.phases:
			if not phase is Dictionary or not phase.get("fixture") is String or not phase.get("room") is String or not phase.get("target") is Vector3 or not phase.target.is_finite() or phase.target.length()>1000 or not _number(phase.get("minutes"),.000001,1440): return false
			if not _whole(phase.get("work_phase"),0,rules.actions[t.kind].phases.size()-1) or phase.get("transport","") not in ["","pickup"]: return false
			if not phase.get("keep_carried",false) is bool: return false
			if phase.get("transport","")=="pickup":
				if bool(phase.get("keep_carried",false)): return false
			elif phase.get("keep_carried",false)!=rules.actions[t.kind].phases[int(phase.work_phase)].get("keep_carried",false): return false
			if phase.has("scheduled_end"):
				if not _number(t.get("requested_at"),0,float(s.elapsed)):return false
				if t.kind not in ["work","school","sleep"] or not _number(phase.scheduled_end,float(t.requested_at),float(t.requested_at)+1440):return false
				var routine: Dictionary=_routine(s.people[t.actor],float(t.requested_at))
				if routine.get("kind")!=t.kind or not is_equal_approx(float(routine.get("ends",-1)),float(phase.scheduled_end)):return false
			if not phase.fixture.begins_with("$") and not _fixtures.has(phase.fixture): return false
			if not phase.get("name") is String or not phase.get("need_delta",{}) is Dictionary: return false
			for key in phase.get("need_delta",{}):
				if key not in NEEDS or not _number(phase.need_delta[key],-1,1): return false
		if not _number(t.get("phase_progress"),0,float(t.phases[int(t.phase_index)].minutes)) or not _number(t.get("performed"),0,10000000) or not _number(t.get("priority_on_choice"),-1,2) or not _number(t.get("waiting_since"),-1,float(s.elapsed)): return false
		for key in ["requested_at","last_performed_at"]:
			if not _number(t.get(key),0,float(s.elapsed)): return false
		for key in ["arrived_at","finished_at"]:
			if not _number(t.get(key),-1,float(s.elapsed)): return false
		if t.get("job_key")!=_job_key(t.actor,t.kind): return false
		var phase: Dictionary = t.phases[int(t.phase_index)]
		if t.get("target")!=phase.target or t.get("fixture")!=phase.fixture or t.get("room")!=phase.room: return false
		if not _number(t.get("phase_minutes"),.000001,1440) or not is_equal_approx(float(t.phase_minutes),float(phase.minutes)) or t.get("phase_name")!=phase.name: return false
		if not _valid_usage(t,s): return false
	var batch_ids: Array = []
	for key in s.jobs:
		var job: Variant = s.jobs[key]
		if not job is Dictionary or not rules.actions.has(job.get("kind")) or not job.get("reserved_by") is String or not job.get("started_effects") is bool or not job.started_effects: return false
		if not _whole(job.get("quantity"),0,100) or not _whole(job.get("towels"),0,float(job.quantity)) or not _whole(job.get("phase_index"),0,rules.actions[job.kind].phases.size()-1) or not _number(job.get("phase_progress"),0,1440): return false
		if not job.get("batch_id") is String or not job.batch_id.begins_with("batch:task_") or job.batch_id in batch_ids: return false
		batch_ids.append(job.batch_id)
		for field in ["container","last_fixture","holder","source_fixture"]:
			if not job.get(field) is String: return false
		if job.last_fixture!=job.source_fixture or not (job.last_fixture.begins_with("$") or _fixtures.has(job.last_fixture)) or not job.get("position") is Vector3 or not job.position.is_finite() or job.position.length()>1000: return false
		if not job.holder.is_empty():
			if not job.container.is_empty() or not s.people.has(job.holder) or job.reserved_by!=job.holder or job.position.distance_to(s.people[job.holder].position+Vector3(0,1,0))>.000001: return false
		elif job.container.is_empty() or job.container!=job.last_fixture: return false
		elif int(job.quantity)>0 and not job.container.begins_with("$"):
			if not _supports.has(job.container) or job.position.distance_to(_surface_position(job.container))>.000001: return false
		if not job.reserved_by.is_empty():
			if not s.people.has(job.reserved_by): return false
			var active_id: String = s.people[job.reserved_by].active_task
			if active_id.is_empty():
				if job.holder!=job.reserved_by: return false
				continue
			var active: Dictionary = s.tasks[active_id]
			if active.kind=="put_down" and active.carried_job==key and job.holder==active.actor: continue
			if active.job_key!=key or not active.started_effects or _work_phase(active)!=job.phase_index: return false
			if active.phases[int(active.phase_index)].get("transport","")!="pickup" and not is_equal_approx(float(active.phase_progress),float(job.phase_progress)): return false
	for actor in s.claims:
		if not s.people.has(actor) or not s.claims[actor] is String or not (s.claims[actor].begins_with("$") or _fixtures.has(s.claims[actor])): return false
		var active_id: String = s.people[actor].active_task
		if active_id.is_empty() or s.tasks[active_id].fixture!=s.claims[actor] or s.tasks[active_id].status not in ["entering","arrived","working","phase_ready","exiting","blocked"]: return false
	for key in s.machines:
		var m: Variant = s.machines[key]
		if key not in ["wash_cycle","dry_cycle"] or not m is Dictionary or not _whole(m.get("quantity"),1,100) or not _number(m.get("ready_at"),float(s.elapsed),10000000): return false
		if not _whole(m.get("towels"),0,float(m.quantity)): return false
		if m.get("inflight")!=("washing_laundry" if key=="wash_cycle" else "drying_laundry") or m.get("output")!=("wet_laundry" if key=="wash_cycle" else "dry_laundry"): return false
	return true

func _valid_usage(task: Dictionary, snapshot_data: Dictionary) -> bool:
	var use: Variant = task.get("usage")
	if not use is Dictionary or not use.get("required") is bool or use.required!=_requires_usage(task.fixture): return false
	if not use.get("anchor_position") is Array or use.anchor_position.size() not in [0,3] or not use.get("posture") is String: return false
	for value in use.anchor_position:
		if not _number(value,-1000,1000): return false
	for key in ["entered_at","exit_started_at","exited_at"]:
		if not _number(use.get(key),-1,float(snapshot_data.elapsed)): return false
	if not use.required:
		return use.get("state")=="none" and use.anchor_position.is_empty() and use.posture.is_empty() and use.entered_at==-1 and use.exit_started_at==-1 and use.exited_at==-1 and task.status not in ["entering","exiting"] and task.pending_cancel_reason.is_empty()
	if not _usage_regions.has(task.fixture) or use.get("state") not in ["approach","entering","using","exiting","exited"]: return false
	if use.anchor_position.is_empty():
		if not use.posture.is_empty() or use.entered_at!=-1 or use.state=="using": return false
	else:
		if not _inside_usage(task.fixture,_point(use.anchor_position)) or use.posture not in _usage_regions[task.fixture].postures or float(use.entered_at)<0: return false
	match str(use.state):
		"approach":
			if task.status not in ["requested","blocked","cancelled"] or not use.anchor_position.is_empty(): return false
		"entering":
			if task.status!="entering" or not use.anchor_position.is_empty(): return false
		"using":
			if task.status not in ["arrived","working","phase_ready"] or not _inside_usage(task.fixture,snapshot_data.people[task.actor].position): return false
		"exiting":
			if task.status!="exiting" or float(use.exit_started_at)<0: return false
			if task.pending_cancel_reason.is_empty() and float(task.phase_progress)<float(task.phase_minutes)-.00000001: return false
		"exited":
			if task.status not in ["phase_ready","completed","cancelled"] or float(use.exited_at)<0: return false
	if task.status not in TERMINAL and use.state!="approach":
		if snapshot_data.people[task.actor].active_task!=task.id or snapshot_data.claims.get(task.actor,"")!=task.fixture: return false
		if occupancy!=null:
			if not snapshot_data.occupancy.get("fixture_users") is Dictionary or not snapshot_data.occupancy.get("room_users") is Dictionary: return false
			if not snapshot_data.occupancy.fixture_users.get(task.fixture) is Array or not snapshot_data.occupancy.room_users.get(task.room) is Array: return false
			if task.actor not in snapshot_data.occupancy.fixture_users[task.fixture] or task.actor not in snapshot_data.occupancy.room_users[task.room]: return false
	return true

static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<.000000001
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not _same(a[i],b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key],b[key]): return false
		return true
	return a==b

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _whole(value: Variant, low: float, high: float) -> bool:
	return _number(value,low,high) and floorf(float(value))==float(value)

static func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _encode(value: Variant) -> Variant:
	if value is Vector3: return {"__position":[value.x,value.y,value.z]}
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key]=_encode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_encode(item))
		return result
	return value

static func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.size()==1 and value.get("__position") is Array and value.__position.size()==3:
			for n in value.__position:
				if not _number(n,-1000,1000): return null
			return _point(value.__position)
		var result: Dictionary = {}
		for key in value: result[key]=_decode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_decode(item))
		return result
	return value
