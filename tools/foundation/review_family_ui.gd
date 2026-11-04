extends SceneTree

# Actual scene rendering for layout review, without advancing household time.
# This establishes neither a completed family day nor natural motion.
const OUT := "res://builds/foundation-family-ui"

func _initialize() -> void:
	create_timer(20).timeout.connect(func():push_error("Family UI capture timed out");quit(1))
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var game=load("res://game/foundation/foundation_world.tscn").instantiate()
	root.add_child(game);game.running=false;game.pause_button.text="再開"
	if not game.initialization_error.is_empty():push_error(game.initialization_error);quit(1);return
	var report: Dictionary={"scope":"Paused actual game UI; rendering and layout review only, no family-day or motion acceptance.","views":[]}
	for dimensions in [Vector2i(1440,1000),Vector2i(1024,700)]:
		root.size=dimensions
		game.family_inspector.show_person("nagisa")
		for ignored in 5:await process_frame
		var bounds: Rect2=game.family_inspector.get_global_rect()
		# The project stretches a 1440x900 logical canvas. Physical window pixels
		# and Control coordinates must not be compared as if they shared a space.
		var canvas_size: Vector2=game.family_inspector.get_viewport_rect().size
		var in_bounds: bool=Rect2(Vector2.ZERO,canvas_size).encloses(bounds)
		report.views.append({"requested_window":[dimensions.x,dimensions.y],"actual_window":[root.size.x,root.size.y],
			"logical_canvas":[canvas_size.x,canvas_size.y],"inspector_bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"within_viewport":in_bounds})
		if not in_bounds:push_error("Family inspector leaves the visible viewport")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT+"/family-%dx%d.png"%[dimensions.x,dimensions.y])
	FileAccess.open(OUT+"/review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.free();quit(0)
