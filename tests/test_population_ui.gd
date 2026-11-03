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
	var folder := "res://docs/verification/v0.8/population"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.get_texture().get_image().save_png(folder+"/"+name+".png")

func run() -> void:
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	var main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("%StartButton").pressed.emit()
	var sim = root.get_node("Sim")
	sim.running = false
	await process_frame
	await process_frame
	expect(sim.people.size()==12 and main.avatars.size()==12,"The actual new-game action starts twelve residents and twelve actors")
	sim.reset(71103,12)
	sim.running = false
	main.get_node("%RosterToggle").toggled.emit(true)
	var search: LineEdit = main.get_node("%ResidentSearch")
	var roster: VBoxContainer = main.get_node("%Roster")
	var scroll: ScrollContainer = roster.get_parent()
	await process_frame
	expect(roster.get_child_count()==12,"All twelve people have selectable roster entries")
	expect(scroll.get_v_scroll_bar().max_value>scroll.size.y,"The twelve-person list can scroll at 1280 by 800")
	expect(scroll.get_global_rect().end.y<=main.get_node("%HUD").get_node("ResidentsPanel").get_global_rect().end.y,"The roster scroll stays inside the residents panel")
	scroll.ensure_control_visible(roster.get_child(11))
	await process_frame
	expect(scroll.scroll_vertical>0,"The last resident can be brought into the visible roster")
	roster.get_child(11).pressed.emit()
	expect(main.selected_id=="yui","Selecting the last roster entry opens the actual new resident")
	expect(main.portrait.texture!=null and main.portrait.texture.resource_path.ends_with("/yui.png"),"The new resident has their own portrait instead of an existing resident's atlas region")
	var partner_ids := []
	for index in main.partner.item_count: partner_ids.append(main.partner.get_item_metadata(index))
	expect(partner_ids.size()==11 and "saki" in partner_ids and "yui" not in partner_ids,"The interaction chooser includes every other living resident")
	await capture("01-twelve-residents-1280")
	search.text = "結衣"
	search.text_changed.emit(search.text)
	await process_frame
	var visible: Array = roster.get_children().filter(func(button): return button.visible)
	expect(visible.size()==1 and "森 結衣" in visible[0].text,"Searching a given name leaves the matching resident selectable")
	visible[0].pressed.emit()
	expect(main.selected_id=="yui","Selecting a search result keeps the matching person's context")
	await capture("02-resident-search-1280")
	search.text = "該当しない名前"
	search.text_changed.emit(search.text)
	expect(roster.get_children().all(func(button): return not button.visible),"An unmatched search does not display unrelated residents")
	search.text = ""
	search.text_changed.emit(search.text)
	expect(roster.get_children().all(func(button): return button.visible),"Clearing the search restores the complete roster")
	search.grab_focus()
	var before_running: bool = sim.running
	var before_cutaway: bool = main.get_node("Town").cutaway
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	main._unhandled_input(key)
	key.keycode = KEY_V
	main._unhandled_input(key)
	expect(sim.running==before_running and main.get_node("Town").cutaway==before_cutaway,"Typing into resident search does not trigger pause or building shortcuts")
	search.release_focus()
	# The smaller authored fixture remains useful for matched comparisons.
	sim.reset(71103,8)
	await process_frame
	expect(main.selected_id=="aoi" and main.avatars.size()==8,"Changing the development roster releases a now-absent selection safely")
	main.queue_free()
	await process_frame
	print("Population UI checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
