extends SceneTree

const Weather = preload("res://game/scripts/world_weather.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);push_error(message)

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<1e-10
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not equivalent(a[index],b[index]): return false
		return true
	return a==b

func advance(weather, elapsed: int) -> bool:
	# The current simulation's calendar: start 13:00, three days per season.
	var absolute: int = 780+elapsed
	return weather.tick(elapsed,posmod(absolute,1440),posmod(int(int(absolute/1440)/3),4))

func advance_rebased(weather, elapsed: int) -> bool:
	var total: int = 1320+elapsed-37
	var day: int = 11+int(total/1440)
	return weather.tick(elapsed,posmod(total,1440),posmod(int(day/3),4))

func cost(weather: Dictionary, minutes: float, effort: float = 0.0, indoor: bool = false, traits: Dictionary = {}) -> Dictionary:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Weather.RULES_PATH))
	return Weather.action_cost(weather,{"indoor":indoor,"outdoor_minutes":minutes,"effort":effort,"traits":traits},rules.cost)

func run() -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Weather.RULES_PATH))
	expect(Weather.valid_rules(rules),"The declared fictional climate has valid four-season assumptions")
	var resident_rng := RandomNumberGenerator.new();resident_rng.seed = 933
	var control_rng := RandomNumberGenerator.new();control_rng.seed = 933
	var single = Weather.new(710)
	var batch = Weather.new(710)
	var seasons := {}
	var all_ticks_ok := true
	var all_snapshots_valid := true
	for minute in range(1,12*1440+1):
		all_ticks_ok = advance(single,minute) and all_ticks_ok
		var observed: Dictionary = single.snapshot()
		seasons[observed.season_index] = true
		all_snapshots_valid = all_snapshots_valid and observed.condition in ["clear","rain"] and is_finite(observed.temperature_c) and observed.rain_intensity>=0 and observed.rain_intensity<=1 and observed.next_change_elapsed>minute
	expect(all_ticks_ok and seasons.size()==4,"Single-minute time traverses all four three-day seasons")
	expect(all_snapshots_valid,"Every observed segment exposes finite weather and a future scheduled boundary")
	expect(advance(batch,12*1440) and equivalent(single.serialize(),batch.serialize()) and equivalent(single.snapshot(),batch.snapshot()),"A twelve-day batch produces the same weather, clock and RNG as single minutes")
	expect(resident_rng.randi()==control_rng.randi(),"Weather generation does not consume the resident decision random stream")
	# Controlled climate rules prove both generated conditions, without assuming
	# a particular seed must happen to rain during the natural stochastic sample.
	var wet_rules: Dictionary = rules.duplicate(true)
	var dry_rules: Dictionary = rules.duplicate(true)
	for season in wet_rules.seasons: season.rain_start = 1.0;season.rain_continue = 1.0
	for season in dry_rules.seasons: season.rain_start = 0.0;season.rain_continue = 0.0
	var wet = Weather.new(711,wet_rules)
	var dry_weather = Weather.new(711,dry_rules)
	expect(wet.snapshot().condition=="rain" and wet.snapshot().rain_intensity>0 and dry_weather.snapshot().condition=="clear" and dry_weather.snapshot().rain_intensity==0,"Controlled climate rules generate real rain and clear states with consistent intensity")
	var afternoon = Weather.new(711,dry_rules)
	var predawn = Weather.new(711,dry_rules)
	afternoon.reset(711,900,1);predawn.reset(711,180,1)
	var winter = Weather.new(711,dry_rules);winter.reset(711,900,3)
	expect(afternoon.snapshot().temperature_c>predawn.snapshot().temperature_c+7 and afternoon.snapshot().temperature_c>winter.snapshot().temperature_c+15,"Synthetic temperature responds to actual time of day and season")

	var boundary = Weather.new(711)
	var at: int = boundary.snapshot().next_change_elapsed
	var serial: int = boundary.snapshot().segment_serial
	expect(advance(boundary,at-1) and boundary.snapshot().segment_serial==serial,"A segment lasts through the minute before its scheduled boundary")
	expect(advance(boundary,at) and boundary.snapshot().segment_serial==serial+1 and boundary.snapshot().next_change_elapsed>at,"A scheduled boundary generates exactly one next segment")
	var paused: Dictionary = boundary.serialize()
	for ignored in 8:
		boundary.snapshot()
		cost(boundary.snapshot(),30)
	expect(equivalent(paused,boundary.serialize()),"Reading weather and evaluating actions while paused advances neither clock nor RNG")
	expect(advance(boundary,at) and equivalent(paused,boundary.serialize()),"Repeated ticks for the same elapsed minute do not draw again")
	expect(not advance(boundary,at-1) and equivalent(paused,boundary.serialize()),"Time reversal is rejected without changing weather")
	expect(not boundary.tick(at+1,0,0) and equivalent(paused,boundary.serialize()),"A contradictory caller calendar is rejected without advancing weather")
	var absolute: int = 780+at
	expect(boundary.matches_clock(at,posmod(absolute,1440),posmod(int(int(absolute/1440)/3),4)) and not boundary.matches_clock(at,0,0) and equivalent(paused,boundary.serialize()),"Clock consistency can be inspected without changing weather or RNG")
	expect(not boundary.reset(711,1440) and equivalent(paused,boundary.serialize()),"An invalid reset preserves the existing timeline")

	var offset = Weather.new(713)
	expect(offset.reset(713,1380,3,2,900) and offset.tick(960,0,0) and offset.snapshot().season_day==0,"An explicit nonzero anchor crosses winter into the next spring at midnight")
	var rebased = Weather.new(714)
	advance(rebased,37)
	var before_rebase: Dictionary = rebased.serialize()
	expect(not rebased.rebase_calendar(38,1320,3,2) and not rebased.rebase_calendar(36,1320,3,2) and not rebased.rebase_calendar(37,1320,3,3) and equivalent(before_rebase,rebased.serialize()),"Rebase rejects time skips, rewinds and invalid calendar values without mutation")
	expect(rebased.rebase_calendar(37,1320,3,2) and equivalent(before_rebase.state,rebased.serialize().state) and before_rebase.rng_state==rebased.serialize().rng_state and before_rebase.sampling_origin==rebased.serialize().sampling_origin,"An explicit same-minute calendar edit preserves the actual weather segment, boundary and RNG")
	expect(rebased.matches_clock(37,1320,3) and rebased.snapshot().season_day==2 and rebased.serialize().origin.elapsed>rebased.serialize().state.segment_started and rebased.valid_save(rebased.serialize()),"Calendar anchor may move past the segment start while sampling-origin validation remains sound")
	var rebased_copy = Weather.new(1)
	expect(rebased_copy.restore(JSON.parse_string(JSON.stringify(rebased.serialize()))) and equivalent(rebased.serialize(),rebased_copy.serialize()),"A rebased calendar and its earlier sampling history survive actual JSON restore")
	var rebased_ticks_ok := true
	for minute in range(38,37+4*1440+1): rebased_ticks_ok = advance_rebased(rebased,minute) and rebased_ticks_ok
	expect(rebased_ticks_ok and advance_rebased(rebased_copy,37+4*1440) and equivalent(rebased.serialize(),rebased_copy.serialize()) and equivalent(rebased.snapshot(),rebased_copy.snapshot()),"Rebased weather continues through season boundaries identically in single minutes and after saved batch replay")
	var saved = Weather.new(712)
	advance(saved,2345)
	var payload: Dictionary = JSON.parse_string(JSON.stringify(saved.serialize()))
	var restored = Weather.new(1)
	expect(restored.restore(payload) and equivalent(saved.serialize(),restored.serialize()),"JSON restore preserves the exact weather segment and independent RNG")
	expect(advance(saved,12*1440) and advance(restored,12*1440) and equivalent(saved.snapshot(),restored.snapshot()) and equivalent(saved.serialize(),restored.serialize()),"Save/resume produces the same later weather over every remaining season")
	var frozen: Dictionary = restored.serialize()
	var bad: Array = []
	var broken: Dictionary = frozen.duplicate(true);broken.schema = Weather.SCHEMA+1;bad.append(broken)
	broken = frozen.duplicate(true);broken.source_id = "unknown-data";bad.append(broken)
	broken = frozen.duplicate(true);broken.context_version = 0;bad.append(broken)
	broken = frozen.duplicate(true);broken.rules_version = 2;bad.append(broken)
	broken = frozen.duplicate(true);broken.weather_seed = -1;bad.append(broken)
	broken = frozen.duplicate(true);broken.rng_state = "not an integer";bad.append(broken)
	broken = frozen.duplicate(true);broken.rng_state = "999999999999999999999999";bad.append(broken)
	for invalid_rng in ["9223372036854775808","-9223372036854775809","00","-0","+1"," 1"]:
		broken = frozen.duplicate(true);broken.rng_state = invalid_rng;bad.append(broken)
	broken = frozen.duplicate(true);broken.origin.minute_of_day = 1440;bad.append(broken)
	broken = frozen.duplicate(true);broken.origin.season_index = 4;bad.append(broken)
	broken = frozen.duplicate(true);broken.origin.season_day = 3;bad.append(broken)
	broken = frozen.duplicate(true);broken.sampling_origin = -1;bad.append(broken)
	broken = frozen.duplicate(true);broken.sampling_origin = broken.origin.elapsed+1;bad.append(broken)
	broken = frozen.duplicate(true);broken.state.elapsed = -1;bad.append(broken)
	broken = frozen.duplicate(true);broken.state.next_change = broken.state.elapsed;bad.append(broken)
	broken = frozen.duplicate(true);broken.state.next_change += 2000;bad.append(broken)
	broken = frozen.duplicate(true);broken.state.serial = 1000000;bad.append(broken)
	broken = frozen.duplicate(true);broken.state.condition = "snow";bad.append(broken)
	broken = frozen.duplicate(true);broken.state.condition = "clear";broken.state.rain_intensity = .3;bad.append(broken)
	broken = frozen.duplicate(true);broken.state.offset_c = NAN;bad.append(broken)
	broken = frozen.duplicate(true);broken.state.offset_c = 99;bad.append(broken)
	broken = frozen.duplicate(true);broken.erase("state");bad.append(broken)
	broken = frozen.duplicate(true);broken.extra = true;bad.append(broken)
	for index in bad.size():
		expect(not restored.restore(bad[index]) and equivalent(frozen,restored.serialize()),"Invalid weather payload %d is rejected before changing timeline or RNG"%index)
	var canonical_bounds_ok := true
	for valid_rng in ["0","9223372036854775807","-9223372036854775808"]:
		var edge: Dictionary = frozen.duplicate(true);edge.rng_state = valid_rng
		var edge_weather = Weather.new(1)
		canonical_bounds_ok = edge_weather.restore(edge) and edge_weather.serialize().rng_state==valid_rng and canonical_bounds_ok
	expect(canonical_bounds_ok,"Canonical signed-64bit RNG state boundaries restore without integer conversion errors")

	var dry := {"temperature_c":20.0,"rain_intensity":0.0}
	var rain := {"temperature_c":20.0,"rain_intensity":.8}
	var hot := {"temperature_c":36.0,"rain_intensity":.8}
	var cold := {"temperature_c":0.0,"rain_intensity":0.0}
	expect(cost(dry,60).valid and cost(dry,60).total==0 and cost(rain,60).total>0 and cost(cold,60).total>0,"Rain and cold alter outdoor cost while comfortable dry weather adds none")
	expect(cost(hot,60,.9).exertion>cost(hot,60,.1).exertion and cost(hot,60,.9).total>cost(hot,60,.1).total,"Exertion interacts with heat rather than requiring a named action rule")
	expect(cost(hot,60,.9,true).total==0 and cost(hot,0,.9).total==0,"Indoor or zero-time components receive no outdoor weather burden")
	expect(cost(rain,30).total<cost(rain,60).total and cost(rain,60).total<=cost(rain,120).total,"Longer outdoor exposure increases cost until its finite cap")
	var enormous := cost(hot,1e100,1.0)
	expect(enormous.valid and is_finite(enormous.total) and enormous.total>=0 and enormous.total<=1,"Even extremely long exposure yields a finite bounded cost")
	var sensitive := cost(hot,60,.5,false,{"negative_emotionality":1.0,"open_mindedness":0.0})
	var tolerant := cost(hot,60,.5,false,{"negative_emotionality":0.0,"open_mindedness":1.0})
	expect(sensitive.total>tolerant.total and sensitive.rain==tolerant.rain and sensitive.thermal==tolerant.thermal,"Traits change a small perceived burden without changing the physical weather or inventing a need")
	var walk_out := cost(rain,15,.4)
	var sheltered_work := cost(hot,60,.5,true)
	var walk_home := cost(rain,15,.4)
	var composed: Dictionary = Weather.combine_costs([walk_out,sheltered_work,walk_home])
	expect(composed.valid and composed.total>=walk_out.total and composed.total<=1 and Weather.combine_costs([]).total==0,"Walking and sheltered work compose without an activity-name list or unbounded sum")
	expect(not cost(hot,-1).valid and not cost({"temperature_c":NAN,"rain_intensity":.5},20).valid and not cost(hot,20,2).valid and not cost(hot,20,.5,false,{"open_mindedness":2}).valid,"Invalid exposure, weather and personal inputs are rejected rather than treated as pleasant weather")
	expect(not Weather.combine_costs([{"valid":false,"total":0}]).valid,"An invalid component is not hidden by composition")
	var cost_before: Dictionary = restored.serialize()
	var weather_input: Dictionary = restored.snapshot()
	var context := {"indoor":false,"outdoor_minutes":30.0,"effort":.2,"traits":{"open_mindedness":.7}}
	var context_before: Dictionary = context.duplicate(true)
	var first: Dictionary = Weather.action_cost(weather_input,context,rules.cost)
	expect(equivalent(first,Weather.action_cost(weather_input,context,rules.cost)) and equivalent(context,context_before) and equivalent(cost_before,restored.serialize()),"Action evaluation is pure and leaves context, weather clock and RNG unchanged")
	print("World weather checks: %d passed, %d failed; synthetic climate, not real weather"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
