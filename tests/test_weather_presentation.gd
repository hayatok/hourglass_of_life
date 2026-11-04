extends SceneTree

const CLEAR := {"condition":"clear", "temperature_c":18.0, "rain_intensity":0.0}
const RAIN := {"condition":"rain", "temperature_c":12.0, "rain_intensity":.8}
const OUT := "res://builds/weather-presentation"
var checks := 0
var failures: Array[String] = []
var artifact_failures: Array[String] = []
var report := {"scope":"Controlled UI and lighting snapshots on the real town scene; not natural-action evidence or a human playtest.",
	"lighting":{}, "layouts":[], "artifacts":[]}

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func rect_data(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func light_state(town: TownEnvironment) -> Dictionary:
	var environment: Environment = town.get_node("WorldEnvironment").environment
	var sun: DirectionalLight3D = town.get_node("Sun")
	var top: Color = town.sky_material.sky_top_color
	return {"sun":sun.light_energy,"ambient":environment.ambient_light_energy,
		"daylight":town.daylight,"cloud":town.cloudiness,"sky":[top.r,top.g,top.b],
		"sun_rotation":[sun.rotation.x,sun.rotation.y,sun.rotation.z]}

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := OUT+"/gpu-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder+"/"+name+".png"
	var error := root.get_texture().get_image().save_png(path)
	report.artifacts.append({"path":path,"written":error==OK})
	if error!=OK: artifact_failures.append(path)

func run() -> void:
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	var sim: LifeSimulation = root.get_node("Sim")
	sim.reset(71103,12)
	sim.running = false
	var main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._start_play()
	sim.running = false
	main.get_node("%HUD")._show_residents(false)
	await process_frame
	await process_frame
	var status: WeatherStatus = main.get_node("%WeatherStatus")
	var town: TownEnvironment = main.get_node("Town")
	var weather = sim.get("weather")
	expect(weather!=null,"The real town has a current weather source for the HUD and sky")
	var current: Dictionary = weather.snapshot() if weather!=null else {}
	main._refresh_ui()
	town.update_lighting()
	expect(not current.is_empty() and status.text==WeatherStatus.format_weather(current),"The real date card displays the current simulation weather snapshot")
	expect(is_equal_approx(town.cloudiness,WeatherStatus.cloud_cover(current)),"The real sky reads the same current weather snapshot as the date card")
	# Freeze presentation during controlled comparison frames. The authoritative
	# town is paused throughout; neither weather nor resident behavior is forced.
	main.set_process(false)
	town.set_process(false)
	var before_people: Array = sim.people.duplicate(true)
	var before_rng: int = sim.rng.state
	var before_elapsed: int = sim.elapsed
	var before_running: bool = sim.running
	var before_weather: Dictionary = current.duplicate(true)
	status.set_weather(CLEAR)
	var clear_text: String = status.text
	status.set_weather(RAIN)
	var rain_text: String = status.text
	status.set_weather({"condition":"rain","temperature_c":-2.5})
	expect(clear_text=="晴れ 18℃" and rain_text=="雨 12℃" and status.text=="雨 -2.5℃","The compact non-button weather line preserves the actual condition and temperature, including negative values")
	expect(status.focus_mode==Control.FOCUS_NONE,"Reading weather does not add a keyboard action or steal button focus")
	town.update_lighting(CLEAR)
	var clear: Dictionary = light_state(town)
	status.set_weather(CLEAR)
	await capture("01-clear-1440")
	town.update_lighting(RAIN)
	var rain: Dictionary = light_state(town)
	status.set_weather(RAIN)
	expect(float(rain.sun)>0 and float(rain.sun)<float(clear.sun) and float(rain.ambient)>0 and float(rain.ambient)<float(clear.ambient),"Rain softens daylight and ambient light while keeping the town illuminated")
	expect(rain.sky!=clear.sky and rain.sun_rotation==clear.sun_rotation and is_equal_approx(rain.daylight,clear.daylight),"Overcast changes the sky without changing the sun's time or direction")
	town.update_lighting(RAIN)
	expect(light_state(town)==rain,"Repeated weather refreshes recompute lighting instead of progressively darkening it")
	report.lighting.day = {"clear":clear,"rain":rain}
	await capture("02-rain-1440")
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800),Vector2i(1024,700)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await process_frame
		await process_frame
		var hud: Control = main.get_node("%HUD")
		var time: Rect2 = hud.get_node("TimePanel").get_global_rect()
		var navigation: Rect2 = hud.get_node("Navigation").get_global_rect()
		var calendar: Rect2 = main.get_node("%Calendar").get_global_rect()
		var clock: Rect2 = main.get_node("%Clock").get_global_rect()
		var line: Rect2 = status.get_global_rect()
		var viewport := Rect2(Vector2.ZERO,Vector2(dimensions))
		var font: Font = status.get_theme_font("font")
		var text_width: float = font.get_string_size(status.text,HORIZONTAL_ALIGNMENT_LEFT,-1,status.get_theme_font_size("font_size")).x
		expect(viewport.encloses(time) and time.encloses(line) and not line.intersects(calendar) and not line.intersects(clock) and text_width<=line.size.x+.5,
			"Weather remains fully readable below the calendar and beside the clock at %d pixels"%dimensions.x)
		expect(not time.intersects(navigation) and time.end.y<hud.get_node("ResidentsPanel").global_position.y,
			"The two-line date card stays clear of navigation and resident panels at %d pixels"%dimensions.x)
		report.layouts.append({"viewport":[dimensions.x,dimensions.y],"weather":rect_data(line),"time":rect_data(time),"navigation":rect_data(navigation)})
		if dimensions.x==1024: await capture("03-rain-1024")
	# An unattached clock fixture exercises midnight without changing Sim's
	# time, residents, RNG, saved weather, or their accepted commitments.
	var midnight := LifeSimulation.new()
	midnight.start_minute = 0
	town.simulation = midnight
	town.update_lighting(CLEAR)
	var clear_night: Dictionary = light_state(town)
	town.update_lighting(RAIN)
	var rain_night: Dictionary = light_state(town)
	expect(is_equal_approx(clear_night.sun,rain_night.sun) and is_equal_approx(clear_night.ambient,rain_night.ambient) and float(rain_night.ambient)>0,
		"Clouds preserve the existing night lighting floor instead of hiding residents after dark")
	town.simulation = sim
	midnight.free()
	report.lighting.night = {"scope":"Controlled clock fixture","clear":clear_night,"rain":rain_night}
	var weather_after: Dictionary = weather.snapshot() if weather!=null else {}
	expect(sim.people==before_people and sim.rng.state==before_rng and sim.elapsed==before_elapsed and sim.running==before_running and weather_after==before_weather,
		"Weather display and controlled lighting leave authoritative residents, clock, RNG, running state and weather unchanged")
	main._refresh_ui()
	town.update_lighting()
	expect(status.text==WeatherStatus.format_weather(current) and is_equal_approx(town.cloudiness,WeatherStatus.cloud_cover(current)),"Normal refresh returns from controlled comparisons to the authoritative current weather")
	main.free()
	report.functional_checks = {"passed":checks-failures.size(),"failed":failures.size(),"failures":failures}
	report.artifact_failures = artifact_failures
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var suffix := "headless" if DisplayServer.get_name()=="headless" else "gpu-%d"%OS.get_process_id()
	var file := FileAccess.open(OUT+"/"+suffix+".json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print("Weather presentation checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() and artifact_failures.is_empty() else 1)
