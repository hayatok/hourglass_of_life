extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://docs/verification/v0.6/ui"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.get_texture().get_image().save_png(folder+"/"+name+".png")

func run() -> void:
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	var main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("%StartButton").pressed.emit()
	var sim = root.get_node("Sim")
	sim.running = false
	var hud: ObservationHUD = main.get_node("%HUD")
	hud.reveal_person()
	await process_frame
	await process_frame
	expect(not hud.residents_panel.visible,"The resident list starts folded so the town has room")
	expect(hud.detail_panel.visible,"Selecting a resident reveals their details")
	expect(not main.get_node("%EventText").visible,"The event history starts folded")
	expect(hud.actions_panel.size.y<80,"The folded action bar uses less than 80 pixels")
	await capture("01-observation-1440")
	main.get_node("%RosterToggle").button_pressed = true
	main.get_node("%HistoryToggle").button_pressed = true
	await process_frame
	await process_frame
	expect(hud.residents_panel.visible and main.get_node("%EventText").visible,"Resident and history toggles reveal their content")
	expect(hud.actions_panel.size.y>150,"Opening history reserves space rather than covering actions")
	expect(hud.detail_panel.get_rect().end.y<hud.actions_panel.position.y,"Details stay clear of the expanded history")
	await capture("02-history-1440")
	main.get_node("%DetailToggle").button_pressed = false
	expect(not hud.detail_panel.visible,"The details can be folded for an unobstructed view")
	hud.reveal_person()
	expect(hud.detail_panel.visible and main.get_node("%DetailToggle").button_pressed,"A new selection reopens the details and its toggle together")
	hud._choose_speed(4)
	expect(sim.speed==30,"The speed menu invokes the existing high-speed action")
	hud._choose_speed(0)
	expect(sim.speed==.5,"The speed menu also exposes slow observation")
	main.get_node("%RosterToggle").button_pressed = false
	main.get_node("%HistoryToggle").button_pressed = false
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	await process_frame
	await process_frame
	var top: Control = hud.get_node("TimePanel")
	var actions: Control = hud.get_node("ActionsPanel/ActionColumn/Actions")
	var within_top := true
	for control in top.get_node("TimeControls").get_children():
		if control is Control and control.visible:
			within_top = within_top and control.get_global_rect().end.x<=root.size.x
	expect(within_top,"Every visible time toolbar control fits at 1280 pixels")
	expect(actions.get_global_rect().end.x<=root.size.x,"Every action fits at 1280 pixels")
	expect(main.get_node("%BenchButton").get_global_rect().end.x<=root.size.x,"The placement action remains reachable at 1280 pixels")
	await capture("03-observation-1280")
	var running_before: bool = sim.running
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	hud._input(space)
	expect(sim.running!=running_before,"Space pauses even after using a toolbar control")
	main.get_node("%MenuButton").pressed.emit()
	var menu_running: bool = sim.running
	hud._input(space)
	expect(sim.running==menu_running,"The HUD shortcut does not resume time behind a menu")
	print("Observation HUD checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	main.free()
	quit(0 if failures.is_empty() else 1)
