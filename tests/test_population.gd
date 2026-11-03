extends SceneTree

const Inspector = preload("res://tools/inspect_population.gd")
const NEWCOMERS = ["saki","haru","tomo","yui"]
var sim
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<1e-10
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not equivalent(a[index],b[index]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	return a==b

func snapshot() -> Dictionary:
	return sim._encode({"definitions":sim.definitions,"people":sim.people,"elapsed":sim.elapsed,"start":sim.start_minute,
		"remainder":sim.minute_remainder,
		"weekday":sim.epoch_weekday,"rng":str(sim.rng.state),"seed":sim.world_seed,"events":sim.events,"meetings":sim.meetings,
		"event_serial":sim.event_serial,"meeting_serial":sim.meeting_serial,"budget":sim.shared_budget,"benches":sim.benches,
		"agenda":sim.agenda.serialize(),"social":sim.social.serialize(),"work":sim.work_family.serialize(),"life":sim.life.serialize()}).duplicate(true)

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data));file.close()

func run() -> void:
	var began: int = Time.get_ticks_msec()
	var source_before: Dictionary = Inspector.source_hashes()
	sim = load("res://game/scripts/simulation.gd").new()
	root.add_child(sim)
	sim.reset(710,8)
	expect(sim.people.size()==8 and sim.definitions.size()==8,"The comparison fixture starts with exactly the original eight residents")
	var old_needs := {}
	for p in sim.people: old_needs[p.id] = [p.fatigue,p.hunger,p.connection,p.quiet]
	sim.reset(710,12)
	var ids := {}
	for p in sim.people: ids[p.id] = true
	expect(sim.people.size()==12 and ids.size()==12 and NEWCOMERS.all(func(id): return ids.has(id)),"The expanded town loads four distinct newcomers alongside the original residents")
	var shared_needs := true
	for id in Inspector.ORIGINAL:
		var p: Dictionary = sim.person(id)
		shared_needs = shared_needs and equivalent(old_needs[id],[p.fatigue,p.hunger,p.connection,p.quiet])
	expect(shared_needs,"The original residents retain the same initial needs; action RNG differences are reported separately")
	expect(sim.work_family.households.has("north_house") and sim.work_family.households.has("mori") and sim.SITES.has("home_north_shared") and sim.SITES.has("home_mori"),"New residents have actual household ledgers and addressable homes")
	var valid_references := true
	for p in sim.people:
		valid_references = valid_references and sim.HOME.has(sim.definitions[p.id].household_id)
		for other in p.relationships: valid_references = valid_references and ids.has(other)
	expect(valid_references,"Initial homes and relationship references resolve within the selected roster")
	# Exercise a signal stream longer than the resident-facing event archive.
	var stream := Inspector.Recorder.new(sim)
	sim.event_added.connect(stream.on_event)
	for index in 520: sim._log("","Population observer capacity check","Observer-only capacity probe")
	stream.observe_minute()
	sim.event_added.disconnect(stream.on_event)
	expect(stream.callback_events==520 and sim.events.size()==500 and stream.finished.is_empty(),"Signal aggregation sees all 520 events without inventing completed interactions from an archive-capacity probe")

	var observations: Array = []
	var cross_meetings := 0
	var cross_projects := 0
	for seed_value in Inspector.SEEDS:
		for count in [8,12]:
			sim.reset(seed_value,count)
			var initial: Array = Inspector.initial_originals(sim)
			var initial_rng: String = str(sim.rng.state)
			var row: Dictionary = Inspector.measure(sim,Inspector.MINUTES)
			row.seed = seed_value;row.initial_originals = initial;row.initial_rng_after_choices = initial_rng
			observations.append(row)
			expect(row.callback_events==row.event_serial_delta and row.completion_signals_accounted,"Every event and both participants' actual completion signals reconcile with unique meeting IDs for seed %d / %d residents"%[seed_value,count])
			expect(row.invalid_numeric_states==0 and row.occupied_spot_collisions==0,"Needs and positions stay finite and furniture is not double-occupied for seed %d / %d residents"%[seed_value,count])
			expect(row.protected_routine_conflicts==0,"Actual meetings do not displace scheduled sleep, school or work for seed %d / %d residents"%[seed_value,count])
			var self_care := true
			for id in row.action_minutes_at_destination:
				var minutes: Dictionary = row.action_minutes_at_destination[id]
				self_care = self_care and minutes.get("eat",0)>0 and minutes.get("sleep",0)>0
			expect(self_care,"Each resident actually eats and sleeps during the three-day observation for seed %d / %d residents"%[seed_value,count])
			if count==12:
				cross_meetings += int(row.completed_pairs_by_group.original_new)
				cross_projects += int(row.completed_projects.original_new)
			print("Population check sample seed=%d count=%d complete=%d cross=%d"%[seed_value,count,row.completed_meetings,row.completed_pairs_by_group.original_new])
	expect(cross_meetings>0,"At least one old/new resident pair actually completes time together in the declared natural samples")
	expect(cross_projects>0,"At least one old/new pair actually completes joint work, beyond merely adding names or accepting plans")
	# Current-format 12-person saves must resume their exact future decisions.
	var path := "user://test-population-current.json"
	var bad_path := "user://test-population-invalid.json"
	sim.reset(711,12)
	sim.advance_minutes(1440+137)
	expect(sim.save_game(path),"The current expanded town can save its actual ongoing state")
	var saved := snapshot()
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	sim.advance_minutes(240)
	var future := snapshot()
	expect(sim.load_game(path) and equivalent(saved,snapshot()),"Loading the current save restores all twelve people, plans, knowledge, households and RNG")
	sim.advance_minutes(240)
	expect(equivalent(future,snapshot()),"Resumed play reproduces the same future decisions and RNG, allowing only JSON floating-point rounding")
	sim.reset(712,12)
	sim.advance_minutes(180)
	var current := snapshot()
	var corruptions: Array = []
	var bad := payload.duplicate(true);bad.people[0].id = "absent_resident";corruptions.append(bad)
	bad = payload.duplicate(true);bad.people[1].id = bad.people[0].id;corruptions.append(bad)
	bad = payload.duplicate(true);bad.people.pop_back();corruptions.append(bad)
	bad = payload.duplicate(true);bad.people[0].household_override = "absent_household";corruptions.append(bad)
	bad = payload.duplicate(true);bad.work_family.households.unknown_house = bad.work_family.households.north_house.duplicate(true);corruptions.append(bad)
	bad = payload.duplicate(true);bad.work_family.households.erase("north_house");corruptions.append(bad)
	for index in corruptions.size():
		write_json(bad_path,corruptions[index])
		expect(not sim.load_game(bad_path) and equivalent(current,snapshot()),"Invalid population save %d is rejected without changing the active town, definitions or RNG"%index)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
	var output := "res://docs/verification/v0.8/population/population-checks.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	write_json(output,{"checks":checks,"failures":failures,"seeds":Inspector.SEEDS,"minutes":Inspector.MINUTES,
		"scope":"Current 8/12-person natural samples and current-format expanded save tests; no old-version migration requirement. Increased total interaction is not asserted.",
		"source_sha256":source_before,"source_unchanged":source_before==Inspector.source_hashes(),"samples":observations,"wall_seconds":(Time.get_ticks_msec()-began)/1000.0})
	print("Population checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)
