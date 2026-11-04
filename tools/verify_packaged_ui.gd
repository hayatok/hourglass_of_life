extends SceneTree

# Run using matching Godot --main-pack <exported PCK> --script <this external file>.
# These checks concern the actual package and visible controls, not human usability.
var main
var checks := 0
var failures: Array[String] = []
var output := ""
var revision := ""
var models := {}
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--revision="): revision = argument.trim_prefix("--revision=")
	call_deferred("run")
func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description);push_error(description)
func run() -> void:
	var text_server := TextServerManager.get_primary_interface()
	var support_file: String = text_server.get_support_data_filename()
	if not support_file.begins_with("res://"): support_file = "res://"+support_file
	expect(ProjectSettings.get_setting("internationalization/locale/include_text_server_data",false) and FileAccess.file_exists(support_file),"The package includes the actual Japanese word/line-break support data, not just editor-side support")
	main = load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	var sim = root.get_node("Sim")
	sim.set_process(false);main.set_process(false)
	sim.reset(711,12);main._start_play();sim.running = false
	expect(main.avatars.size()==12 and main.roster.get_child_count()==12,"The package starts the twelve-person town and its complete selection list")
	var weather_before: Dictionary = sim.weather.serialize()
	var snapshot: Dictionary = sim.weather.snapshot()
	expect(FileAccess.file_exists("res://data/weather.json") and snapshot.synthetic and snapshot.condition in ["clear","rain"],"The actual package includes the explicit fictional climate and a valid current weather state")
	main._refresh_ui();main.get_node("Town").update_lighting()
	expect(main.get_node("%WeatherStatus").text==WeatherStatus.format_weather(snapshot),"The packaged date card shows the authoritative current weather and temperature")
	main._refresh_ui();main.get_node("Town").update_lighting()
	expect(sim.weather.serialize()==weather_before and is_equal_approx(main.get_node("Town").cloudiness,WeatherStatus.cloud_cover(snapshot)),"Reading the packaged weather and sky preserves the paused weather random stream")
	for id in ["haru","saki","tomo","yui"]:
		var model = main.avatars[id].jrpg
		var capability: Dictionary = model.capabilities()
		var good: bool = capability.source_model.ends_with(id+"/CH_"+id.capitalize()+".glb") and capability.contract_errors.is_empty()
		expect(good,id+": the dedicated body, real bound skeleton and all nine clips load from the package")
		expect(capability.facial_controls==["Blink","TiredEyes"] and capability.material_mode=="TEXTURE_TOON",id+": source-atlas toon shading and its two actual eye controls load")
		model.prepare_lods()
		var lods := true
		for level in [0,1,2,0]: lods = model.set_lod(level) and lods
		expect(lods,id+": every packaged distance LOD swaps with its compatible skin")
		models[id] = capability
		var contacts = main.avatars[id].contacts
		var grip: Dictionary = contacts.interaction_motion._play_grip_solution(contacts,"L")
		expect(grip.get("supported",false) and grip.get("pads",{}).size()==2,id+": packaged finger measurements bind to the real current rig and solve the physical disc grip")
	var portraits := true
	for button in main.roster.get_children(): portraits = portraits and button.icon!=null
	expect(portraits,"All twelve portrait choices work, including the original atlas and the four new portraits")
	expect(is_instance_valid(main.interaction_view.object_node("workshop_radio")) and main.tabletop_view.piece_nodes.size()==16 and is_instance_valid(main.tabletop_view.board_node),"The package reconstructs one real radio and the board with all sixteen physical tokens")
	expect(FileAccess.file_exists("res://data/sewing-work.json") and sim.sewing.objects.size()==9 and main.sewing_view.object_nodes.size()==9,"The package contains the finite six cloth pieces and three actual sewing tools, each rendered once")
	var cloth=main.sewing_view.object_node("sewing_cloth_01")
	var support: Dictionary=cloth.local_contacts("sewing")
	expect(support.get("support_left") is Vector3 and support.get("support_right") is Vector3,"The packaged workpiece resolves support from its real folded mesh surface")
	var before_zoom: float = main.distance
	main.get_node("%ZoomIn").pressed.emit()
	expect(main.distance<before_zoom and not sim.running,"The exported zoom-in control changes the actual camera distance while paused")
	main.get_node("%ZoomOut").pressed.emit()
	expect(is_equal_approx(main.distance,before_zoom),"The exported zoom-out control reverses zoom without advancing the clock")
	main._select("saki")
	main.get_node("%ProposeButton").pressed.emit()
	var proposals = main.proposals
	expect(proposals.visible and not sim.running,"The packaged resident card opens the new proposal flow and holds time")
	proposals.choose_kind("play")
	expect(proposals.get_node("%Play").text=="一緒に遊ぶ" and proposals.get_node("%Execute").text.contains("四目並べ") and proposals.get_node("%Execute").text.contains("咲"),"The packaged play proposal names the real resident and tabletop game before execution")
	proposals.choose_kind("support")
	var target: String = proposals.partner.get_selected_metadata()
	expect(proposals.get_node("%Execute").text.contains(sim.person(target).name) and proposals.get_node("%Execute").text.contains("咲"),"The packaged confirmation names the helper and the selected resident")
	proposals.close_panel()
	expect(not proposals.visible and not sim.running,"Cancelling the packaged proposal preserves the original pause")
	proposals.open_for("tomo");proposals.choose_kind("project");proposals._select_partner("yui");proposals.choose_activity("craft")
	expect(proposals.get_node("%ProjectActivity").visible and "智" in proposals.get_node("%Execute").text and "結衣" in proposals.get_node("%Execute").text and "布小物" in proposals.get_node("%Execute").text,"The actual package exposes the cloth recipe and names both participants before submitting")
	proposals.close_panel()
	main.get_node("%DetailToggle").button_pressed = true
	main.get_node("%PlansTab").pressed.emit()
	expect(main.detail_tab==4 and main.get_node("%DetailText").is_visible_in_tree() and not main.get_node("%DetailText").text.is_empty(),"The packaged notebook exposes the full confirmed-promise page")
	main.get_node("%DetailToggle").button_pressed = false
	var before_benches: Array = sim.benches.duplicate(true)
	var before_budget: int = sim.shared_budget
	main.get_node("%BuildToggle").button_pressed = true
	main.get_node("%BenchButton").pressed.emit()
	expect(main.placement and is_instance_valid(main.bench_preview),"The actual package contains the placeable bench preview")
	main.get_node("%CancelPlacement").pressed.emit()
	expect(not main.placement and sim.benches==before_benches and sim.shared_budget==before_budget,"Cancelling the packaged placement leaves the starting benches unchanged")
	var report := {"scope":"Actual exported PCK loaded by matching Godot; package/control smoke only. No save/load or fabricated town actions. Native app interaction is recorded separately.",
		"checks":checks,"failures":failures,"models":models,"text_server_support_file":support_file,"engine":Engine.get_version_info(),
		"provenance":{"source_revision":revision,"scope":"Identification only; no SHA or hash affects the outcome or count."}}
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	main.free()
	print("Packaged UI checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
