extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);push_error(message)

func run() -> void:
	root.size=Vector2i(1280,800)
	var main=load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	var sim=root.get_node("Sim");sim.set_process(false);sim.running=false
	var path: String="user://test-load-feedback-%d.json"%OS.get_process_id()
	expect(sim.save_game(path),"A dedicated current-format test save can be written without touching the player's save")
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));raw.schema=6
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(raw))
	var saved_text:=FileAccess.get_file_as_string(path)
	var before: Dictionary=sim._encode({"people":sim.people,"elapsed":sim.elapsed,"rng":str(sim.rng.state)})
	main._continue_game(path)
	await process_frame
	expect(main.title.visible and not main.get_node("%HUD").visible and main.info_dialog.visible,"Rejected Continue displays its actual dialog above the title, where the HUD toast would be hidden")
	expect("新しい町" in main.info_dialog.dialog_text and not sim.load_error.is_empty(),"The actual incompatible-format response explains how to proceed")
	expect(sim._encode({"people":sim.people,"elapsed":sim.elapsed,"rng":str(sim.rng.state)})==before and FileAccess.get_file_as_string(path)==saved_text,"The failed load preserves the live town and the original save contents")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://builds/load-feedback")
		root.get_texture().get_image().save_png("res://builds/load-feedback/old-format.png")
	main.info_dialog.hide()
	expect(sim.save_game(path),"The isolated test can write the new format")
	main._continue_game(path)
	await process_frame
	expect(not main.title.visible and main.get_node("%HUD").visible and not main.info_dialog.visible,"A current-format Continue opens the actual town successfully")
	main.free();DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Load feedback checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
