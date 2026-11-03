class_name SaveValidation
extends RefCounted

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func encoded(value: Variant, depth: int = 0) -> bool:
	if depth>32: return false
	if value is Dictionary:
		if value.has("__vector3"):
			var xyz = value.__vector3
			if not xyz is Array or xyz.size()!=3: return false
			for coordinate in xyz:
				if not number(coordinate): return false
			return true
		for key in value:
			if not encoded(value[key],depth+1): return false
	if value is Array:
		if value.size()>10000: return false
		for entry in value:
			if not encoded(entry,depth+1): return false
	return true

static func vector(value: Variant) -> bool:
	return value is Dictionary and value.has("__vector3") and encoded(value)

static func record(value: Variant, text_keys: Array, numeric_keys: Array) -> bool:
	if not value is Dictionary: return false
	for key in text_keys:
		if not value.get(key) is String: return false
	for key in numeric_keys:
		if not number(value.get(key)): return false
	return true

static func valid(raw: Variant, definitions: Dictionary, sites: Dictionary) -> bool:
	if not raw is Dictionary or not encoded(raw): return false
	if not record(raw,["rng_state"],["schema","elapsed","start_minute","epoch_weekday","budget","meeting_serial","remainder"]): return false
	if int(raw.schema) not in [1,2,3,4] or not raw.rng_state.is_valid_int(): return false
	if raw.has("route_layout") and (not number(raw.route_layout) or raw.route_layout<0 or raw.route_layout!=int(raw.route_layout)): return false
	if raw.elapsed<0 or raw.start_minute<0 or raw.start_minute>=1440 or raw.epoch_weekday<0 or raw.epoch_weekday>6: return false
	if raw.budget<0 or raw.remainder<0 or raw.remainder>=1: return false
	for key in ["people","events","meetings","benches"]:
		if not raw.get(key) is Array: return false
	if raw.people.size()!=definitions.size(): return false
	var seen = {}
	for p in raw.people:
		if not record(p,["id","name","occupation","place","destination","action","reason","meeting_id","routine_id"],["age","remaining","fatigue","hunger","connection","quiet","goal_progress","travel_minutes","activity_minutes"]): return false
		if not definitions.has(p.id) or seen.has(p.id): return false
		seen[p.id] = true
		if not sites.has(p.place) or not sites.has(p.destination): return false
		for key in ["position","target"]:
			if not vector(p.get(key)): return false
		for key in ["moving","supported","goal_notified"]:
			if not p.get(key) is bool: return false
		for key in ["work_satisfaction","earned_today","care_minutes","private_project","action_elapsed"]:
			if p.has(key) and not number(p[key]): return false
		for key in ["session_meal_paid","habit_recorded","career_retired"]:
			if p.has(key) and not p[key] is bool: return false
		if p.has("alive") and not p.alive is bool: return false
		if p.has("activity_spot") and not p.activity_spot is String: return false
		for key in ["base_age"]:
			if p.has(key) and not number(p[key]): return false
		for key in ["stage","current_goal","goal_kind","legacy_read_id","household_override"]:
			if p.has(key) and not p[key] is String: return false
		if p.has("goal_kind") and p.goal_kind not in ["creative","career","model"]: return false
		if p.has("household_override") and p.household_override not in ["","ogawa","saeki","shared_house","aoi_apartment"]: return false
		if p.has("known_plans"):
			if not p.known_plans is Array: return false
			for plan in p.known_plans:
				if not plan is String: return false
		if p.has("goal_history"):
			if not p.goal_history is Array: return false
			for goal in p.goal_history:
				if not record(goal,["goal","reason"],["progress","minute"]): return false
		if p.has("legacy_read_recorded") and not p.legacy_read_recorded is bool: return false
		if p.has("inspiration"):
			if not p.inspiration is Dictionary: return false
			if not p.inspiration.is_empty() and (not record(p.inspiration,["kind","source","title"],["until"]) or not definitions.has(p.inspiration.source)): return false
		for key in ["path","memories"]:
			if not p.get(key) is Array: return false
		for point in p.path:
			if not vector(point): return false
		for memory in p.memories:
			if not record(memory,["other","title","text","kind"],["minute"]): return false
		if not p.get("relationships") is Dictionary: return false
		for other in p.relationships:
			if not definitions.has(other) or not record(p.relationships[other],["from","to"],["familiarity","trust","ease","unresolved_expectation"]): return false
		if p.has("habits"):
			if not p.habits is Array: return false
			for habit in p.habits:
				if not record(habit,["kind","place","cue"],["strength"]) or not habit.get("days") is Array: return false
				for day in habit.days:
					if not number(day): return false
	for e in raw.events:
		if not record(e,["clock","resident_id","title","text"],["minute","day"]): return false
	for bench in raw.benches:
		if not vector(bench): return false
	for meeting in raw.meetings:
		if not record(meeting,["id","a","b","location","state"],["remaining","waited"]): return false
		if not definitions.has(meeting.a) or not definitions.has(meeting.b): return false
		if not meeting.get("spontaneous") is bool: return false
		if meeting.get("mode","")=="project":
			if not record(meeting.get("project"),["key","title","place"],["cost"]): return false
			if not vector(meeting.project.get("center")) or not sites.has(meeting.project.place): return false
			if meeting.project.key not in ["radio","model","bread","photo","music","craft"] or not meeting.get("materials_ready") is bool: return false
	if raw.has("social"):
		var social = raw.social
		if not social is Dictionary or not social.get("appointments") is Array or not social.get("offer") is Dictionary or not number(social.get("serial")): return false
		for planned in social.appointments:
			if not record(planned,["id","a","b","location","state"],["start","duration","made_at"]): return false
			if not definitions.has(planned.a) or not definitions.has(planned.b): return false
		if not social.offer.is_empty():
			if not record(social.offer,["a","b","location"],["start","duration","made_at"]): return false
			if not definitions.has(social.offer.a) or not definitions.has(social.offer.b): return false
	if raw.has("work_family"):
		var life = raw.work_family
		if not life is Dictionary or not life.get("households") is Dictionary or not life.get("supports") is Array or not number(life.get("serial")): return false
		for id in ["ogawa","saeki","shared_house"]:
			var h = life.households.get(id)
			if not record(h,[],["cash","home_load","earned_today","spent_today"]) or not h.get("material_days") is Dictionary or not h.get("ledger") is Array: return false
			for entry in h.ledger:
				if not record(entry,[],["day","earned","support","expenses","balance"]): return false
		for help in life.supports:
			if not record(help,["id","giver","receiver","kind","place","state"],["requested","began"]): return false
			if not definitions.has(help.giver) or not definitions.has(help.receiver): return false
		if life.has("projects"):
			if not life.projects is Dictionary: return false
			for key in ["radio","model","bread","photo","music","craft"]:
				if not number(life.projects.get(key)): return false
		if life.households.has("aoi_apartment"):
			if not record(life.households.aoi_apartment,[],["cash","home_load","earned_today","spent_today"]): return false
	if raw.has("life"):
		var course = raw.life
		if not course is Dictionary or not number(course.get("year_seen")): return false
		if not course.get("chapter_ready") is bool or not course.get("chapter_acknowledged") is bool: return false
		if course.has("final_reviewed") and not course.final_reviewed is bool: return false
		if course.has("chapter_mode") and course.chapter_mode not in ["three_years","resumed","last"]: return false
		for key in ["announced","applied","legacy","chronicle"]:
			if not course.get(key) is Array: return false
		for key in ["announced","applied"]:
			for value in course[key]:
				if not value is String: return false
		for entry in course.chronicle:
			if not record(entry,["key","title","text"],["day","minute"]): return false
		for item in course.legacy:
			if not record(item,["id","owner","label","place"],["created","edition","uses"]): return false
			if not definitions.has(item.owner) or not sites.has(item.place) or not vector(item.get("position")): return false
			if not item.get("entries") is Array or not item.get("readers") is Array: return false
			for entry in item.entries:
				if not record(entry,["goal"],["minute"]): return false
			for reader in item.readers:
				if not record(reader,["id"],["edition","minute"]) or not definitions.has(reader.id): return false
	return true
