class_name WorldWeather
extends RefCounted

# Current local climate: independent of resident decisions, rendering and network.
const RULES_PATH := "res://data/weather.json"
const SCHEMA := 2
const SEED_SALT := 0x57454154
const MAX_ELAPSED := 1440*12*1000
const CONDITIONS := ["clear","rain"]

var _rules: Dictionary
var _rng := RandomNumberGenerator.new()
var _seed := 0
var _origin: Dictionary = {}
var _sampling_origin := 0
var _state: Dictionary = {}

func _init(world_seed: int = 711, rules: Dictionary = {}) -> void:
	_rules = rules.duplicate(true) if not rules.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	assert(valid_rules(_rules),"WorldWeather requires explicit valid synthetic climate assumptions")
	reset(world_seed)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _unit(value: Variant) -> bool:
	return _number(value) and value>=0 and value<=1

static func _whole(value: Variant, low: int = 0, high: int = MAX_ELAPSED) -> bool:
	return _number(value) and value>=low and value<=high and value==int(value)

static func valid_rng_state(value: Variant) -> bool:
	# Never call int() or a numeric parser until the canonical ASCII magnitude
	# is known to fit signed 64 bits. Oversized untrusted input must not log an
	# engine conversion error as a side effect of rejecting the save.
	if not value is String or value.is_empty(): return false
	var negative: bool = value.begins_with("-")
	var magnitude: String = value.substr(1) if negative else value
	if magnitude.is_empty() or magnitude.length()>19: return false
	if magnitude=="0": return not negative
	if magnitude.begins_with("0"): return false
	for index in magnitude.length():
		var code: int = magnitude.unicode_at(index)
		if code<48 or code>57: return false
	var limit := "9223372036854775808" if negative else "9223372036854775807"
	return magnitude.length()<limit.length() or (magnitude.length()==limit.length() and magnitude<=limit)

static func parse_rng_state(value: String) -> int:
	# Only called after valid_rng_state. Accumulate negative digits directly
	# so INT64_MIN never requires an overflowing positive intermediate value.
	var negative := value.begins_with("-")
	var result := 0
	for index in range(1 if negative else 0,value.length()):
		var digit: int = value.unicode_at(index)-48
		result = result*10-digit if negative else result*10+digit
	return result

static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not _whole(rules.get("rules_version"),1,1) or not rules.get("synthetic") is bool or not rules.synthetic: return false
	if not rules.get("source_id") is String or rules.source_id.is_empty() or not _whole(rules.get("context_version"),1): return false
	if rules.get("days_per_season")!=3 or not rules.get("seasons") is Array or rules.seasons.size()!=4: return false
	var ids: Array = []
	for season in rules.seasons:
		if not season is Dictionary or not season.get("id") is String or season.id.is_empty() or season.id in ids: return false
		if not season.get("label") is String or season.label.is_empty(): return false
		ids.append(season.id)
		if not _number(season.get("mean_c")) or season.mean_c< -20 or season.mean_c>40: return false
		if not _number(season.get("diurnal_amplitude_c")) or season.diurnal_amplitude_c<0 or season.diurnal_amplitude_c>10: return false
		if not _unit(season.get("rain_start")) or not _unit(season.get("rain_continue")): return false
	if not rules.get("segment_minutes") is Dictionary: return false
	for condition in CONDITIONS:
		var span = rules.segment_minutes.get(condition)
		if not span is Array or span.size()!=2 or not _whole(span[0],1,1440) or not _whole(span[1],int(span[0]),1440): return false
	var rain = rules.get("rain_intensity")
	if not rain is Array or rain.size()!=2 or not _unit(rain[0]) or not _unit(rain[1]) or rain[0]<=0 or rain[0]>rain[1]: return false
	if not _number(rules.get("segment_offset_c")) or rules.segment_offset_c<0 or rules.segment_offset_c>5: return false
	if not _number(rules.get("rain_cooling_c")) or rules.rain_cooling_c<0 or rules.rain_cooling_c>5: return false
	if not _whole(rules.get("warmest_minute"),0,1439) or not rules.get("cost") is Dictionary: return false
	var cost: Dictionary = rules.cost
	for key in ["comfort_low_c","comfort_high_c","thermal_span_c","exposure_minutes","rain_weight","thermal_weight","exertion_weight"]:
		if not _number(cost.get(key)): return false
	return cost.comfort_low_c>=-10 and cost.comfort_high_c<=40 and cost.comfort_low_c<cost.comfort_high_c and cost.thermal_span_c>0 and cost.thermal_span_c<=50 and cost.exposure_minutes>=1 and cost.exposure_minutes<=1440 and _unit(cost.rain_weight) and _unit(cost.thermal_weight) and _unit(cost.exertion_weight)

func reset(world_seed: int, minute_of_day: int = 780, season_index: int = 0, season_day: int = 0, elapsed: int = 0) -> bool:
	if not _whole(world_seed,0,2147483647) or not _whole(minute_of_day,0,1439) or not _whole(season_index,0,3) or not _whole(season_day,0,2) or not _whole(elapsed): return false
	_seed = world_seed
	_sampling_origin = elapsed
	_origin = {"elapsed":elapsed,"minute_of_day":minute_of_day,"season_index":season_index,"season_day":season_day}
	_state = {"elapsed":elapsed,"condition":"clear","serial":0}
	_rng.seed = world_seed^SEED_SALT
	_sample(elapsed)
	return true

func _clock_at(elapsed: int) -> Dictionary:
	var total: int = int(_origin.minute_of_day)+elapsed-int(_origin.elapsed)
	var day: int = int(_origin.season_index)*3+int(_origin.season_day)+int(total/1440)
	return {"minute_of_day":posmod(total,1440),"season_index":posmod(int(day/3),4),"season_day":posmod(day,3)}

func _sample(at: int) -> void:
	var clock := _clock_at(at)
	var season: Dictionary = _rules.seasons[clock.season_index]
	var probability: float = season.rain_continue if _state.condition=="rain" else season.rain_start
	_state.condition = "rain" if _rng.randf()<probability else "clear"
	_state.rain_intensity = _rng.randf_range(float(_rules.rain_intensity[0]),float(_rules.rain_intensity[1])) if _state.condition=="rain" else 0.0
	_state.offset_c = _rng.randf_range(-float(_rules.segment_offset_c),float(_rules.segment_offset_c))
	_state.segment_started = at
	var duration: Array = _rules.segment_minutes[_state.condition]
	_state.next_change = at+_rng.randi_range(int(duration[0]),int(duration[1]))
	_state.serial = int(_state.serial)+1

func matches_clock(elapsed: int, minute_of_day: int, season_index: int) -> bool:
	# Pure integration guard: normal reset/restore must already agree. A caller
	# can detect external fixture clock edits without drawing or silently rebasing.
	if not _whole(elapsed) or elapsed<int(_state.elapsed): return false
	var clock := _clock_at(elapsed)
	return _whole(minute_of_day,0,1439) and _whole(season_index,0,3) and minute_of_day==clock.minute_of_day and season_index==clock.season_index

func rebase_calendar(elapsed: int, minute_of_day: int, season_index: int, season_day: int) -> bool:
	# Explicit fixture-only calendar edit. Sampling history and the pending
	# boundary stay in elapsed time; this cannot skip or rewind weather time.
	if not _whole(elapsed) or elapsed!=int(_state.elapsed): return false
	if not _whole(minute_of_day,0,1439) or not _whole(season_index,0,3) or not _whole(season_day,0,2): return false
	_origin = {"elapsed":elapsed,"minute_of_day":minute_of_day,"season_index":season_index,"season_day":season_day}
	return true

func tick(elapsed: int, minute_of_day: int, season_index: int) -> bool:
	if not matches_clock(elapsed,minute_of_day,season_index): return false
	# Cross each scheduled weather boundary, not each rendered frame. A large
	# batch sees the same seasonal context and draws as individual minute ticks.
	while int(_state.next_change)<=elapsed: _sample(int(_state.next_change))
	_state.elapsed = elapsed
	return true

func snapshot() -> Dictionary:
	var clock := _clock_at(int(_state.elapsed))
	var season: Dictionary = _rules.seasons[clock.season_index]
	var phase: float = TAU*(int(clock.minute_of_day)-int(_rules.warmest_minute))/1440.0
	var temperature: float = float(season.mean_c)+float(season.diurnal_amplitude_c)*cos(phase)+float(_state.offset_c)-float(_rules.rain_cooling_c)*float(_state.rain_intensity)
	return {"source_id":_rules.source_id,"context_version":int(_rules.context_version),"synthetic":true,
		"elapsed":int(_state.elapsed),"minute_of_day":clock.minute_of_day,"season_index":clock.season_index,"season_day":clock.season_day,
		"season":season.id,"condition":_state.condition,"rain_intensity":float(_state.rain_intensity),"temperature_c":temperature,
		"next_change_elapsed":int(_state.next_change),"segment_serial":int(_state.serial)}

func serialize() -> Dictionary:
	return {"schema":SCHEMA,"source_id":_rules.source_id,"context_version":int(_rules.context_version),"rules_version":int(_rules.rules_version),
		"weather_seed":_seed,"rng_state":str(_rng.state),"sampling_origin":_sampling_origin,"origin":_origin.duplicate(true),"state":_state.duplicate(true)}

func valid_save(payload: Variant) -> bool:
	if not payload is Dictionary or payload.size()!=9 or not _whole(payload.get("schema"),SCHEMA,SCHEMA) or payload.get("source_id")!=_rules.source_id or not _whole(payload.get("context_version"),1) or payload.context_version!=_rules.context_version or not _whole(payload.get("rules_version"),1,1): return false
	if not _whole(payload.get("weather_seed"),0,2147483647) or not valid_rng_state(payload.get("rng_state")) or not _whole(payload.get("sampling_origin")): return false
	var origin = payload.get("origin");var state = payload.get("state")
	if not origin is Dictionary or origin.size()!=4 or not state is Dictionary or state.size()!=7: return false
	if not _whole(origin.get("elapsed"),int(payload.sampling_origin)) or not _whole(origin.get("minute_of_day"),0,1439) or not _whole(origin.get("season_index"),0,3) or not _whole(origin.get("season_day"),0,2): return false
	if not _whole(state.get("elapsed"),int(origin.elapsed)) or state.get("condition") not in CONDITIONS: return false
	if not _whole(state.get("segment_started"),int(payload.sampling_origin),int(state.elapsed)) or not _whole(state.get("next_change"),int(state.elapsed)+1,MAX_ELAPSED+1440) or not _whole(state.get("serial"),1): return false
	if not _unit(state.get("rain_intensity")) or not _number(state.get("offset_c")) or absf(float(state.offset_c))>float(_rules.segment_offset_c): return false
	if state.condition=="clear" and state.rain_intensity!=0: return false
	if state.condition=="rain" and (state.rain_intensity<_rules.rain_intensity[0] or state.rain_intensity>_rules.rain_intensity[1]): return false
	var duration: Array = _rules.segment_minutes[state.condition]
	if not _whole(state.next_change-state.segment_started,int(duration[0]),int(duration[1])): return false
	var minimum: int = mini(int(_rules.segment_minutes.clear[0]),int(_rules.segment_minutes.rain[0]))
	var maximum: int = maxi(int(_rules.segment_minutes.clear[1]),int(_rules.segment_minutes.rain[1]))
	return state.segment_started>=payload.sampling_origin+(state.serial-1)*minimum and state.segment_started<=payload.sampling_origin+(state.serial-1)*maximum

func restore(payload: Variant) -> bool:
	if not valid_save(payload): return false
	# Validate everything before committing; rejection leaves clock and RNG alone.
	_seed = int(payload.weather_seed)
	_sampling_origin = int(payload.sampling_origin)
	_origin = payload.origin.duplicate(true);_state = payload.state.duplicate(true)
	for key in ["elapsed","minute_of_day","season_index","season_day"]: _origin[key] = int(_origin[key])
	for key in ["elapsed","segment_started","next_change","serial"]: _state[key] = int(_state[key])
	_rng.seed = _seed^SEED_SALT
	_rng.state = parse_rng_state(payload.rng_state)
	return true

static func action_cost(weather: Dictionary, context: Dictionary, cost_rules: Dictionary) -> Dictionary:
	# No activity IDs or person lookup. A caller can evaluate walking, waiting,
	# working or resting components with its own known context and traits.
	var invalid := {"valid":false,"rain":0.0,"thermal":0.0,"exertion":0.0,"total":0.0}
	if not context.get("indoor") is bool or not _number(context.get("outdoor_minutes")) or context.outdoor_minutes<0: return invalid
	if not _unit(weather.get("rain_intensity")) or not _number(weather.get("temperature_c")): return invalid
	if not _unit(context.get("effort",0.0)) or not context.get("traits",{}) is Dictionary: return invalid
	var traits: Dictionary = context.get("traits",{})
	for trait_key in ["negative_emotionality","open_mindedness"]:
		if not _unit(traits.get(trait_key,.5)): return invalid
	for key in ["comfort_low_c","comfort_high_c","thermal_span_c","exposure_minutes","rain_weight","thermal_weight","exertion_weight"]:
		if not _number(cost_rules.get(key)): return invalid
	if cost_rules.thermal_span_c<=0 or cost_rules.exposure_minutes<=0 or cost_rules.comfort_low_c>=cost_rules.comfort_high_c: return invalid
	for key in ["rain_weight","thermal_weight","exertion_weight"]:
		if not _unit(cost_rules[key]): return invalid
	if context.indoor: return {"valid":true,"rain":0.0,"thermal":0.0,"exertion":0.0,"total":0.0}
	var exposure := clampf(float(context.outdoor_minutes)/float(cost_rules.exposure_minutes),0,1)
	var hot := maxf(0,float(weather.temperature_c)-float(cost_rules.comfort_high_c))
	var cold := maxf(0,float(cost_rules.comfort_low_c)-float(weather.temperature_c))
	var rain := float(weather.rain_intensity)*exposure*float(cost_rules.rain_weight)
	var thermal := clampf(maxf(hot,cold)/float(cost_rules.thermal_span_c),0,1)*exposure*float(cost_rules.thermal_weight)
	var exertion := clampf(hot/float(cost_rules.thermal_span_c),0,1)*exposure*float(context.get("effort",0))*float(cost_rules.exertion_weight)
	var perceived := 1.0+.15*(float(traits.get("negative_emotionality",.5))-.5)-.10*(float(traits.get("open_mindedness",.5))-.5)
	return {"valid":true,"rain":rain,"thermal":thermal,"exertion":exertion,"total":clampf((1-(1-rain)*(1-thermal)*(1-exertion))*perceived,0,1)}

static func combine_costs(parts: Array) -> Dictionary:
	var remaining := 1.0
	for part in parts:
		if not part is Dictionary or part.get("valid")!=true or not _unit(part.get("total")): return {"valid":false,"total":0.0}
		remaining *= 1-float(part.total)
	return {"valid":true,"total":clampf(1-remaining,0,1)}
