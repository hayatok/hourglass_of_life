extends SceneTree

var checks := 0
var failures: Array[String] = []
var sim: LifeSimulation
var report := {"scope":"Controlled weather-only decisions and real routes, not human playtesting", "pairs":[]}

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);push_error(message)

func set_condition(wet: bool) -> bool:
	var payload := sim.weather.serialize()
	payload.state.condition = "rain" if wet else "clear"
	payload.state.rain_intensity = .9 if wet else 0.0
	# The comparison starts at elapsed zero. 180 minutes is valid for both
	# authored segment lengths; the next draw remains the same saved draw.
	payload.state.next_change = 180
	return sim.weather.restore(payload)

func state() -> Dictionary:
	return sim._encode({"people":sim.people,"definitions":sim.definitions,"elapsed":sim.elapsed,"start_minute":sim.start_minute,"epoch_weekday":sim.epoch_weekday,"remainder":sim.minute_remainder,"rng":str(sim.rng.state),"weather":sim.weather.serialize(),
		"events":sim.events,"meetings":sim.meetings,"agenda":sim.agenda.serialize(),"budget":sim.shared_budget,"social":sim.social.serialize(),"work":sim.work_family.serialize(),"life":sim.life.serialize(),"interactions":sim.interactions.serialize(),"tabletop":sim.tabletop.serialize()})

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a),float(b))
	if a is Vector3 and b is Vector3:
		return a.distance_to(b)<.00001
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	return a==b

func run() -> void:
	sim = LifeSimulation.new();root.add_child(sim);sim.set_process(false)
	sim.reset(71103,12)
	var fumi := sim.person("fumi")
	var rain := {"condition":"rain","rain_intensity":.9,"temperature_c":18.0}
	var dry := {"condition":"clear","rain_intensity":0.0,"temperature_c":18.0}
	var before := state()
	var outside := sim.resident_weather.evaluate(fumi,{"kind":"photo","place":"garden"},rain)
	var sheltered := sim.resident_weather.evaluate(fumi,{"kind":"social","place":"bakery_cafe"},rain)
	expect(outside.eligible and not outside.indoor and outside.activity_minutes>0,"A garden candidate exposes its actual outdoor activity time")
	expect(sheltered.eligible and sheltered.indoor and sheltered.activity_minutes==0 and sheltered.walking_minutes>0,"A cafe's real roof shelters activity but not the walk there")
	expect(outside.penalty>sim.resident_weather.evaluate(fumi,{"kind":"photo","place":"garden"},dry).penalty,"Rain increases the same outdoor candidate's score penalty")
	expect(outside.penalty>=0 and outside.penalty<=.3 and sheltered.penalty<outside.penalty,"Finite weather penalties favor a sheltered alternative without banning outdoors")
	expect(sim.resident_weather.evaluate(fumi,{"kind":"work","place":"workshop"},rain).penalty==0,"Required work is not re-scored by the voluntary weather adapter")
	expect(not sim.resident_weather.evaluate(fumi,{"kind":"rest","place":"off_map_home"},rain).eligible,"An unmodeled off-map home is not misclassified as an outdoor rest")
	expect(state()==before,"Inspecting a candidate consumes no time or decision/weather RNG and assigns no action")
	# Keep the same people, needs, money, plans and decision draw in every pair.
	# The extra-work/known-partner systems remain present; only future planning
	# is held back in this bounded immediate-venue comparison.
	var path := "user://test-weather-behavior-%d.json"%OS.get_process_id()
	for p in sim.people: p.next_plan_minute = 100000
	expect(sim.save_game(path),"A dedicated real baseline save can be made")
	var wet_out := 0;var dry_out := 0;var changed := 0;var outdoor_in_rain := 0
	var chosen_routes: Array = []
	var restore_ok := true;var condition_ok := true
	for id in ["aoi","osamu","fumi","haru","saki","tomo","yui"]:
		for decision_seed in range(1,129):
			var pair := {"id":id,"decision_seed":decision_seed}
			for wet in [false,true]:
				restore_ok = sim.load_game(path) and restore_ok
				var p := sim.person(id)
				if p.is_empty() or not sim._routine_at(p).is_empty(): continue
				condition_ok = set_condition(wet) and condition_ok
				sim.rng.seed = decision_seed
				var decision_before: int = sim.rng.state
				sim._choose_action(p)
				var indoors := sim.activities.inside(p.destination,p.target)
				pair["wet" if wet else "dry"] = {"action":p.action,"destination":p.destination,"indoor":indoors,"reason":p.reason,"decision_rng_before":str(decision_before)}
				if wet:
					if not indoors: wet_out+=1;outdoor_in_rain+=1
				else:
					if not indoors: dry_out+=1
			if not pair.has("wet") or not pair.has("dry"): continue
			if pair.wet.action!=pair.dry.action or pair.wet.destination!=pair.dry.destination:
				changed+=1
				chosen_routes.append(pair.duplicate(true))
			if report.pairs.size()<12 and (pair.wet.action!=pair.dry.action or pair.wet.destination!=pair.dry.destination): report.pairs.append(pair)
	expect(restore_ok and condition_ok,"All paired decisions restore the same real save with valid controlled weather")
	expect(changed>0 and wet_out<dry_out,"Weather alone changes some real choices and reduces outdoor selections in paired draws")
	expect(outdoor_in_rain>0,"Rain still leaves people who choose outdoor time")
	# Follow one changed choice through the real assignment and street/room path.
	var reached := false
	for pair in chosen_routes:
		if pair.wet.action not in ["rest","eat","social","hobby","photo"] or not pair.wet.indoor: continue
		sim.load_game(path);set_condition(true);sim.rng.seed = pair.decision_seed
		var p := sim.person(pair.id);sim._choose_action(p)
		var target: Vector3 = p.target;var destination: String = p.destination
		var origin: Vector3 = p.position
		for minute in 180:
			if not p.moving: break
			sim._move(p)
		reached = not p.moving and p.position.distance_to(target)<.001 and p.place==destination
		report.route = {"id":pair.id,"origin":str(origin),"target":str(target),"destination":destination,"reached":reached}
		break
	expect(reached,"A weather-selected sheltered activity arrives through the actual route, without teleport assignment")
	# Urgent needs and an authored duty retain precedence over weather scores.
	sim.load_game(path);set_condition(true)
	var a := sim.person("aoi");a.fatigue=.9;sim._choose_action(a)
	expect(a.action=="rest" and a.destination==sim.home_for(a),"Urgent fatigue keeps precedence in rain")
	a.fatigue=.2;a.hunger=.9;sim._choose_action(a)
	expect(a.action=="eat" and a.destination==sim.home_for(a),"Urgent hunger keeps precedence in rain")
	var maho := sim.person("maho");sim._choose_action(maho)
	expect(not maho.routine_id.is_empty() and maho.action=="work","An active cafe/bakery duty remains an actual duty in rain")
	# Real save/load protects both streams, future weather and later decisions.
	sim.load_game(path);sim.advance_minutes(137.25);sim.save_game(path)
	var saved := state();var weather_before := sim.weather.serialize()
	sim.advance_minutes(333);var future := state()
	expect(sim.load_game(path) and equivalent(state(),saved),"The current-format town restores exact weather, people and both random streams")
	sim.advance_minutes(333)
	expect(equivalent(state(),future),"Restored weather and resident decisions reproduce the same later town")
	sim.load_game(path);sim.advance_minutes(333.75);var batch_future := state()
	sim.load_game(path)
	for quarter in 1335: sim.advance_minutes(.25)
	expect(equivalent(state(),batch_future),"Production Sim quarter-minute batches match a single batch across weather boundaries")
	sim.running=false;var paused := state();sim._process(2.0)
	expect(state()==paused,"A paused production Sim does not advance weather, people or either random stream")
	var invalid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path));invalid.weather.state.elapsed+=1
	var invalid_path := path+".bad";FileAccess.open(invalid_path,FileAccess.WRITE).store_string(JSON.stringify(invalid))
	var live := state()
	expect(not sim.load_game(invalid_path) and state()==live,"A contradictory weather/calendar save is rejected before mutating the town")
	invalid = JSON.parse_string(FileAccess.get_file_as_string(path))
	invalid.rng_state = "999999999999999999999999";FileAccess.open(invalid_path,FileAccess.WRITE).store_string(JSON.stringify(invalid))
	expect(not sim.load_game(invalid_path) and state()==live,"An overflowing resident RNG string is rejected without engine conversion errors or mutation")
	invalid = JSON.parse_string(FileAccess.get_file_as_string(path))
	for field in ["elapsed","start_minute","epoch_weekday"]:
		var malformed: Dictionary = invalid.duplicate(true);malformed[field]+= .25
		FileAccess.open(invalid_path,FileAccess.WRITE).store_string(JSON.stringify(malformed))
		expect(not sim.load_game(invalid_path) and state()==live,"A fractional %s is rejected without truncating the clock or mutating the town"%field)
	invalid.schema = 7;FileAccess.open(invalid_path,FileAccess.WRITE).store_string(JSON.stringify(invalid))
	expect(not sim.load_game(invalid_path) and state()==live and not sim.load_error.is_empty(),"The previous development format is rejected with a readable reason")
	# Scenario/debug clock edits are distinct from restoring a saved town.
	sim.reset(155,12);sim.advance_minutes(15)
	var prior_weather := sim.weather.serialize()
	sim.start_minute=900;sim._reconcile_weather_clock()
	var rebased := sim.weather.serialize()
	expect(rebased.state==prior_weather.state and rebased.rng_state==prior_weather.rng_state and sim.weather.snapshot().minute_of_day==sim.minute_of_day(),"An explicit same-minute debug calendar change preserves the weather segment and draws")
	sim.elapsed+=5;sim._reconcile_weather_clock()
	expect(sim.weather.snapshot().elapsed==sim.elapsed and sim.weather.snapshot().minute_of_day==sim.minute_of_day() and sim.weather.serialize().rng_state==rebased.rng_state,"A forward fixture jump reconciles its calendar without an unnecessary weather reroll")
	sim.elapsed=0;sim._reconcile_weather_clock()
	var fresh := WorldWeather.new();fresh.reset(155,sim.minute_of_day(),0,0,0)
	expect(equivalent(sim.weather.serialize(),fresh.serialize()),"An explicit rewind starts a new fixture timeline; normal save restoration uses its saved timeline instead")
	report.merge({"checks":checks,"failures":failures,"decision_pairs":7*128,"changed_choices":changed,"dry_outdoor":dry_out,"rain_outdoor":wet_out,"weather_saved":weather_before},true)
	DirAccess.make_dir_recursive_absolute("res://builds/weather")
	FileAccess.open("res://builds/weather/behavior.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path));DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))
	print("Weather behavior checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free();quit(0 if failures.is_empty() else 1)
