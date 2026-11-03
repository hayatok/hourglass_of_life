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
	main = load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	var sim = root.get_node("Sim")
	sim.set_process(false);main.set_process(false)
	sim.reset(711,12);main._start_play();sim.running = false
	expect(main.avatars.size()==12 and main.roster.get_child_count()==12,"The package starts the twelve-person town and its complete selection list")
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
	var portraits := true
	for button in main.roster.get_children(): portraits = portraits and button.icon!=null
	expect(portraits,"All twelve portrait choices work, including the original atlas and the four new portraits")
	main._select("saki")
	main.get_node("%ProposeButton").pressed.emit()
	var proposals = main.proposals
	expect(proposals.visible and not sim.running,"The packaged resident card opens the new proposal flow and holds time")
	proposals.choose_kind("support")
	var target: String = proposals.partner.get_selected_metadata()
	expect(proposals.get_node("%Execute").text.contains(sim.person(target).name) and proposals.get_node("%Execute").text.contains("咲"),"The packaged confirmation names the helper and the selected resident")
	proposals.close_panel()
	expect(not proposals.visible and not sim.running,"Cancelling the packaged proposal preserves the original pause")
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
		"checks":checks,"failures":failures,"models":models,"engine":Engine.get_version_info(),
		"provenance":{"source_revision":revision,"scope":"Identification only; no SHA or hash affects the outcome or count."}}
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	main.free()
	print("Packaged UI checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
