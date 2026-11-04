extends SceneTree

const OUT := "res://builds/foundation-household"

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1440,1000)
	DirAccess.make_dir_recursive_absolute(OUT)
	var game=load("res://game/foundation/foundation_world.tscn").instantiate()
	root.add_child(game);game.set_process(false)
	if not game.initialization_error.is_empty():push_error(game.initialization_error);quit(1);return
	var duration:=360.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--minutes="):duration=float(argument.trim_prefix("--minutes="))
	var timeline: Array=[]
	var collisions: Array=[]
	var next_sample:=0.0
	var started:=Time.get_ticks_msec()
	while game.household.elapsed<duration:
		game.executor.step(1.0/30.0,1.0/60.0)
		game.household_props.sync(1.0/30.0)
		# Furniture work now requires the actual deferred skeletal support sample.
		# A tight clock loop without an engine frame cannot establish that contact.
		await process_frame
		var ids: Array=game.residents.keys()
		for first in ids.size():
			for second in range(first+1,ids.size()):
				var a: FoundationResident=game.residents[ids[first]]
				var b: FoundationResident=game.residents[ids[second]]
				if a.visible and b.visible and a.global_position.distance_to(b.global_position)<.47:
					if collisions.size()<20:collisions.append({"at":game.household.elapsed,"actors":[ids[first],ids[second]],"distance":a.global_position.distance_to(b.global_position)})
		if game.household.elapsed>=next_sample:
			var row: Dictionary={"at":game.household.elapsed,"people":{},"inventory":game.household.inventory.duplicate(true)}
			for id in game.residents:
				var task: Dictionary=game.household.task_for(id)
				row.people[id]={"task":task.get("kind",""),"phase":task.get("phase_name",""),"body":game.residents[id].snapshot(),"execution":game.executor.execution[id].duplicate(true)}
			timeline.append(row);next_sample+=30
	game._update_household_ui()
	if DisplayServer.get_name()!="headless":
		for ignored in 4:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"/household.png")
	var report: Dictionary={"scope":"New house/actor/life integration at physical motor speed and .5 game minutes per second. Not a natural-animation or finished-household quality acceptance.",
		"duration_minutes":game.household.elapsed,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,
		"timeline":timeline,"overlapping_bodies":collisions,"life":game.household.snapshot(),"execution":game.executor.execution}
	FileAccess.open(OUT+"/inspection.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	var completed: Dictionary={}
	for id in game.household.people:completed[id]=game.household.people[id].history.completed
	print("Household integration observed ",game.household.elapsed," minutes; completed=",completed,"; overlapping bodies=",collisions.size())
	game.free();quit(1 if not collisions.is_empty() else 0)
