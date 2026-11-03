extends SceneTree

const ORIGINAL = ["nagisa","ryo","rin","osamu","fumi","maho","ritsu","aoi"]
const SEEDS = [710,711,712]
const MINUTES = 3*1440

class Recorder:
	extends RefCounted
	var sim
	var start_serial: int
	var callback_events := 0
	var pending: Array = []
	var facts := {}
	var meetings := {}
	var finished := {}
	var pair_counts := {}
	var participant_counts := {}
	var initiators := {}
	var actions := {}
	var person_minutes := 0
	var critical_hunger_minutes := 0
	var critical_fatigue_minutes := 0
	var high_housework_minutes := 0
	var household_minutes := 0
	var protected_conflicts := 0
	var invalid_states := 0
	var occupied_collisions := 0
	var conflicts: Array = []
	var min_cash := INF
	var max_home_load := 0.0
	var observed_work := {}
	var terminal_snapshots := {}
	var terminal_participants := {}
	var shared_time_signals := 0
	var unmatched_shared_time_signals := 0
	var same_minute_plan_overwrites := 0

	func _init(world) -> void:
		sim = world
		start_serial = sim.event_serial
		for p in sim.people:
			actions[p.id] = {}
			participant_counts[p.id] = 0

	func on_event(event: Dictionary) -> void:
		callback_events += 1
		# Some fact fields are attached after _log emits. Keep the reference and
		# inspect it at the end of this minute, before the archive can truncate it.
		pending.append(event)
		for meeting in sim.meetings: meetings[meeting.id] = meeting.duplicate(true)
		var p: Dictionary = sim.person(event.get("resident_id",""))
		if p.is_empty() or p.memories.is_empty(): return
		var memory: Dictionary = p.memories[-1]
		if memory.kind!="shared_time" or memory.minute!=event.minute or memory.title!=event.title or memory.text!=event.text: return
		shared_time_signals += 1
		var id: String = p.meeting_id
		if not meetings.has(id) or meetings[id].state!="engaged" or float(meetings[id].remaining)>0:
			unmatched_shared_time_signals += 1
			return
		if not terminal_participants.has(id): terminal_participants[id] = {}
		terminal_participants[id][p.id] = true
		terminal_snapshots[id] = {"meeting":meetings[id].duplicate(true),
			"plan":sim.person(meetings[id].a).cognition_plan.duplicate(true),"minute":event.minute}

	func _finish_record(id: String, terminal: Dictionary) -> void:
		var meeting: Dictionary = terminal.meeting
		var plan: Dictionary = terminal.plan
		var ids: Array = [meeting.a,meeting.b]
		ids.sort()
		var key: String = ":".join(ids)
		var current: Dictionary = sim.person(meeting.a).cognition_plan
		if current.get("meeting","")!=id: same_minute_plan_overwrites += 1
		var introduction: String = plan.get("introduction_event","")
		var project: Dictionary = meeting.get("project",{})
		finished[id] = {"id":id,"a":meeting.a,"b":meeting.b,"activity":project.get("key","social"),
			"kind":"project" if meeting.get("mode","")=="project" else "social",
			"origin":"resident" if meeting.get("autonomous",false) or meeting.get("spontaneous",false) else "player",
			"group":_group(meeting.a,meeting.b),"finished":terminal.minute,
			"observed_engaged_minutes":int(observed_work.get(id,0)),"introduction_event":introduction,
			"introduction_observed_in_window":facts.has(introduction)}
		pair_counts[key] = int(pair_counts.get(key,0))+1
		for actor in ids: participant_counts[actor] = int(participant_counts.get(actor,0))+1
		initiators[meeting.a] = int(initiators.get(meeting.a,0))+1

	func _group(first: String, second: String) -> String:
		var old_first: bool = first in ORIGINAL
		var old_second: bool = second in ORIGINAL
		return "original_original" if old_first and old_second else ("new_new" if not old_first and not old_second else "original_new")

	func observe_minute() -> void:
		for event in pending:
			if event.get("fact","")=="introduction": facts[event.event_id] = event.duplicate(true)
		pending.clear()
		for id in terminal_snapshots:
			if not finished.has(id) and terminal_participants[id].size()==2: _finish_record(id,terminal_snapshots[id])
		for meeting in sim.meetings:
			meetings[meeting.id] = meeting.duplicate(true)
			if meeting.state=="engaged": observed_work[meeting.id] = int(observed_work.get(meeting.id,0))+1
		var occupied := {}
		for p in sim.people:
			if not sim.life.is_alive(p): continue
			person_minutes += 1
			if p.hunger>.9: critical_hunger_minutes += 1
			if p.fatigue>.9: critical_fatigue_minutes += 1
			if not is_finite(float(p.hunger)) or not is_finite(float(p.fatigue)) or not p.position.is_finite(): invalid_states += 1
			if not p.moving:
				actions[p.id][p.action] = int(actions[p.id].get(p.action,0))+1
				var spot: String = p.get("activity_spot","")
				if not spot.is_empty():
					if occupied.has(spot): occupied_collisions += 1
					occupied[spot] = p.id
			var routine: Dictionary = sim._routine_at(p)
			if not routine.is_empty():
				var required: String = sim._routine_action(routine)
				if required in ["work","school","sleep"] and not p.meeting_id.is_empty() and p.action!=required:
					protected_conflicts += 1
					if conflicts.size()<8: conflicts.append({"person":p.id,"minute":sim.elapsed,"routine":routine.id,"action":p.action,"meeting":p.meeting_id})
		for household_id in sim.work_family.households:
			if not sim.people.any(func(p): return sim.life.is_alive(p) and sim.work_family.household_id(p)==household_id): continue
			var h: Dictionary = sim.work_family.households[household_id]
			household_minutes += 1
			min_cash = minf(min_cash,float(h.cash))
			max_home_load = maxf(max_home_load,float(h.home_load))
			if h.home_load>.95: high_housework_minutes += 1

	func summary(minutes: int) -> Dictionary:
		var groups := {"original_original":0,"original_new":0,"new_new":0}
		var projects := groups.duplicate()
		var resident_completed := 0
		var introduced_projects := 0
		for row in finished.values():
			groups[row.group] += 1
			if row.origin=="resident": resident_completed += 1
			if row.kind=="project":
				projects[row.group] += 1
				if row.introduction_observed_in_window: introduced_projects += 1
		var zero: Array = []
		for id in participant_counts:
			if participant_counts[id]==0: zero.append(id)
		var highest_pair := 0
		for value in pair_counts.values(): highest_pair = maxi(highest_pair,int(value))
		var highest_initiator := 0
		for value in initiators.values(): highest_initiator = maxi(highest_initiator,int(value))
		var partner_sets := {}
		for id in participant_counts: partner_sets[id] = {}
		for pair in pair_counts:
			var ids: PackedStringArray = str(pair).split(":")
			partner_sets[ids[0]][ids[1]] = true
			partner_sets[ids[1]][ids[0]] = true
		var degrees := {}
		for id in partner_sets: degrees[id] = partner_sets[id].size()
		return {"population":sim.people.size(),"minutes":minutes,"person_minutes":person_minutes,
			"callback_events":callback_events,"event_serial_delta":sim.event_serial-start_serial,"retained_events":sim.events.size(),
			"shared_time_signals":shared_time_signals,"unmatched_shared_time_signals":unmatched_shared_time_signals,
			"same_minute_plan_overwrites_recovered":same_minute_plan_overwrites,
			"completion_signals_accounted":shared_time_signals==2*finished.size() and unmatched_shared_time_signals==0,
			"completed_meetings":finished.size(),"resident_completed_meetings":resident_completed,
			"completed_projects":projects,"completed_pairs_by_group":groups,
			"completed_participations_per_resident_day":2.0*finished.size()/maxf(1,person_minutes/1440.0),
			"unique_completed_pairs":pair_counts.size(),"pair_counts":pair_counts,"participant_counts":participant_counts,
			"unique_completed_partners_per_resident":degrees,
			"initiator_counts":initiators,"zero_participation":zero,
			"top_pair_share":float(highest_pair)/maxi(1,finished.size()),"top_initiator_share":float(highest_initiator)/maxi(1,finished.size()),
			"introductions_received":facts.size(),"introduction_linked_projects":introduced_projects,
			"action_minutes_at_destination":actions,"critical_hunger_person_minutes":critical_hunger_minutes,
			"critical_fatigue_person_minutes":critical_fatigue_minutes,"household_minutes":household_minutes,
			"critical_hunger_share":float(critical_hunger_minutes)/maxi(1,person_minutes),
			"critical_fatigue_share":float(critical_fatigue_minutes)/maxi(1,person_minutes),
			"high_housework_household_minutes":high_housework_minutes,"min_household_cash":min_cash,"max_home_load":max_home_load,
			"high_housework_share":float(high_housework_minutes)/maxi(1,household_minutes),
			"protected_routine_conflicts":protected_conflicts,"conflict_examples":conflicts,
			"invalid_numeric_states":invalid_states,"occupied_spot_collisions":occupied_collisions,
			"completed_records":finished.values()}

static func source_hashes() -> Dictionary:
	var result := {}
	for folder in ["game/scripts","data"]:
		var names := DirAccess.get_files_at("res://"+folder)
		names.sort()
		for name in names:
			if name.ends_with(".gd") or name.ends_with(".json"):
				var path: String = folder+"/"+name
				result[path] = FileAccess.get_sha256("res://"+path)
	for path in ["tools/inspect_population.gd","tests/test_population.gd"]:
		if FileAccess.file_exists("res://"+path): result[path] = FileAccess.get_sha256("res://"+path)
	return result

static func initial_originals(sim) -> Array:
	var result: Array = []
	for id in ORIGINAL:
		var p: Dictionary = sim.person(id)
		result.append(sim._encode({"id":id,"fatigue":p.fatigue,"hunger":p.hunger,"connection":p.connection,"quiet":p.quiet,
			"action":p.action,"reason":p.reason,"place":p.place,"destination":p.destination,"position":p.position,"moving":p.moving}))
	return result

static func measure(sim, minutes: int) -> Dictionary:
	var recorder := Recorder.new(sim)
	sim.event_added.connect(recorder.on_event)
	for minute in minutes:
		sim.advance_minutes(1)
		recorder.observe_minute()
	sim.event_added.disconnect(recorder.on_event)
	return recorder.summary(minutes)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var output := "res://docs/verification/v0.8/population/population-comparison.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	var began: int = Time.get_ticks_msec()
	var before := source_hashes()
	var sim = load("res://game/scripts/simulation.gd").new()
	root.add_child(sim)
	var samples: Array = []
	for seed_value in SEEDS:
		for count in [8,12]:
			sim.reset(seed_value,count)
			var initial := initial_originals(sim)
			var initial_rng: String = str(sim.rng.state)
			var row := measure(sim,MINUTES)
			row.seed = seed_value
			row.initial_originals = initial
			row.initial_rng_after_choices = initial_rng
			samples.append(row)
			print("POPULATION_SAMPLE seed=%d population=%d completed=%d original_new=%d projects=%s"%[seed_value,count,row.completed_meetings,row.completed_pairs_by_group.original_new,JSON.stringify(row.completed_projects)])
	var report := {"scope":"3 seeds x 3 representative days, ordinary 8/12-person towns, no interventions. Counts observe actual completed meetings, not accepted invitations. More residents do not imply a higher per-person interaction rate or prove player enjoyment.",
		"randomness":"The additional initial residents consume RNG before the first actions are selected. Shared seeds do not isolate the extra social contacts as a causal treatment. Initial original-resident needs/actions and post-choice RNG are recorded for each population.",
		"aggregation":"Every event reaches event_added. Actual completion is captured synchronously while both shared_time memories and the engaged meeting still exist; each meeting ID is counted once. Minute-end aggregation is independent of subsequent plan replacement. Mutable introduction metadata is read after the minute. Both participants' shared_time signal count is reconciled against twice the completed meeting count.",
		"seeds":SEEDS,"minutes":MINUTES,"source_sha256":before,"source_unchanged":before==source_hashes(),
		"samples":samples,"wall_seconds":(Time.get_ticks_msec()-began)/1000.0}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("Population comparison: %d samples; %.3f seconds"%[samples.size(),report.wall_seconds])
	sim.free()
	quit()
