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

func verify_person_context(main, sim) -> void:
	sim.reset(71103)
	sim.running = false
	main._select("aoi")
	main.get_node("%NowTab").pressed.emit()
	main.toast_left = 0
	main.get_node("%Toast").visible = false
	var p: Dictionary = sim.person("aoi")
	var introduction := "佐伯 文さんから、佐伯 修さんが修理に詳しいと聞いた。"
	p.cognition_plan = {"kind":"project","partner":"osamu","title":"譲り受けたラジオの修理",
		"stage":"travel","reason":introduction}
	var later := {"id":"hud_later","a":"aoi","b":"osamu","title":"ラジオ修理",
		"start":300,"departures":{"aoi":270},"state":"planned","meeting_id":"","place":"workshop"}
	var earlier := {"id":"hud_earlier","a":"aoi","b":"fumi","title":"写真の整理",
		"start":150,"departures":{"aoi":120},"state":"planned","meeting_id":"","place":"workshop"}
	sim.agenda.records = [later,earlier]
	var agreements_before: Array = sim.agenda.records.duplicate(true)
	var relationships_before: Dictionary = p.relationships.duplicate(true)
	var knowledge_before: Array = p.knowledge.duplicate(true)
	main._refresh_detail()
	expect(introduction in main.get_node("%Reason").text,"An introduction names the person who supplied the information")
	expect(not introduction in main.get_node("%DetailText").text,"The current plan's trigger is shown once rather than repeated in its body")
	expect("佐伯 修" in main.get_node("%DetailText").text,"The current plan keeps its actual activity partner separate from the introduction source")
	expect(main.get_node("%NextPlan").text=="今日 15:30 · 佐伯 文さんと写真の整理","The nearest real agreement shows its time, partner and activity")
	expect(not "写真の整理" in main.get_node("%DetailText").text and not "ラジオ修理" in main.get_node("%DetailText").text,"Future agreements are not repeated as a list below the current plan")
	expect(not "暮らしの背景" in main.get_node("%DetailText").text,"The current view leaves fixed background out of the live activity")
	await process_frame
	await process_frame
	expect(main.get_node("%DetailText").get_parent().size.y>100,"A wrapped introduction still leaves room for the current activity at 1280 pixels")
	await capture("04-introduction-fixture-1280")
	sim.social.appointments = [{"id":"hud_social","a":"aoi","b":"ritsu","start":90,"state":"planned"}]
	main._refresh_detail()
	expect(main.get_node("%NextPlan").text=="今日 14:30 · 三浦 律さんとゆっくり話す","An earlier accepted conversation takes priority over a later workshop agreement")
	sim.social.appointments.clear()
	earlier.state = "postponed"
	main._refresh_detail()
	expect("18:00" in main.get_node("%NextPlan").text and not "写真の整理" in main.get_node("%NextPlan").text,"A postponed agreement stops appearing as the next confirmed plan")
	earlier.state = "planned"
	p.cognition_plan.stage = "completed"
	main._refresh_detail()
	expect("一緒に進めたこと" in main.get_node("%DetailText").text and "佐伯 修" in main.get_node("%DetailText").text,"A completed plan retains the result and the person who took part")
	expect(main.get_node("%DetailText").text.count(introduction)==1,"A completed activity retains its introduction once beside its result")
	expect(introduction not in main.get_node("%Reason").text,"The completed plan's trigger does not replace the reason for today's current action")
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	await process_frame
	await process_frame
	await capture("05-completed-context-fixture-1440")
	main.get_node("%LifeTab").pressed.emit()
	expect(sim.definitions[p.id].public_private_difference in main.get_node("%DetailText").text,"The life tab preserves the person's fixed background")
	expect(sim.agenda.records==agreements_before and p.relationships==relationships_before and p.knowledge==knowledge_before,"Reading activity, introductions and results leaves agreements, relationships and knowledge unchanged")
	main.get_node("%NowTab").pressed.emit()
	p.cognition_plan.clear()
	main._refresh_detail()
	expect(not main.get_node("%DetailText").text.is_empty(),"A person without a current plan still shows their own interests or experience")

func verify_partner_selection(main, sim) -> void:
	sim.reset(71103)
	sim.running = false
	main._select("aoi")
	var defaults_preserved: bool = main.partner.get_selected_metadata()=="osamu"
	var p: Dictionary = sim.person("osamu")
	p.cognition_plan = {"kind":"project","partner":"aoi","stage":"execute","title":"ラジオの調整"}
	main._select("fumi")
	main._select("osamu")
	var plan_selected: bool = main.partner.get_selected_metadata()=="aoi"
	# A live encounter is authoritative if an older plan names somebody else.
	sim.meetings.append({"id":"hud_current_partner","a":"maho","b":"osamu","state":"engaged"})
	p.meeting_id = "hud_current_partner"
	main._select("fumi")
	main._select("osamu")
	var meeting_selected: bool = main.partner.get_selected_metadata()=="maho"
	sim.meetings.clear()
	p.meeting_id = ""
	# Missing and deceased plan partners must fall back to an available person.
	p.cognition_plan.partner = "missing_person"
	main._select("fumi")
	main._select("osamu")
	var safe_fallback: bool = sim.life.is_alive(sim.person(main.partner.get_selected_metadata()))
	sim.person("aoi").alive = false
	p.cognition_plan.partner = "aoi"
	main._select("fumi")
	main._select("osamu")
	safe_fallback = safe_fallback and main.partner.get_selected_metadata()!="aoi" and sim.life.is_alive(sim.person(main.partner.get_selected_metadata()))
	sim.person("aoi").alive = true
	main._select("fumi")
	main._select("osamu")
	expect(defaults_preserved and plan_selected and meeting_selected and safe_fallback,"Selecting another resident starts with their live activity partner, preserves idle defaults and excludes unavailable people")
	main.toast_left = 0
	main.get_node("%Toast").visible = false
	await capture("06-current-partner-selection-fixture-1440")
	for index in main.partner.item_count:
		if main.partner.get_item_metadata(index)=="ritsu": main.partner.select(index)
	main._refresh_detail()
	main._refresh_ui()
	main._process(1.0)
	await process_frame
	await process_frame
	expect(main.partner.get_selected_metadata()=="ritsu","A manually chosen proposal partner stays selected through person and frame refreshes")
	await capture("07-manual-partner-preserved-fixture-1440")

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
	await verify_person_context(main,sim)
	await verify_partner_selection(main,sim)
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
