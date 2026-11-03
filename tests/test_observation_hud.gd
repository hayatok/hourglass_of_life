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
	var folder := "res://docs/verification/ui-redesign"
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
	await process_frame
	await process_frame
	expect(hud.residents_panel.visible,"A new town offers a visible portrait roster so a first resident can be chosen")
	expect(hud.actions_panel.visible and not hud.detail_panel.visible,"The selected resident has a compact card while the notebook starts closed")
	expect(not hud.get_node("HistoryPanel").visible and not hud.get_node("BuildPanel").visible,"History and town construction are separate deliberate modes")
	expect(main.get_node("%ProposeButton").text.contains(sim.person(main.selected_id).name.split(" ")[-1]),"The proposal entry names the resident who will receive it")
	await capture("01-new-town-1440")
	main.get_node("%RosterToggle").button_pressed = false
	main._select("saki")
	expect(not hud.detail_panel.visible,"Choosing another resident keeps the world visible instead of opening a wall of details")
	main.get_node("%DetailToggle").button_pressed = true
	expect(hud.detail_panel.visible and main.get_node("%NotebookName").text.contains("咲"),"The notebook opens explicitly for the selected resident")
	main.get_node("%RelationsTab").pressed.emit()
	expect(not main.get_node("%Goal").visible and not main.get_node("%Reason").visible,"Relationships have their own page without unrelated needs and goals above it")
	main.get_node("%HistoryToggle").button_pressed = true
	expect(hud.get_node("HistoryPanel").visible and not hud.detail_panel.visible,"Opening town events replaces the notebook rather than stacking opaque panels")
	await capture("02-events-1440")
	main.get_node("%CloseHistory").pressed.emit()
	expect(not hud.history_open,"The visible close action dismisses town events")
	hud._choose_speed(4)
	expect(sim.speed==30 and not sim.running,"Changing the speed to thirty while paused preserves the pause")
	hud._choose_speed(0)
	expect(sim.speed==.5 and not sim.running,"Slow observation can also be selected without unexpectedly starting time")
	main.get_node("%PauseButton").pressed.emit()
	expect(sim.running,"Only the explicit resume action starts time again")
	sim.running = false
	main.get_node("%BuildToggle").button_pressed = true
	expect(hud.get_node("BuildPanel").visible and main.get_node("%BenchButton").text.contains("20"),"Town editing reveals the bench cost next to the shared budget")
	var budget_before: int = sim.shared_budget
	var benches_before: Array = sim.benches.duplicate()
	main.get_node("%BenchButton").pressed.emit()
	expect(main.placement and hud.get_node("PlacementHint").visible and is_instance_valid(main.bench_preview),"Bench placement offers a visible world preview and cancellation before spending anything")
	main.get_node("%CancelPlacement").pressed.emit()
	expect(not main.placement and not main.bench_preview.visible and sim.shared_budget==budget_before and sim.benches==benches_before,"Cancelling placement removes the preview and leaves the town and budget unchanged")
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800),Vector2i(1024,768)]:
		root.size = dimensions;root.content_scale_size = dimensions
		await process_frame
		await process_frame
		var card: Rect2 = hud.actions_panel.get_global_rect()
		var time: Rect2 = hud.get_node("TimeDock").get_global_rect()
		var tools: Rect2 = hud.get_node("TownTools").get_global_rect()
		expect(not card.intersects(time) and not time.intersects(tools),"Resident, time and town controls stay separate at %d pixels"%dimensions.x)
		for name in ["ProposeButton","DetailToggle","PauseButton","RosterToggle","MenuButton"]:
			var rect: Rect2 = main.get_node("%"+name).get_global_rect()
			expect(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(rect),name+" remains reachable inside the %d-pixel viewport"%dimensions.x)
		await capture("03-observation-%d"%dimensions.x)
	await verify_person_context(main,sim)
	await verify_partner_selection(main,sim)
	main._select("aoi")
	main._build_roster()
	var highlighted: Array = main.roster.get_children().filter(func(button): return button.button_pressed)
	expect(highlighted.size()==1 and highlighted[0].get_meta("resident_id")=="aoi","Rebuilding the roster preserves the visible selected resident")
	sim.running = false
	main.dragging = true
	main.get_node("%ProposeButton").pressed.emit()
	expect(main.proposals.visible and not main.dragging and not sim.running,"Opening a proposal cancels camera dragging and keeps a paused town paused")
	var blocked_space := InputEventKey.new();blocked_space.keycode = KEY_SPACE;blocked_space.pressed = true
	hud._input(blocked_space)
	main._unhandled_input(blocked_space)
	expect(not sim.running,"Neither background shortcut handler starts time behind a proposal")
	main.proposals.close_panel()
	main._set_speed(1.0);hud._process(0)
	expect(hud.speed_menu.text.begins_with("ふつう") and not sim.running,"Normal speed has a readable label even when the engine stores it as a float")
	var reply: Dictionary = sim.support_goal("aoi")
	main._refresh_events();hud._process(0)
	main.get_node("%LatestEvent").pressed.emit()
	expect(hud.history_open and "葵" in main.get_node("%EventHeading").text and reply.text in main.get_node("%EventText").text,"A real resident reply can be reopened from its visible event preview with the correct person's record")
	main.get_node("%CloseHistory").pressed.emit()
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
	main.get_node("%ResumeButton").pressed.emit()
	var before_journal: bool = sim.running
	main.get_node("%JournalButton").pressed.emit()
	expect(main.get_node("%JournalScreen").visible and not sim.running and not main.get_node("%JournalBody").text.is_empty(),"Town records open from the actual live world and hold time while the player reads")
	await capture("08-live-journal")
	main.get_node("%JournalContinueButton").pressed.emit()
	expect(not main.get_node("%JournalScreen").visible and sim.running==before_journal,"Returning from town records restores the previous time state")
	main._select("saki");main.following = true
	main.get_node("%ResidentSearch").text = "該当なし"
	main._to_title();main._new_game()
	expect(main.selected_id=="aoi" and not main.following and main.distance>14 and main.get_node("%ResidentSearch").text.is_empty() and main.roster.get_children().all(func(button): return button.visible),"Starting a new town clears the old search, selection and camera tracking instead of inheriting stale UI context")
	print("Observation HUD checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	main.free()
	quit(0 if failures.is_empty() else 1)
