class_name WeatherStatus
extends Label

# UI reads the simulation's current snapshot; it never samples or advances it.
func set_weather(snapshot: Dictionary) -> void:
	text = format_weather(snapshot)

static func format_weather(snapshot: Dictionary) -> String:
	var condition: String = {"clear": "晴れ", "rain": "雨"}.get(str(snapshot.get("condition", "")), "—")
	var temperature: Variant = snapshot.get("temperature_c")
	if not (temperature is int or temperature is float) or not is_finite(float(temperature)):
		return condition
	var shown := snappedf(float(temperature), .1)
	var degrees := str(roundi(shown)) if is_equal_approx(shown, roundf(shown)) else "%.1f" % shown
	return "%s %s℃" % [condition, degrees]

static func cloud_cover(snapshot: Dictionary) -> float:
	# Presentation fallback for the two authored weather conditions. An explicit
	# snapshot value takes precedence; the function owns no RNG or world state.
	var cover: Variant = snapshot.get("cloud_cover")
	if (cover is int or cover is float) and is_finite(float(cover)):
		return clampf(float(cover), 0, 1)
	return .82 if snapshot.get("condition", "") == "rain" else 0.0
