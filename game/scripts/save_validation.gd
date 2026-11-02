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
	if int(raw.schema) not in [1,2] or not raw.rng_state.is_valid_int(): return false
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
	if raw.has("social"):
		var social = raw.social
		if not social is Dictionary or not social.get("appointments") is Array or not social.get("offer") is Dictionary or not number(social.get("serial")): return false
		for planned in social.appointments:
			if not record(planned,["id","a","b","location","state"],["start","duration","made_at"]): return false
			if not definitions.has(planned.a) or not definitions.has(planned.b): return false
		if not social.offer.is_empty():
			if not record(social.offer,["a","b","location"],["start","duration","made_at"]): return false
			if not definitions.has(social.offer.a) or not definitions.has(social.offer.b): return false
	return true
