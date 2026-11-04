extends SceneTree

# Controlled starts at real approaches, then native furniture entry and exit.
# This does not replace a normal-speed full family-day review.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func sofa_case(id: String) -> void:
	var game=load("res://game/foundation/foundation_world.tscn").instantiate()
	root.add_child(game);game.set_process(false)
	if not game.initialization_error.is_empty():expect(false,game.initialization_error);game.free();return
	var day: HouseholdDay=game.household
	day.start_minute=18*60 # Controlled free evening; sleeping children may decline at 04:00.
	var response: Dictionary
	if id=="rin":
		day.request("ryo","care")
		response=day.request(id,"family_time")
	else:response=day.request(id,"care")
	if response.status!="requested":expect(false,id+": a family-time intention can be formed");game.free();return
	var task: Dictionary=response.task
	var actor: FoundationResident=game.residents[id]
	# Deliberate fixture setup, not evidence of routing from a bedroom.
	actor.global_position=task.target;actor.configure(actor.snapshot().profile)
	actor.face_heading(PI)
	for ignored in 240:
		actor.tick_body(1.0/30);await process_frame
		if actor.body_is_settled():break
	day.set_position(id,actor.global_position)
	expect(day.arrive(id,task.id).status=="entering",id+": reaching the sofa approach does not count as sitting or shared time")
	var use: FoundationFurnitureUse=game.executor.furniture[id]
	if not use.begin(task):expect(false,id+": sofa entry begins");game.free();return
	for ignored in 600:
		use.advance(1.0/30);day.set_position(id,actor.global_position);await process_frame
		if use.ready() and actor.furniture_contacts_ready():break
	if not actor.furniture_contacts_ready():
		DirAccess.make_dir_recursive_absolute("res://builds/furniture-use")
		FileAccess.open("res://builds/furniture-use/"+id+".json",FileAccess.WRITE).store_string(JSON.stringify(HouseholdDay._encode(actor.furniture_pose.telemetry()),"\t"))
	expect(use.ready() and actor.furniture_contacts_ready(),id+": the real skeletal body reaches and contacts the sofa seat")
	var feet: Dictionary=actor.furniture_pose.telemetry().get("feet",{}).get("sides",{})
	if id=="rin":
		expect(feet.size()==2 and feet.values().all(func(foot):return foot.support_kind=="free" and not foot.required and foot.body_weight_support=="seat" and foot.actual_support_point.y>.02),"A short lower leg may dangle above the real floor while the seat supports the child; no floor contact is claimed")
	else:expect(feet.size()==2 and feet.values().all(func(foot):return foot.required and foot.support_kind=="floor" and foot.support_error_m<=.03),id+": adult feet still require actual floor support")
	if DisplayServer.get_name()!="headless":
		game.target=actor.global_position+Vector3.UP*.4;game.distance=3.3;game.pitch=.32;game.yaw=-1.9
		game._update_camera();game._update_household_ui()
		await process_frame;await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://builds/furniture-use")
		root.get_texture().get_image().save_png("res://builds/furniture-use/"+id+"-sofa.png")
	response=day.begin_use(id,task.id,actor.global_position,"sit")
	expect(response.status=="arrived",id+": actual seated root is admitted by the home's usage region: "+str(actor.global_position))
	expect(day.person(id).actual_minutes.is_empty(),id+": entering the seat gives no family-time credit")
	day.cancel(id,task.id,"席を離れる");use.begin_exit()
	for ignored in 600:
		use.advance(1.0/30);day.set_position(id,actor.global_position);await process_frame
		if use.exit_ready():break
	expect(use.exit_ready() and actor.global_position.distance_to(task.target)<.065,id+": standing and leaving returns to the actual approach")
	response=day.end_use(id,task.id,actor.global_position)
	expect(response.status=="cancelled" and use.finalize_exit(),id+": the real exit releases the task and furniture transaction together")
	game.free();await process_frame

func run() -> void:
	for id in ["nagisa","ryo","rin"]:
		if OS.get_cmdline_user_args().is_empty() or id in OS.get_cmdline_user_args():await sofa_case(id)
	print("Furniture use integration: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
