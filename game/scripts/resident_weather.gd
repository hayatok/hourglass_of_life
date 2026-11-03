class_name ResidentWeather
extends RefCounted

# Weather supplies a bounded extra burden to voluntary venue choices. It does
# not assign an action, cancel a commitment, read another person's needs or draw.
var sim: LifeSimulation
var config: Dictionary

func _init(owner_sim: LifeSimulation) -> void:
	sim = owner_sim
	config = JSON.parse_string(FileAccess.get_file_as_string(WorldWeather.RULES_PATH))

func evaluate(p: Dictionary, option: Dictionary, observed: Dictionary = {}) -> Dictionary:
	var result := {"eligible":false,"total":0.0,"penalty":0.0,"indoor":false,"walking_minutes":0.0,"activity_minutes":0.0}
	if option.get("kind","") not in config.choice.free_kinds: return result
	var place: String = option.get("place","")
	if not sim.SITES.has(place) or place.begins_with("off_map_"): return result
	var spot: Dictionary = sim.activities.reserve(p,option.kind,place) if not option.has("target") else {}
	var target: Vector3 = option.get("target",spot.get("approach",sim.SITES[place]+sim._offset(sim.people.find(p))))
	var indoor := sim.activities.inside(place,target)
	# Off-map homes/school/work are beyond the simulated roofs. Do not invent
	# shelter there; their exposure is deferred until that environment exists.
	var same_room := indoor and sim.activities.inside(place,p.position)
	# This is a straight-distance estimate for scoring, not a claim that the
	# eventual route is straight. _assign still uses the physical street/aisles.
	var walk := 0.0 if same_room else minf(float(config.choice.walk_cap_minutes),p.position.distance_to(target)/sim.WALK_METERS_PER_MINUTE)
	var weather: Dictionary = sim.weather.snapshot() if observed.is_empty() else observed
	var traits: Dictionary = sim.definitions[p.id].traits
	var walking := WorldWeather.action_cost(weather,{"indoor":false,"outdoor_minutes":walk,"effort":.45,"traits":traits},config.cost)
	var activity := WorldWeather.action_cost(weather,{"indoor":indoor,"outdoor_minutes":float(config.choice.expected_minutes),"effort":.2,"traits":traits},config.cost)
	var composed := WorldWeather.combine_costs([walking,activity])
	if not composed.valid: return result
	result.merge({"eligible":true,"total":composed.total,"penalty":float(config.choice.score_weight)*float(composed.total),
		"indoor":indoor,"walking_minutes":walk,"activity_minutes":0.0 if indoor else float(config.choice.expected_minutes),"target":target},true)
	return result

func reason(original: String, exposure: Dictionary, weather: Dictionary) -> String:
	if not exposure.get("eligible",false): return original
	if weather.get("condition","")=="rain":
		if exposure.indoor: return "外は雨。屋内で過ごそう。"+original
		if exposure.total>.05: return "雨でも、今は外で過ごしたい。"+original
	return original
