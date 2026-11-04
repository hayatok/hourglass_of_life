class_name LifeSimulation
extends Node

signal event_added(event: Dictionary)
signal town_changed
signal chapter_reached

const SAVE_PATH = "user://life-save.json"
const LEGACY_SAVE_PATH = "user://life-save-v01.json"
const WALK_METERS_PER_MINUTE = .36
const HUNGER_PER_MINUTE = .0013
const FATIGUE_PER_MINUTE = .0007
const BASE_POPULATION = 8
const EXPANDED_POPULATION = 12
const HOME = {"ogawa": "home_ogawa", "saeki": "home_saeki", "shared_house": "home_shared", "aoi_apartment":"off_map_home", "north_house":"home_north_shared", "mori":"home_mori"}
const SITES = {
	"home_ogawa": Vector3(-9, 0, 6), "home_saeki": Vector3(-9, 0, -4),
	"home_shared": Vector3(9, 0, 6), "bakery_cafe": Vector3(8, 0, -5),
	"workshop": Vector3(0, 0, -7), "square": Vector3(0, 0, 1),
	"garden": Vector3(-3, 0, 3), "home_north_shared":Vector3(-9,0,-14), "home_mori":Vector3(9,0,-15), "off_map_school": Vector3(14, 0, 7),
	"off_map_workplace": Vector3(14, 0, 5), "off_map_home":Vector3(14,0,6)
}
const ENTRIES = {
	"home_ogawa": Vector3(-9, 0, 8.8), "home_saeki": Vector3(-9, 0, -1.2),
	"home_shared": Vector3(9, 0, 8.8), "bakery_cafe": Vector3(8, 0, -2.2),
	"workshop": Vector3(0, 0, -4.8), "home_north_shared":Vector3(-9,0,-11.2), "home_mori":Vector3(9,0,-12.2)
}
const OUTER_ENTRIES = {
	"home_ogawa": Vector3(-9,0,10), "home_saeki": Vector3(-9,0,0),
	"home_shared": Vector3(9,0,10), "bakery_cafe": Vector3(8,0,-1),
	"workshop": Vector3(0,0,-4.3), "home_north_shared":Vector3(-9,0,-10), "home_mori":Vector3(9,0,-11)
}
const WAYPOINTS = [
	Vector3(-5, 0, -4), Vector3(0, 0, -4), Vector3(4.4, 0, -4),
	Vector3(-5, 0, 1), Vector3(0, 0, 1), Vector3(4.4, 0, 1),
	Vector3(-5, 0, 7), Vector3(0, 0, 7), Vector3(4.4, 0, 7), Vector3(13, 0, 7),
	Vector3(4.4,0,10.3), Vector3(13,0,10.3),
	Vector3(-5,0,-10),Vector3(4.4,0,-11)
]
const LINKS = [[0,1],[1,2],[3,4],[4,5],[6,7],[7,8],[0,3],[1,4],[2,5],[3,6],[4,7],[5,8],[8,10],[10,11],[11,9],[0,12],[2,13],[12,13]]
const ACTION_NAMES = {
	"sleep": "眠っている", "work": "仕事に取り組む", "school": "学校で過ごす",
	"care": "家族と過ごす", "rest": "ひと息つく", "eat": "食事をする",
	"hobby": "好きなことに取り組む", "social": "誰かと過ごしたい", "photo": "町を撮る",
	"meet": "一緒に話す", "play":"四目並べで遊ぶ", "prepare":"待ち合わせの準備", "travel": "移動する", "chores":"家の用事を片付ける", "joint_work":"一緒に制作する", "own_life":"町外で暮らしている", "legacy":"残された記録を見ている", "remembered":"町に残る記憶"
}
const ROUTINE_NAMES = {
	"sleep": "いつもの睡眠の時間", "off_shift_sleep": "夜勤のない日の睡眠",
	"post_shift_sleep": "夜勤を終えて休む時間", "bakery_shift": "パン屋の仕事",
	"cafe_shift": "喫茶店の仕事", "remote_work": "引き受けた仕事",
	"after_school_care": "凛と過ごす約束", "school": "学校の時間",
	"after_school_home":"学校のあと、家で過ごす時間",
	"new_work":"町外の工房での仕事", "away_private":"町外で自分の暮らしを過ごす時間",
	"model_work":"模型工房で引き受けた仕事",
	"work_shift":"引き受けた仕事の時間",
	"classes": "授業の時間", "workshop": "工房での仕事", "night_shift": "町外での夜勤", "appointment":"誰かと会う約束の準備", "agenda":"相談して決めた約束の準備", "support_care":"相談して引き受けた世話の時間", "support_chores":"相談して引き受けた家の用事"
}

var people: Array = []
var definitions: Dictionary = {}
var events: Array = []
var meetings: Array = []
var benches: Array = []
var elapsed: int = 0
var start_minute: int = 13 * 60
var epoch_weekday: int = 5
var speed: float = 1.0
var running: bool = false
var minutes_per_second: float = 6.0
var shared_budget: int = 100
var rng = RandomNumberGenerator.new()
var graph = AStar3D.new()
var minute_remainder: float = 0
var meeting_serial: int = 0
var event_serial: int = 0
var world_seed: int = 71103
var rejection_context: Dictionary = {}
var social: SocialLife
var work_family: WorkFamily
var life: LifeCourse
var activities: ActivityPlaces
var cognition: ResidentCognition
var resident_activities: ResidentActivities
var planner: ResidentPlanner
var agenda: ResidentAgenda
var support_plans: ResidentSupportPlans
var interactions: WorldInteractions
var tabletop: TabletopGame
var sewing: SewingWork
var weather: WorldWeather
var resident_weather: ResidentWeather
var load_error := ""

func _ready() -> void:
	_build_graph()
	reset()

func _process(delta: float) -> void:
	if running and speed > 0:
		advance_minutes(delta * minutes_per_second * speed,true)

func _build_graph() -> void:
	graph.clear()
	for i in WAYPOINTS.size():
		graph.add_point(i, WAYPOINTS[i])
	for edge in LINKS:
		graph.connect_points(edge[0], edge[1])

func _cast_definitions(population: int) -> Dictionary:
	if population not in [BASE_POPULATION,EXPANDED_POPULATION]: return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	if not data is Dictionary or data.get("residents",[]).size()<population: return {}
	var cast := {}
	for i in population:
		var d: Dictionary = data.residents[i]
		# JSON numbers are floats; Array membership distinguishes float from int.
		for routine in d.routines:
			var days: Array = []
			for day in routine.on_days: days.append(int(day))
			routine.on_days = days
		cast[d.id] = d
	return cast

func reset(seed_value: int = 71103, population: int = BASE_POPULATION) -> void:
	var cast := _cast_definitions(population)
	if cast.is_empty():
		push_error("Unsupported resident roster: %d"%population)
		return
	if graph.get_point_count() == 0:
		_build_graph()
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	definitions.clear()
	people.clear()
	events.clear()
	meetings.clear()
	benches = [Vector3(0, 0, 2.5)]
	if activities==null: activities = ActivityPlaces.new(self)
	activities.configure_benches(benches)
	elapsed = 0
	start_minute = 780
	epoch_weekday = 5
	shared_budget = 100
	speed = 1
	running = false
	minute_remainder = 0
	meeting_serial = 0
	event_serial = 0
	world_seed = seed_value
	rejection_context.clear()
	rng.seed = seed_value
	if weather==null: weather = WorldWeather.new()
	weather.reset(posmod(world_seed,2147483648),minute_of_day(),0,0,elapsed)
	if resident_weather==null: resident_weather = ResidentWeather.new(self)
	for id in cast: definitions[id] = cast[id]
	for i in definitions.size():
		var d: Dictionary = definitions.values()[i]
		var home = HOME[d.household_id]
		var p = {
			"id": d.id, "name": d.name, "age": int(d.age_years), "occupation": d.occupation,
			"position": SITES[home] + _offset(i), "place": home, "destination": home,
			"target": SITES[home] + _offset(i), "path": [], "moving": false,
			"action": "rest", "reason": "今日はどんな時間にしよう", "remaining": 0.0,"activity_spot":"",
			"fatigue": 0.20 + rng.randf_range(0, 0.12), "hunger": 0.20,
			"connection": 0.35 + rng.randf_range(0, 0.15), "quiet": 0.20,
			"goal_progress": 0.0, "goal_notified": false, "meeting_id": "",
			"memories": [], "relationships": {}, "routine_id": "", "supported": false,
			"travel_minutes": 0, "activity_minutes": 0
		}
		people.append(p)
	for rel in data.relationship_seeds:
		if not definitions.has(rel.from) or not definitions.has(rel.to): continue
		var r = person(rel.from)
		r.relationships[rel.to] = rel.duplicate(true)
	if social==null: social = SocialLife.new(self)
	social.reset()
	if work_family==null: work_family = WorkFamily.new(self)
	work_family.reset()
	if life==null: life = LifeCourse.new(self)
	life.reset()
	if cognition==null: cognition = ResidentCognition.new(self)
	cognition.reset()
	if resident_activities==null: resident_activities = ResidentActivities.new(self)
	if planner==null: planner = ResidentPlanner.new(self)
	planner.reset()
	if agenda==null: agenda = ResidentAgenda.new(self)
	agenda.reset()
	if support_plans==null: support_plans = ResidentSupportPlans.new(self)
	support_plans.reset()
	if interactions==null: interactions = WorldInteractions.new(self)
	interactions.reset()
	if tabletop==null: tabletop = TabletopGame.new(self)
	tabletop.reset()
	if sewing==null: sewing = SewingWork.new(self)
	sewing.reset()
	for p in people:
		# The clock starts in an existing day, so active shifts are already underway.
		var routine = _routine_at(p)
		if not routine.is_empty():
			p.place = _place_for(p,routine.place)
			p.position = SITES[p.place]+_offset(people.find(p))
		_choose_action(p)
	_log("", "町の新しい一日", "住人の暮らしを眺め、気になった人を選んでみましょう。")
	town_changed.emit()

func _offset(index: int) -> Vector3:
	return Vector3((index % 3 - 1) * 0.65, 0, (index % 2) * 0.65)

func person(id: String) -> Dictionary:
	for p in people:
		if p.id == id:
			return p
	return {}

func day_index() -> int:
	return int((start_minute + elapsed) / 1440.0)

func minute_of_day() -> int:
	return (start_minute + elapsed) % 1440

func weekday() -> int:
	return (epoch_weekday + day_index()) % 7

func calendar_text() -> String:
	var day = day_index()
	var season = ["春", "夏", "秋", "冬"][int(day / 3.0) % 4]
	var week = ["月", "火", "水", "木", "金", "土", "日"][weekday()]
	return "%d年目  %s %d日  %s曜" % [1 + int(day / 12.0), season, day % 3 + 1, week]

func clock_text() -> String:
	var m = minute_of_day()
	return "%02d:%02d" % [int(m / 60.0), m % 60]

func advance_minutes(amount: float, stop_at_review: bool = false) -> void:
	_reconcile_weather_clock()
	minute_remainder += amount
	while minute_remainder >= 1.0:
		minute_remainder -= 1.0
		elapsed += 1
		weather.tick(elapsed,minute_of_day(),int(day_index()/3.0)%4)
		life.tick()
		interactions.tick()
		tabletop.tick()
		sewing.tick()
		work_family.tick()
		support_plans.tick()
		agenda.tick()
		social.tick()
		for p in people:
			_tick_person(p)
		_tick_meetings()
		if elapsed % 60 == 0:
			_try_spontaneous()
		if minute_of_day() == 0:
			_log("", "日が変わりました", "町の時間は、昨日の出来事とともに続きます。")
		if stop_at_review and life.chapter_ready:
			minute_remainder = 0
			break

func _routine_at(p: Dictionary, minute: int = -1, week: int = -1) -> Dictionary:
	var base = _authored_routine_at(p,minute,week)
	return work_family.adjust_routine(p,base,minute,week) if work_family!=null else base

func _authored_routine_at(p: Dictionary, minute: int = -1, week: int = -1) -> Dictionary:
	if minute < 0:
		minute = minute_of_day()
	if week < 0:
		week = weekday()
	for routine in life.routines(p) if life!=null else definitions[p.id].routines:
		var begin = int(routine.start_minute)
		var duration = int(routine.duration_minutes)
		if week in routine.on_days and minute >= begin and minute < begin + duration:
			return routine
		if (week + 6) % 7 in routine.on_days and begin + duration > 1440 and minute < begin + duration - 1440:
			return routine
	return {}

func commitment_text(p: Dictionary) -> String:
	if not life.is_alive(p): return "これまでの時間は、町と人の記録に残っています"
	var active = _routine_at(p)
	if not active.is_empty():
		return ROUTINE_NAMES.get(active.id, "引き受けた予定")
	var next = _next_commitment(p)
	if next.minutes < 1440:
		return "%d時間%d分後：%s" % [int(next.minutes / 60.0), int(next.minutes) % 60, ROUTINE_NAMES.get(next.id, "予定")]
	return "今日はこのあと、決まった予定はありません"

func _next_commitment(p: Dictionary) -> Dictionary:
	var result = social.next_commitment(p) if social!=null else {"minutes":2880,"id":""}
	if agenda!=null:
		var planned: Dictionary = agenda.next_commitment(p)
		if planned.minutes<result.minutes: result = planned
	for offset in range(0, 3):
		var day = (weekday() + offset) % 7
		for routine in life.routines(p) if life!=null else definitions[p.id].routines:
			if day not in routine.on_days:
				continue
			var gap = offset * 1440 + int(routine.start_minute) - minute_of_day()
			if gap > 0 and gap < result.minutes:
				result = {"minutes": gap, "id": routine.id}
	return result

func _routine_action(r: Dictionary) -> String:
	if r.has("action"): return r.action
	if r.id=="after_school_home": return "hobby"
	if "sleep" in r.id:
		return "sleep"
	if r.id == "school" or r.id == "classes":
		return "school"
	if r.id in ["after_school_care","support_care"]:
		return "care"
	if r.id=="support_chores": return "chores"
	return "work"

func _place_for(p: Dictionary, location: String) -> String:
	return home_for(p) if location == "home" else location

func home_for(p: Dictionary) -> String:
	return life.home_for(p) if life!=null else HOME[definitions[p.id].household_id]

func _tick_person(p: Dictionary) -> void:
	if not life.is_alive(p): return
	p.hunger = clampf(p.hunger + HUNGER_PER_MINUTE, 0, 1)
	p.fatigue = clampf(p.fatigue + FATIGUE_PER_MINUTE, 0, 1)
	p.connection = clampf(p.connection + 0.0006, 0, 1)
	p.quiet = clampf(p.quiet + (0.0005 if p.action == "meet" else -0.00015), 0, 1)
	if p.meeting_id.is_empty():
		var r = _routine_at(p)
		if not r.is_empty() and p.routine_id != r.id:
			_assign(p, _routine_action(r), _place_for(p, r.place), 30, ROUTINE_NAMES.get(r.id, "予定の時間"))
			p.routine_id = r.id
		elif r.is_empty() and not p.routine_id.is_empty():
			p.routine_id = ""
			_choose_action(p)
	if p.moving:
		_move(p)
		return
	if not p.meeting_id.is_empty():
		return
	p.activity_minutes += 1
	social.activity_tick(p)
	work_family.activity_tick(p)
	life.activity_tick(p)
	p.remaining -= 1
	match p.action:
		"sleep":
			p.fatigue = maxf(0, p.fatigue - 0.004)
		"rest":
			p.fatigue = maxf(0, p.fatigue - 0.003)
			p.quiet = maxf(0, p.quiet - 0.003)
		"eat":
			p.hunger = maxf(0, p.hunger - 0.035)
		"hobby":
			p.quiet = maxf(0, p.quiet - 0.0015)
			p.goal_progress = minf(1, p.goal_progress + work_family.hobby_progress(p))
		"photo":
			p.quiet = maxf(0,p.quiet-.0015)
			if p.id=="fumi" or definitions[p.id].get("goal_activity","")=="photo": p.goal_progress = minf(1,p.goal_progress+work_family.hobby_progress(p))
		"care":
			p.connection = maxf(0, p.connection - 0.002)
		"own_life":
			p.hunger = maxf(0,p.hunger-.006)
			p.fatigue = maxf(0,p.fatigue-.003)
	if p.goal_progress >= 1 and not p.goal_notified:
		p.goal_notified = true
		_remember(p, "", "取り組みが一歩進んだ", p.current_goal, "goal")
		life.goal_completed(p)
	if p.remaining <= 0:
		_choose_action(p)

func _choose_action(p: Dictionary) -> void:
	_reconcile_weather_clock()
	if not life.is_alive(p): return
	if not p.meeting_id.is_empty():
		return
	var d = definitions[p.id]
	var home = home_for(p)
	var r = _routine_at(p)
	if not r.is_empty():
		_assign(p, _routine_action(r), _place_for(p, r.place), 30, ROUTINE_NAMES.get(r.id, "予定の時間"))
		p.routine_id = r.id
		return
	if agenda!=null and agenda.prepare(p): return
	var options: Array = [
		{"kind":"rest", "place":home, "need":p.fatigue, "goal":0.15, "relation":0.15, "role":0.3, "habit":0.4, "fun":0.5, "cost":0.1, "reason":"自分のペースで休みたい"},
		{"kind":"eat", "place":home, "need":p.hunger, "goal":0.2, "relation":0.2, "role":0.4, "habit":0.6, "fun":0.55, "cost":0.1, "reason":"そろそろ食事にしよう"},
		{"kind":"social", "place":"bakery_cafe", "need":p.connection, "goal":d.values.belonging, "relation":0.5, "role":0.3, "habit":0.3, "fun":d.traits.extraversion, "cost":p.quiet*0.6, "reason":"誰かの顔を見て、近況を聞きたい"},
		{"kind":"hobby", "place":_hobby_place(p), "need":maxf(p.quiet, 0.3), "goal":d.values.creativity, "relation":0.2, "role":0.4, "habit":0.65, "fun":0.75, "cost":p.fatigue*0.4, "reason":p.current_goal if p.goal_kind!="career" else (d.goals[1] if p.id!="aoi" else "好きなものの制作と記録を、自分のペースで続けたい")},
		{"kind":"photo", "place":"garden", "need":p.quiet*0.6+p.connection*0.2, "goal":d.values.autonomy*0.7, "relation":0.2, "role":0.2, "habit":0.3, "fun":0.6, "cost":0.2, "reason":"少し外へ出て、町を眺めたい"}
	]
	work_family.add_options(p,options)
	life.add_options(p,options)
	planner.add_options(p,options)
	# A place the player adds becomes an actual alternative for free time.
	var seat := activities.reserve(p,"social","square")
	if not seat.is_empty():
		options.append({"kind":"social", "place":"square", "need":p.connection, "goal":d.values.belonging, "relation":.5, "role":.3, "habit":.3, "fun":d.traits.extraversion, "cost":p.position.distance_to(seat.approach)*.015+p.quiet*.6, "reason":"広場で休みながら、誰かと話せたらいいな"})
	if p.fatigue > 0.78:
		_assign(p, "rest", home, 60, "疲れたので、まず休みたい")
		return
	if p.hunger > 0.75:
		_assign(p, "eat", home, 25, "お腹がすいた。食事を先にしよう")
		return
	var observed_weather := weather.snapshot()
	for o in options:
		o.weather_exposure = resident_weather.evaluate(p,o,observed_weather)
		if o.kind=="social": o.relation = social.venue_interest(p,o.place)
		o.score = .26*o.need+.20*o.goal+.16*o.relation+.10*o.role+.08*o.habit+.08*o.fun-.12*o.cost
		o.score += social.habit_bonus(p,o)
		o.score += life.action_bonus(p,o)
		o.score -= o.weather_exposure.penalty
		o.score += cognition.action_bonus(p,o.kind,o.place,o.get("partner",""))
		if p.supported and o.kind == "hobby":
			o.score += 0.06
	options.sort_custom(func(a,b): return a.score > b.score)
	var shortlist: Array = []
	for o in options:
		if o.score >= options[0].score - 0.12 and shortlist.size() < 3:
			shortlist.append(o)
	var total: float = 0
	for o in shortlist:
		o.weight = exp((o.score-options[0].score)/0.08)
		total += o.weight
	var roll = rng.randf()*total
	var chosen = shortlist[0]
	for o in shortlist:
		roll -= o.weight
		if roll <= 0:
			chosen = o
			break
	var reason: String = resident_weather.reason(chosen.reason,chosen.weather_exposure,observed_weather)
	if chosen.kind in ["joint_work","social_plan","planned_project","play"]:
		if planner.begin(p,chosen): return
		_assign(p,"rest",home,30,"相手の予定も大切にして、次の機会を待とう")
		return
	if not p.inspiration.is_empty() and elapsed<p.inspiration.until and chosen.kind==p.inspiration.kind:
		reason += "。%sさんの記録を参考にしてみたい"%person(p.inspiration.source).name
	_assign(p, chosen.kind, chosen.place, rng.randi_range(35, 75), reason, chosen.get("target"))
	p.legacy_read_id = chosen.get("legacy_id","")
	p.supported = false

func _reconcile_weather_clock() -> void:
	# Normal play only ticks the saved timeline. Public clock fields are also
	# used by scenario fixtures/debug time jumps; explicitly reconcile those
	# edits here, never during load validation or presentation.
	if weather==null: return
	if weather.matches_clock(elapsed,minute_of_day(),int(day_index()/3.0)%4):
		weather.tick(elapsed,minute_of_day(),int(day_index()/3.0)%4)
		return
	var prior: int = weather.snapshot().elapsed
	if elapsed<prior:
		# A backwards debug jump starts a new timeline, not a saved replay.
		weather.reset(posmod(world_seed,2147483648),minute_of_day(),int(day_index()/3.0)%4,day_index()%3,elapsed)
	else:
		var old_day: int = int((start_minute+prior)/1440.0)
		weather.rebase_calendar(prior,posmod(start_minute+prior,1440),int(old_day/3.0)%4,old_day%3)
		weather.tick(elapsed,minute_of_day(),int(day_index()/3.0)%4)

func _hobby_place(p: Dictionary) -> String:
	var configured: String = definitions[p.id].get("hobby_place","")
	if not configured.is_empty(): return _place_for(p,configured)
	if p.id == "osamu":
		return "workshop"
	if p.id == "fumi":
		return "garden"
	return home_for(p)

func _assign(p: Dictionary, kind: String, place: String, duration: float, reason: String, exact_target: Variant = null, spot_id: String = "") -> void:
	_finish_activity_experience(p)
	p.preparing_agenda_id = ""
	var activity: Dictionary = activities.spots.get(spot_id,{})
	if activity.is_empty() and exact_target==null: activity = activities.reserve(p,kind,place)
	p.activity_spot = activity.get("id","")
	p.action = kind
	p.reason = reason
	p.remaining = duration
	p.action_elapsed = 0
	p.habit_recorded = false
	p.session_meal_paid = false
	p.legacy_read_id = ""
	p.legacy_read_recorded = false
	p.destination = place
	p.cognition_session = {"kind":kind,"place":place,"fatigue":p.fatigue,"quiet":p.quiet}
	var index = people.find(p)
	p.target = exact_target if exact_target != null else SITES.get(place, Vector3.ZERO) + _offset(index)
	if not activity.is_empty(): p.target = activity.approach
	p.path = route(p.position, p.place, p.target, place)
	p.moving = not p.path.is_empty()
	if not p.moving:
		p.place = place

func _finish_activity_experience(p: Dictionary) -> void:
	if cognition==null or not p.meeting_id.is_empty() or p.moving or p.get("action_elapsed",0)<20: return
	var session: Dictionary = p.get("cognition_session",{})
	if session.is_empty(): return
	var kind: String = session.kind
	if kind=="prepare": return
	var relief := maxf(0,float(session.fatigue)-float(p.fatigue))
	var enjoyment := clampf(.5+relief+(.12 if kind in ["hobby","photo"] else 0),0,1)
	cognition.experience(p,"",kind,{"place":session.place},
		{"enjoyment":enjoyment,"burden":clampf(p.fatigue-float(session.fatigue)+.25,0,1)})

func route(origin: Vector3, origin_place: String, target: Vector3, destination: String) -> Array:
	if origin.distance_to(target) < .1:
		return []
	# During a journey, place still names the departure site. Estimate a new
	# route from the room the person physically occupies, including its aisles.
	if not activities.inside(origin_place,origin):
		for site in activities.rooms:
			if activities.inside(site,origin):
				origin_place = site
				break
	if origin_place == destination and activities.inside(destination,origin) and activities.inside(destination,target):
		return activities.indoor_route(destination,origin,target)
	var public_shortcut := origin_place==destination and origin.distance_to(target)<3
	var public_obstacles: Array = _public_route_obstacles()
	if public_shortcut:
		if _public_segment_clear(origin,target,public_obstacles): return [target]
	var path: Array = []
	var departure: Vector3 = ENTRIES.get(origin_place, origin)
	if ENTRIES.has(origin_place) and (activities.inside(origin_place,origin) or origin.distance_to(departure)<.6):
		if origin.distance_to(departure)>.1: path.append_array(activities.indoor_route(origin_place,origin,departure))
		path.append(OUTER_ENTRIES[origin_place])
		departure = _street_corner(OUTER_ENTRIES[origin_place])
		path.append(departure)
	else:
		departure = origin
	var entry: Vector3 = ENTRIES.get(destination, target)
	var outside: Vector3 = OUTER_ENTRIES.get(destination,entry)
	var approach = _street_corner(outside) if ENTRIES.has(destination) else entry
	var begin = graph.get_closest_point(departure)
	var end = graph.get_closest_point(approach)
	for point in graph.get_point_path(begin, end):
		if path.is_empty() or path[-1].distance_to(point) > .1:
			path.append(point)
	if path.is_empty() or path[-1].distance_to(approach) > .1:
		path.append(approach)
	if path.is_empty() or path[-1].distance_to(outside) > .1:
		path.append(outside)
	if path.is_empty() or path[-1].distance_to(entry) > .1:
		path.append(entry)
	if entry.distance_to(target) > .1:
		path.append_array(activities.indoor_route(destination,entry,target))
	# Keep the street graph for the detour. Its final connectors also need to
	# clear furniture: the closest street point can lie across the same table.
	return _public_clear_path(origin,path,public_obstacles)

func _public_route_obstacles() -> Array:
	# ActivityPlaces already expands authored public tables by the .18m body
	# radius. The editable PR_Bench bounds are x +/- .875, z -.334 .. .310;
	# round outward before applying the same clearance, leaving its .65m
	# front approach accessible. A reservation does not make furniture vanish.
	var result: Array = activities.public_obstacles.duplicate()
	for bench in benches:
		result.append(Rect2(Vector2(bench.x-.88,bench.z-.34),Vector2(1.76,.66)).grow(.18))
	return result

func _public_segment_clear(first: Vector3, second: Vector3, occupied: Array) -> bool:
	var a := Vector2(first.x,first.z);var b := Vector2(second.x,second.z)
	for rect: Rect2 in occupied:
		if rect.has_point(a) or rect.has_point(b): return false
		var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for side in 4:
			if Geometry2D.segment_intersects_segment(a,b,corners[side],corners[(side+1)%4])!=null: return false
	return true

func _public_clear_path(origin: Vector3, path: Array, occupied: Array) -> Array:
	var result: Array = []
	var previous := origin
	for point: Vector3 in path:
		if _public_segment_clear(previous,point,occupied):
			result.append(point)
		else:
			var detour := AStar3D.new()
			var corners: Array = [previous,point]
			for rect: Rect2 in occupied:
				# A small extra margin keeps segments off an inclusive rectangle
				# edge, without changing the requested endpoint or body size.
				var outer := rect.grow(.02)
				for corner: Vector2 in [outer.position,Vector2(outer.end.x,outer.position.y),outer.end,Vector2(outer.position.x,outer.end.y)]:
					corners.append(Vector3(corner.x,0,corner.y))
			for index in corners.size(): detour.add_point(index,corners[index])
			for first in corners.size():
				for second in range(first+1,corners.size()):
					if _public_segment_clear(corners[first],corners[second],occupied): detour.connect_points(first,second)
			var steps := detour.get_point_path(0,1)
			# Never fall back to the known blocked straight line.
			if steps.is_empty(): return []
			for index in range(1,steps.size()): result.append(steps[index])
		previous = point
	return result

func _street_corner(entry: Vector3) -> Vector3:
	return Vector3(-5 if entry.x < -5 else (4.4 if entry.x > 4.4 else 0),0,entry.z)

func _available_bench(origin: Vector3, participants: Array = []) -> Variant:
	var best: Variant = null
	var distance = INF
	for bench in benches:
		var busy = false
		if activities.pair_for("bench",bench,participants).size()<2: busy = true
		for m in meetings:
			if m.location == "bench" and m.get("center",Vector3.ZERO).distance_to(bench)<1.8:
				busy = true
		if not busy and origin.distance_to(bench)<distance:
			best = bench
			distance = origin.distance_to(bench)
	return best

func _move(p: Dictionary) -> void:
	var distance: float = WALK_METERS_PER_MINUTE
	p.travel_minutes += 1
	while distance > 0 and not p.path.is_empty():
		var point: Vector3 = p.path[0]
		var gap = p.position.distance_to(point)
		if gap <= distance:
			p.position = point
			p.path.pop_front()
			distance -= gap
		else:
			p.position = p.position.move_toward(point, distance)
			distance = 0
	if p.path.is_empty():
		p.moving = false
		p.place = p.destination

func propose_rest(id: String) -> Dictionary:
	var p = person(id)
	if not life.is_alive(p):
		return {"status":"decline", "text":"その人が見つかりません"}
	var r = _routine_at(p)
	if not r.is_empty() or not p.meeting_id.is_empty():
		return _reply(p, "counteroffer", "今は%s。一区切りついてから休みたい。" % commitment_text(p))
	_assign(p, "rest", home_for(p), 60, "少し休もうと思う。声をかけてくれてありがとう")
	return _reply(p, "accept", "少し休もうと思う。自分の時間も必要だね。")

func support_goal(id: String) -> Dictionary:
	var p = person(id)
	if not life.is_alive(p):
		return {"status":"decline", "text":"その人が見つかりません"}
	var r = _routine_at(p)
	if not r.is_empty() or not p.meeting_id.is_empty():
		return _reply(p, "defer", "そのことは気になっている。今の予定が済んだら考えたい。")
	p.supported = true
	_choose_action(p)
	return _reply(p, "accept", "やってみたいと思っていた。自分のペースで取り組んでみる。")

func propose_meeting(first: String, second: String, location: String = "bench") -> Dictionary:
	return social.propose(first,second,location)

func confirm_offer(selected: String) -> Dictionary:
	return social.confirm_offer(selected)

func propose_support(receiver: String, giver: String) -> Dictionary:
	return work_family.propose_support(receiver,giver)

func propose_project(first: String, second: String, activity: String = "") -> Dictionary:
	return work_family.propose_project(first,second,activity)

func propose_play(first: String, second: String) -> Dictionary:
	return tabletop.propose(first,second)

func _begin_meeting(a: Dictionary, b: Dictionary, center: Vector3, location: String, spontaneous: bool, duration: int = 25, not_before: int = 0, appointment_id: String = "", venue_override: String = "", activity_group: String = "") -> bool:
	var venue = "square" if location == "bench" else (a.place if spontaneous else ("bakery_cafe" if location=="cafe" else "workshop"))
	if not venue_override.is_empty(): venue = venue_override
	var group := activity_group if not activity_group.is_empty() else location
	var pair := activities.pair_for(group,center,[a.id,b.id])
	if group in ["bench","cafe","radio","model","bread","photo","music","craft","tabletop"] and pair.size()<2: return false
	meeting_serial += 1
	var id = "meeting_%d" % meeting_serial
	var m = {"id":id,"a":a.id,"b":b.id,"location":location,"center":center,"state":"travel","duration":duration,"remaining":duration,"not_before":not_before,"appointment_id":appointment_id,"waited":0,"spontaneous":spontaneous}
	meetings.append(m)
	for i in 2:
		var p = a if i == 0 else b
		p.meeting_id = id
		_assign(p, "meet", venue, duration, "相手と合流してから、ゆっくり話したい", center+Vector3(-.6 if i==0 else .6,0,.08 if location=="bench" else 0),pair[i].id if pair.size()==2 else "")
	if location!="project" and planner!=null: planner.track(m)
	return true

func _tick_meetings() -> void:
	var ended: Array = []
	for m in meetings:
		var a = person(m.a)
		var b = person(m.b)
		if not work_family.meeting_compatible(a,m) or not work_family.meeting_compatible(b,m):
			_finish_meeting(m, false)
			ended.append(m)
			continue
		if tabletop.handles(m):
			var play_stage: String = tabletop.advance(m)
			if play_stage in ["completed","interrupted"]:
				_finish_meeting(m,play_stage=="completed");ended.append(m)
			continue
		if sewing.supports(m):
			if not m.has("sewing_id") and not sewing.begin(m):
				_finish_meeting(m,false);ended.append(m);continue
			var sewing_stage: String = sewing.advance(m)
			if sewing_stage in ["completed","interrupted"]:
				_finish_meeting(m,sewing_stage=="completed");ended.append(m);continue
			if sewing_stage=="working":
				if m.state!="engaged":
					m.state="engaged";planner.engaged(m)
				if not work_family.project_tick(m):
					_finish_meeting(m,false);ended.append(m);continue
				m.remaining=maxf(0,float(m.remaining)-1)
				for p in [a,b]: p.connection=maxf(0,p.connection-.006)
				sewing.worked(m)
				m.remaining=sewing.work_remaining(m)
			continue
		if interactions.supports(m):
			if not m.has("interaction_id") and not interactions.begin(m):
				_finish_meeting(m,false);ended.append(m);continue
			var stage: String = interactions.advance(m)
			if stage=="interrupted":
				_finish_meeting(m,false);ended.append(m);continue
			if stage=="completed":
				_finish_meeting(m,true);ended.append(m);continue
			if stage!="working": continue
			if m.state!="engaged":
				m.state = "engaged"
				planner.engaged(m)
				_log(a.id,"ラジオを作業台へ運びました","%sさんと、実物を支えながらラジオを調整する。"%b.name)
			if not work_family.project_tick(m):
				_finish_meeting(m,false);ended.append(m);continue
			m.remaining -= 1
			for p in [a,b]: p.connection = maxf(0,p.connection-.012)
			interactions.worked(m)
			continue
		if m.state in ["travel","waiting"]:
			m.waited += 1
			if not a.moving and not b.moving:
				if elapsed<m.get("not_before",0):
					m.state = "waiting"
					a.reason = "約束の時刻まで、ここでひと息つく"
					b.reason = "少し早く着いた。約束の時刻を待っている"
					continue
				m.state = "engaged"
				planner.engaged(m)
				a.reason = "%sさんと、近況を話している" % b.name
				b.reason = "%sさんと、同じ時間を過ごしている" % a.name
				if m.get("mode","")=="project":
					a.reason = "%sさんと、%sを一緒に進めている"%[b.name,m.project.title]
					b.reason = "%sさんと、%sに取り組んでいる"%[a.name,m.project.title]
				_log(a.id, "二人が合流しました", "%sと%sが、%sを始めた。" % [a.name,b.name,m.project.title if m.get("mode","")=="project" else "同じ場所で話す時間"])
			elif m.waited > 180:
				_finish_meeting(m,false)
				ended.append(m)
		else:
			if not work_family.project_tick(m):
				_finish_meeting(m,false)
				ended.append(m)
				continue
			m.remaining -= 1
			for p in [a,b]:
				p.connection = maxf(0, p.connection-.012)
			if m.remaining <= 0:
				_finish_meeting(m,true)
				ended.append(m)
	for m in ended:
		meetings.erase(m)

func _finish_meeting(m: Dictionary, completed: bool) -> void:
	var a = person(m.a)
	var b = person(m.b)
	if tabletop.handles(m):
		tabletop.end(m,completed)
		planner.finish(m,completed)
		for p in [a,b]: p.meeting_id = "";p.remaining = 0;p.routine_id = ""
		return
	sewing.end(m,completed)
	interactions.end(m,completed)
	# Finished work remains real even if a later cleanup is forcibly interrupted.
	var achieved: bool = completed or m.get("work_completed",false)
	# A replay of a completed object is not a new completed conversation.
	var shared_success: bool = bool(m.get("sewing_presented",false)) if sewing.supports(m) else achieved
	social.finish(m,shared_success)
	if achieved: work_family.finish_project(m)
	if agenda!=null: agenda.finish(m,achieved)
	if shared_success:
		var used_skill: String = m.get("project",{}).get("skill","")
		_learn_profile(a,b,used_skill)
		_learn_profile(b,a,used_skill)
	planner.finish(m,achieved)
	if not achieved and m.get("mode","")=="project" and m.state=="engaged":
		for pair in [[a,b],[b,a]]:
			cognition.experience(pair[0],pair[1].id,"joint_work",{"place":pair[0].place},
				{"completed":false,"enjoyment":.3,"burden":.65})
	if not completed and not achieved:
		_log(a.id,"予定を見直しました","次の予定や移動の都合で、今回は話す時間を取れなかった。")
	for p in [a,b]:
		p.meeting_id = ""
		p.remaining = 0
		p.routine_id = ""

func _learn_profile(observer: Dictionary, other: Dictionary, practiced_skill: String = "") -> void:
	var skill := practiced_skill
	if skill.is_empty():
		for interest in other.interests:
			if other.skills.has(interest):
				skill = interest
				break
	var skills := {}
	if not skill.is_empty(): skills[skill] = other.skills.get(skill,0)
	_log(other.id,"得意なことを知った","%sさんの%sについて、%sさんと話した。"%[
		other.name,ResidentCognition.INTEREST_LABELS.get(skill,"好きなこと"),observer.name])
	var fact: Dictionary = events[-1]
	fact.fact = "profile"
	fact.value = {"person":other.id,"skills":skills,"interests":other.interests.slice(0,1)}
	fact.participants = [observer.id,other.id]
	cognition.observe(other,fact)
	cognition.observe(observer,fact)

func _try_spontaneous() -> void:
	for a in people:
		if a.moving or not a.meeting_id.is_empty() or a.action != "social":
			continue
		var candidates = people.duplicate()
		candidates.sort_custom(func(b,c): return social.partner_score(a,b)>social.partner_score(a,c))
		for b in candidates:
			if not life.is_alive(b) or a.id == b.id or b.moving or not b.meeting_id.is_empty():
				continue
			if b.action not in ["social","photo","rest"] or b.quiet > .6:
				continue
			if a.position.distance_to(b.position) < 2.8 and _routine_at(b).is_empty():
				if _next_commitment(a).minutes >= 60 and _next_commitment(b).minutes >= 60:
					var seat = _available_bench((a.position+b.position)*.5,[a.id,b.id]) if a.place=="square" else null
					_begin_meeting(a,b,seat if seat!=null else (a.position+b.position)*.5,"bench" if seat!=null else "standing",true)
					return

func _relation(p: Dictionary, other: String) -> Dictionary:
	if not p.relationships.has(other):
		p.relationships[other] = {"from":p.id,"to":other,"roles":["acquaintance"],"familiarity":.05,"trust":.2,"ease":.25,"unresolved_expectation":0.0}
	return p.relationships[other]

func _reply(p: Dictionary, status: String, text: String) -> Dictionary:
	var context = "%s:%s:%s" % [p.id,status,text]
	if rejection_context.get(p.id,"") != context:
		_log(p.id, {"accept":"提案への返事","defer":"少し待ってほしい","decline":"今は休みたい","counteroffer":"別の案を考えたい"}.get(status,"返事"), text)
		rejection_context[p.id] = context
	return {"status":status,"text":text,"resident_id":p.id}

func place_bench(position: Vector3) -> Dictionary:
	position = Vector3(snappedf(position.x,.5),0,snappedf(position.z,.5))
	if shared_budget < 20:
		return {"status":"decline","text":"町の共有予算が足りません"}
	if absf(position.x)>5 or position.z<0 or position.z>8:
		return {"status":"decline","text":"広場の中の、通りや入口から離れた場所に置いてください"}
	if activities.bench_overlaps_furniture(position):
		return {"status":"decline","text":"作業台や家具と重ならない場所を選んでください"}
	for bench in benches:
		if bench.distance_to(position)<1.8:
			return {"status":"decline","text":"ベンチ同士の間を少し空けてください"}
	benches.append(Vector3(snappedf(position.x,.5),0,snappedf(position.z,.5)))
	activities.configure_benches(benches)
	shared_budget -= 20
	_log("", "座って過ごせる場所が増えました", "このベンチを使うか、誰と過ごすかは住人が決めます。")
	town_changed.emit()
	return {"status":"accept","text":"ベンチを置きました"}

func _remember(p: Dictionary, other: String, title: String, text: String, kind: String) -> void:
	p.memories.append({"minute":elapsed,"other":other,"title":title,"text":text,"kind":kind})
	_log(p.id,title,text)
	if cognition!=null: cognition.observe(p,events[-1])

func _log(id: String, title: String, text: String) -> void:
	event_serial += 1
	var e = {"event_id":"event_%d"%event_serial,"minute":elapsed,"clock":clock_text(),"day":day_index(),"resident_id":id,"title":title,"text":text}
	events.append(e)
	if events.size()>500:
		events.pop_front()
	event_added.emit(e)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(LEGACY_SAVE_PATH)

func save_game(path: String = SAVE_PATH) -> bool:
	_reconcile_weather_clock()
	var data = {"schema":SaveValidation.CURRENT_SCHEMA,"elapsed":elapsed,"start_minute":start_minute,"epoch_weekday":epoch_weekday,"rng_state":str(rng.state),"people":people,"events":events,"meetings":meetings,"benches":benches,"budget":shared_budget,"meeting_serial":meeting_serial,"remainder":minute_remainder,"social":social.serialize(),"work_family":work_family.serialize(),"life":life.serialize()}
	data.world_seed = world_seed
	data.event_serial = event_serial
	data.agenda = agenda.serialize()
	data.interactions = interactions.serialize()
	data.tabletop = tabletop.serialize()
	data.weather = weather.serialize()
	data.sewing = sewing.serialize()
	data.route_layout = 1
	var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_encode(data)))
	file.close()
	var error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))
	return error == OK

func load_game(path: String = SAVE_PATH) -> bool:
	load_error = ""
	if path==SAVE_PATH and not FileAccess.file_exists(path) and FileAccess.file_exists(LEGACY_SAVE_PATH):
		path = LEGACY_SAVE_PATH
	if not FileAccess.file_exists(path):
		return false
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or not raw.get("people") is Array: return false
	if raw.get("schema",0)!=SaveValidation.CURRENT_SCHEMA:
		load_error = "この開発版では保存形式が変わりました。新しい町を始めてください。"
		return false
	# Replays and population comparisons keep their saved authored roster.
	if raw.people.size() not in [BASE_POPULATION,EXPANDED_POPULATION]: return false
	var cast: Dictionary = definitions if definitions.size()==raw.people.size() else _cast_definitions(raw.people.size())
	if cast.is_empty() or not SaveValidation.valid(raw,cast,SITES,HOME.keys()):
		return false
	var restored_weather := WorldWeather.new()
	if not restored_weather.restore(raw.get("weather")): return false
	var data = _decode(raw)
	weather = restored_weather
	definitions = cast
	people = data.people
	elapsed = int(data.elapsed)
	start_minute = int(data.start_minute)
	epoch_weekday = int(data.epoch_weekday)
	rng.state = WorldWeather.parse_rng_state(data.rng_state)
	events = data.events
	meetings = data.meetings
	benches = data.benches
	shared_budget = int(data.budget)
	meeting_serial = int(data.meeting_serial)
	world_seed = int(data.get("world_seed",71103))
	event_serial = int(data.get("event_serial",0))
	for event in events:
		var event_id: String = event.get("event_id","")
		if event_id.begins_with("event_"): event_serial = maxi(event_serial,int(event_id.trim_prefix("event_")))
	minute_remainder = float(data.remainder)
	social.restore(data.get("social",{}))
	work_family.restore(data.get("work_family",{}))
	life.restore(data.get("life",{}))
	agenda.restore(data.get("agenda",{}))
	interactions.restore(data.get("interactions",{}))
	tabletop.restore(data.get("tabletop",{}))
	sewing.restore(data.sewing)
	for p in people:
		cognition.upgrade_person(p)
		planner.upgrade_person(p)
		support_plans.upgrade_person(p)
		tabletop.upgrade_person(p)
	activities.configure_benches(benches)
	for p in people:
		if not activities.spots.has(p.get("activity_spot","")): p.activity_spot = ""
		if int(data.get("route_layout",0))<1 and p.moving:
			var origin_place: String = p.place
			for site in activities.rooms:
				if activities.inside(site,p.position): origin_place = site;break
			p.path = route(p.position,origin_place,p.target,p.destination)
			p.moving = not p.path.is_empty()
	rejection_context.clear()
	town_changed.emit()
	return true

func _encode(value: Variant) -> Variant:
	if value is Vector3:
		return {"__vector3":[value.x,value.y,value.z]}
	if value is Array:
		var out: Array = []
		for v in value:
			out.append(_encode(v))
		return out
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value:
			out[key] = _encode(value[key])
		return out
	return value

func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("__vector3"):
			return Vector3(value.__vector3[0],value.__vector3[1],value.__vector3[2])
		var out: Dictionary = {}
		for key in value:
			out[key] = _decode(value[key])
		return out
	if value is Array:
		var out: Array = []
		for v in value:
			out.append(_decode(v))
		return out
	return value
