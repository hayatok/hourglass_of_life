extends SceneTree

# Short, bounded observation of the actual house. No test totals are inferred
# from captures; the report keeps real life, motor and final pose separately.
const OUT := "res://builds/foundation-furniture-world"

func _initialize() -> void:call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1280,800)
	var game=load("res://game/foundation/foundation_world.tscn").instantiate()
	root.add_child(game);game.set_process(false)
	if not game.initialization_error.is_empty():push_error(game.initialization_error);quit(1);return
	var frames:=300;var focus:="ryo"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="):frames=int(argument.trim_prefix("--frames="))
		if argument.begins_with("--focus="):focus=argument.trim_prefix("--focus=")
	var samples: Array=[];var started:=Time.get_ticks_msec();var completed:=0
	for frame in frames:
		game.executor.step(1.0/30.0,1.0/60.0)
		game.household_props.sync(1.0/30)
		var at: Vector3=game.residents[focus].global_position
		var use: FoundationFurnitureUse=game.executor.furniture[focus]
		if use.active() and use.session.kind=="bed":at=use.session.original+Vector3.UP*.3
		game.target=at+Vector3.UP*.5;game.distance=6;game._update_camera();game._update_household_ui()
		await process_frame
		completed=frame+1
		if frame%60==59:
			var row: Dictionary={"frame":completed,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"people":{}}
			for id in game.residents:
				row.people[id]={"task":game.household.task_for(id),"execution":game.executor.execution[id],"furniture":game.executor.furniture[id].snapshot(),
					"motor":game.residents[id].snapshot(),"pose":game.residents[id].furniture_pose.telemetry()}
			samples.append(HouseholdDay._encode(row))
			print("Household frame ",completed," in ",row.wall_seconds," seconds; furniture ",use.session.get("phase","none"))
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUT+"/%s-%04d.png"%[focus,completed])
		if Time.get_ticks_msec()-started>45000:break
	var report: Dictionary={"scope":"Short actual house observation; no natural-motion or family-day acceptance.","frames":completed,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"samples":samples}
	FileAccess.open(OUT+"/"+focus+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.free();quit(0)
