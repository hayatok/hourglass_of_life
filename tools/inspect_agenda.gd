extends SceneTree

var output := "res://docs/verification/v0.6/agenda-diagnosis"
var label := "working-tree"
var examples := {}
var sim
var report: Array = []
var current: Dictionary = {}
var tracked: Dictionary = {}
var finished: Dictionary = {}
var recent: Array = []
var seen_events := 0
var source_hashes := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for source in ["simulation","resident_agenda","resident_planner","resident_cognition","resident_activities","social_life","work_family","resident_knowledge_exchange"]:
		var source_path: String = "res://game/scripts/"+source+".gd"
		if FileAccess.file_exists(source_path): source_hashes[source] = FileAccess.get_sha256(source_path)
	sim = load("res://game/scripts/simulation.gd").new()
	root.add_child(sim)
	sim.event_added.connect(_event)
	var began := Time.get_ticks_msec()
	for seed_value in range(710,720):
		for intervention in [false,true]:
			current = {"seed":seed_value,"intervention":intervention,"terminal_states":{},"causes":{},"closing_texts":{},"event_titles":{},"attempts_at_terminal":0,"event_count":0,"by_activity":{},"pending":0,"revisions_at_terminal":0,"kept_without_revision":0,"kept_after_revision":0}
			tracked.clear();finished.clear();recent.clear()
			sim.reset(seed_value)
			if intervention: sim.work_family.propose_project("aoi","osamu","radio")
			sim.advance_minutes(12*1440-sim.start_minute)
			_scan_new()
			current.created = sim.agenda.serial
			current.closed = finished.size()
			current.retained_records = sim.agenda.records.size()
			current.pending_records = []
			for record in sim.agenda.records:
				if record.state in ["planned","travel"]:
					current.pending += 1
					current.pending_records.append({"id":record.id,"a":record.a,"b":record.b,"state":record.state,"start":record.start})
			current.accounted = int(current.closed)+int(current.pending)==int(current.created)
			assert(current.accounted,"Every created agreement must have one terminal or pending outcome")
			report.append(current.duplicate(true))
			print("AGENDA_DIAG seed=%d intervention=%s created=%d closed=%d pending=%d causes=%s elapsed_ms=%d"%[seed_value,intervention,current.created,current.closed,current.pending,JSON.stringify(current.causes),Time.get_ticks_msec()-began])
			_write_summary()

	_write_summary()
	print("AGENDA_DIAG_DONE %d full terminal records from %d event callbacks"%[report.reduce(func(total,row): return total+int(row.closed),0),seen_events])
	sim.free()
	quit()

func _event(event: Dictionary) -> void:
	if current.is_empty(): return
	seen_events += 1
	current.event_count += 1
	_count(current.event_titles,event.title)
	recent.append(event.duplicate(true))
	if recent.size()>8: recent.pop_front()
	_scan_new()
	if event.title not in ["約束を過ごした","約束の区切り"]: return
	for record in sim.agenda.records:
		if record.state in ["planned","travel"] or finished.has(record.id) or int(record.finished_at)!=int(event.minute): continue
		if record.a!=event.resident_id: continue
		finished[record.id] = true
		var cause := _cause(record,event.text)
		_count(current.terminal_states,record.state)
		_count(current.causes,cause)
		_count(current.closing_texts,event.text)
		current.attempts_at_terminal += int(record.attempts)
		current.revisions_at_terminal += record.get("revisions",[]).size()
		if record.state=="kept":
			if record.get("revisions",[]).is_empty(): current.kept_without_revision += 1
			else: current.kept_after_revision += 1
		if not current.by_activity.has(record.activity): current.by_activity[record.activity] = {}
		_count(current.by_activity[record.activity],cause)
		var row := _record_snapshot(record)
		row.seed = current.seed;row.intervention = current.intervention
		row.cause = cause;row.closing_text = event.text
		row.created_snapshot = tracked.get(record.id,{})
		row.recent_events = recent.duplicate(true)
		if not examples.has(cause): examples[cause] = []
		if examples[cause].size()<2: examples[cause].append(_json(row))

func _scan_new() -> void:
	for record in sim.agenda.records:
		if not tracked.has(record.id): tracked[record.id] = _record_snapshot(record)

func _record_snapshot(record: Dictionary) -> Dictionary:
	var a: Dictionary = sim.person(record.a)
	var b: Dictionary = sim.person(record.b)
	var result := record.duplicate(true)
	result.now = int(sim.elapsed)
	result.clock = sim.clock_text()
	result.people = [_person(a),_person(b)]
	var activity: Dictionary = sim.agenda._activity(a,b,record.activity)
	if not activity.is_empty():
		activity.place=record.place;activity.center=record.center;activity.group=record.venue if record.activity=="social" else record.activity
		var physical: Array = sim.agenda._physical_pair(activity,[a.id,b.id])
		result.available_pair = sim.activities.pair_for(activity.group,record.center,[a.id,b.id]).size()==2
		result.physical_pair = physical.size()==2
		result.estimated_journeys = {}
		for i in physical.size():
			var p: Dictionary = a if i==0 else b
			result.estimated_journeys[p.id] = sim.agenda._journey_minutes(p,physical[i].approach,record.place) if sim.agenda.has_method("_journey_minutes") else sim.agenda._travel(p.position,p.place,physical[i].approach,record.place)
		result.agreement_now = [sim.agenda._agreement(a,b,activity,record.origin=="resident"),sim.agenda._agreement(b,a,activity,record.origin=="resident")]
	return result

func _person(p: Dictionary) -> Dictionary:
	var authored: Dictionary = sim._authored_routine_at(p)
	var active: Dictionary = sim._routine_at(p)
	var left: int = 0
	if not authored.is_empty():
		var since: int = sim.minute_of_day()-int(authored.start_minute)
		if since<0: since+=1440
		left=maxi(0,int(authored.duration_minutes)-since)
	var support: Array = []
	for help in sim.work_family.supports:
		if help.state in ["travel","active","handoff"] and p.id in [help.giver,help.receiver]: support.append(help.duplicate(true))
	return {"id":p.id,"action":p.action,"place":p.place,"destination":p.destination,"position":p.position,"moving":p.moving,"hunger":p.hunger,"fatigue":p.fatigue,"quiet":p.quiet,"reason":p.reason,"routine":active,"authored_routine":authored,"remaining_routine_minutes":left,"next_commitment":sim._next_commitment(p),"meeting_id":p.meeting_id,"action_remaining":p.remaining,"action_elapsed":p.action_elapsed,"support":support}

func _cause(record: Dictionary, text: String) -> String:
	if record.state=="kept": return "kept"
	if record.state=="ended": return "death_or_departed"
	if not record.get("outcome","").is_empty(): return str(record.outcome)
	if "食事や休息を先" in text: return "meal_or_rest"
	if "移動に必要な時間が変わった" in text: return "changed_journey"
	if "予定どおりに合流できなかった" in text: return "deadline"
	if "使う予定だった場所がなくなった" in text: return "missing_place"
	if "予定していた活動が変わった" in text: return "missing_activity"
	var a: Dictionary = sim.person(record.a)
	var b: Dictionary = sim.person(record.b)
	for p in [a,b]:
		var active: Dictionary = sim._routine_at(p)
		if not active.is_empty(): return "routine_or_care"
	if not record.meeting_id.is_empty(): return "meeting_interrupted_other"
	for p in [a,b]:
		if not p.meeting_id.is_empty(): return "another_engagement"
		if p.action in ["eat","sleep"] or p.hunger>.75 or p.fatigue>.82: return "meal_or_rest_at_admission"
	var activity: Dictionary = sim.agenda._activity(a,b,record.activity)
	if not activity.is_empty():
		activity.place=record.place;activity.center=record.center;activity.group=record.venue if record.activity=="social" else record.activity
		if sim.activities.pair_for(activity.group,record.center,[a.id,b.id]).size()<2: return "seat_capacity"
		for p in [a,b]:
			var other: Dictionary = b if p.id==a.id else a
			var agreement: Dictionary = sim.agenda._agreement(p,other,activity,record.origin=="resident")
			if agreement.status!="accept": return "consent_or_resources"
	if record.activity=="social":
		for p in [a,b]:
			if int(sim._next_commitment(p).minutes)<90: return "next_commitment_admission_buffer"
	return "admission_other"

func _count(target: Dictionary, key: String) -> void:
	target[key] = int(target.get(key,0))+1

func _write_summary() -> void:
	var file := FileAccess.open(output+"/summary.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"implementation":label,"source_sha256":source_hashes,"examples":examples,"scope":"seeds 710..719 x 12 representative days, natural and matched one radio-project intervention","method":"terminal outcomes captured synchronously from event_added; each agreement retained in this diagnostic independently of the game's 64-record agenda cap or 500-event cap; reason inference from live states is labeled separately from closing text","samples":report}),"  "))
	file.close()

func _json(value: Variant) -> Variant:
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _json(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_json(item))
		return result
	return value
