extends SceneTree

const OUT := "res://builds/motion-retarget/engine-review"
var errors: Array[String] = []

func _initialize() -> void: call_deferred("run")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(OUT+"/"+label+".png")!=OK: errors.append("Capture failed: "+label)

func run() -> void:
	root.size=Vector2i(1100,900)
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	DirAccess.make_dir_recursive_absolute(OUT)
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("dfddd1")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("fff5dd");environment.ambient_light_energy=.5
	env.environment=environment;world.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=.7;sun.shadow_enabled=true;world.add_child(sun)
	var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(12,14);floor_mesh.mesh=plane
	var material:=StandardMaterial3D.new();material.albedo_color=Color("c6bba6");floor_mesh.material_override=material;world.add_child(floor_mesh)
	var actor:=FoundationResident.new();actor.name="NagisaMotionReview";world.add_child(actor)
	if not actor.configure({"walk_speed":.9639}) or not actor.load_resident("nagisa"):
		push_error("Foundation motion could not load");quit(1);return
	var contacts: bool="--contacts" in OS.get_cmdline_user_args()
	if contacts:
		actor.configure({"walk_speed":.9639,"turn_speed":PI*.5})
		if not actor.enable_contact_locomotion():push_error("Support locomotion adapter could not configure");quit(1);return
	var camera:=Camera3D.new();camera.fov=34;camera.position=Vector3(3.5,2.1,4.2);world.add_child(camera)
	camera.look_at(Vector3(0,.85,0));camera.current=true
	var samples: Array=[]
	for frame in 60:
		actor.tick_body(1.0/60)
		if contacts:await process_frame
	await capture("nagisa-idle")
	actor.follow_path([Vector3(0,0,5)])
	for frame in 240:
		actor.tick_body(1.0/60)
		if contacts:await process_frame
		camera.position=actor.position+Vector3(3.5,2.1,4.2);camera.look_at(actor.position+Vector3(0,.85,0))
		if frame in [30,60,80,100,120,140,160,180,200]:
			var pose_record: Dictionary=actor.motion_state()
			pose_record.frame=frame
			pose_record.unmodified_base_pose_bones={}
			if contacts:pose_record.support_pose=actor.locomotion.telemetry()
			for bone in ["pelvis","foot.L","toe.L","foot.R","toe.R"]:
				var point: Vector3=actor.model.skeleton.get_bone_global_pose(actor.model.skeleton.find_bone("DEF-"+bone)).origin
				pose_record.unmodified_base_pose_bones[bone]=[point.x,point.y,point.z]
			samples.append(pose_record)
			await capture("nagisa-walk-%03d"%frame)
	actor.stop()
	for frame in 90:
		actor.tick_body(1.0/60)
		if contacts:await process_frame
	actor.play_action("sit_enter")
	for frame in 85:
		actor.tick_body(1.0/60)
		if contacts:await process_frame
		if frame in [0,30,60,84]:await capture("nagisa-sit-%03d"%frame)
	var report: Dictionary={"scope":"Transferred target skeleton and motor integration review. Screenshots require visual assessment; no natural-gait acceptance implied.","samples":samples,"errors":errors,"action":actor.motion_state()}
	FileAccess.open(OUT+"/inspection.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	world.free();quit(0 if errors.is_empty() else 1)
